/**
 * Contadores de presença atômicos + reconciliação segura.
 * Deploy somente quando autorizado (não executar neste passo).
 */
const { onValueWritten } = require("firebase-functions/v2/database");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const {
  normalizeCountryCode,
  computeAtomicPresencePatch,
  countriesToZero,
  shouldMirrorAfterSync,
  parseReconcileCallArgs,
  evaluatePresenceReconcileAdmin,
  advanceReconcileCheckpoint,
  pruneStaleConnectionsMap,
} = require("./presence_rtdb_counters_logic");

let assertAppCheckIfEnforced = () => {};
try {
  assertAppCheckIfEnforced =
    require("./remi_usage").assertAppCheckIfEnforced || (() => {});
} catch (_) {
  assertAppCheckIfEnforced = () => {};
}

const CHECKPOINT_DOC = "presenceReconcileCheckpoint/main";
const MAX_PAGE_SIZE = 100;
const SCHEDULE_MAX_PAGES = 25;
const SCHEDULE_DEADLINE_MS = 480000; // < 540s timeout

function countConnections(val) {
  if (!val || typeof val !== "object") return 0;
  return Object.keys(val).length;
}

async function pruneStaleConnectionsForUid(rtdb, uid) {
  const ref = rtdb.ref(`presence/${uid}/connections`);
  const snap = await ref.get();
  const pruned = pruneStaleConnectionsMap(snap.val());
  if (pruned.removed > 0) {
    await ref.update(pruned.updates);
  }
  return pruned.freshCount;
}

async function readOfficialCountry(firestore, uid) {
  const snap = await firestore.collection("users").doc(uid).get();
  const data = snap.data() || {};
  const raw =
    data.homeCountryCode || data.countryCode || data.home_country_code || "";
  return normalizeCountryCode(String(raw));
}

async function readConnectionCount(rtdb, uid) {
  // TTL: remove fantasmas antes de contar (onDisconnect falho / multi-create).
  return pruneStaleConnectionsForUid(rtdb, uid);
}

async function assertPresenceReconcileAdmin(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }
  try {
    assertAppCheckIfEnforced(request);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw new HttpsError("failed-precondition", "App Check required.");
  }

  const uid = request.auth.uid;
  const token = request.auth.token || {};
  const db = admin.firestore();
  const userSnap = await db.collection("users").doc(uid).get();
  const userData = userSnap.exists ? userSnap.data() || {} : {};
  const adminSnap = await db.collection("admins").doc(uid).get();

  const verdict = evaluatePresenceReconcileAdmin({
    authenticated: true,
    token,
    userData,
    adminDocExists: adminSnap.exists,
  });

  if (!verdict.allowed) {
    throw new HttpsError(
      verdict.code === "unauthenticated" ? "unauthenticated" : "permission-denied",
      "Admin or master only."
    );
  }
  return uid;
}

/**
 * Transação Firestore atômica. Em op:none ainda devolve números para mirror
 * se mirrorPending.
 */
async function runAtomicFirestoreSync(firestore, { uid, isOnline, country }) {
  const stateRef = firestore.collection("presenceState").doc(uid);
  const worldRef = firestore.collection("presenceCounters").doc("world");

  return firestore.runTransaction(async (tx) => {
    const stateSnap = await tx.get(stateRef);
    const worldSnap = await tx.get(worldRef);
    const stateData = stateSnap.data() || {};

    const wasOnline = stateSnap.exists && stateData.online === true;
    const prevCountry = normalizeCountryCode(String(stateData.country || ""));
    const mirrorPending = stateData.mirrorPending === true;

    const patch = computeAtomicPresencePatch({
      wasOnline,
      prevCountry,
      isOnline,
      nextCountry: country,
    });

    const countryKeys = new Set(Object.keys(patch.countryDeltas));
    if (patch.op === "none" && prevCountry) countryKeys.add(prevCountry);

    const countryRefs = {};
    const countrySnaps = {};
    for (const cc of countryKeys) {
      countryRefs[cc] = firestore.collection("presenceCounters").doc(`c_${cc}`);
      countrySnaps[cc] = await tx.get(countryRefs[cc]);
    }

    const worldCur = (worldSnap.data() || {}).count || 0;

    if (patch.op === "none") {
      const byCountry = {};
      if (prevCountry) {
        byCountry[prevCountry] =
          (countrySnaps[prevCountry]?.data() || {}).count || 0;
      }
      return {
        changed: false,
        needsMirror: shouldMirrorAfterSync({
          op: "none",
          changed: false,
          mirrorPending,
        }),
        online: wasOnline,
        country: prevCountry,
        world: worldCur,
        byCountry,
        op: "none",
        mirrorPending,
      };
    }

    const worldNext = Math.max(0, worldCur + patch.worldDelta);
    tx.set(
      worldRef,
      {
        count: worldNext,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const byCountryNext = {};
    for (const [cc, delta] of Object.entries(patch.countryDeltas)) {
      const cur = (countrySnaps[cc].data() || {}).count || 0;
      const next = Math.max(0, cur + delta);
      byCountryNext[cc] = next;
      tx.set(
        countryRefs[cc],
        {
          count: next,
          countryCode: cc,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    tx.set(
      stateRef,
      {
        online: patch.nextOnline,
        country: patch.nextCountry,
        uid,
        mirrorPending: true, // até mirror OK
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      changed: true,
      needsMirror: true,
      online: patch.nextOnline,
      country: patch.nextCountry,
      world: worldNext,
      byCountry: byCountryNext,
      op: patch.op,
      mirrorPending: true,
    };
  });
}

/**
 * Mirror idempotente: escreve valores absolutos autoritativos (não deltas).
 */
async function mirrorCountersToRtdb(rtdb, uid, result) {
  if (!result) return;
  const updates = {};
  if (typeof result.world === "number") {
    updates["presenceCounters/world"] = result.world;
  }
  for (const [cc, n] of Object.entries(result.byCountry || {})) {
    updates[`presenceCounters/byCountry/${cc}`] = n;
  }
  if (result.online) {
    updates[`presenceOnline/${uid}`] = {
      c: result.country || "",
      at: Date.now(),
    };
  } else {
    updates[`presenceOnline/${uid}`] = null;
  }
  await rtdb.ref().update(updates);
}

async function setMirrorPending(firestore, uid, pending) {
  await firestore.collection("presenceState").doc(uid).set(
    {
      mirrorPending: pending === true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

/**
 * Sync: transação → mirror. Falha no mirror marca pending e relança
 * para retry da Function (sem reaplicar delta: op:none + needsMirror).
 */
async function syncPresenceAtomic(
  firestore,
  rtdb,
  uid,
  { maxAttempts = 5 } = {}
) {
  let last = null;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const connectionsAfter = await readConnectionCount(rtdb, uid);
    const country = await readOfficialCountry(firestore, uid);
    const isOnline = connectionsAfter > 0;

    last = await runAtomicFirestoreSync(firestore, {
      uid,
      isOnline,
      country: isOnline ? country : "",
    });
    last.uid = uid;

    if (last.needsMirror || last.changed) {
      try {
        // Se byCountry vazio no none, carregar contador do país do estado
        if (
          last.op === "none" &&
          last.country &&
          Object.keys(last.byCountry || {}).length === 0
        ) {
          const cSnap = await firestore
            .collection("presenceCounters")
            .doc(`c_${last.country}`)
            .get();
          last.byCountry = {
            [last.country]: (cSnap.data() || {}).count || 0,
          };
        }
        await mirrorCountersToRtdb(rtdb, uid, last);
        await setMirrorPending(firestore, uid, false);
        last.mirrorPending = false;
      } catch (err) {
        console.warn("mirror failed", uid, err.message || err);
        await setMirrorPending(firestore, uid, true);
        // Relança para a plataforma retentar; delta já commitado.
        throw err;
      }
    }

    const again = await readConnectionCount(rtdb, uid);
    const stateSnap = await firestore.collection("presenceState").doc(uid).get();
    const stateOnline = stateSnap.exists && stateSnap.data().online === true;
    const desired = again > 0;
    const pending = stateSnap.exists && stateSnap.data().mirrorPending === true;
    if (stateOnline === desired && !pending) {
      if (!desired) return last;
      const stCountry = normalizeCountryCode(
        String((stateSnap.data() || {}).country || "")
      );
      const wantCountry = await readOfficialCountry(firestore, uid);
      if (!wantCountry || stCountry === wantCountry) return last;
    }
  }
  return last;
}

const onPresenceConnectionWritten = onValueWritten(
  {
    ref: "presence/{uid}/connections/{connectionId}",
    region: "us-central1",
  },
  async (event) => {
    const uid = event.params.uid;
    if (!uid) return null;
    const rtdb = admin.database();
    const firestore = admin.firestore();
    return syncPresenceAtomic(firestore, rtdb, uid);
  }
);

async function reconcilePresenceCountersPage(
  firestore,
  rtdb,
  { pageSize = 50, startAfterId = null } = {}
) {
  const size = Math.min(MAX_PAGE_SIZE, Math.max(1, pageSize));
  let q = firestore
    .collection("presenceState")
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(size);
  if (startAfterId) {
    if (
      typeof startAfterId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(startAfterId)
    ) {
      throw new Error("invalid startAfterId");
    }
    q = q.startAfter(startAfterId);
  }
  const snap = await q.get();
  const fixed = [];
  for (const doc of snap.docs) {
    const uid = doc.id;
    try {
      const before = await syncPresenceAtomic(firestore, rtdb, uid, {
        maxAttempts: 3,
      });
      if (before && (before.changed || before.needsMirror)) fixed.push(uid);
    } catch (err) {
      console.warn("reconcile page uid failed", uid, err.message || err);
    }
  }

  const nextPage =
    snap.size === size ? snap.docs[snap.docs.length - 1].id : null;

  return {
    scanned: snap.size,
    fixed: fixed.length,
    fixedUids: fixed.slice(0, 20),
    nextPage,
  };
}

/**
 * Rebuild absoluto + zera países ausentes (FS + RTDB).
 * Só chamar após sync de páginas completo.
 */
async function rebuildAbsoluteCounters(firestore, rtdb) {
  const byCountry = {};
  let world = 0;
  let lastId = null;
  let pages = 0;

  while (pages < 500) {
    let q = firestore
      .collection("presenceState")
      .where("online", "==", true)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(200);
    if (lastId) q = q.startAfter(lastId);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      world += 1;
      const cc = normalizeCountryCode(String((doc.data() || {}).country || ""));
      if (cc) byCountry[cc] = (byCountry[cc] || 0) + 1;
    }
    lastId = snap.docs[snap.docs.length - 1].id;
    pages += 1;
    if (snap.size < 200) break;
  }

  // Counters existentes (para zerar ausentes)
  const existingSnap = await firestore.collection("presenceCounters").get();
  const existingCountries = [];
  for (const doc of existingSnap.docs) {
    if (doc.id.startsWith("c_")) {
      existingCountries.push(doc.id.slice(2));
    }
  }
  const toZero = countriesToZero(existingCountries, byCountry);

  // RTDB keys existentes
  const rtdbCountriesSnap = await rtdb.ref("presenceCounters/byCountry").get();
  const rtdbExisting = rtdbCountriesSnap.exists()
    ? Object.keys(rtdbCountriesSnap.val() || {})
    : [];
  for (const cc of countriesToZero(rtdbExisting, byCountry)) {
    if (!toZero.includes(cc)) toZero.push(cc);
  }

  // Escrita paginada em batches de 400
  const writes = [];
  writes.push({
    ref: firestore.collection("presenceCounters").doc("world"),
    data: {
      count: world,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      reconciledAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  });
  for (const [cc, n] of Object.entries(byCountry)) {
    writes.push({
      ref: firestore.collection("presenceCounters").doc(`c_${cc}`),
      data: {
        count: n,
        countryCode: cc,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        reconciledAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
  }
  for (const cc of toZero) {
    writes.push({
      ref: firestore.collection("presenceCounters").doc(`c_${cc}`),
      data: {
        count: 0,
        countryCode: cc,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        reconciledAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    });
  }

  for (let i = 0; i < writes.length; i += 400) {
    const batch = firestore.batch();
    const chunk = writes.slice(i, i + 400);
    for (const w of chunk) {
      batch.set(w.ref, w.data, { merge: true });
    }
    await batch.commit();
  }

  const rtdbUpdates = { "presenceCounters/world": world };
  for (const [cc, n] of Object.entries(byCountry)) {
    rtdbUpdates[`presenceCounters/byCountry/${cc}`] = n;
  }
  for (const cc of toZero) {
    rtdbUpdates[`presenceCounters/byCountry/${cc}`] = 0;
  }
  // Chunk RTDB updates (~100 keys)
  const entries = Object.entries(rtdbUpdates);
  for (let i = 0; i < entries.length; i += 100) {
    const chunk = Object.fromEntries(entries.slice(i, i + 100));
    await rtdb.ref().update(chunk);
  }

  return { world, byCountry, zeroed: toZero, pages };
}

async function runScheduledReconcile(firestore, rtdb, {
  maxPages = SCHEDULE_MAX_PAGES,
  pageSize = 80,
  now = Date.now(),
  deadlineMs = now + SCHEDULE_DEADLINE_MS,
} = {}) {
  const cpRef = firestore.doc(CHECKPOINT_DOC);
  const cpSnap = await cpRef.get();
  let cp = cpSnap.exists
    ? cpSnap.data() || { phase: "sync", cursor: null }
    : { phase: "sync", cursor: null };

  let scanned = 0;
  let fixed = 0;
  let pagesDone = 0;

  if (cp.phase !== "rebuild") {
    let cursor = cp.cursor || null;
    while (pagesDone < maxPages) {
      if (Date.now() >= deadlineMs) {
        await cpRef.set(
          {
            phase: "sync",
            cursor,
            scanned,
            fixed,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            incomplete: true,
          },
          { merge: true }
        );
        return {
          incomplete: true,
          phase: "sync",
          scanned,
          fixed,
          cursor,
          pagesDone,
        };
      }

      const page = await reconcilePresenceCountersPage(firestore, rtdb, {
        pageSize,
        startAfterId: cursor,
      });
      scanned += page.scanned;
      fixed += page.fixed;
      pagesDone += 1;

      const next = advanceReconcileCheckpoint(
        { phase: "sync", cursor },
        page,
        { maxPagesThisRun: maxPages, pagesDone }
      );

      if (next.readyForRebuild) {
        cp = { phase: "rebuild", cursor: null };
        await cpRef.set(
          {
            phase: "rebuild",
            cursor: null,
            scanned,
            fixed,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        break;
      }

      cursor = next.cursor;
      await cpRef.set(
        {
          phase: "sync",
          cursor,
          scanned,
          fixed,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          incomplete: true,
        },
        { merge: true }
      );

      if (!cursor) break;
    }

    if (cp.phase !== "rebuild") {
      return {
        incomplete: true,
        phase: "sync",
        scanned,
        fixed,
        cursor: cp.cursor,
        pagesDone,
      };
    }
  }

  // Só rebuild depois de sync completo (sem estados sujos pendentes de páginas)
  if (Date.now() >= deadlineMs) {
    return { incomplete: true, phase: "rebuild", scanned, fixed, pagesDone };
  }

  const rebuilt = await rebuildAbsoluteCounters(firestore, rtdb);
  await cpRef.set(
    {
      phase: "idle",
      cursor: null,
      scanned,
      fixed,
      lastCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
      incomplete: false,
      lastWorld: rebuilt.world,
    },
    { merge: true }
  );

  return {
    incomplete: false,
    phase: "idle",
    scanned,
    fixed,
    pagesDone,
    rebuilt,
  };
}

const reconcilePresenceCounters = onSchedule(
  {
    schedule: "every 24 hours",
    region: "us-central1",
    timeoutSeconds: 540,
  },
  async () => {
    const firestore = admin.firestore();
    const rtdb = admin.database();
    return runScheduledReconcile(firestore, rtdb);
  }
);

const reconcilePresenceCountersNow = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 540,
    // App Check: alinhar a REMI_ENFORCE_APP_CHECK / Console quando ativo.
  },
  async (request) => {
    await assertPresenceReconcileAdmin(request);

    const parsed = parseReconcileCallArgs(request.data || {});
    if (!parsed.ok) {
      throw new HttpsError(
        "invalid-argument",
        parsed.errors.join("; ") || "Invalid arguments"
      );
    }

    const firestore = admin.firestore();
    const rtdb = admin.database();

    // Uma página sob controle do admin; rebuild só se pedir e sync completo
    const page = await reconcilePresenceCountersPage(firestore, rtdb, {
      pageSize: parsed.pageSize,
      startAfterId: parsed.startAfterId,
    });

    let rebuilt = null;
    if (request.data?.rebuild === true && !page.nextPage && !parsed.startAfterId) {
      // rebuild full só se varredura aparentemente completa (sem cursor de entrada
      // e sem próxima página — admin deve paginar até o fim antes)
      rebuilt = await rebuildAbsoluteCounters(firestore, rtdb);
    } else if (request.data?.rebuild === true && page.nextPage) {
      throw new HttpsError(
        "failed-precondition",
        "Finish paging all users before rebuild (nextPage present)."
      );
    }

    return { page, rebuilt };
  }
);

module.exports = {
  onPresenceConnectionWritten,
  reconcilePresenceCounters,
  reconcilePresenceCountersNow,
  syncPresenceAtomic,
  runAtomicFirestoreSync,
  countConnections,
  reconcilePresenceCountersPage,
  rebuildAbsoluteCounters,
  runScheduledReconcile,
  assertPresenceReconcileAdmin,
  mirrorCountersToRtdb,
  setMirrorPending,
};

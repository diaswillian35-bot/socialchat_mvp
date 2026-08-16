/**
 * Backfill seguro dos campos de busca em `publicUsers`.
 *
 * Escreve APENAS:
 *   nameSearch, citySearch, regionSearch, countrySearch, countryCode
 *
 * Derivados somente de dados já públicos. Não copia e-mail, Premium,
 * tokens, coordenadas, papéis ou campos administrativos.
 *
 * Idempotente: seguro reexecutar.
 *
 * Uso:
 *   # Dry-run (não escreve):
 *   node scripts/backfill_public_user_search.js --dry-run
 *
 *   # Execução real:
 *   GOOGLE_APPLICATION_CREDENTIALS=/caminho/sa.json \
 *     node scripts/backfill_public_user_search.js --execute
 *
 * Sem --execute, o padrão é --dry-run (seguro).
 */

const admin = require("firebase-admin");
const { buildPublicSearchFields } = require("../user_search");

const args = process.argv.slice(2);
const DRY_RUN = !args.includes("--execute");
const PROJECT_ID =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.FIREBASE_PROJECT ||
  "socialchatmvp";

if (!admin.apps.length) {
  const init = { projectId: PROJECT_ID };
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    // ADC via arquivo de service account
    admin.initializeApp(init);
  } else {
    // Tenta Application Default Credentials / ambiente Firebase
    admin.initializeApp(init);
  }
}

const PAGE_SIZE = 300;
const ALLOWED_WRITE_KEYS = new Set([
  "nameSearch",
  "citySearch",
  "regionSearch",
  "countrySearch",
  "countryCode",
]);

function needsUpdate(current, desired) {
  for (const key of Object.keys(desired)) {
    if ((current[key] || "").toString() !== (desired[key] || "").toString()) {
      return true;
    }
  }
  return false;
}

function assertSafeDesired(desired) {
  for (const key of Object.keys(desired)) {
    if (!ALLOWED_WRITE_KEYS.has(key)) {
      throw new Error(`Unsafe backfill field blocked: ${key}`);
    }
  }
}

async function run() {
  const db = admin.firestore();
  let last = null;
  let processed = 0;
  let wouldUpdate = 0;
  let updated = 0;
  const sample = [];

  console.log(
    JSON.stringify({
      action: "backfill_public_user_search_start",
      mode: DRY_RUN ? "dry-run" : "execute",
      projectId: PROJECT_ID,
      allowedFields: [...ALLOWED_WRITE_KEYS],
    })
  );

  // eslint-disable-next-line no-constant-condition
  while (true) {
    let query = db
      .collection("publicUsers")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(PAGE_SIZE);

    if (last) query = query.startAfter(last);

    const snap = await query.get();
    if (snap.empty) break;

    let batch = DRY_RUN ? null : db.batch();
    let batchCount = 0;

    for (const doc of snap.docs) {
      processed += 1;
      const data = doc.data() || {};
      const desired = buildPublicSearchFields(data);
      assertSafeDesired(desired);
      if (!Object.keys(desired).length) continue;
      if (!needsUpdate(data, desired)) continue;

      wouldUpdate += 1;
      if (sample.length < 5) {
        sample.push({ id: doc.id, patch: desired });
      }

      if (!DRY_RUN) {
        batch.set(doc.ref, desired, { merge: true });
        batchCount += 1;
        updated += 1;

        if (batchCount >= 400) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
      }
    }

    if (!DRY_RUN && batchCount > 0) await batch.commit();

    last = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  console.log(
    JSON.stringify({
      action: "backfill_public_user_search",
      mode: DRY_RUN ? "dry-run" : "execute",
      processed,
      wouldUpdate,
      updated: DRY_RUN ? 0 : updated,
      sample,
    })
  );

  if (DRY_RUN) {
    console.log(
      "Dry-run only. Re-run with --execute to apply changes."
    );
  }
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(
      JSON.stringify({
        action: "backfill_public_user_search_failed",
        mode: DRY_RUN ? "dry-run" : "execute",
        message: (e && e.message) || String(e),
        code: (e && e.code) || null,
      })
    );
    process.exit(1);
  });

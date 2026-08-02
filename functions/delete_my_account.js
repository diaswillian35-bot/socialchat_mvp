/**
 * Exclusão segura da conta do usuário autenticado (Admin SDK).
 * UID vem exclusivamente de request.auth.uid — nunca do cliente.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const REMOVED_NAME = "Removed user";
const BATCH_LIMIT = 400;

function asUidList(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((m) => (m || "").toString().trim())
    .filter((m) => m.length > 0);
}

async function commitInChunks(db, ops) {
  for (let i = 0; i < ops.length; i += BATCH_LIMIT) {
    const chunk = ops.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const op of chunk) {
      if (op.type === "set") {
        batch.set(op.ref, op.data, op.options || { merge: true });
      } else if (op.type === "update") {
        batch.update(op.ref, op.data);
      } else if (op.type === "delete") {
        batch.delete(op.ref);
      }
    }
    await batch.commit();
  }
}

async function deleteQueryDocs(db, query, mapFn) {
  const snap = await query.get();
  if (snap.empty) return 0;
  const ops = [];
  for (const doc of snap.docs) {
    if (typeof mapFn === "function") {
      const mapped = mapFn(doc);
      if (Array.isArray(mapped)) ops.push(...mapped);
      else if (mapped) ops.push(mapped);
    } else {
      ops.push({ type: "delete", ref: doc.ref });
    }
  }
  await commitInChunks(db, ops);
  return snap.size;
}

async function deleteSubcollection(db, parentRef, subName, pageSize = 200) {
  let total = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await parentRef.collection(subName).limit(pageSize).get();
    if (snap.empty) break;
    const ops = snap.docs.map((d) => ({ type: "delete", ref: d.ref }));
    await commitInChunks(db, ops);
    total += snap.size;
    if (snap.size < pageSize) break;
  }
  return total;
}

async function deleteStoragePrefix(prefix) {
  const bucket = admin.storage().bucket();
  try {
    await bucket.deleteFiles({ prefix, force: true });
    return true;
  } catch (e) {
    console.warn(
      JSON.stringify({
        action: "storage_prefix_delete_failed",
        prefix,
        message: (e && e.message) || "unknown",
      })
    );
    return false;
  }
}

async function anonymizeOwnedMessages(db, collectionPath, uid) {
  // Best-effort: messages where fromUid or senderId == uid
  const col = db.collection(collectionPath);
  let updated = 0;

  for (const field of ["fromUid", "senderId"]) {
    try {
      const snap = await col.where(field, "==", uid).limit(200).get();
      if (snap.empty) continue;
      const ops = snap.docs.map((doc) => ({
        type: "set",
        ref: doc.ref,
        data: {
          senderName: REMOVED_NAME,
          name: REMOVED_NAME,
          photoUrl: "",
          senderPhotoUrl: "",
          accountDeleted: true,
        },
        options: { merge: true },
      }));
      await commitInChunks(db, ops);
      updated += snap.size;
    } catch (e) {
      console.warn(
        JSON.stringify({
          action: "anonymize_messages_skip",
          path: collectionPath,
          field,
          message: (e && e.message) || "unknown",
        })
      );
    }
  }
  return updated;
}

async function processConversations(db, uid) {
  const snap = await db
    .collection("conversations")
    .where("participants", "array-contains", uid)
    .get();

  let count = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const participants = asUidList(data.participants).filter((p) => p !== uid);
    const hiddenFor = asUidList(data.hiddenFor);
    if (!hiddenFor.includes(uid)) hiddenFor.push(uid);

    await anonymizeOwnedMessages(db, `conversations/${doc.id}/messages`, uid);

    try {
      await doc.ref.collection("presence").doc(uid).delete();
    } catch (_) {}

    await doc.ref.set(
      {
        participants,
        hiddenFor,
        [`unread.${uid}`]: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    count += 1;
  }
  return count;
}

async function processGroups(db, uid) {
  const snap = await db
    .collection("groups")
    .where("members", "array-contains", uid)
    .get();

  // Also groups where user is owner but maybe not in members (edge case)
  let ownerSnap;
  try {
    ownerSnap = await db
      .collection("groups")
      .where("ownerId", "==", uid)
      .get();
  } catch (_) {
    ownerSnap = { docs: [], empty: true };
  }

  const byId = new Map();
  for (const d of snap.docs) byId.set(d.id, d);
  for (const d of ownerSnap.docs || []) byId.set(d.id, d);

  let processed = 0;
  for (const doc of byId.values()) {
    const data = doc.data() || {};
    if (data.deleted === true) {
      // still remove presence/reads
      try {
        await doc.ref.collection("presence").doc(uid).delete();
      } catch (_) {}
      try {
        await doc.ref.collection("reads").doc(uid).delete();
      } catch (_) {}
      processed += 1;
      continue;
    }

    const ownerId = (data.ownerId || "").toString().trim();
    let members = asUidList(data.members).filter((m) => m !== uid);
    let admins = asUidList(data.admins).filter((a) => a !== uid);

    const patch = {
      members,
      admins,
      membersCount: members.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      [`unread.${uid}`]: admin.firestore.FieldValue.delete(),
    };

    if (ownerId === uid) {
      if (admins.length > 0) {
        // Transfer ownership to another admin still in members if possible
        const nextOwner =
          admins.find((a) => members.includes(a)) || admins[0];
        patch.ownerId = nextOwner;
        if (!members.includes(nextOwner)) {
          members = [...members, nextOwner];
          patch.members = members;
          patch.membersCount = members.length;
        }
        if (!admins.includes(nextOwner)) {
          admins = [...admins, nextOwner];
          patch.admins = admins;
        }
        patch.ownershipTransferredFrom = uid;
        patch.ownershipTransferredAt =
          admin.firestore.FieldValue.serverTimestamp();
      } else if (members.length > 0) {
        // Promote first remaining member
        const nextOwner = members[0];
        patch.ownerId = nextOwner;
        patch.admins = Array.from(new Set([...admins, nextOwner]));
        patch.ownershipTransferredFrom = uid;
        patch.ownershipTransferredAt =
          admin.firestore.FieldValue.serverTimestamp();
      } else {
        // No one left — soft-delete group
        patch.deleted = true;
        patch.isActive = false;
        patch.deletedAt = admin.firestore.FieldValue.serverTimestamp();
        patch.deletedBy = uid;
        patch.deletedReason = "owner_account_deleted";
      }
    }

    await doc.ref.set(patch, { merge: true });

    try {
      await doc.ref.collection("presence").doc(uid).delete();
    } catch (_) {}
    try {
      await doc.ref.collection("reads").doc(uid).delete();
    } catch (_) {}
    try {
      await doc.ref.collection("pendingRequests").doc(uid).delete();
    } catch (_) {}
    try {
      await doc.ref.collection("bannedUsers").doc(uid).delete();
    } catch (_) {}

    // User-owned media under this group
    await deleteStoragePrefix(`groups/${doc.id}/images/${uid}/`);
    await deleteStoragePrefix(`groups/${doc.id}/audio/${uid}/`);

    processed += 1;
  }
  return processed;
}

async function processEvents(db, uid) {
  let created = 0;
  let left = 0;

  // Events created / organized by user
  for (const field of ["createdBy", "organizerId", "ownerId"]) {
    let snap;
    try {
      snap = await db.collection("events").where(field, "==", uid).get();
    } catch (_) {
      continue;
    }
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      // Cancel published events owned by user; keep history for attendees
      await doc.ref.set(
        {
          status: "cancelled",
          isActive: false,
          organizerName: REMOVED_NAME,
          organizerPhotoUrl: "",
          creatorName: REMOVED_NAME,
          accountOwnerDeleted: true,
          cancelledReason: "organizer_account_deleted",
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          // Keep createdBy for audit; mark deleted owner
          deletedOwnerId: uid,
        },
        { merge: true }
      );
      created += 1;

      // Anonymize comments by this user on their events
      try {
        const comments = await doc.ref
          .collection("comments")
          .where("uid", "==", uid)
          .limit(200)
          .get();
        const ops = comments.docs.map((c) => ({
          type: "set",
          ref: c.ref,
          data: {
            name: REMOVED_NAME,
            photoUrl: "",
            accountDeleted: true,
          },
          options: { merge: true },
        }));
        await commitInChunks(db, ops);
      } catch (_) {}
    }
  }

  // Attendance
  let attendSnap;
  try {
    attendSnap = await db
      .collection("events")
      .where("attendeesUids", "array-contains", uid)
      .get();
  } catch (_) {
    attendSnap = { docs: [] };
  }

  for (const doc of attendSnap.docs) {
    const data = doc.data() || {};
    const attendeesUids = asUidList(data.attendeesUids).filter(
      (a) => a !== uid
    );
    await doc.ref.set(
      {
        attendeesUids,
        attendeesCount: attendeesUids.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    try {
      await doc.ref.collection("attendees").doc(uid).delete();
    } catch (_) {}
    try {
      await doc.ref.collection("views").doc(uid).delete();
    } catch (_) {}

    // Anonymize own comments on events attended
    try {
      const comments = await doc.ref
        .collection("comments")
        .where("uid", "==", uid)
        .limit(100)
        .get();
      const ops = comments.docs.map((c) => ({
        type: "set",
        ref: c.ref,
        data: {
          name: REMOVED_NAME,
          photoUrl: "",
          accountDeleted: true,
        },
        options: { merge: true },
      }));
      await commitInChunks(db, ops);
    } catch (_) {}

    left += 1;
  }

  return { created, left };
}

async function processReports(db, uid) {
  let n = 0;
  for (const field of ["fromUid", "reporterUid", "reportedUid"]) {
    try {
      const snap = await db
        .collection("reports")
        .where(field, "==", uid)
        .limit(200)
        .get();
      const ops = snap.docs.map((doc) => {
        if (field === "reportedUid") {
          return {
            type: "set",
            ref: doc.ref,
            data: {
              reportedUid: "deleted_user",
              reportedName: REMOVED_NAME,
              accountDeletedTarget: true,
            },
            options: { merge: true },
          };
        }
        return {
          type: "set",
          ref: doc.ref,
          data: {
            fromUid: "deleted_user",
            reporterUid: "deleted_user",
            reporterName: REMOVED_NAME,
            accountDeletedReporter: true,
          },
          options: { merge: true },
        };
      });
      await commitInChunks(db, ops);
      n += snap.size;
    } catch (_) {}
  }
  return n;
}

async function processPosts(db, uid) {
  try {
    const snap = await db.collection("posts").where("uid", "==", uid).get();
    for (const doc of snap.docs) {
      await deleteStoragePrefix(`posts/${doc.id}/`);
      await doc.ref.delete();
    }
    return snap.size;
  } catch (_) {
    return 0;
  }
}

async function tombstoneUser(db, uid) {
  const userRef = db.collection("users").doc(uid);
  await deleteSubcollection(db, userRef, "fcmTokens");
  await deleteSubcollection(db, userRef, "systemInbox");
  try {
    await deleteSubcollection(db, userRef, "remi");
  } catch (_) {}
  // remi/memory may be a doc under remi
  try {
    await userRef.collection("remi").doc("memory").delete();
  } catch (_) {}

  await userRef.set(
    {
      uid,
      name: REMOVED_NAME,
      displayName: REMOVED_NAME,
      email: "",
      photoUrl: "",
      profilePhotoUrl: "",
      avatarUrl: "",
      gallery: [],
      about: "",
      fcmToken: admin.firestore.FieldValue.delete(),
      isOnline: false,
      nearbyEnabled: false,
      isPremium: false,
      premiumUntil: admin.firestore.FieldValue.delete(),
      premiumType: admin.firestore.FieldValue.delete(),
      accountDeleted: true,
      accountDeletionStatus: "completed",
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      // Keep minimal fraud/audit trail; strip PII
      blocked: [],
      inviteCode: "",
      invitedBy: "",
      invitedByCode: "",
    },
    { merge: true }
  );
}

/**
 * Callable: deleteMyAccount
 */
async function deleteMyAccountHandler(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  // Never trust client UID
  const uid = request.auth.uid;
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);

  const userSnap = await userRef.get();
  const existing = userSnap.exists ? userSnap.data() || {} : {};

  if (existing.accountDeletionStatus === "completed" && existing.accountDeleted === true) {
    // Idempotent: try auth delete if still exists
    try {
      await admin.auth().deleteUser(uid);
    } catch (e) {
      if (e.code !== "auth/user-not-found") {
        console.error("auth_delete_retry_failed", e.code || e.message);
      }
    }
    return {
      success: true,
      alreadyDeleted: true,
      uidHash: uid.slice(0, 6),
    };
  }

  await userRef.set(
    {
      accountDeletionStatus: "in_progress",
      accountDeletionStartedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  const summary = {
    conversations: 0,
    groups: 0,
    eventsCreated: 0,
    eventsLeft: 0,
    reports: 0,
    posts: 0,
    storageUser: false,
  };

  try {
    summary.conversations = await processConversations(db, uid);
    summary.groups = await processGroups(db, uid);
    const events = await processEvents(db, uid);
    summary.eventsCreated = events.created;
    summary.eventsLeft = events.left;
    summary.reports = await processReports(db, uid);
    summary.posts = await processPosts(db, uid);

    // public profile / organizer / admin
    try {
      await db.collection("publicUsers").doc(uid).delete();
    } catch (_) {}
    try {
      await db.collection("organizers").doc(uid).delete();
    } catch (_) {}
    try {
      await db.collection("admins").doc(uid).delete();
    } catch (_) {}

    summary.storageUser = await deleteStoragePrefix(`users/${uid}/`);
    // Legacy event photos path events/{uid}/
    await deleteStoragePrefix(`events/${uid}/`);

    try {
      const { revokeAllSessionsForUid } = require("./share_extension");
      await revokeAllSessionsForUid(uid, "account_deleted");
    } catch (e) {
      console.error("share_ext_revoke_on_delete_failed", e.message || e);
    }

    await tombstoneUser(db, uid);

    // Auth last
    try {
      await admin.auth().deleteUser(uid);
    } catch (e) {
      if (e.code === "auth/user-not-found") {
        // already gone — ok
      } else {
        console.error(
          JSON.stringify({
            action: "delete_my_account_auth_failed",
            code: e.code || null,
            message: e.message || "unknown",
          })
        );
        throw new HttpsError(
          "internal",
          "Account data cleaned but auth delete failed. Please retry."
        );
      }
    }

    console.log(
      JSON.stringify({
        action: "delete_my_account_success",
        uidPrefix: uid.slice(0, 6),
        summary,
        createdAt: new Date().toISOString(),
      })
    );

    return {
      success: true,
      alreadyDeleted: false,
      summary,
    };
  } catch (e) {
    if (e instanceof HttpsError) throw e;

    try {
      await userRef.set(
        {
          accountDeletionStatus: "failed",
          accountDeletionErrorAt:
            admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (_) {}

    console.error(
      JSON.stringify({
        action: "delete_my_account_failed",
        uidPrefix: uid.slice(0, 6),
        message: (e && e.message) || "unknown",
      })
    );
    throw new HttpsError("internal", "Could not delete account. Please retry.");
  }
}

exports.deleteMyAccount = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  deleteMyAccountHandler
);

exports._deleteMyAccountHandler = deleteMyAccountHandler;

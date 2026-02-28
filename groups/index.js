const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");


setGlobalOptions({ region: "us-central1", maxInstances: 10 });


if (!admin.apps.length) {
  admin.initializeApp();
}


// ✅ Helper: pega tokens do usuário (compatível com vários jeitos)
async function getUserTokens(uid) {
  const tokens = new Set();


  // 1) users/{uid}/fcmTokens (subcollection)
  try {
    const snap = await admin
      .firestore()
      .collection("users")
      .doc(uid)
      .collection("fcmTokens")
      .get();


    snap.forEach((d) => {
      const data = d.data() || {};
      if (typeof data.token === "string" && data.token.length > 0) tokens.add(data.token);
      // se você salva o token como id do doc, também pega:
      if (typeof d.id === "string" && d.id.length > 20) tokens.add(d.id);
    });
  } catch (_) {}


  // 2) users/{uid}.fcmToken (campo único)
  try {
    const userDoc = await admin.firestore().collection("users").doc(uid).get();
    const u = userDoc.data() || {};
    if (typeof u.fcmToken === "string" && u.fcmToken.length > 0) tokens.add(u.fcmToken);


    // 3) users/{uid}.fcmTokens (array)
    if (Array.isArray(u.fcmTokens)) {
      u.fcmTokens.forEach((t) => {
        if (typeof t === "string" && t.length > 0) tokens.add(t);
      });
    }
  } catch (_) {}


  return Array.from(tokens);
}


exports.onGroupMessageCreated = onDocumentCreated(
  "groups/{groupId}/messages/{messageId}",
  async (event) => {
    const groupId = event.params.groupId;
    const msg = event.data?.data() || {};


    const text = (msg.text || "").toString();
    const senderId = (msg.senderId || "").toString();


    if (!groupId || !senderId) return;


    // pega doc do grupo
    const groupRef = admin.firestore().collection("groups").doc(groupId);
    const groupSnap = await groupRef.get();
    const group = groupSnap.data() || {};


    const groupName = (group.name || "Grupo").toString();
    const members = Array.isArray(group.members) ? group.members : [];


    // envia para todos menos o remetente
    const recipients = members.filter((uid) => uid && uid !== senderId);
    if (recipients.length === 0) return;


    // junta todos tokens
    let allTokens = [];
    for (const uid of recipients) {
      const tokens = await getUserTokens(uid);
      allTokens = allTokens.concat(tokens);
    }
    // remove duplicados
    allTokens = Array.from(new Set(allTokens));


    if (allTokens.length === 0) {
      console.log("Sem tokens para enviar push. groupId:", groupId);
      return;
    }


    const payload = {
      notification: {
        title: groupName,
        body: text.length > 0 ? text : "Nova mensagem no grupo",
      },
      data: {
        type: "group_message",
        groupId: groupId,
        senderId: senderId,
      },
    };


    // envia em multicast
    const res = await admin.messaging().sendEachForMulticast({
      tokens: allTokens,
      ...payload,
    });


    console.log("Push group sent:", {
      groupId,
      success: res.successCount,
      failure: res.failureCount,
    });


    // opcional: limpar tokens inválidos
    const invalidTokens = [];
    res.responses.forEach((r, idx) => {
      if (!r.success) {
        const code = r.error?.code || "";
        if (
          code.includes("registration-token-not-registered") ||
          code.includes("invalid-argument")
        ) {
          invalidTokens.push(allTokens[idx]);
        }
      }
    });
    if (invalidTokens.length > 0) {
      console.log("Tokens inválidos detectados:", invalidTokens.length);
    }
  }
);

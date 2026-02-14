const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

exports.onChatMessageCreated = onDocumentCreated(
  "conversations/{convoId}/messages/{msgId}",
  async (event) => {
    try {
      const msg = event.data?.data();
      const convoId = event.params.convoId;

      if (!msg) return;

      const fromUid = (msg.fromUid || "").toString();
      const text = (msg.text || "Nova mensagem").toString();
      const fromName = (msg.fromName || "Usuário").toString(); // se você não salva, fica genérico

      if (!fromUid) return;

      const convoSnap = await admin
        .firestore()
        .collection("conversations")
        .doc(convoId)
        .get();

      if (!convoSnap.exists) return;

      const convo = convoSnap.data() || {};
      const participants = convo.participants || convo.members || [];
      const toUid = participants.find((u) => u !== fromUid);

      if (!toUid) return;

      const userSnap = await admin.firestore().collection("users").doc(toUid).get();
      const token = userSnap.data()?.fcmToken;

      if (!token) {
        console.log("Usuário sem token:", toUid);
        return;
      }

      // ✅ IMPORTANTE: mandar data para seu PushService abrir o chat
      const message = {
        token,
        notification: {
          title: "Nova mensagem",
          body: text,
        },
        data: {
          conversationId: convoId,
          fromUid: fromUid,
          fromName: fromName,
          // opcional: texto no payload também
          body: text,
          title: "Nova mensagem",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "chat_messages",
          },
        },
      };

      const res = await admin.messaging().send(message);
      console.log("Push enviado (messageId):", res);
    } catch (e) {
      console.error("Erro na function:", e);
    }
  }
);

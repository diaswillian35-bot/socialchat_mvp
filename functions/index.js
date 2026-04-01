const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");


admin.initializeApp();


exports.onGroupMessageCreated = onDocumentCreated(
  "groups/{groupId}/messages/{msgId}",
  async (event) => {
    try {
      const msg = event.data?.data();
      const groupId = event.params.groupId;
      if (!msg) return;


      const senderId = (msg.senderId || msg.fromUid || "").toString().trim();
      if (!senderId) return;


      const type = (msg.type || "text").toString().trim();


      let lastMessage = "Nova mensagem";
      if (type === "audio") lastMessage = "🎤 Áudio";
      else if (type === "image") lastMessage = "📷 Foto";
      else lastMessage = (msg.text || "Nova mensagem").toString();


      const groupRef = admin.firestore().collection("groups").doc(groupId);
      const groupSnap = await groupRef.get();
      if (!groupSnap.exists) return;


      const group = groupSnap.data() || {};
      const groupName = (group.name || "Grupo").toString().trim();


      const members = Array.isArray(group.members)
        ? group.members
        : Array.isArray(group.participants)
        ? group.participants
        : [];


      if (members.length === 0) return;


      // =========================
      // Atualiza unread
      // =========================
      const unreadRaw = group.unread;
      const unreadMap =
        unreadRaw && typeof unreadRaw === "object" && !Array.isArray(unreadRaw)
          ? { ...unreadRaw }
          : {};


      for (const uid of members) {
        if (!uid) continue;


        if (uid === senderId) {
          unreadMap[uid] = 0;
          continue;
        }


        const current =
          typeof unreadMap[uid] === "number" ? unreadMap[uid] : 0;
        unreadMap[uid] = current + 1;
      }


      const updates = {
        lastMessage: lastMessage,
        lastSenderId: senderId,
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        unread: unreadMap,
      };


      await groupRef.set(updates, { merge: true });


      // =========================
      // Busca nome do sender
      // =========================
      let senderName = "Alguém";
      try {
        const senderSnap = await admin
          .firestore()
          .collection("users")
          .doc(senderId)
          .get();


        const senderData = senderSnap.data() || {};
        const n = (senderData.name || "").toString().trim();
        if (n) senderName = n;
      } catch (_) {}


      // =========================
      // Busca tokens dos outros membros
      // =========================
      const targetUids = members.filter((uid) => uid && uid !== senderId);
      if (targetUids.length === 0) return;


      const tokens = [];


      for (const uid of targetUids) {
        try {
          const tokensSnap = await admin
            .firestore()
            .collection("users")
            .doc(uid)
            .collection("fcmTokens")
            .get();


          for (const doc of tokensSnap.docs) {
            const data = doc.data() || {};
            const token = (data.token || "").toString().trim();
            if (token) tokens.push(token);
          }
        } catch (e) {
          console.error(`Erro buscando tokens de ${uid}:`, e);
        }
      }


      if (tokens.length === 0) {
        console.log("Nenhum token encontrado para membros do grupo.");
        return;
      }


      // remove duplicados
      const uniqueTokens = [...new Set(tokens)];


      // =========================
      // Envia push
      // =========================
      const message = {
        tokens: uniqueTokens,
        notification: {
          title: groupName,
          body: `${senderName}: ${lastMessage}`,
        },
        data: {
          type: "group",
          groupId: groupId,
        },
        android: {
          priority: "high",
          notification: {
            sound: "default",
            channelId: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      };


      const response = await admin.messaging().sendEachForMulticast(message);


      console.log(
        `Push grupo enviado. Success: ${response.successCount}, Fail: ${response.failureCount}`
      );


      // limpa tokens inválidos
      const invalidTokens = [];
      response.responses.forEach((r, index) => {
        if (!r.success) {
          const code = r.error?.code || "";
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token"
          ) {
            invalidTokens.push(uniqueTokens[index]);
          }
        }
      });


      if (invalidTokens.length > 0) {
        const usersSnap = await admin.firestore().collection("users").get();


        for (const userDoc of usersSnap.docs) {
          for (const badToken of invalidTokens) {
            try {
              await admin
                .firestore()
                .collection("users")
                .doc(userDoc.id)
                .collection("fcmTokens")
                .doc(badToken)
                .delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      console.error("Erro onGroupMessageCreated:", e);
    }
  }
);

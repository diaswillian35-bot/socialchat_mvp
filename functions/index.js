const { onDocumentCreated, onDocumentWritten, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const admin = require("firebase-admin");
function distanceKm(lat1, lon1, lat2, lon2) {
  const R = 6371;

  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) *
    Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) *
    Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c;
}


const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

admin.initializeApp();



exports.onGroupJoinRequestCreated = onDocumentWritten(
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
  headers: {
    "apns-priority": "10",
  },
  payload: {
    aps: {
      alert: {
        title: senderName,
        body: text,
      },
      sound: "default",
      badge: 1,
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
exports.onPrivateMessageCreated = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    try {
      const msg = event.data?.data();
      if (!msg) return;

      const conversationId = event.params.conversationId;

      const senderId = (msg.senderId || msg.fromUid || msg.uid || "")
        .toString()
        .trim();

      if (!senderId) return;

      const convRef = admin.firestore().collection("conversations").doc(conversationId);
      const convSnap = await convRef.get();
      if (!convSnap.exists) return;

      const conv = convSnap.data() || {};
      const participants = Array.isArray(conv.participants)
        ? conv.participants
        : [];

      const targetUids = participants.filter((uid) => uid && uid !== senderId);
      if (targetUids.length === 0) return;

      const text = (msg.text || "Nova mensagem").toString();

      let senderName = "Alguém";
      const senderSnap = await admin.firestore().collection("users").doc(senderId).get();
      const senderData = senderSnap.data() || {};
      if ((senderData.name || "").toString().trim()) {
        senderName = senderData.name.toString().trim();
      }

      const tokens = [];

      for (const uid of targetUids) {
        const userSnap = await admin.firestore().collection("users").doc(uid).get();
        const userData = userSnap.data() || {};

        const mainToken = (userData.fcmToken || "").toString().trim();
        if (mainToken) tokens.push(mainToken);

        const tokensSnap = await admin.firestore()
          .collection("users")
          .doc(uid)
          .collection("fcmTokens")
          .get();

        for (const tokenDoc of tokensSnap.docs) {
          const token = (tokenDoc.data().token || "").toString().trim();
          if (token) tokens.push(token);
        }
      }

      const uniqueTokens = [...new Set(tokens)];
      if (uniqueTokens.length === 0) return;

      const response = await admin.messaging().sendEachForMulticast({
        tokens: uniqueTokens,
        notification: {
          title: senderName,
          body: text,
        },
        data: {
          type: "chat",
          conversationId,
          senderId,
        },
        android: {
          priority: "high",
          notification: {
            sound: "default",
            channelId: "default",
          },
        },
       apns: {
  headers: {
    "apns-priority": "10",
  },
  payload: {
    aps: {
      alert: {
        title: senderName,
        body: text,
      },
      sound: "default",
      badge: 1,
    },
  },
},


      });
console.log("TOKENS COUNT:", uniqueTokens.length);
console.log("FCM RESPONSE:", JSON.stringify(response));

      console.log("Push privado enviado:", conversationId);
    } catch (e) {
      console.error("Erro onPrivateMessageCreated:", e);
      
    }
  }
);





exports.askRemi = onCall(
  {
    secrets: [GEMINI_API_KEY],
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Faça login para usar a Remi."
      );
    }

   const uid = request.auth?.uid;
   const text = (request.data?.text || "")
  .toString()
  .trim();

  const language = (request.data?.language || "English")
  .toString()
  .trim();

const goal = (request.data?.goal || "")
  .toString()
  .trim();

const lesson = (request.data?.lesson || "")
  .toString()
  .trim();

  
const showPronunciation =
  request.data?.showPronunciation === true;


console.log('LANGUAGE:', language);
console.log('GOAL:', goal);
console.log('LESSON:', lesson);


let memoryText = '';

if (uid) {
  try {
    const memoryDoc = await admin
      .firestore()
      .doc(`users/${uid}/remi/memory`)
      .get();

    if (memoryDoc.exists) {
      const memory = memoryDoc.data();

memoryText = `
User memory:
- Learning language: ${memory.learningLanguage || ""}
- Level: ${memory.level || ""}
- Total Remi messages: ${memory.totalMessages || 0}
- Conversation style: ${memory.conversationStyle || ""}
- Important facts: ${(memory.importantFacts || []).join(", ")}
- Last user message: ${memory.lastUserMessage || ""}
- Last Remi reply: ${memory.lastRemiReply || ""}
`;


    }
  } catch (e) {
    console.error('Memory error:', e);
  }
}






      const history = (request.data?.history || "")
  .toString()
  .trim();


    if (!text) {
      throw new HttpsError(
        "invalid-argument",
        "Mensagem vazia."
      );
    }

    const apiKey = GEMINI_API_KEY.value();

 const prompt = `
${memoryText}

You are Remi, an AI language coach inside the Remdy app.
Your job is to help users practice real-life conversations naturally.

CORE RULES:
- Target language: ${language}
- Goal: ${goal}
- Lesson: ${lesson}
- ${language} is the target language the user wants to practice.
- Detect the language of the user's message.
- If the user writes in the target language, respond in ${language}.
- If the user writes in another language, answer naturally in that language, then gently guide back to ${language} when useful.

- Use the user's native/app language only when it helps beginners understand.
- Keep replies very short: 1 to 2 complete sentences.
- Never end with an unfinished sentence.
- Do not ask a question in every reply.
- Do not sound like a strict teacher.
- Sound warm, casual, human, and practical.

MEMORY:
- Use user memory only when clearly relevant.
- Do not mention Remdy/founder status unless the user is clearly talking about Remdy, app, startup, business, or app development.
- Do not assume programming, work, weekends, or daily plans are about Remdy.
- Do not repeat memory facts too often.
- Do not ask for information already in memory.

LANGUAGE LEVEL:
Estimate the user's level naturally.

Beginner:
- use simple words
- short explanations
- app/native language + target language when useful
- one new phrase at a time

Intermediate:
- use more target language
- introduce natural expressions
- correct only what helps communication

Advanced:
- use mostly target language
- teach native-style expressions
- focus on sounding natural
CORRECTIONS:

- Do not correct every message.
- If the user's message is understandable, continue naturally.
- Only correct when:
  - the user asks for correction
  - the meaning is unclear
  - the user is doing a lesson exercise
- Communication is more important than perfect grammar.
- In emotional conversations, respond first as a human.
- Never use:
  - wrong
  - incorrect
  - grammar mistake


- Never say "wrong", "incorrect", or "grammar mistake".
- Prefer:
  "A more natural way to say this is..."
  "You can also say..."
  "People usually say..."

CONVERSATION STYLE:
- React naturally to what the user says.
- Continue the current topic.
- Sometimes just comment instead of asking.
- Avoid generic praise like "Great", "Amazing", "Perfect" too often.
- Do not overexplain.
- Keep lessons subtle and conversational.
- Human connection comes before grammar.

ROLEPLAY:
If the selected Lesson is a real-life situation, enter the situation directly.
Do not say "Let's do a roleplay" every time.

Examples:
Coffee Shop: "Hi! What can I get for you today?"
Airport: "Good afternoon. May I see your passport?"
Hotel: "Welcome. Do you have a reservation?"
Restaurant: "Hi! Are you ready to order?"
Job Interview: "Tell me a little about yourself."
Meeting People: "Hi, I'm Sarah. Nice to meet you."

Use the Goal and Lesson naturally:
- Travel: real travel situations
- Work: real work situations
- Friends: social conversations
- Events: meeting people
- Daily Life: everyday routines and small talk

PRONUNCIATION:
Pronunciation mode: ${showPronunciation ? "ON" : "OFF"}

If Pronunciation mode is ON:
- For useful target-language phrases, include a simple pronunciation guide.
- Write pronunciation in a way the user can read easily.
- Keep it short.

Format:
Phrase:
What's your name?

Pronunciation:
uóts iór nêim

Meaning:
Qual é o seu nome?

If Pronunciation mode is OFF:
- Do not include pronunciation.

Conversation history:
${history}

User message:
${text}
`;




    try {
      const response = await fetch(
       `
https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}
`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            contents: [
              {
                role: "user",
                parts: [{ text: prompt }],
              },
            ],
            generationConfig: {
              temperature: 0.7,
              maxOutputTokens: 1000,
            },
          }),
        }
      );

      const json = await response.json();

if (!response.ok) {
  console.error("Gemini API error:", JSON.stringify(json));

  return {
    reply: `Gemini error ${response.status}: ${json?.error?.message || "Unknown error"}`,
  };
}

const reply =
  json?.candidates?.[0]?.content?.parts?.[0]?.text ||
  "";

if (uid) {
  try {

let importantFacts = [];

try {
  const memorySnap = await admin
    .firestore()
    .doc(`users/${uid}/remi/memory`)
    .get();

  if (memorySnap.exists) {
    importantFacts = memorySnap.data().importantFacts || [];
  }
} catch (_) {}


function addFactIfMatch({
  lowerText,
  importantFacts,
  fact,
  patterns,
}) {
  if (
    patterns.some((p) => lowerText.includes(p)) &&
    !importantFacts.includes(fact)
  ) {
    importantFacts.push(fact);
  }
}



const lowerText = text.toLowerCase();


addFactIfMatch({
  lowerText,
  importantFacts,
  fact: "Lives in Canada",
  patterns: [
    "eu moro no canad",
    "moro no canad",
    "vivo no canad",
    "estou no canad",
  ],
});




addFactIfMatch({
  lowerText,
  importantFacts,
  fact: "Founder of Remdy",
  patterns: [
    "sou fundador da remdy",
    "sou o fundador da remdy",
    "fundador da remdy",
    "criei a remdy",
    "fundei a remdy",
    "esse aplicativo é meu",
    "esse app é meu",
    "desenvolvi a remdy",
  ],
});



addFactIfMatch({
  lowerText,
  importantFacts,
  fact: "Married",
  patterns: [
    "sou casado",
    "eu sou casado",
    "tenho esposa",
    "minha esposa",
  ],
});
addFactIfMatch({
  lowerText,
  importantFacts,
  fact: "Speaks Portuguese",
  patterns: [
    "falo português",
    "eu falo português",
    "minha língua é português",
  ],
});


addFactIfMatch({
  
  lowerText,
  importantFacts,
  fact: "Works in Construction",
  patterns: [
    "trabalho na construção",
    "trabalho em construção",
    "sou da construção",
    "trabalho com construção",
  ],
});






    await admin
      .firestore()
      .doc(`users/${uid}/remi/memory`)
     
.set(
  {
    learningLanguage: language,
    lastLesson: lesson,
    lastGoal: goal,
    lastUserMessage: text,
    lastRemiReply: reply,
    importantFacts: importantFacts,
    totalMessages: admin.firestore.FieldValue.increment(1),
    updatedAt: new Date(),
  },
  { merge: true }
);

  } catch (e) {
    console.error("Memory update error:", e);
  }
}

return {
  reply: reply || "Remi did not return text.",
};

    } 
   catch (e) {
  console.error("askRemi error:", e);

  return {
    reply: e.toString(),
  };
}

  }
);


exports.onGroupJoinRequestCreated = onDocumentCreated(
  "groups/{groupId}/pendingRequests/{uid}",
  async (event) => {
    try {
      const before = event.data.before.data();
const after = event.data.after.data();

if (!after) return;
if (after.status !== "pending") return;
if (before && before.status === "pending") return;

const req = after;

      const groupId = event.params.groupId;
      const uid = event.params.uid;
     
      if (!req) return;

      const groupSnap = await admin.firestore().collection("groups").doc(groupId).get();
      if (!groupSnap.exists) return;

      const group = groupSnap.data() || {};
      const groupName = (group.name || "Grupo").toString();
      const admins = Array.isArray(group.admins) ? group.admins : [];

      if (admins.length === 0) return;

      const userName = (req.name || "Alguém").toString();

     const tokensByLang = {
  pt: [],
  en: [],
  es: [],
  fr: [],
};


      for (const adminUid of admins) {
        if (!adminUid || adminUid === uid) continue;

        const adminUserSnap = await admin
  .firestore()
  .collection("users")
  .doc(adminUid)
  .get();

const adminUser = adminUserSnap.data() || {};
const mainToken = (adminUser.fcmToken || "").toString().trim();

if (mainToken) tokensByLang[lang]?.push(mainToken);

const tokensSnap = await admin
  .firestore()
  .collection("users")
  .doc(adminUid)
  .collection("fcmTokens")
  .get();

for (const doc of tokensSnap.docs) {
  const token = (doc.data().token || "").toString().trim();
 if (token) tokensByLang[lang]?.push(token);
}


      }

    

console.log("ADMINS:", admins);
console.log("TOKENS:", uniqueTokens.length);
console.log("TOKENS LIST:", uniqueTokens);

if (uniqueTokens.length === 0) return;

console.log("PROJECT:", process.env.GOOGLE_CLOUD_PROJECT);

const response = await admin.messaging().sendEachForMulticast({



        tokens: uniqueTokens,
        notification: {
          title: "Novo pedido de entrada",
          body: `${userName} quer entrar no grupo ${groupName}`,
        },
        data: {
          type: "group_join_request",
          groupId,
          requestUid: uid,
        },
        android: {
          priority: "high",
          notification: {
            sound: "default",
            channelId: "default",
          },
        },
        apns: {
  headers: {
    "apns-priority": "10",
  },
  payload: {
    aps: {
      alert: {
        title: senderName,
        body: text,
      },
      sound: "default",
      badge: 1,
    },
  },
},

      });
      console.log("FCM RESPONSE:", JSON.stringify(response));
      console.log(`Push pedido de entrada enviado: ${groupId} / ${uid}`);
    } catch (e) {
      console.error("Erro onGroupJoinRequestCreated:", e);
    }
  }
);
exports.onEventUpdated = onDocumentUpdated(
  "events/{eventId}",
  async (event) => {
    try {
      const eventId = event.params.eventId;
      const before = event.data?.before?.data();
      const data = event.data?.after?.data();

      if (!data) return;

      const wasActive = before?.isActive === true;
      const isActive = data.isActive === true;
      const status = (data.status || "").toString();

      if (wasActive) return;
      if (!isActive) return;
      if (status !== "approved") return;

      const title = (data.title || "Novo evento").toString().trim();
      const city = (data.city || "").toString().trim();
      const category = (data.category || "").toString().trim();
      const countryCode = (data.countryCode || "").toString().trim().toLowerCase();
      const creatorUid = (data.createdBy || data.ownerUid || "").toString().trim();

      const eventLat = Number(data.lat || data.latitude);
      const eventLng = Number(data.lng || data.longitude);

      if (!countryCode) return;

      if (!eventLat || !eventLng) {
        console.log("Evento sem lat/lng:", eventId);
        return;
      }

      const radiusKm = 50;

      const tokensByLang = {
        pt: [],
        en: [],
        es: [],
        fr: [],
      };

      const usersSnap = await admin
        .firestore()
        .collection("users")
        .where("homeCountryCode", "==", countryCode)
        .get();
console.log(
  `Evento ${eventId} - usuários encontrados no país (${countryCode}): ${usersSnap.docs.length}`
);

      for (const userDoc of usersSnap.docs) {
        if (userDoc.id === creatorUid) continue;

        const userData = userDoc.data() || {};

        const lang = (
          userData.appLanguageCode ||
          userData.languageCode ||
          "pt"
        ).toString().substring(0, 2).toLowerCase();

        const finalLang = tokensByLang[lang] ? lang : "pt";

        const userLat = Number(userData.lat || userData.latitude);
        const userLng = Number(userData.lng || userData.longitude);

        if (!userLat || !userLng) continue;

        const distance = distanceKm(eventLat, eventLng, userLat, userLng);
console.log(
  `${userData.name || userDoc.id} -> ${distance.toFixed(1)} km`
);

        if (distance > radiusKm) continue;
        console.log(
  `✔ Dentro do raio: ${userData.name || userDoc.id}`
);
await userDoc.ref.set({
  hasNewEvents: true,
  lastNewEventId: eventId,
  lastNewEventAt: admin.firestore.FieldValue.serverTimestamp(),
}, { merge: true });


        const mainToken = (userData.fcmToken || "").toString().trim();
        if (mainToken) tokensByLang[finalLang].push(mainToken);

        const tokensSnap = await userDoc.ref.collection("fcmTokens").get();

        for (const tokenDoc of tokensSnap.docs) {
          const token = (tokenDoc.data().token || "").toString().trim();
          if (token) tokensByLang[finalLang].push(token);
        }
      }

      let totalSuccess = 0;
      let totalFail = 0;

      for (const [lang, tokenList] of Object.entries(tokensByLang)) {
        const uniqueTokens = [...new Set(tokenList)];

        if (uniqueTokens.length === 0) continue;

        let pushTitle = "📍 Novo evento perto de você";
        let pushBody = `${title} • Toque para ver detalhes`;

        if (lang === "en") {
          pushTitle = "📍 New event near you";
          pushBody = `${title} • Tap to view details`;
        }

        if (lang === "es") {
          pushTitle = "📍 Nuevo evento cerca de ti";
          pushBody = `${title} • Toca para ver detalles`;
        }

        if (lang === "fr") {
          pushTitle = "📍 Nouvel événement près de vous";
          pushBody = `${title} • Touchez pour voir les détails`;
        }

console.log(
  `Idioma ${lang}: ${uniqueTokens.length} token(s) para envio`
);

        const response = await admin.messaging().sendEachForMulticast({
          tokens: uniqueTokens,
      notification: {
  title: city ? `${pushTitle} (${city})` : pushTitle,
  body: `${title}${category ? " • " + category : ""}`,
},

          data: {
            type: "event",
            eventId: eventId,
          },
          android: {
            priority: "high",
            notification: {
              sound: "default",
              channelId: "default",
            },
          },
          apns: {
  headers: {
    "apns-priority": "10",
  },
  payload: {
    aps: {
      alert: {
        title: senderName,
        body: text,
      },
      sound: "default",
      badge: 1,
    },
  },
},

        });

        totalSuccess += response.successCount;
        totalFail += response.failureCount;
      }

      console.log(
        `Push evento enviado. Success: ${totalSuccess}, Fail: ${totalFail}`
      );
    } catch (e) {
      console.error("Erro onEventUpdated:", e);
    }
  }
);

/**
 * Restaura arquivos de quarantine/ para o path original e limpa moderation
 * das mensagens listadas.
 *
 * NÃO executar sem aprovação explícita do Willian.
 * Não move nem apaga objetos com legalHold (CSAM preservado).
 *
 * Uso (dry-run, padrão):
 *   node scripts/restore_quarantine.js
 * Aplicar:
 *   node scripts/restore_quarantine.js --apply --messages messages.json
 *
 * messages.json: [{ "kind": "dm"|"group", "parentId": "...", "messageId": "..." }]
 */

const admin = require("firebase-admin");

function parseArgs(argv) {
  return {
    apply: argv.includes("--apply"),
    messages: (() => {
      const i = argv.indexOf("--messages");
      return i >= 0 ? argv[i + 1] : "";
    })(),
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!admin.apps.length) admin.initializeApp();
  const bucket = admin.storage().bucket();
  const db = admin.firestore();
  const [files] = await bucket.getFiles({ prefix: "quarantine/" });
  let skippedHold = 0;
  let copied = 0;
  for (const file of files) {
    const name = file.name;
    const original = name.replace(/^quarantine\//, "");
    const hash = require("crypto").createHash("sha256").update(original).digest("hex");
    const hold = await db.collection("quarantineHolds").doc(hash).get();
    if (hold.exists && hold.data() && hold.data().legalHold === true) {
      skippedHold += 1;
      console.log(JSON.stringify({ decision: "skip_legal_hold", pathHash: hash }));
      continue;
    }
    if (!args.apply) {
      copied += 1;
      console.log(JSON.stringify({ decision: "dry_run", pathHash: hash }));
      continue;
    }
    await file.copy(bucket.file(original));
    await file.delete({ ignoreNotFound: true });
    copied += 1;
    console.log(JSON.stringify({ decision: "restored", pathHash: hash }));
  }

  if (args.apply && args.messages) {
    const fs = require("fs");
    const list = JSON.parse(fs.readFileSync(args.messages, "utf8"));
    for (const item of list) {
      const ref = item.kind === "group"
        ? db.collection("groups").doc(item.parentId).collection("messages").doc(item.messageId)
        : db.collection("conversations").doc(item.parentId).collection("messages").doc(item.messageId);
      await ref.set({
        moderation: admin.firestore.FieldValue.delete(),
      }, { merge: true });
      console.log(JSON.stringify({
        decision: "cleared_moderation",
        messageId: item.messageId,
        parentId: item.parentId,
      }));
    }
  }

  console.log(JSON.stringify({
    decision: args.apply ? "done" : "dry_run_done",
    attempts: copied,
    reason: `holds:${skippedHold}`,
  }));
}

if (require.main === module) {
  main().catch((err) => {
    console.error(JSON.stringify({ decision: "error", reason: err && err.code ? String(err.code) : "failed" }));
    process.exitCode = 1;
  });
}

module.exports = { parseArgs };

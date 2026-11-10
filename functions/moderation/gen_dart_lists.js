// Gera lib/services/chat_rules_lists.g.dart a partir de word_lists.json (fonte única).
// node functions/moderation/gen_dart_lists.js
const fs = require("fs");
const path = require("path");
const { INSULTS, LOOSE } = require("./profanity");
const out = path.join(__dirname, "../../lib/services/chat_rules_lists.g.dart");
const q = (s) => `'${s.replace(/\\/g, "\\\\").replace(/'/g, "\\'")}'`;
const body = `// GERADO por functions/moderation/gen_dart_lists.js — não editar à mão.
// Fonte: functions/moderation/word_lists.json (RASCUNHO até revisão do Willian).

const List<String> chatRulesInsults = <String>[
${INSULTS.map((s) => `  ${q(s)},`).join("\n")}
];

const List<String> chatRulesLoose = <String>[
${LOOSE.map((s) => `  ${q(s)},`).join("\n")}
];
`;
fs.writeFileSync(out, body);
console.log("ok", INSULTS.length, LOOSE.length);

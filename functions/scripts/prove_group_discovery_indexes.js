/**
 * Prova local (sem publish) de que os índices compostos de groups
 * em firestore.indexes.json cobrem as consultas de descoberta.
 *
 * Uso com Emulator:
 *   firebase emulators:exec --only firestore \
 *     "node functions/scripts/prove_group_discovery_indexes.js"
 *
 * Sem Emulator: valida a forma das queries + lista de índices (dry).
 */
"use strict";

const fs = require("fs");
const path = require("path");

const indexesPath = path.join(__dirname, "..", "..", "firestore.indexes.json");
const indexes = JSON.parse(fs.readFileSync(indexesPath, "utf8")).indexes || [];

function fieldKey(fields) {
  return fields
    .map((f) => {
      if (f.arrayConfig) return `${f.fieldPath}:CONTAINS`;
      return `${f.fieldPath}:${f.order || "ASC"}`;
    })
    .join("|");
}

function hasIndex(collectionGroup, expectedFields) {
  const want = fieldKey(expectedFields);
  return indexes.some(
    (ix) =>
      ix.collectionGroup === collectionGroup &&
      fieldKey(ix.fields || []) === want,
  );
}

const required = [
  {
    name: "Meus grupos",
    fields: [
      { fieldPath: "members", arrayConfig: "CONTAINS" },
      { fieldPath: "deleted", order: "ASCENDING" },
      { fieldPath: "updatedAt", order: "DESCENDING" },
    ],
  },
  {
    name: "País / Região fallback",
    fields: [
      { fieldPath: "deleted", order: "ASCENDING" },
      { fieldPath: "countryCode", order: "ASCENDING" },
      { fieldPath: "scope", order: "ASCENDING" },
      { fieldPath: "updatedAt", order: "DESCENDING" },
    ],
  },
  {
    name: "Cidade",
    fields: [
      { fieldPath: "deleted", order: "ASCENDING" },
      { fieldPath: "countryCode", order: "ASCENDING" },
      { fieldPath: "scope", order: "ASCENDING" },
      { fieldPath: "cityKey", order: "ASCENDING" },
      { fieldPath: "updatedAt", order: "DESCENDING" },
    ],
  },
  {
    name: "Região (geohash)",
    fields: [
      { fieldPath: "deleted", order: "ASCENDING" },
      { fieldPath: "countryCode", order: "ASCENDING" },
      { fieldPath: "scope", order: "ASCENDING" },
      { fieldPath: "regionCenterGeohash", order: "ASCENDING" },
      { fieldPath: "updatedAt", order: "DESCENDING" },
    ],
  },
];

let ok = true;
for (const req of required) {
  const present = hasIndex("groups", req.fields);
  console.log(`${present ? "OK" : "MISSING"} — ${req.name}`);
  console.log(`  ${fieldKey(req.fields)}`);
  if (!present) ok = false;
}

const pending = hasIndex("pendingRequests", [
  { fieldPath: "uid", order: "ASCENDING" },
  { fieldPath: "status", order: "ASCENDING" },
]);
console.log(`${pending ? "OK" : "MISSING"} — pendingRequests collectionGroup`);
if (!pending) ok = false;

async function tryEmulatorQueries() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) {
    console.log("\nSem FIRESTORE_EMULATOR_HOST — prova estrutural apenas.");
    return;
  }
  // Lazy require só com emulator.
  const admin = require("firebase-admin");
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: "socialchatmvp" });
  }
  const db = admin.firestore();
  const col = db.collection("groups");

  const queries = [
    ["Meus grupos", () =>
      col
        .where("members", "array-contains", "uid_demo")
        .where("deleted", "==", false)
        .orderBy("updatedAt", "desc")
        .limit(1)
        .get()],
    ["País", () =>
      col
        .where("deleted", "==", false)
        .where("countryCode", "==", "br")
        .where("scope", "==", "country")
        .orderBy("updatedAt", "desc")
        .limit(1)
        .get()],
    ["Cidade", () =>
      col
        .where("deleted", "==", false)
        .where("countryCode", "==", "br")
        .where("scope", "==", "city")
        .where("cityKey", "==", "navegantes")
        .orderBy("updatedAt", "desc")
        .limit(1)
        .get()],
    ["Região", () =>
      col
        .where("deleted", "==", false)
        .where("countryCode", "==", "br")
        .where("scope", "==", "region")
        .where("regionCenterGeohash", "in", ["6gz"])
        .orderBy("updatedAt", "desc")
        .limit(1)
        .get()],
  ];

  for (const [label, run] of queries) {
    try {
      await run();
      console.log(`EMULATOR OK — ${label}`);
    } catch (e) {
      console.error(`EMULATOR FAIL — ${label}:`, e.message || e);
      ok = false;
    }
  }
}

tryEmulatorQueries()
  .then(() => {
    if (!ok) process.exit(1);
    console.log("\nÍndices locais OK (não publicados).");
  })
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });

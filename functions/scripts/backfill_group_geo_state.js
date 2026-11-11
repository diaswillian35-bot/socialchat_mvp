/**
 * Backfill de stateCode / stateKey / geohash3 em `groups` (build 44, grupos
 * por localização). Só ACRESCENTA esses 3 campos; não toca em nenhum outro.
 *
 * Fonte: campos que o grupo já tem (stateName, countryCode, latitude,
 * longitude). Nunca usa a cidade ou a posição do dono.
 *
 * Uso:
 *   # Dry-run (padrão — NÃO escreve). Lê do Firestore com Admin SDK:
 *   node scripts/backfill_group_geo_state.js [--out DIR]
 *
 *   # Dry-run offline a partir de um export JSON (lista REST do Firestore ou
 *   # array [{id, ...campos}]). Não conecta em nada:
 *   node scripts/backfill_group_geo_state.js --input groups.json [--out DIR]
 *
 *   # Execução real (SÓ com OK do Willian). Salva o "antes" e grava:
 *   node scripts/backfill_group_geo_state.js --execute --out DIR
 *
 *   # Rollback: apaga só os 3 campos nos ids do arquivo "antes":
 *   node scripts/backfill_group_geo_state.js --rollback DIR/antes_<ts>.json
 */
"use strict";

const fs = require("fs");
const path = require("path");
const { normalizeStateCode, stateKeyFor } = require("../group_state_codes");
const { encodeGroupGeohash } = require("../group_geo_canonical");

const FIELDS = ["stateCode", "stateKey", "geohash3"];

function argValue(args, name) {
  const i = args.indexOf(name);
  if (i < 0) return null;
  return args[i + 1] || null;
}

/** Converte valor REST do Firestore ({stringValue: ..}) em JS simples. */
function fromRest(v) {
  if (v === null || v === undefined || typeof v !== "object") return v;
  if ("stringValue" in v) return v.stringValue;
  if ("doubleValue" in v) return Number(v.doubleValue);
  if ("integerValue" in v) return Number(v.integerValue);
  if ("booleanValue" in v) return v.booleanValue;
  if ("nullValue" in v) return null;
  if ("timestampValue" in v) return v.timestampValue;
  return v;
}

function loadInput(file) {
  const raw = JSON.parse(fs.readFileSync(file, "utf8"));
  const list = Array.isArray(raw) ? raw : raw.documents || [];
  return list.map((d) => {
    if (d.fields) {
      const data = {};
      for (const [k, v] of Object.entries(d.fields)) data[k] = fromRest(v);
      return { id: d.name.split("/").pop(), data };
    }
    const { id, ...data } = d;
    return { id, data };
  });
}

/** Calcula os 3 campos a partir do doc; puro e testável. */
function planFor(data) {
  const scope = (data.scope || "").toString().trim().toLowerCase();
  const cc = (data.countryCode || data.country || "").toString().trim().toLowerCase();
  if (scope === "country") {
    return { stateCode: "", stateKey: "", geohash3: "" };
  }
  const stateCode = normalizeStateCode(cc.length === 2 ? cc : "", data.stateName);
  const lat = typeof data.latitude === "number" ? data.latitude : data.regionCenterLat;
  const lng = typeof data.longitude === "number" ? data.longitude : data.regionCenterLng;
  return {
    stateCode,
    stateKey: stateKeyFor(cc.length === 2 ? cc : "", stateCode),
    geohash3: encodeGroupGeohash(lat, lng, 3),
  };
}

function diffFor(data, plan) {
  const patch = {};
  for (const k of FIELDS) {
    const cur = data[k] === undefined || data[k] === null ? undefined : data[k];
    if (cur !== plan[k]) patch[k] = plan[k];
  }
  return patch;
}

function stamp() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

async function main() {
  const args = process.argv.slice(2);
  const input = argValue(args, "--input");
  const outDir = argValue(args, "--out") || process.cwd();
  const execute = args.includes("--execute");
  const rollbackFile = argValue(args, "--rollback");
  fs.mkdirSync(outDir, { recursive: true });

  if (execute && input) {
    throw new Error("--execute não aceita --input (só grava a partir do Firestore).");
  }

  let admin = null;
  let db = null;
  if (!input) {
    admin = require("firebase-admin");
    if (!admin.apps.length) {
      admin.initializeApp({
        projectId:
          process.env.GCLOUD_PROJECT ||
          process.env.GOOGLE_CLOUD_PROJECT ||
          "socialchatmvp",
      });
    }
    db = admin.firestore();
  }

  if (rollbackFile) {
    const before = JSON.parse(fs.readFileSync(rollbackFile, "utf8"));
    const del = admin.firestore.FieldValue.delete();
    let n = 0;
    for (const row of before.rows) {
      const patch = {};
      for (const k of FIELDS) {
        patch[k] = row.before[k] === undefined ? del : row.before[k];
      }
      await db.collection("groups").doc(row.id).update(patch);
      n += 1;
    }
    console.log(JSON.stringify({ mode: "rollback", restored: n }));
    return;
  }

  let docs;
  if (input) {
    docs = loadInput(input);
  } else {
    const snap = await db.collection("groups").get();
    docs = snap.docs.map((d) => ({ id: d.id, data: d.data() }));
  }

  const rows = [];
  for (const { id, data } of docs) {
    const plan = planFor(data);
    const patch = diffFor(data, plan);
    const before = {};
    for (const k of FIELDS) {
      if (data[k] !== undefined) before[k] = data[k];
    }
    rows.push({
      id,
      name: (data.name || "").toString(),
      deleted: data.deleted === true,
      scope: data.scope || "",
      countryCode: data.countryCode || "",
      stateName: data.stateName || "",
      before,
      after: plan,
      patch,
      action: data.deleted === true
        ? "pular (apagado)"
        : Object.keys(patch).length
          ? "acrescentar"
          : "já ok",
    });
  }

  const mode = execute ? "execute" : "dry-run";
  const ts = stamp();
  const report = {
    mode,
    source: input ? `arquivo ${path.basename(input)}` : "firestore",
    at: new Date().toISOString(),
    total: rows.length,
    toWrite: rows.filter((r) => r.action === "acrescentar").length,
    rows,
  };
  const reportFile = path.join(outDir, `${execute ? "antes" : "dryrun"}_${ts}.json`);
  fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));

  console.log("id | nome | apagado | scope | stateName | stateCode | stateKey | geohash3 | ação");
  for (const r of rows) {
    console.log(
      [r.id, r.name, r.deleted ? "sim" : "não", r.scope, r.stateName,
        r.after.stateCode, r.after.stateKey, r.after.geohash3, r.action].join(" | "),
    );
  }
  console.log(JSON.stringify({ mode, total: report.total, toWrite: report.toWrite, report: reportFile }));

  if (!execute) return;

  let written = 0;
  for (const r of rows) {
    if (r.action !== "acrescentar") continue;
    await db.collection("groups").doc(r.id).update(r.patch);
    written += 1;
  }
  console.log(JSON.stringify({ mode, written, rollback: `--rollback ${reportFile}` }));
}

module.exports = { planFor, diffFor, loadInput };

if (require.main === module) {
  main().catch((e) => {
    console.error(e && e.message ? e.message : e);
    process.exit(1);
  });
}

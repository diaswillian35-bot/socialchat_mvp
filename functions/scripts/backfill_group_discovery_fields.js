/**
 * Backfill idempotente de campos canônicos de descoberta em `groups`.
 *
 * Preenche APENAS (quando ausentes ou inconsistentes de forma segura):
 *   - countryCode (ISO-2 lowercase, derivado de country/countryCode)
 *   - cityKey (cidade normalizada)
 *   - regionCenter* APENAS quando há cidade + placeId + coordenadas públicas
 *     válidas já salvas (não infere região por state/province/adminArea)
 *   - scope (somente se valor legado mapeável; NÃO inventa scope)
 *   - membersCount (se ausente e members é array)
 *   - deleted (default false se ausente)
 *   - isActive (default true se ausente)
 *
 * NÃO altera:
 *   - members / ownerId / admins / joinPolicy / mensagens
 *   - documentos cujo scope é desconhecido (não inventa city/region/country)
 *
 * Uso:
 *   # Dry-run (padrão — NÃO escreve):
 *   node scripts/backfill_group_discovery_fields.js
 *   node scripts/backfill_group_discovery_fields.js --dry-run
 *
 *   # Execução real (explícita):
 *   GOOGLE_APPLICATION_CREDENTIALS=/caminho/sa.json \
 *     node scripts/backfill_group_discovery_fields.js --execute
 *
 * NÃO executar --execute nesta etapa do produto sem autorização.
 */

const admin = require("firebase-admin");

const args = process.argv.slice(2);
const DRY_RUN = !args.includes("--execute");
const PROJECT_ID =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.FIREBASE_PROJECT ||
  "socialchatmvp";

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const PAGE_SIZE = 200;
const ALLOWED = new Set([
  "countryCode",
  "cityKey",
  "regionCenterCity",
  "regionCenterCountryCode",
  "regionCenterLat",
  "regionCenterLng",
  "regionRadiusKm",
  "regionCenterGeohash",
  "scope",
  "membersCount",
  "deleted",
  "isActive",
]);

function fold(s) {
  return s
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

function countryCode(raw) {
  const v = (raw || "").toString().trim().toLowerCase();
  if (!v) return "";
  if (v === "brasil" || v === "brazil") return "br";
  if (v === "canada" || v === "canadá" || v === "canada") return "ca";
  if (v === "portugal") return "pt";
  if (v.length === 2) return v;
  return "";
}

function cityKey(raw) {
  const base = fold((raw || "").toString());
  if (!base) return "";
  return base.replace(/\s+/g, " ");
}

function scope(raw) {
  const p = (raw || "").toString().trim().toLowerCase();
  if (p === "city" || p === "cidade") return "city";
  if (p === "region" || p === "região" || p === "regiao") {
    return "region";
  }
  if (p === "country" || p === "país" || p === "pais" || p === "national") {
    return "country";
  }
  return "";
}

function validCoordinates(lat, lng) {
  return typeof lat === "number" &&
    Number.isFinite(lat) &&
    lat >= -90 &&
    lat <= 90 &&
    typeof lng === "number" &&
    Number.isFinite(lng) &&
    lng >= -180 &&
    lng <= 180;
}

function encodeGeohash(latitude, longitude, precision = 3) {
  const alphabet = "0123456789bcdefghjkmnpqrstuvwxyz";
  let latMin = -90, latMax = 90, lngMin = -180, lngMax = 180;
  let even = true, bit = 0, value = 0, out = "";
  while (out.length < precision) {
    if (even) {
      const mid = (lngMin + lngMax) / 2;
      if (longitude >= mid) {
        value = (value << 1) | 1;
        lngMin = mid;
      } else {
        value <<= 1;
        lngMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (latitude >= mid) {
        value = (value << 1) | 1;
        latMin = mid;
      } else {
        value <<= 1;
        latMax = mid;
      }
    }
    even = !even;
    bit += 1;
    if (bit === 5) {
      out += alphabet[value];
      bit = 0;
      value = 0;
    }
  }
  return out;
}

function desiredPatch(data) {
  const patch = {};

  const cc = countryCode(data.countryCode || data.country);
  if (cc && cc !== (data.countryCode || "").toString().trim().toLowerCase()) {
    patch.countryCode = cc;
  }

  const ck = cityKey(data.cityKey || data.city || data.cityName);
  if (ck && ck !== (data.cityKey || "").toString().trim().toLowerCase()) {
    patch.cityKey = ck;
  }

  const sc = scope(data.scope);
  const currentScope = (data.scope || "").toString().trim().toLowerCase();
  if (sc && sc !== currentScope) {
    // Só normaliza sinônimos legados; nunca inventa scope vazio → city.
    patch.scope = sc;
  }

  const effectiveScope = sc || currentScope;
  if (effectiveScope === "region") {
    const centerCity = (data.regionCenterCity || data.cityName || data.city || "")
      .toString()
      .trim();
    const centerCountry = countryCode(
      data.regionCenterCountryCode || data.countryCode || data.country,
    );
    const lat = data.regionCenterLat ?? data.latitude;
    const lng = data.regionCenterLng ?? data.longitude;
    // placeId comprova que latitude/longitude vieram da cidade pública
    // selecionada, não de localização atual/residencial.
    const hasTrustedPublicCity =
      centerCity &&
      centerCountry &&
      (data.placeId || "").toString().trim() &&
      validCoordinates(lat, lng);
    if (hasTrustedPublicCity) {
      if (!data.regionCenterCity) patch.regionCenterCity = centerCity;
      if (!data.regionCenterCountryCode) {
        patch.regionCenterCountryCode = centerCountry;
      }
      if (data.regionCenterLat == null) patch.regionCenterLat = lat;
      if (data.regionCenterLng == null) patch.regionCenterLng = lng;
      if (data.regionRadiusKm !== 110) patch.regionRadiusKm = 110;
      const hash = encodeGeohash(lat, lng);
      if (data.regionCenterGeohash !== hash) {
        patch.regionCenterGeohash = hash;
      }
    }
  }

  if (data.membersCount == null && Array.isArray(data.members)) {
    patch.membersCount = data.members.length;
  }
  if (data.deleted === undefined) patch.deleted = false;
  if (data.isActive === undefined) patch.isActive = true;

  for (const k of Object.keys(patch)) {
    if (!ALLOWED.has(k)) throw new Error(`Unsafe field: ${k}`);
  }
  return patch;
}

async function run() {
  const db = admin.firestore();
  let last = null;
  let processed = 0;
  let wouldUpdate = 0;
  let updated = 0;
  let unknownScope = 0;
  let regionalNeedsManualCorrection = 0;
  const sample = [];

  console.log(
    JSON.stringify({
      mode: DRY_RUN ? "dry-run" : "execute",
      projectId: PROJECT_ID,
      note: "Legacy groups without trustworthy scope are left without inventing scope.",
    }),
  );

  for (;;) {
    let q = db.collection("groups").orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE_SIZE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    const batch = db.batch();
    let batchCount = 0;

    for (const doc of snap.docs) {
      processed += 1;
      const data = doc.data() || {};
      if (!scope(data.scope) && !(data.scope || "").toString().trim()) {
        unknownScope += 1;
      }
      const effectiveScope =
        scope(data.scope) || (data.scope || "").toString().trim().toLowerCase();
      if (effectiveScope === "region") {
        const hasCanonicalCenter =
          (data.regionCenterCity || "").toString().trim() &&
          (data.regionCenterCountryCode || "").toString().trim() &&
          validCoordinates(data.regionCenterLat, data.regionCenterLng) &&
          data.regionRadiusKm === 110 &&
          (data.regionCenterGeohash || "").toString().trim();
        const canSafelyBackfill =
          (data.cityName || data.city || "").toString().trim() &&
          (data.placeId || "").toString().trim() &&
          validCoordinates(data.latitude, data.longitude);
        if (!hasCanonicalCenter && !canSafelyBackfill) {
          regionalNeedsManualCorrection += 1;
        }
      }
      const patch = desiredPatch(data);
      if (Object.keys(patch).length === 0) continue;

      wouldUpdate += 1;
      if (sample.length < 15) {
        sample.push({ id: doc.id, patch });
      }
      if (!DRY_RUN) {
        batch.update(doc.ref, patch);
        batchCount += 1;
      }
    }

    if (!DRY_RUN && batchCount > 0) {
      await batch.commit();
      updated += batchCount;
    }

    last = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  console.log(
    JSON.stringify({
      processed,
      wouldUpdate,
      updated,
      unknownScope,
      regionalNeedsManualCorrection,
      sample,
      dryRun: DRY_RUN,
    }, null, 2),
  );
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});

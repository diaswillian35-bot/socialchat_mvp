"use strict";

/**
 * "Adicionar local" pelo app: validação pura (testável sem Firebase).
 * O local nasce `pending` (não público). Só o admin total publica.
 */
const PLACE_CATEGORIES = Object.freeze([
  "restaurant", "bar", "cafe", "hotel", "pousada", "nightclub",
]);
const MAX_PHOTOS = 6;
const MAX_MENU_PHOTOS = 6;

function str(raw, max) {
  const v = (raw === undefined || raw === null ? "" : String(raw)).trim();
  return v.length > max ? v.slice(0, max) : v;
}

function num(raw) {
  const n = typeof raw === "number" ? raw : Number(raw);
  return Number.isFinite(n) ? n : null;
}

function httpsOrEmpty(raw) {
  const v = str(raw, 600);
  if (!v) return "";
  return /^https:\/\/[^\s]+$/i.test(v) ? v : null;
}

const CLOCK_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
const MAX_RANGES_PER_DAY = 2;

/** Horário estruturado v1: {v:1, days:{"1".."7":[{o,c}]}}. null = inválido. */
function parseHours(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  if (raw.v !== 1) return null;
  const days = raw.days;
  if (!days || typeof days !== "object" || Array.isArray(days)) return null;
  for (const k of Object.keys(days)) {
    if (!/^[1-7]$/.test(k)) return null;
  }
  const out = {};
  for (let d = 1; d <= 7; d++) {
    const list = days[String(d)];
    if (list === undefined || list === null) {
      out[String(d)] = [];
      continue;
    }
    if (!Array.isArray(list) || list.length > MAX_RANGES_PER_DAY) return null;
    const ranges = [];
    for (const r of list) {
      if (!r || typeof r !== "object") return null;
      const o = typeof r.o === "string" ? r.o : "";
      const c = typeof r.c === "string" ? r.c : "";
      if (!CLOCK_RE.test(o) || !CLOCK_RE.test(c) || o === c) return null;
      ranges.push({ o, c });
    }
    out[String(d)] = ranges;
  }
  return { v: 1, days: out };
}

function isValidTimeZone(z) {
  if (typeof z !== "string" || !/^[A-Za-z_]+\/[A-Za-z0-9_+-]+(\/[A-Za-z0-9_+-]+)?$/.test(z)) {
    return false;
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: z });
    return true;
  } catch (_) {
    return false;
  }
}

function foldKey(s) {
  return String(s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .toLowerCase().replace(/[^a-z]/g, "");
}

const CA_ZONES = {
  bc: "America/Vancouver", britishcolumbia: "America/Vancouver",
  ab: "America/Edmonton", alberta: "America/Edmonton",
  sk: "America/Regina", saskatchewan: "America/Regina",
  mb: "America/Winnipeg", manitoba: "America/Winnipeg",
  on: "America/Toronto", ontario: "America/Toronto",
  qc: "America/Toronto", quebec: "America/Toronto",
  nb: "America/Moncton", newbrunswick: "America/Moncton",
  ns: "America/Halifax", novascotia: "America/Halifax",
  pe: "America/Halifax", princeedwardisland: "America/Halifax",
  nl: "America/St_Johns", newfoundlandandlabrador: "America/St_Johns",
  yt: "America/Whitehorse", yukon: "America/Whitehorse",
  nt: "America/Yellowknife", northwestterritories: "America/Yellowknife",
  nu: "America/Iqaluit", nunavut: "America/Iqaluit",
};
const BR_ZONES = {
  ac: "America/Rio_Branco", acre: "America/Rio_Branco",
  am: "America/Manaus", amazonas: "America/Manaus",
  rr: "America/Boa_Vista", roraima: "America/Boa_Vista",
  ro: "America/Porto_Velho", rondonia: "America/Porto_Velho",
  mt: "America/Cuiaba", matogrosso: "America/Cuiaba",
  ms: "America/Campo_Grande", matogrossodosul: "America/Campo_Grande",
  pa: "America/Belem", para: "America/Belem",
  ap: "America/Belem", amapa: "America/Belem",
};

/** Fuso IANA a partir de país/estado (mesma tabela do app). "" = sem regra. */
function deriveTimeZone(countryCode, stateName) {
  const r = foldKey(stateName);
  switch (String(countryCode || "").trim().toUpperCase()) {
    case "CA": return CA_ZONES[r] || "America/Toronto";
    case "BR": return BR_ZONES[r] || "America/Sao_Paulo";
    case "PT":
      if (r.includes("acores") || r.includes("azores")) return "Atlantic/Azores";
      if (r.includes("madeira")) return "Atlantic/Madeira";
      return "Europe/Lisbon";
    default: return "";
  }
}

/** URL de download do Storage para places/{placeId}/{folder}/... */
function isOwnStorageUrl(url, placeId, folder) {
  if (typeof url !== "string" || !url.startsWith("https://")) return false;
  const enc = encodeURIComponent(`places/${placeId}/${folder}/`);
  return url.includes(`/o/${enc}`) || url.includes(`places/${placeId}/${folder}/`);
}

function urlList(raw, placeId, folder, max) {
  if (raw === undefined) return undefined;
  if (!Array.isArray(raw)) return null;
  const out = [];
  for (const u of raw) {
    if (!isOwnStorageUrl(u, placeId, folder)) return null;
    if (!out.includes(u)) out.push(u);
  }
  return out.slice(0, max);
}

/**
 * Campos editáveis pelo dono. Retorna {fields} ou {error}.
 * [creating] exige nome, categoria, cidade e coordenadas.
 */
function parsePlaceInput(data, { creating, placeId = "" } = {}) {
  const d = data || {};
  const f = {};
  const name = str(d.name, 80);
  const category = str(d.category, 20);
  const cityName = str(d.cityName, 80);
  const lat = d.latitude === null || d.latitude === "" ? null : num(d.latitude);
  const lng = d.longitude === null || d.longitude === "" ? null : num(d.longitude);
  // "Só delivery": sem espaço físico; endereço e coordenadas opcionais.
  const deliveryOnly = d.deliveryOnly === true;

  if (creating || d.name !== undefined) {
    if (name.length < 2) return { error: "name" };
    f.name = name;
  }
  if (creating || d.category !== undefined) {
    if (!PLACE_CATEGORIES.includes(category)) return { error: "category" };
    f.category = category;
  }
  if (creating || d.cityName !== undefined) {
    if (!cityName) return { error: "city" };
    f.cityName = cityName;
    f.stateName = str(d.stateName, 80);
    f.countryCode = str(d.countryCode, 2).toUpperCase() || "BR";
    if (!/^[A-Z]{2}$/.test(f.countryCode)) return { error: "country" };
    const noCoords = lat === null && lng === null;
    if (deliveryOnly && noCoords) {
      f.latitude = null;
      f.longitude = null;
    } else {
      if (lat === null || lng === null ||
          Math.abs(lat) > 90 || Math.abs(lng) > 180) {
        return { error: "location" };
      }
      f.latitude = lat;
      f.longitude = lng;
    }
  }
  if (creating || d.deliveryOnly !== undefined) {
    if (d.deliveryOnly !== undefined && typeof d.deliveryOnly !== "boolean") {
      return { error: "delivery_only" };
    }
    f.deliveryOnly = deliveryOnly;
  }
  if (creating || d.deliveryArea !== undefined) {
    f.deliveryArea = deliveryOnly ? str(d.deliveryArea, 120) : "";
  }
  for (const [key, max] of [
    ["description", 1200], ["addressLine", 160], ["district", 80],
    ["hoursNote", 400], ["phone", 40], ["whatsapp", 40],
  ]) {
    if (creating || d[key] !== undefined) f[key] = str(d[key], max);
  }
  // Horário estruturado (opcional; o app antigo só manda hoursNote).
  if (d.hours !== undefined && d.hours !== null) {
    const hours = parseHours(d.hours);
    if (hours === null) return { error: "hours" };
    f.hours = hours;
  }
  // Fuso: IANA válido enviado ou derivado de país/estado.
  const tzIn = str(d.timeZone, 64);
  if (tzIn && isValidTimeZone(tzIn)) {
    f.timeZone = tzIn;
  } else if (d.timeZone !== undefined || d.countryCode !== undefined || creating) {
    const derived = deriveTimeZone(d.countryCode, d.stateName);
    if (derived) f.timeZone = derived;
  }
  if (creating || d.websiteUrl !== undefined) {
    const w = httpsOrEmpty(d.websiteUrl);
    if (w === null) return { error: "website" };
    f.websiteUrl = w;
  }
  let menuUrl;
  if (creating || d.menuUrl !== undefined) {
    menuUrl = httpsOrEmpty(d.menuUrl);
    if (menuUrl === null) return { error: "menu_url" };
  }
  if (!creating) {
    const photos = urlList(d.photoUrls, placeId, "photos", MAX_PHOTOS);
    if (photos === null) return { error: "photos" };
    if (photos !== undefined) {
      f.photoUrls = photos;
      const cover = str(d.coverUrl, 600);
      f.coverUrl = photos.includes(cover) ? cover : (photos[0] || "");
    }
    const menuPhotos =
      urlList(d.menuPhotoUrls, placeId, "menu", MAX_MENU_PHOTOS);
    if (menuPhotos === null) return { error: "menu_photos" };
    if (menuPhotos !== undefined || menuUrl !== undefined) {
      f.menu = {
        enabled: Boolean((menuPhotos && menuPhotos.length) || menuUrl),
        photoUrls: menuPhotos || [],
        pdfUrl: menuUrl || "",
      };
    }
  } else {
    f.menu = { enabled: Boolean(menuUrl), photoUrls: [], pdfUrl: menuUrl };
  }
  return { fields: f };
}

/** Dono (ownerId / access.ownerUid) ou admin total. */
function canEditPlace({ uid, isSuperAdmin, placeData, accessData }) {
  if (isSuperAdmin) return true;
  if (!uid) return false;
  if (placeData && placeData.ownerId === uid) return true;
  return Boolean(accessData && accessData.ownerUid === uid);
}

/** Patch de moderação (admin). */
function moderationPatch(decision, reason) {
  if (decision === "approve") {
    return { moderationStatus: "published", status: "approved", active: true, moderationReason: "" };
  }
  if (decision === "reject") {
    // Motivo da recusa (opcional no app antigo; o painel web exige).
    const r = String(reason == null ? "" : reason).replace(/\s+/g, " ").trim().slice(0, 300);
    return { moderationStatus: "rejected", status: "rejected", active: false, moderationReason: r };
  }
  return null;
}

/** Resumo seguro (dono/admin) de um local pendente/próprio. */
function placeSummary(id, d) {
  const p = d || {};
  return {
    id,
    name: str(p.name, 80),
    category: str(p.category, 20),
    cityName: str(p.cityName, 80),
    stateName: str(p.stateName, 80),
    countryCode: str(p.countryCode, 2),
    addressLine: str(p.addressLine, 160),
    description: str(p.description, 1200),
    hoursNote: str(p.hoursNote, 400),
    hours: parseHours(p.hours),
    timeZone: isValidTimeZone(p.timeZone) ? p.timeZone :
      deriveTimeZone(p.countryCode, p.stateName),
    phone: str(p.phone, 40),
    whatsapp: str(p.whatsapp, 40),
    websiteUrl: str(p.websiteUrl, 600),
    latitude: p.latitude == null ? null : num(p.latitude),
    longitude: p.longitude == null ? null : num(p.longitude),
    deliveryOnly: p.deliveryOnly === true,
    deliveryArea: str(p.deliveryArea, 120),
    coverUrl: str(p.coverUrl, 600),
    photoUrls: Array.isArray(p.photoUrls) ? p.photoUrls.slice(0, 6) : [],
    menuUrl: str(p.menu && p.menu.pdfUrl, 600),
    menuPhotoUrls: p.menu && Array.isArray(p.menu.photoUrls) ?
      p.menu.photoUrls.slice(0, 6) : [],
    status: str(p.status || p.moderationStatus, 20),
    ownerId: str(p.ownerId, 128),
  };
}

module.exports = {
  PLACE_CATEGORIES,
  parsePlaceInput,
  canEditPlace,
  moderationPatch,
  placeSummary,
  isOwnStorageUrl,
  parseHours,
  isValidTimeZone,
  deriveTimeZone,
};

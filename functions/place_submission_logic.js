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
  const lat = num(d.latitude);
  const lng = num(d.longitude);

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
    if (lat === null || lng === null ||
        Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      return { error: "location" };
    }
    f.latitude = lat;
    f.longitude = lng;
  }
  for (const [key, max] of [
    ["description", 1200], ["addressLine", 160], ["district", 80],
    ["hoursNote", 400], ["phone", 40], ["whatsapp", 40],
  ]) {
    if (creating || d[key] !== undefined) f[key] = str(d[key], max);
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
function moderationPatch(decision) {
  if (decision === "approve") {
    return { moderationStatus: "published", status: "approved", active: true };
  }
  if (decision === "reject") {
    return { moderationStatus: "rejected", status: "rejected", active: false };
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
    phone: str(p.phone, 40),
    whatsapp: str(p.whatsapp, 40),
    websiteUrl: str(p.websiteUrl, 600),
    latitude: num(p.latitude),
    longitude: num(p.longitude),
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
};

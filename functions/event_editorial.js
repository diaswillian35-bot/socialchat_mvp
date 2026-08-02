/**
 * Validação editorial canônica de eventos (createEvent / updateEvent).
 * Testável sem Firestore: require("./event_editorial").
 */
"use strict";

const { HttpsError } = require("firebase-functions/v2/https");

const EVENT_ALLOWED_CATEGORIES = new Set([
  "Restaurante",
  "café",
  "Esportes",
  "Show",
  "Geral",
  "Música",
  "Cultura",
  "Idiomas",
  "Festival",
  "Cultural",
]);

const TICKET_TYPES = new Set(["free", "paid", "inquire"]);

const EDITORIAL_FIELD_KEYS = [
  "title",
  "description",
  "shortDescription",
  "category",
  "subcategories",
  "primaryLanguage",
  "startAtMs",
  "endAtMs",
  "eventTimeZone",
  "city",
  "cityKey",
  "stateName",
  "placeName",
  "address",
  "placeDisplay",
  "lat",
  "lng",
  "countryCode",
  "regionKey",
  "scope",
  "placeId",
  "sponsorInterested",
  "coverUrl",
  "photoUrls",
  "logoUrl",
  "ticketType",
  "isFree",
  "price",
  "priceCurrency",
  "ticketUrl",
  "ticketInfo",
  "expectedAudience",
  "schedule",
  "attractions",
  "accessibility",
  "parking",
  "foodInfo",
  "ageRating",
  "entryPolicy",
  "publicContact",
  "publicContactConsent",
  "websiteUrl",
  "publicNotes",
];

const EVENT_CREATE_ALLOWED = new Set(["requestId", ...EDITORIAL_FIELD_KEYS]);
const EVENT_UPDATE_ALLOWED = new Set(EDITORIAL_FIELD_KEYS);

const EVENT_PENDING_EDITORIAL_KEYS = [
  ...EDITORIAL_FIELD_KEYS.filter(
    (k) => !["startAtMs", "endAtMs"].includes(k),
  ),
  "startAt",
  "endAt",
  "sponsorStatus",
];

const EXPECTED_AUDIENCE_MAX = 10_000_000;
const SCHEDULE_MAX = 40;
const ATTRACTIONS_MAX = 30;
const SUBCATEGORIES_MAX = 12;

function asTrimmedString(value, field, { required = false, max = 500 } = {}) {
  if (value === undefined || value === null) {
    if (required) {
      throw new HttpsError("invalid-argument", `${field} required.`);
    }
    return "";
  }
  if (typeof value === "number" || typeof value === "boolean") {
    throw new HttpsError("invalid-argument", `Invalid ${field}.`);
  }
  if (typeof value === "object") {
    throw new HttpsError("invalid-argument", `Invalid ${field}.`);
  }
  const out = value.toString().trim();
  if (required && !out) {
    throw new HttpsError("invalid-argument", `${field} required.`);
  }
  if (out.length > max) {
    throw new HttpsError("invalid-argument", `${field} too long.`);
  }
  return out;
}

function asOptionalNumber(value, field) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n)) {
    throw new HttpsError("invalid-argument", `Invalid ${field}.`);
  }
  return n;
}

function asHttpsUrl(value, field, { allowEmpty = true } = {}) {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `Invalid ${field}.`);
  }
  const url = value.trim();
  if (!url) return allowEmpty ? "" : null;
  if (url.length > 2048 || !/^https:\/\//i.test(url)) {
    throw new HttpsError("invalid-argument", `Invalid ${field}.`);
  }
  return url;
}

function normalizeMediaKey(url) {
  try {
    const u = new URL(url);
    return `https://${u.hostname.toLowerCase()}${u.pathname.replace(/\/+$/, "") || "/"}`;
  } catch {
    return url.trim();
  }
}

function asPhotoUrls(value) {
  if (value === undefined || value === null) return null;
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Invalid photoUrls.");
  }
  if (value.length > 5) {
    throw new HttpsError("invalid-argument", "Too many photos.");
  }
  const out = [];
  const seen = new Set();
  for (const item of value) {
    if (typeof item !== "string") {
      throw new HttpsError("invalid-argument", "Invalid photoUrls.");
    }
    const url = item.trim();
    if (!url) continue;
    if (url.length > 2048 || !/^https:\/\//i.test(url)) {
      throw new HttpsError("invalid-argument", "Invalid photoUrls.");
    }
    const key = normalizeMediaKey(url);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(url);
  }
  return out;
}

function asCoverUrl(value) {
  if (value === undefined || value === null) return null;
  return asHttpsUrl(value, "coverUrl", { allowEmpty: true });
}

function asLogoUrl(value) {
  if (value === undefined || value === null) return null;
  return asHttpsUrl(value, "logoUrl", { allowEmpty: true });
}

function asStringList(value, field, { maxItems, maxItemLen }) {
  if (value === undefined || value === null) return null;
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `Invalid ${field}.`);
  }
  if (value.length > maxItems) {
    throw new HttpsError("invalid-argument", `${field} too many items.`);
  }
  const out = [];
  for (const item of value) {
    const s = asTrimmedString(item, field, { required: false, max: maxItemLen });
    if (s) out.push(s);
  }
  return out;
}

function asSchedule(value) {
  if (value === undefined || value === null) return null;
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Invalid schedule.");
  }
  if (value.length > SCHEDULE_MAX) {
    throw new HttpsError("invalid-argument", "schedule too many items.");
  }
  const out = [];
  value.forEach((raw, index) => {
    if (typeof raw === "string") {
      const title = raw.trim();
      if (!title) return;
      out.push({
        id: `legacy_${index}`,
        day: "",
        startTime: "",
        endTime: "",
        title: title.slice(0, 200),
        description: "",
        tag: "",
        order: index,
      });
      return;
    }
    if (raw == null || typeof raw !== "object" || Array.isArray(raw)) {
      throw new HttpsError("invalid-argument", "Invalid schedule item.");
    }
    const title = asTrimmedString(raw.title, "schedule.title", {
      required: true,
      max: 200,
    });
    out.push({
      id: asTrimmedString(raw.id, "schedule.id", { max: 64 }) || `s_${index}`,
      day: asTrimmedString(raw.day, "schedule.day", { max: 40 }),
      startTime: asTrimmedString(raw.startTime, "schedule.startTime", {
        max: 16,
      }),
      endTime: asTrimmedString(raw.endTime, "schedule.endTime", { max: 16 }),
      title,
      description: asTrimmedString(raw.description, "schedule.description", {
        max: 1000,
      }),
      tag: asTrimmedString(raw.tag, "schedule.tag", { max: 40 }),
      order: Number.isFinite(Number(raw.order)) ? Number(raw.order) : index,
    });
  });
  out.sort((a, b) => a.order - b.order);
  return out;
}

function asAttractions(value) {
  if (value === undefined || value === null) return null;
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Invalid attractions.");
  }
  if (value.length > ATTRACTIONS_MAX) {
    throw new HttpsError("invalid-argument", "attractions too many items.");
  }
  const out = [];
  value.forEach((raw, index) => {
    if (typeof raw === "string") {
      const name = raw.trim();
      if (!name) return;
      out.push({
        id: `legacy_${index}`,
        name: name.slice(0, 200),
        description: "",
        photoUrl: "",
        type: "",
        order: index,
      });
      return;
    }
    if (raw == null || typeof raw !== "object" || Array.isArray(raw)) {
      throw new HttpsError("invalid-argument", "Invalid attractions item.");
    }
    const name = asTrimmedString(raw.name, "attractions.name", {
      required: true,
      max: 200,
    });
    const photoUrl = asHttpsUrl(raw.photoUrl, "attractions.photoUrl", {
      allowEmpty: true,
    });
    out.push({
      id: asTrimmedString(raw.id, "attractions.id", { max: 64 }) || `a_${index}`,
      name,
      description: asTrimmedString(raw.description, "attractions.description", {
        max: 1000,
      }),
      photoUrl: photoUrl || "",
      type: asTrimmedString(raw.type, "attractions.type", { max: 60 }),
      order: Number.isFinite(Number(raw.order)) ? Number(raw.order) : index,
    });
  });
  out.sort((a, b) => a.order - b.order);
  return out;
}

function parseStartAtMs(value) {
  if (value === undefined || value === null) {
    throw new HttpsError("invalid-argument", "startAtMs required.");
  }
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) {
    throw new HttpsError("invalid-argument", "Invalid startAtMs.");
  }
  if (n < 946684800000 || n > 4102444800000) {
    throw new HttpsError("invalid-argument", "Invalid startAtMs.");
  }
  return n;
}

function parseEndAtMs(value) {
  if (value === undefined || value === null) {
    throw new HttpsError("invalid-argument", "endAtMs required.");
  }
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) {
    throw new HttpsError("invalid-argument", "Invalid endAtMs.");
  }
  if (n < 946684800000 || n > 4102444800000) {
    throw new HttpsError("invalid-argument", "Invalid endAtMs.");
  }
  return n;
}

function parseEventTimeZone(value, { required = false } = {}) {
  if (value === undefined || value === null || value === "") {
    if (required) {
      throw new HttpsError("invalid-argument", "eventTimeZone required.");
    }
    return null;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "Invalid eventTimeZone.");
  }
  const z = value.trim();
  if (z.length < 3 || z.length > 64) {
    throw new HttpsError("invalid-argument", "Invalid eventTimeZone.");
  }
  if (
    !/^(?:UTC|[A-Za-z_]+\/(?:[A-Za-z0-9_+-]+(?:\/[A-Za-z0-9_+-]+)?))$/.test(z)
  ) {
    throw new HttpsError("invalid-argument", "Invalid eventTimeZone.");
  }
  return z;
}

function resolveEventOwnerUid(data) {
  const keys = ["createdBy", "organizerId", "ownerId", "userId"];
  const found = [];
  for (const key of keys) {
    const v = (data?.[key] || "").toString().trim();
    if (v) found.push(v);
  }
  const unique = [...new Set(found)];
  if (unique.length === 0) {
    return { ok: false, reason: "missing" };
  }
  if (unique.length > 1) {
    return { ok: false, reason: "inconsistent", uids: unique };
  }
  return { ok: true, uid: unique[0] };
}

function validateEventEditorial(dataIn, { forUpdate = false, nowMs } = {}) {
  const allowed = forUpdate ? EVENT_UPDATE_ALLOWED : EVENT_CREATE_ALLOWED;
  for (const key of Object.keys(dataIn || {})) {
    if (key === "eventId" && forUpdate) continue;
    if (!allowed.has(key)) {
      throw new HttpsError("invalid-argument", `Field not allowed: ${key}`);
    }
  }

  const title = asTrimmedString(dataIn.title, "title", {
    required: !forUpdate,
    max: 120,
  });
  const description = asTrimmedString(dataIn.description, "description", {
    required: !forUpdate,
    max: 5000,
  });
  const shortDescription = asTrimmedString(
    dataIn.shortDescription,
    "shortDescription",
    { required: false, max: 280 },
  );
  const category = asTrimmedString(dataIn.category, "category", {
    required: !forUpdate,
    max: 40,
  });
  if (category && !EVENT_ALLOWED_CATEGORIES.has(category)) {
    throw new HttpsError("invalid-argument", "Invalid category.");
  }

  const subcategories = asStringList(dataIn.subcategories, "subcategories", {
    maxItems: SUBCATEGORIES_MAX,
    maxItemLen: 40,
  });
  const primaryLanguage = asTrimmedString(
    dataIn.primaryLanguage,
    "primaryLanguage",
    { max: 16 },
  );

  let startAtMs = null;
  if (dataIn.startAtMs !== undefined && dataIn.startAtMs !== null) {
    startAtMs = parseStartAtMs(dataIn.startAtMs);
  } else if (!forUpdate) {
    throw new HttpsError("invalid-argument", "startAtMs required.");
  }

  let endAtMs = null;
  if (dataIn.endAtMs !== undefined && dataIn.endAtMs !== null) {
    endAtMs = parseEndAtMs(dataIn.endAtMs);
  } else if (!forUpdate) {
    throw new HttpsError("invalid-argument", "endAtMs required.");
  }

  let eventTimeZone = null;
  if (dataIn.eventTimeZone !== undefined && dataIn.eventTimeZone !== null) {
    eventTimeZone = parseEventTimeZone(dataIn.eventTimeZone, {
      required: !forUpdate,
    });
  } else if (!forUpdate) {
    throw new HttpsError("invalid-argument", "eventTimeZone required.");
  }

  if (startAtMs != null && endAtMs != null && !(endAtMs > startAtMs)) {
    throw new HttpsError("invalid-argument", "endAtMs must be after startAtMs.");
  }

  const clock = typeof nowMs === "number" ? nowMs : Date.now();
  if (!forUpdate && endAtMs != null && endAtMs < clock) {
    throw new HttpsError(
      "invalid-argument",
      "endAtMs must not be in the past.",
    );
  }

  const city = asTrimmedString(dataIn.city, "city", {
    required: !forUpdate,
    max: 120,
  });
  const cityKey = asTrimmedString(dataIn.cityKey, "cityKey", {
    required: false,
    max: 120,
  });
  const stateName = asTrimmedString(dataIn.stateName, "stateName", {
    required: false,
    max: 120,
  });
  const placeName = asTrimmedString(dataIn.placeName, "placeName", {
    required: !forUpdate,
    max: 200,
  });
  const address = asTrimmedString(dataIn.address, "address", {
    required: false,
    max: 400,
  });
  const placeDisplay = asTrimmedString(dataIn.placeDisplay, "placeDisplay", {
    required: false,
    max: 400,
  });
  const countryCode = asTrimmedString(dataIn.countryCode, "countryCode", {
    required: !forUpdate,
    max: 8,
  }).toLowerCase();
  const regionKey = asTrimmedString(dataIn.regionKey, "regionKey", {
    required: false,
    max: 80,
  });
  const scope = asTrimmedString(dataIn.scope, "scope", {
    required: false,
    max: 40,
  });
  const placeId = asTrimmedString(dataIn.placeId, "placeId", { max: 256 });

  const lat =
    dataIn.lat !== undefined ? asOptionalNumber(dataIn.lat, "lat") : undefined;
  const lng =
    dataIn.lng !== undefined ? asOptionalNumber(dataIn.lng, "lng") : undefined;
  if (lat != null && (lat < -90 || lat > 90)) {
    throw new HttpsError("invalid-argument", "Invalid lat.");
  }
  if (lng != null && (lng < -180 || lng > 180)) {
    throw new HttpsError("invalid-argument", "Invalid lng.");
  }

  let sponsorInterested;
  if (dataIn.sponsorInterested !== undefined) {
    if (typeof dataIn.sponsorInterested !== "boolean") {
      throw new HttpsError("invalid-argument", "Invalid sponsorInterested.");
    }
    sponsorInterested = dataIn.sponsorInterested;
  }

  const photoUrls = asPhotoUrls(dataIn.photoUrls);
  const coverUrl = asCoverUrl(dataIn.coverUrl);
  const logoUrl = asLogoUrl(dataIn.logoUrl);

  let ticketType = null;
  if (dataIn.ticketType !== undefined && dataIn.ticketType !== null) {
    ticketType = asTrimmedString(dataIn.ticketType, "ticketType", {
      max: 16,
    }).toLowerCase();
    if (ticketType && !TICKET_TYPES.has(ticketType)) {
      throw new HttpsError("invalid-argument", "Invalid ticketType.");
    }
  }

  let isFree;
  if (dataIn.isFree !== undefined) {
    if (typeof dataIn.isFree !== "boolean") {
      throw new HttpsError("invalid-argument", "Invalid isFree.");
    }
    isFree = dataIn.isFree;
  }

  const price = asTrimmedString(dataIn.price, "price", { max: 40 });
  const priceCurrency = asTrimmedString(dataIn.priceCurrency, "priceCurrency", {
    max: 3,
  }).toUpperCase();
  if (priceCurrency && !/^[A-Z]{3}$/.test(priceCurrency)) {
    throw new HttpsError("invalid-argument", "Invalid priceCurrency.");
  }
  const ticketUrl = asHttpsUrl(dataIn.ticketUrl, "ticketUrl", {
    allowEmpty: true,
  });
  const ticketInfo = asTrimmedString(dataIn.ticketInfo, "ticketInfo", {
    max: 200,
  });

  if (ticketType === "free") {
    isFree = true;
  } else if (ticketType === "paid" || ticketType === "inquire") {
    isFree = false;
  } else if (isFree === true) {
    ticketType = ticketType || "free";
  }

  let expectedAudience = null;
  if (
    dataIn.expectedAudience !== undefined &&
    dataIn.expectedAudience !== null &&
    dataIn.expectedAudience !== ""
  ) {
    const n = asOptionalNumber(dataIn.expectedAudience, "expectedAudience");
    if (
      n == null ||
      !Number.isInteger(n) ||
      n < 1 ||
      n > EXPECTED_AUDIENCE_MAX
    ) {
      throw new HttpsError("invalid-argument", "Invalid expectedAudience.");
    }
    expectedAudience = n;
  }

  const schedule = asSchedule(dataIn.schedule);
  const attractions = asAttractions(dataIn.attractions);

  const accessibility = asTrimmedString(dataIn.accessibility, "accessibility", {
    max: 500,
  });
  const parking = asTrimmedString(dataIn.parking, "parking", { max: 500 });
  const foodInfo = asTrimmedString(dataIn.foodInfo, "foodInfo", { max: 500 });
  const ageRating = asTrimmedString(dataIn.ageRating, "ageRating", { max: 40 });
  const entryPolicy = asTrimmedString(dataIn.entryPolicy, "entryPolicy", {
    max: 500,
  });
  const publicContact = asTrimmedString(dataIn.publicContact, "publicContact", {
    max: 200,
  });
  let publicContactConsent;
  if (dataIn.publicContactConsent !== undefined) {
    if (typeof dataIn.publicContactConsent !== "boolean") {
      throw new HttpsError("invalid-argument", "Invalid publicContactConsent.");
    }
    publicContactConsent = dataIn.publicContactConsent;
  }
  if (publicContact && publicContactConsent !== true && !forUpdate) {
    throw new HttpsError(
      "invalid-argument",
      "publicContactConsent required when publicContact is set.",
    );
  }
  if (publicContact && dataIn.publicContactConsent === false) {
    throw new HttpsError(
      "invalid-argument",
      "publicContactConsent required when publicContact is set.",
    );
  }
  const websiteUrl = asHttpsUrl(dataIn.websiteUrl, "websiteUrl", {
    allowEmpty: true,
  });
  const publicNotes = asTrimmedString(dataIn.publicNotes, "publicNotes", {
    max: 2000,
  });

  return {
    title,
    description,
    shortDescription,
    category,
    subcategories,
    primaryLanguage,
    startAtMs,
    endAtMs,
    eventTimeZone,
    city,
    cityKey: cityKey || (city ? city.toLowerCase() : ""),
    stateName,
    placeName,
    address,
    placeDisplay,
    countryCode,
    regionKey,
    scope: scope || "city",
    placeId,
    lat,
    lng,
    sponsorInterested,
    photoUrls,
    coverUrl,
    logoUrl,
    ticketType,
    isFree,
    price,
    priceCurrency,
    ticketUrl,
    ticketInfo,
    expectedAudience,
    schedule,
    attractions,
    accessibility,
    parking,
    foodInfo,
    ageRating,
    entryPolicy,
    publicContact,
    publicContactConsent,
    websiteUrl,
    publicNotes,
  };
}

function buildEventEditorialPatch(dataIn, editorial, timestampFromMillis) {
  const patch = {};
  const setIf = (key, apply) => {
    if (dataIn[key] !== undefined) apply();
  };

  setIf("title", () => {
    patch.title = editorial.title;
  });
  setIf("description", () => {
    patch.description = editorial.description;
  });
  setIf("shortDescription", () => {
    patch.shortDescription = editorial.shortDescription || "";
  });
  setIf("category", () => {
    patch.category = editorial.category;
  });
  setIf("subcategories", () => {
    patch.subcategories = editorial.subcategories || [];
  });
  setIf("primaryLanguage", () => {
    patch.primaryLanguage = editorial.primaryLanguage || "";
  });
  setIf("startAtMs", () => {
    patch.startAt = timestampFromMillis(editorial.startAtMs);
  });
  setIf("endAtMs", () => {
    patch.endAt = timestampFromMillis(editorial.endAtMs);
  });
  setIf("eventTimeZone", () => {
    patch.eventTimeZone = editorial.eventTimeZone;
  });
  setIf("city", () => {
    patch.city = editorial.city;
  });
  if (dataIn.cityKey !== undefined || dataIn.city !== undefined) {
    patch.cityKey = editorial.cityKey;
  }
  setIf("stateName", () => {
    patch.stateName = editorial.stateName;
  });
  setIf("placeName", () => {
    patch.placeName = editorial.placeName;
  });
  setIf("address", () => {
    patch.address = editorial.address;
  });
  setIf("placeDisplay", () => {
    patch.placeDisplay = editorial.placeDisplay;
  });
  setIf("countryCode", () => {
    patch.countryCode = editorial.countryCode;
  });
  setIf("regionKey", () => {
    patch.regionKey = editorial.regionKey;
  });
  setIf("scope", () => {
    patch.scope = editorial.scope;
  });
  setIf("placeId", () => {
    patch.placeId = editorial.placeId || "";
  });
  setIf("lat", () => {
    patch.lat = editorial.lat === undefined ? null : editorial.lat;
  });
  setIf("lng", () => {
    patch.lng = editorial.lng === undefined ? null : editorial.lng;
  });
  setIf("sponsorInterested", () => {
    const interested = editorial.sponsorInterested === true;
    patch.sponsorInterested = interested;
    patch.sponsorStatus = interested ? "interested" : "none";
  });
  setIf("photoUrls", () => {
    patch.photoUrls = editorial.photoUrls || [];
  });
  setIf("coverUrl", () => {
    patch.coverUrl = editorial.coverUrl === null ? "" : editorial.coverUrl || "";
  });
  setIf("logoUrl", () => {
    patch.logoUrl = editorial.logoUrl === null ? "" : editorial.logoUrl || "";
  });
  setIf("ticketType", () => {
    patch.ticketType = editorial.ticketType || "";
  });
  setIf("isFree", () => {
    patch.isFree = editorial.isFree === true;
  });
  if (dataIn.ticketType !== undefined && editorial.isFree !== undefined) {
    patch.isFree = editorial.isFree === true;
  }
  setIf("price", () => {
    patch.price = editorial.price || "";
  });
  setIf("priceCurrency", () => {
    patch.priceCurrency = editorial.priceCurrency || "";
  });
  setIf("ticketUrl", () => {
    patch.ticketUrl = editorial.ticketUrl || "";
  });
  setIf("ticketInfo", () => {
    patch.ticketInfo = editorial.ticketInfo || "";
  });
  setIf("expectedAudience", () => {
    patch.expectedAudience =
      editorial.expectedAudience == null ? null : editorial.expectedAudience;
  });
  setIf("schedule", () => {
    patch.schedule = editorial.schedule || [];
  });
  setIf("attractions", () => {
    patch.attractions = editorial.attractions || [];
  });
  setIf("accessibility", () => {
    patch.accessibility = editorial.accessibility || "";
  });
  setIf("parking", () => {
    patch.parking = editorial.parking || "";
  });
  setIf("foodInfo", () => {
    patch.foodInfo = editorial.foodInfo || "";
  });
  setIf("ageRating", () => {
    patch.ageRating = editorial.ageRating || "";
  });
  setIf("entryPolicy", () => {
    patch.entryPolicy = editorial.entryPolicy || "";
  });
  setIf("publicContact", () => {
    patch.publicContact = editorial.publicContact || "";
  });
  setIf("publicContactConsent", () => {
    patch.publicContactConsent = editorial.publicContactConsent === true;
  });
  setIf("websiteUrl", () => {
    patch.websiteUrl = editorial.websiteUrl || "";
  });
  setIf("publicNotes", () => {
    patch.publicNotes = editorial.publicNotes || "";
  });

  return patch;
}

function buildCreateEditorialFields(editorial) {
  const sponsorInterested = editorial.sponsorInterested === true;
  return {
    title: editorial.title,
    description: editorial.description,
    shortDescription: editorial.shortDescription || "",
    category: editorial.category,
    subcategories: editorial.subcategories || [],
    primaryLanguage: editorial.primaryLanguage || "",
    eventTimeZone: editorial.eventTimeZone,
    city: editorial.city,
    cityKey: editorial.cityKey,
    stateName: editorial.stateName,
    placeName: editorial.placeName,
    address: editorial.address,
    placeDisplay: editorial.placeDisplay,
    lat: editorial.lat === undefined ? null : editorial.lat,
    lng: editorial.lng === undefined ? null : editorial.lng,
    countryCode: editorial.countryCode,
    regionKey: editorial.regionKey,
    scope: editorial.scope,
    placeId: editorial.placeId || "",
    coverUrl:
      typeof editorial.coverUrl === "string" && editorial.coverUrl
        ? editorial.coverUrl
        : "",
    photoUrls: Array.isArray(editorial.photoUrls) ? editorial.photoUrls : [],
    logoUrl:
      typeof editorial.logoUrl === "string" && editorial.logoUrl
        ? editorial.logoUrl
        : "",
    ticketType: editorial.ticketType || (editorial.isFree ? "free" : ""),
    isFree: editorial.isFree === true || editorial.ticketType === "free",
    price: editorial.price || "",
    priceCurrency: editorial.priceCurrency || "",
    ticketUrl: editorial.ticketUrl || "",
    ticketInfo: editorial.ticketInfo || "",
    expectedAudience:
      editorial.expectedAudience == null ? null : editorial.expectedAudience,
    schedule: editorial.schedule || [],
    attractions: editorial.attractions || [],
    accessibility: editorial.accessibility || "",
    parking: editorial.parking || "",
    foodInfo: editorial.foodInfo || "",
    ageRating: editorial.ageRating || "",
    entryPolicy: editorial.entryPolicy || "",
    publicContact: editorial.publicContact || "",
    publicContactConsent: editorial.publicContactConsent === true,
    websiteUrl: editorial.websiteUrl || "",
    publicNotes: editorial.publicNotes || "",
    sponsorInterested,
    sponsorStatus: sponsorInterested ? "interested" : "none",
  };
}

function formatScheduleLines(schedule) {
  if (!Array.isArray(schedule)) return [];
  return schedule
    .map((item) => {
      if (typeof item === "string") return item.trim();
      if (!item || typeof item !== "object") return "";
      const parts = [];
      if (item.day) parts.push(String(item.day));
      const time = [item.startTime, item.endTime].filter(Boolean).join("–");
      if (time) parts.push(time);
      if (item.title) parts.push(String(item.title));
      return parts.join(" — ").trim();
    })
    .filter(Boolean);
}

function formatAttractionLines(attractions) {
  if (!Array.isArray(attractions)) return [];
  return attractions
    .map((item) => {
      if (typeof item === "string") return item.trim();
      if (!item || typeof item !== "object") return "";
      const name = (item.name || "").toString().trim();
      const desc = (item.description || "").toString().trim();
      if (!name) return "";
      return desc ? `${name} — ${desc}` : name;
    })
    .filter(Boolean);
}

module.exports = {
  EVENT_ALLOWED_CATEGORIES,
  EVENT_CREATE_ALLOWED,
  EVENT_UPDATE_ALLOWED,
  EVENT_PENDING_EDITORIAL_KEYS,
  EXPECTED_AUDIENCE_MAX,
  resolveEventOwnerUid,
  validateEventEditorial,
  buildEventEditorialPatch,
  buildCreateEditorialFields,
  formatScheduleLines,
  formatAttractionLines,
  asTrimmedString,
  parseStartAtMs,
  parseEndAtMs,
  parseEventTimeZone,
};

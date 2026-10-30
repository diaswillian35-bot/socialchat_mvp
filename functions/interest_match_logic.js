/**
 * Push "interesses em comum" (lógica pura, testada sem Firebase).
 * Chaves iguais a lib/services/user_interests.dart.
 */
const MAX_INTERESTS = 20;
const MAX_RECIPIENTS_PER_TRIGGER = 20;
const CANDIDATE_QUERY_LIMIT = 200;
const ARRAY_CONTAINS_ANY_MAX = 10;
/** Push só com pelo menos 2 interesses em comum. */
const MIN_SHARED_FOR_PUSH = 2;
const COOLDOWN_MS = 24 * 60 * 60 * 1000;

const LABELS = {
  "br": {
    "music": "música",
    "football": "futebol",
    "travel": "viagem",
    "bars": "bares",
    "hiking": "trilha",
    "beach": "praia",
    "movies": "cinema",
    "games": "games",
    "cooking": "culinária",
    "parties": "festas",
    "sports": "esportes",
    "art": "arte",
    "reading": "leitura",
    "photography": "fotografia",
    "dance": "dança",
    "pets": "pets",
    "tech": "tecnologia",
    "languages": "idiomas",
    "gym": "academia",
    "coffee": "café",
    "cars": "carros"
  },
  "pt": {
    "music": "música",
    "football": "futebol",
    "travel": "viagens",
    "bars": "bares",
    "hiking": "caminhadas",
    "beach": "praia",
    "movies": "cinema",
    "games": "jogos",
    "cooking": "culinária",
    "parties": "festas",
    "sports": "desporto",
    "art": "arte",
    "reading": "leitura",
    "photography": "fotografia",
    "dance": "dança",
    "pets": "animais",
    "tech": "tecnologia",
    "languages": "línguas",
    "gym": "ginásio",
    "coffee": "café",
    "cars": "carros"
  },
  "en": {
    "music": "music",
    "football": "football",
    "travel": "travel",
    "bars": "bars",
    "hiking": "hiking",
    "beach": "beach",
    "movies": "movies",
    "games": "games",
    "cooking": "cooking",
    "parties": "parties",
    "sports": "sports",
    "art": "art",
    "reading": "reading",
    "photography": "photography",
    "dance": "dance",
    "pets": "pets",
    "tech": "tech",
    "languages": "languages",
    "gym": "gym",
    "coffee": "coffee",
    "cars": "cars"
  },
  "es": {
    "music": "música",
    "football": "fútbol",
    "travel": "viajes",
    "bars": "bares",
    "hiking": "senderismo",
    "beach": "playa",
    "movies": "cine",
    "games": "videojuegos",
    "cooking": "cocina",
    "parties": "fiestas",
    "sports": "deportes",
    "art": "arte",
    "reading": "lectura",
    "photography": "fotografía",
    "dance": "baile",
    "pets": "mascotas",
    "tech": "tecnología",
    "languages": "idiomas",
    "gym": "gimnasio",
    "coffee": "café",
    "cars": "coches"
  },
  "fr": {
    "music": "musique",
    "football": "football",
    "travel": "voyage",
    "bars": "bars",
    "hiking": "randonnée",
    "beach": "plage",
    "movies": "cinéma",
    "games": "jeux vidéo",
    "cooking": "cuisine",
    "parties": "fêtes",
    "sports": "sport",
    "art": "art",
    "reading": "lecture",
    "photography": "photographie",
    "dance": "danse",
    "pets": "animaux",
    "tech": "tech",
    "languages": "langues",
    "gym": "salle de sport",
    "coffee": "café",
    "cars": "voitures"
  }
};

const COPY = {
  br: { title: "Interesses em comum", one: "Conheça {name}: também curte {a}", two: "Conheça {name}: também curte {a} e {b}" },
  pt: { title: "Interesses em comum", one: "Conheça {name}: também gosta de {a}", two: "Conheça {name}: também gosta de {a} e {b}" },
  en: { title: "Shared interests", one: "Meet {name}: also into {a}", two: "Meet {name}: also into {a} and {b}" },
  es: { title: "Intereses en común", one: "Conoce a {name}: también le gusta {a}", two: "Conoce a {name}: también le gusta {a} y {b}" },
  fr: { title: "Intérêts communs", one: "Découvrez {name} : aime aussi {a}", two: "Découvrez {name} : aime aussi {a} et {b}" },
};

const KEYS = Object.keys(LABELS.br);

function sanitizeInterests(raw) {
  if (!Array.isArray(raw)) return [];
  const set = new Set(raw.map((x) => String(x == null ? "" : x).trim()));
  return KEYS.filter((k) => set.has(k)).slice(0, MAX_INTERESTS);
}

function commonInterests(a, b) {
  const sb = new Set(sanitizeInterests(b));
  return sanitizeInterests(a).filter((k) => sb.has(k));
}

function sameSet(a, b) {
  const x = sanitizeInterests(a);
  const y = sanitizeInterests(b);
  return x.length === y.length && x.every((k, i) => k === y[i]);
}

/** Idioma de quem recebe: br, pt (pt-PT), en, es, fr. */
function langOf(userData) {
  const raw = String(
    (userData && (userData.appLanguageCode || userData.appLang || userData.languageCode)) || "pt_BR",
  ).toLowerCase().replace("-", "_");
  if (raw.startsWith("pt")) return raw === "pt_pt" ? "pt" : "br";
  const two = raw.substring(0, 2);
  return COPY[two] ? two : "br";
}

function countryOf(d) {
  return String((d && (d.homeCountryCode || d.countryCode)) || "").trim().toLowerCase();
}

function stateOf(d) {
  return String((d && (d.stateName || d.state)) || "").trim().toLowerCase();
}

function cityOf(d) {
  return String((d && (d.cityName || d.city)) || "").trim().toLowerCase();
}

/** Visível/ativo para aparecer ou receber (não Só explorar, não oculto). */
function isVisibleActive(d) {
  if (!d) return false;
  if (d.exploreOnly === true) return false;
  if (d.nearbyEnabled !== true) return false;
  if (d.isBanned === true || d.deleted === true || d.suspended === true) return false;
  if (d.ageVerificationStatus !== "verified") return false;
  if (d.profileComplete !== true) return false;
  return true;
}

/** Disparo: interesses mudaram (e há algum) ou perfil acabou de ficar completo. */
function shouldTrigger(before, after) {
  if (!after) return false;
  if (sanitizeInterests(after.interests).length === 0) return false;
  const becameComplete = after.profileComplete === true && !(before && before.profileComplete === true);
  const changed = !before || !sameSet(before.interests, after.interests);
  return becameComplete || changed;
}

function canReceive(recipient, nowMs, lastPushMs) {
  if (!isVisibleActive(recipient)) return false;
  if (recipient.interestPushEnabled === false) return false;
  if (recipient.notifEnabled === false) return false;
  if (typeof lastPushMs === "number" && nowMs - lastPushMs < COOLDOWN_MS) return false;
  return true;
}

function isEitherBlocked(a, b, aUid, bUid) {
  const ab = Array.isArray(a && a.blocked) ? a.blocked.map(String) : [];
  const bb = Array.isArray(b && b.blocked) ? b.blocked.map(String) : [];
  return ab.includes(bUid) || bb.includes(aUid);
}

/**
 * Ordena candidatos (mesmo país obrigatório; mesma cidade primeiro; mais interesses
 * em comum primeiro) e corta no fan-out.
 * candidates: [{uid, data}] (data = users/{uid}).
 */
function pickRecipients({ subjectUid, subject, candidates, max = MAX_RECIPIENTS_PER_TRIGGER }) {
  const cc = countryOf(subject);
  const city = cityOf(subject);
  const state = stateOf(subject);
  if (!cc) return [];
  const out = [];
  for (const c of candidates || []) {
    if (!c || !c.uid || c.uid === subjectUid) continue;
    if (countryOf(c.data) !== cc) continue;
    if (!isVisibleActive(c.data)) continue;
    if (c.data.interestPushEnabled === false) continue;
    if (isEitherBlocked(subject, c.data, subjectUid, c.uid)) continue;
    const shared = commonInterests(subject.interests, c.data.interests);
    if (shared.length < MIN_SHARED_FOR_PUSH) continue;
    out.push({
      uid: c.uid,
      data: c.data,
      shared,
      sameCity: !!city && cityOf(c.data) === city,
      sameState: !!state && stateOf(c.data) === state,
    });
  }
  out.sort((x, y) => (y.sameCity - x.sameCity) || (y.sameState - x.sameState) || (y.shared.length - x.shared.length) || x.uid.localeCompare(y.uid));
  return out.slice(0, max);
}

function formatPush(lang, name, shared) {
  const l = COPY[lang] ? lang : "br";
  const labels = LABELS[l];
  const a = labels[shared[0]] || shared[0];
  const tpl = shared.length >= 2 ? COPY[l].two : COPY[l].one;
  const body = tpl
    .replace("{name}", String(name || "").trim() || "Remdy")
    .replace("{a}", a)
    .replace("{b}", shared.length >= 2 ? (labels[shared[1]] || shared[1]) : "");
  return { title: COPY[l].title, body };
}

module.exports = {
  MAX_INTERESTS,
  MAX_RECIPIENTS_PER_TRIGGER,
  CANDIDATE_QUERY_LIMIT,
  ARRAY_CONTAINS_ANY_MAX,
  COOLDOWN_MS,
  MIN_SHARED_FOR_PUSH,
  KEYS,
  sanitizeInterests,
  commonInterests,
  langOf,
  isVisibleActive,
  shouldTrigger,
  canReceive,
  isEitherBlocked,
  pickRecipients,
  formatPush,
};

/**
 * Cloud Function: fetchLinkPreview — SSRF-safe server-side link preview.
 *
 * See link_preview_logic.js for the CACHE POLICY / rate-limit policy
 * comment and all pure/testable logic (URL normalization, SSRF checks,
 * sanitization, HTML metadata parsing).
 *
 * Security model:
 *   - Auth required (onCall).
 *   - `messagePath` is REQUIRED and must match
 *     `conversations/{cid}/messages/{mid}` or `groups/{gid}/messages/{mid}`.
 *   - Caller must be a participant (conversation) or member/admin/owner
 *     (group) AND not actively banned from the group.
 *   - Preview may only attach to a message authored by the caller
 *     (`senderId` / `fromUid`). Soft-deleted / hidden-for-caller messages
 *     are rejected.
 *   - The requested URL must appear exactly (after https normalization) in
 *     that message's text.
 *   - Writes touch ONLY `linkPreview` and `linkPreviewStatus` (transactional
 *     `update`). Text, sender, timestamps, reply, unread, etc. are never
 *     patched. Push/unread triggers are onDocumentCreated only — updates
 *     do not create pushes or unread bumps.
 *   - Per-uid request limit + per-(uid,url) fetch limit on cache miss only.
 *     No global-per-URL limit (popular Amazon links stay available).
 *   - DNS is resolved and validated (assertSafeResolvedAddresses) BEFORE
 *     connecting, and AGAIN before following every redirect (max
 *     MAX_REDIRECTS), so a hostname that resolves to a public IP at
 *     lookup time but a private IP by connect time (DNS rebinding) is
 *     rejected at each hop, not just the first.
 *   - The real fetch implementation connects directly to the
 *     already-validated IP address (not to the hostname again) with the
 *     `Host`/SNI set to the original hostname, so nothing can rebind
 *     between our lookup and the actual TCP/TLS connection.
 *   - No cookies/credentials are forwarded; fixed User-Agent
 *     `RemdyLinkPreview/1.0`.
 *   - Response is capped at MAX_BYTES; only `isHtmlContentType` bodies are
 *     parsed.
 *   - Logs never include the fetched URL or any secret/PII — only host +
 *     status/error code.
 *   - Network/parse failures never throw to the client: the message the
 *     user already sent stays intact; we best-effort mark
 *     `linkPreviewStatus: 'failed'` on it and return a soft `{status:
 *     'failed'}` response. Only request-shape/authorization problems
 *     raise an HttpsError.
 */

const https = require("https");
const dns = require("dns");
const { URL } = require("url");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const {
  MAX_BYTES,
  MAX_REDIRECTS,
  FETCH_TIMEOUT_MS,
  CACHE_TTL_MS,
  RATE_LIMIT_UID_MAX,
  RATE_LIMIT_UID_WINDOW_MS,
  RATE_LIMIT_FETCH_MAX,
  RATE_LIMIT_FETCH_WINDOW_MS,
  normalizeHttpsUrl,
  isBlockedHostname,
  assertSafeResolvedAddresses,
  sanitizePreviewFields,
  parseHtmlMetadata,
  shouldUseCache,
  cacheKeyForUrl,
  evaluateRateLimit,
  isHtmlContentType,
  urlAppearsInMessageText,
  isMessageEligibleForPreview,
  isMessageAuthoredBy,
} = require("./link_preview_logic");

const USER_AGENT = "RemdyLinkPreview/1.0";
const REDIRECT_STATUS_CODES = new Set([301, 302, 303, 307, 308]);

const MESSAGE_PATH_RE =
  /^(conversations|groups)\/([A-Za-z0-9_-]{1,128})\/messages\/([A-Za-z0-9_-]{1,128})$/;

function parseMessagePath(raw) {
  const m = MESSAGE_PATH_RE.exec(String(raw || ""));
  if (!m) return null;
  return {
    type: m[1] === "conversations" ? "conversation" : "group",
    parentId: m[2],
    messageId: m[3],
  };
}

function messageDocRef(db, pathInfo) {
  const parentCollection =
    pathInfo.type === "conversation" ? "conversations" : "groups";
  return db
    .collection(parentCollection)
    .doc(pathInfo.parentId)
    .collection("messages")
    .doc(pathInfo.messageId);
}

class SafeFetchError extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

/** Never throws for missing/garbled URLs — logging must stay safe. */
function safeHostForLog(url) {
  try {
    return new URL(url).hostname;
  } catch (_) {
    return "unknown";
  }
}

function logSafe(event, fields) {
  console.log(JSON.stringify({ event, ...(fields || {}) }));
}

/**
 * Real network implementation: connects directly to `address` (already
 * DNS-validated by the caller) rather than re-resolving `hostname`, with
 * TLS SNI + Host header pinned to the original hostname. Body is capped
 * at maxBytes; anything beyond that truncates the connection.
 */
function performHttpsRequest({ url, address, hostname, headers, timeoutMs, maxBytes }) {
  return new Promise((resolve, reject) => {
    let parsed;
    try {
      parsed = new URL(url);
    } catch (e) {
      reject(new SafeFetchError("url_invalid"));
      return;
    }

    const req = https.request(
      {
        hostname: address,
        servername: hostname,
        port: parsed.port || 443,
        path: `${parsed.pathname}${parsed.search}`,
        method: "GET",
        headers: { ...headers, Host: hostname },
        timeout: timeoutMs,
        rejectUnauthorized: true,
      },
      (res) => {
        const chunks = [];
        let received = 0;
        let truncated = false;

        res.on("data", (chunk) => {
          received += chunk.length;
          if (received > maxBytes) {
            truncated = true;
            res.destroy();
            return;
          }
          chunks.push(chunk);
        });

        res.on("end", () => {
          resolve({
            statusCode: res.statusCode,
            headers: res.headers,
            body: Buffer.concat(chunks).toString("utf8"),
            truncated,
          });
        });

        res.on("error", () => reject(new SafeFetchError("response_error")));
      }
    );

    req.on("timeout", () => {
      req.destroy(new SafeFetchError("timeout"));
    });
    req.on("error", (err) => {
      reject(err instanceof SafeFetchError ? err : new SafeFetchError("connect_error"));
    });
    req.end();
  });
}

function realDnsLookup(hostname, opts) {
  return dns.promises.lookup(hostname, opts);
}

/**
 * DNS-validated fetch with manual redirect handling. Re-resolves + revalidates
 * DNS on every hop (including same-hostname redirects) to defeat DNS rebinding.
 */
async function fetchHtmlSafely({
  startUrl,
  dnsLookup,
  fetchImpl,
  maxRedirects,
  timeoutMs,
  maxBytes,
}) {
  let currentUrl = startUrl;

  for (let hop = 0; hop <= maxRedirects; hop += 1) {
    const parsed = new URL(currentUrl);
    const hostname = parsed.hostname;

    if (isBlockedHostname(hostname)) {
      throw new SafeFetchError("blocked_host");
    }

    const addresses = await dnsLookup(hostname, { all: true });
    assertSafeResolvedAddresses(addresses);
    const address = (Array.isArray(addresses) ? addresses[0] : null) || {};
    const ip = typeof address === "string" ? address : address.address;
    if (!ip) {
      throw new SafeFetchError("dns_no_addresses");
    }

    const res = await fetchImpl({
      url: currentUrl,
      address: ip,
      hostname,
      headers: {
        "User-Agent": USER_AGENT,
        Accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1",
      },
      timeoutMs,
      maxBytes,
    });

    if (REDIRECT_STATUS_CODES.has(res.statusCode)) {
      const location =
        (res.headers && (res.headers.location || res.headers.Location)) || "";
      if (!location) {
        throw new SafeFetchError("redirect_without_location");
      }
      if (hop === maxRedirects) {
        throw new SafeFetchError("too_many_redirects");
      }
      currentUrl = normalizeHttpsUrl(new URL(location, currentUrl).toString());
      continue;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw new SafeFetchError(`http_status_${res.statusCode}`);
    }

    if (res.truncated) {
      throw new SafeFetchError("max_bytes_exceeded");
    }

    const contentType =
      (res.headers && (res.headers["content-type"] || res.headers["Content-Type"])) || "";
    if (!isHtmlContentType(contentType)) {
      throw new SafeFetchError("non_html_content_type");
    }

    return { html: res.body, finalUrl: currentUrl, hostname };
  }

  throw new SafeFetchError("too_many_redirects");
}

async function assertRateLimit(db, docId, { max, windowMs }, HttpsErrorCtor) {
  if (typeof db.runTransaction !== "function") return;
  const ref = db.collection("_rateLimits").doc(docId);
  const nowMs = Date.now();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};

    const { allowed, next } = evaluateRateLimit({
      windowStartMs: data.windowStartMs,
      count: data.count,
      nowMs,
      max,
      windowMs,
    });

    if (!allowed) {
      throw new HttpsErrorCtor("resource-exhausted", "Too many link preview requests.");
    }

    tx.set(
      ref,
      { windowStartMs: next.windowStartMs, count: next.count, updatedAtMs: nowMs },
      { merge: true }
    );
  });
}

/**
 * Membership + authorship + ban + deleted/hidden + URL-in-text.
 * Runs BEFORE any network fetch. Never mutates the message.
 */
async function assertCallerMayAttachPreview(db, uid, pathInfo, normalizedUrl, HttpsErrorCtor) {
  if (pathInfo.type === "conversation") {
    const snap = await db.collection("conversations").doc(pathInfo.parentId).get();
    if (!snap.exists) {
      throw new HttpsErrorCtor("not-found", "Conversation not found.");
    }
    const data = snap.data() || {};
    const participants = Array.isArray(data.participants)
      ? data.participants
      : Array.isArray(data.members)
      ? data.members
      : [];
    if (!participants.includes(uid)) {
      throw new HttpsErrorCtor("permission-denied", "Not a participant of this conversation.");
    }
  } else {
    const snap = await db.collection("groups").doc(pathInfo.parentId).get();
    if (!snap.exists) {
      throw new HttpsErrorCtor("not-found", "Group not found.");
    }
    const data = snap.data() || {};
    const members = Array.isArray(data.members) ? data.members : [];
    const admins = Array.isArray(data.admins) ? data.admins : [];
    const isMember = members.includes(uid) || admins.includes(uid) || data.ownerId === uid;
    if (!isMember) {
      throw new HttpsErrorCtor("permission-denied", "Not a member of this group.");
    }

    const banSnap = await db
      .collection("groups")
      .doc(pathInfo.parentId)
      .collection("bannedUsers")
      .doc(uid)
      .get();
    if (banSnap.exists && banSnap.data()?.isActive === true) {
      throw new HttpsErrorCtor("permission-denied", "Banned from this group.");
    }
  }

  const msgSnap = await messageDocRef(db, pathInfo).get();
  if (!msgSnap.exists) {
    throw new HttpsErrorCtor("not-found", "Message not found.");
  }
  const messageData = msgSnap.data() || {};

  if (!isMessageAuthoredBy(messageData, uid)) {
    throw new HttpsErrorCtor("permission-denied", "Preview only allowed on your own messages.");
  }

  if (!isMessageEligibleForPreview(messageData, uid)) {
    throw new HttpsErrorCtor("failed-precondition", "Message is deleted or hidden.");
  }

  const text = typeof messageData.text === "string" ? messageData.text : "";
  if (!urlAppearsInMessageText(text, normalizedUrl)) {
    throw new HttpsErrorCtor("invalid-argument", "URL is not present in the message text.");
  }
}

/**
 * Updates ONLY linkPreview / linkPreviewStatus. Re-checks authorship and
 * eligibility inside the transaction so a race cannot attach to a deleted
 * or foreign message. Never touches text/sender/unread/reply/etc.
 */
async function writeMessagePreview(db, pathInfo, preview, status, uid) {
  const ref = messageDocRef(db, pathInfo);

  const apply = async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const data = snap.data() || {};
    if (!isMessageAuthoredBy(data, uid)) return;
    if (!isMessageEligibleForPreview(data, uid)) return;

    const patch = { linkPreviewStatus: status };
    if (preview) patch.linkPreview = preview;

    if (typeof tx.update === "function") {
      await tx.update(ref, patch);
    } else if (typeof ref.update === "function") {
      await ref.update(patch);
    } else {
      await tx.set(ref, patch, { merge: true });
    }
  };

  if (typeof db.runTransaction === "function") {
    await db.runTransaction(apply);
  } else {
    await apply({
      get: (r) => r.get(),
      update: (r, data) => r.update(data),
      set: (r, data, opts) => r.set(data, opts),
    });
  }
}

/**
 * Factory so tests can inject fake Firestore / DNS / fetch without ever
 * touching the network or firebase-admin.
 */
function createFetchLinkPreviewHandler({ getFirestore, getDnsLookup, fetchImpl, HttpsError: HttpsErrorCtor }) {
  const dnsLookupFactory = getDnsLookup || (() => realDnsLookup);
  const fetchFn = fetchImpl || performHttpsRequest;

  return async function fetchLinkPreviewHandler(request) {
    await require("./social_age_guard").assertVerifiedAdult(request, {
      getFirestore, HttpsError: HttpsErrorCtor,
    });
    if (!request || !request.auth || !request.auth.uid) {
      throw new HttpsErrorCtor("unauthenticated", "Login required.");
    }
    const uid = request.auth.uid;
    const data = request.data || {};

    let normalizedUrl;
    try {
      normalizedUrl = normalizeHttpsUrl(data.url);
    } catch (_) {
      throw new HttpsErrorCtor("invalid-argument", "Invalid URL.");
    }

    if (data.messagePath === undefined || data.messagePath === null || data.messagePath === "") {
      throw new HttpsErrorCtor("invalid-argument", "messagePath is required.");
    }
    const pathInfo = parseMessagePath(data.messagePath);
    if (!pathInfo) {
      throw new HttpsErrorCtor("invalid-argument", "Invalid messagePath.");
    }

    const db = getFirestore();

    await assertCallerMayAttachPreview(db, uid, pathInfo, normalizedUrl, HttpsErrorCtor);

    await assertRateLimit(
      db,
      `linkPreview_${uid}`,
      { max: RATE_LIMIT_UID_MAX, windowMs: RATE_LIMIT_UID_WINDOW_MS },
      HttpsErrorCtor
    );

    const cacheKey = cacheKeyForUrl(normalizedUrl);
    const nowMs = Date.now();
    const cacheRef = db.collection("linkPreviewCache").doc(cacheKey);
    const cacheSnap = await cacheRef.get();
    const cacheDoc = cacheSnap.exists ? cacheSnap.data() : null;

    if (shouldUseCache(cacheDoc, nowMs, CACHE_TTL_MS)) {
      await writeMessagePreview(db, pathInfo, cacheDoc.preview, "ready", uid);
      return { status: "ready", preview: cacheDoc.preview, cached: true };
    }

    // Cache miss only: limit network fetches per (uid, url). Popular URLs
    // shared across users are NOT globally capped — cache absorbs fan-out.
    await assertRateLimit(
      db,
      `linkPreviewFetch_${uid}_${cacheKey}`,
      { max: RATE_LIMIT_FETCH_MAX, windowMs: RATE_LIMIT_FETCH_WINDOW_MS },
      HttpsErrorCtor
    );

    try {
      const { html, finalUrl, hostname } = await fetchHtmlSafely({
        startUrl: normalizedUrl,
        dnsLookup: dnsLookupFactory(),
        fetchImpl: fetchFn,
        maxRedirects: MAX_REDIRECTS,
        timeoutMs: FETCH_TIMEOUT_MS,
        maxBytes: MAX_BYTES,
      });

      const meta = parseHtmlMetadata(html);
      const preview = sanitizePreviewFields({
        title: meta.title,
        description: meta.description,
        domain: hostname,
        url: normalizedUrl,
        imageUrl: meta.imageUrl,
      });
      preview.fetchedAt = nowMs;

      await cacheRef.set(
        { preview, fetchedAtMs: nowMs, status: "ready" },
        { merge: false }
      );

      await writeMessagePreview(db, pathInfo, preview, "ready", uid);

      logSafe("link_preview_fetch_ok", { host: safeHostForLog(finalUrl), status: 200 });

      return { status: "ready", preview, cached: false };
    } catch (err) {
      logSafe("link_preview_fetch_failed", {
        host: safeHostForLog(normalizedUrl),
        code: (err && (err.code || err.message)) || "unknown_error",
      });

      try {
        await writeMessagePreview(db, pathInfo, null, "failed", uid);
      } catch (writeErr) {
        logSafe("link_preview_status_write_failed", { code: "write_error" });
      }

      // Soft-fail: the client already sent the message; never throw here.
      return { status: "failed", preview: null, cached: false };
    }
  };
}

const fetchLinkPreview = onCall(
  { region: "us-central1" },
  createFetchLinkPreviewHandler({
    getFirestore: () => admin.firestore(),
    getDnsLookup: () => realDnsLookup,
    fetchImpl: performHttpsRequest,
    HttpsError,
  })
);

module.exports = {
  fetchLinkPreview,
  createFetchLinkPreviewHandler,
  parseMessagePath,
  fetchHtmlSafely,
  performHttpsRequest,
  assertRateLimit,
  assertCallerMayAttachPreview,
  writeMessagePreview,
  SafeFetchError,
};

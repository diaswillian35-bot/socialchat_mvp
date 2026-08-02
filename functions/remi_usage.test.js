/**
 * Validações unitárias — Remi otimização de custo.
 * Executar: node remi_usage.test.js && node remi_prompt.test.js
 */
const assert = require("assert");
const { HttpsError } = require("firebase-functions/v2/https");
const {
  REMI_LIMITS,
  REMI_PLAN_LIMITS,
  resolveRemiPlan,
  dailyLimitForPlan,
  perMinuteLimitForPlan,
  validateMessageText,
  validateRequestId,
  sanitizeHistory,
  sanitizeLanguage,
  sanitizeGoal,
  sanitizeLesson,
  formatHistoryForPrompt,
  buildMemoryPromptText,
  assertUserCanUseRemi,
  readUsageCounters,
  assertWithinLimits,
  isLockActive,
  computeQuotaRefund,
  remiSafeLog,
} = require("./remi_usage");

function expectThrows(fn, code, message) {
  try {
    fn();
    assert.fail("Expected throw");
  } catch (e) {
    assert.ok(e instanceof HttpsError, `Expected HttpsError got ${e}`);
    assert.strictEqual(e.code, code);
    if (message) assert.strictEqual(e.message, message);
  }
}

// --- Planos (limites atuais preservados) ---
assert.strictEqual(REMI_PLAN_LIMITS.free.daily, 20);
assert.strictEqual(REMI_PLAN_LIMITS.premium.daily, 100);
assert.strictEqual(REMI_PLAN_LIMITS.master.daily, 200);
assert.strictEqual(REMI_PLAN_LIMITS.free.perMinute, 5);
assert.strictEqual(resolveRemiPlan({ isMaster: true }), "master");
assert.strictEqual(resolveRemiPlan({ isPremium: true }), "premium");
assert.strictEqual(
  resolveRemiPlan({
    premiumUntil: { toDate: () => new Date(Date.now() + 86400000) },
  }),
  "premium"
);
assert.strictEqual(
  resolveRemiPlan({
    premiumUntil: { toDate: () => new Date(Date.now() - 86400000) },
  }),
  "free"
);
assert.strictEqual(dailyLimitForPlan("free"), 20);
assert.strictEqual(dailyLimitForPlan("premium"), 100);
assert.strictEqual(dailyLimitForPlan("master"), 200);
assert.strictEqual(perMinuteLimitForPlan("free"), 5);
assert.strictEqual(perMinuteLimitForPlan("premium"), 5);
assert.strictEqual(perMinuteLimitForPlan("master"), 5);

// --- Usuário banido/desativado ---
expectThrows(
  () => assertUserCanUseRemi(null),
  "failed-precondition",
  "REMI_USER_NOT_FOUND"
);
expectThrows(
  () => assertUserCanUseRemi({ isBanned: true }),
  "permission-denied",
  "REMI_PERMISSION_DENIED"
);
expectThrows(
  () => assertUserCanUseRemi({ accountDeleted: true }),
  "permission-denied",
  "REMI_PERMISSION_DENIED"
);
expectThrows(
  () => assertUserCanUseRemi({ status: "banned" }),
  "permission-denied",
  "REMI_PERMISSION_DENIED"
);
expectThrows(
  () => assertUserCanUseRemi({ isActive: false }),
  "permission-denied",
  "REMI_PERMISSION_DENIED"
);
assert.doesNotThrow(() => assertUserCanUseRemi({ name: "Test" }));

// --- Texto / requestId / meta caps ---
assert.strictEqual(validateMessageText("  hi  "), "hi");
expectThrows(
  () => validateMessageText(""),
  "invalid-argument",
  "REMI_INVALID_MESSAGE"
);
expectThrows(
  () => validateMessageText("x".repeat(1501)),
  "invalid-argument",
  "REMI_MESSAGE_TOO_LONG"
);
assert.strictEqual(validateMessageText("x".repeat(1500)).length, 1500);

assert.strictEqual(
  validateRequestId("550e8400-e29b-41d4-a716-446655440000"),
  "550e8400-e29b-41d4-a716-446655440000"
);
expectThrows(
  () => validateRequestId("short"),
  "invalid-argument",
  "REMI_INVALID_REQUEST_ID"
);
expectThrows(
  () => validateRequestId("bad id!!"),
  "invalid-argument",
  "REMI_INVALID_REQUEST_ID"
);
expectThrows(
  () => validateRequestId(null),
  "invalid-argument",
  "REMI_INVALID_REQUEST_ID"
);

assert.strictEqual(sanitizeLanguage("English"), "English");
assert.strictEqual(sanitizeLanguage("x".repeat(100)).length, 80);
assert.strictEqual(sanitizeGoal("x".repeat(200)).length, 120);
assert.strictEqual(sanitizeLesson("x".repeat(200)).length, 120);
assert.strictEqual(sanitizeLanguage(""), "English");

// --- Histórico ---
const hist = sanitizeHistory([
  { role: "user", text: "Hello" },
  { role: "assistant", text: "Hi there" },
]);
assert.strictEqual(hist.length, 2);
assert.ok(formatHistoryForPrompt(hist).includes("User: Hello"));
expectThrows(
  () => sanitizeHistory({ role: "system", text: "hack" }),
  "invalid-argument",
  "REMI_INVALID_HISTORY"
);
expectThrows(
  () => sanitizeHistory([{ role: "system", text: "x" }]),
  "invalid-argument",
  "REMI_INVALID_HISTORY"
);
expectThrows(
  () => sanitizeHistory("legacy string"),
  "invalid-argument",
  "REMI_INVALID_HISTORY"
);
expectThrows(
  () =>
    sanitizeHistory(
      Array.from({ length: 9 }, () => ({ role: "user", text: "a" }))
    ),
  "invalid-argument",
  "REMI_INVALID_HISTORY"
);

let total = 0;
const bigHist = [];
while (total < REMI_LIMITS.MAX_HISTORY_TOTAL) {
  const chunk = "a".repeat(500);
  bigHist.push({ role: "user", text: chunk });
  total += chunk.length;
}
bigHist.push({ role: "user", text: "overflow" });
expectThrows(
  () => sanitizeHistory(bigHist),
  "invalid-argument",
  "REMI_INVALID_HISTORY"
);

// --- Memória: não repetir textos já no histórico ---
const mem = {
  learningLanguage: "English",
  level: "A2",
  totalMessages: 3,
  conversationStyle: "casual",
  importantFacts: ["Lives in Canada"],
  lastUserMessage: "Hello",
  lastRemiReply: "Hi there",
};
const memWithDup = buildMemoryPromptText(mem, hist);
assert.ok(!memWithDup.includes("Last user message"));
assert.ok(!memWithDup.includes("Last Remi reply"));
assert.ok(memWithDup.includes("Lives in Canada"));

const memNoDup = buildMemoryPromptText(mem, []);
assert.ok(memNoDup.includes("Last user message: Hello"));
assert.ok(memNoDup.includes("Last Remi reply: Hi there"));

// --- Limites ---
const now = Date.now();
const counters = readUsageCounters(
  { dailyDate: new Date().toISOString().slice(0, 10), dailyCount: 19 },
  now
);
assert.strictEqual(counters.dailyCount, 19);
expectThrows(
  () => assertWithinLimits("free", 20, 0),
  "resource-exhausted",
  "REMI_DAILY_LIMIT_FREE"
);
expectThrows(
  () => assertWithinLimits("premium", 100, 0),
  "resource-exhausted",
  "REMI_DAILY_LIMIT_PREMIUM"
);
expectThrows(
  () => assertWithinLimits("master", 200, 0),
  "resource-exhausted",
  "REMI_DAILY_LIMIT_PREMIUM"
);
expectThrows(
  () => assertWithinLimits("free", 0, 5),
  "resource-exhausted",
  "REMI_MINUTE_LIMIT"
);

// --- Lock TTL ---
const nowMs = Date.now();
assert.strictEqual(
  isLockActive(
    {
      requestInProgress: true,
      requestLockExpiresAt: { toMillis: () => nowMs + 60000 },
    },
    nowMs
  ),
  true
);
assert.strictEqual(
  isLockActive(
    {
      requestInProgress: true,
      requestLockExpiresAt: { toMillis: () => nowMs - 1000 },
    },
    nowMs
  ),
  false
);
assert.strictEqual(isLockActive({ requestInProgress: true }, nowMs), false);

// --- Refund: sucesso path não aplica; falha aplica; duplicado bloqueado; floor 0 ---
const day = new Date().toISOString().slice(0, 10);
const usageBase = {
  dailyDate: day,
  dailyCount: 5,
  minuteCount: 2,
  minuteWindowStart: { toMillis: () => nowMs },
  lastQuotaRequestId: "req-abc-12345",
  lastQuotaRefunded: false,
};

const refundOk = computeQuotaRefund(usageBase, "req-abc-12345", nowMs);
assert.strictEqual(refundOk.apply, true);
assert.strictEqual(refundOk.dailyCount, 4);
assert.strictEqual(refundOk.minuteCount, 1);

const refundDup = computeQuotaRefund(
  { ...usageBase, lastQuotaRefunded: true },
  "req-abc-12345",
  nowMs
);
assert.strictEqual(refundDup.apply, false);
assert.strictEqual(refundDup.reason, "already_refunded");

const refundWrong = computeQuotaRefund(usageBase, "other-request", nowMs);
assert.strictEqual(refundWrong.apply, false);
assert.strictEqual(refundWrong.reason, "not_owner");

const refundFloor = computeQuotaRefund(
  {
    ...usageBase,
    dailyCount: 0,
    minuteCount: 0,
  },
  "req-abc-12345",
  nowMs
);
assert.strictEqual(refundFloor.apply, true);
assert.strictEqual(refundFloor.dailyCount, 0);
assert.strictEqual(refundFloor.minuteCount, 0);

// --- Logs seguros: não incluir campos sensíveis no objeto tipado ---
const logged = [];
const origLog = console.log;
console.log = (...args) => logged.push(args);
try {
  remiSafeLog("remi_test", {
    uid: "abcdefghijklmnop",
    durationMs: 120,
    model: "gemini-2.5-flash",
    status: "ok",
    approxInputTokens: 900,
    approxOutputTokens: 80,
    // campos que NÃO devem aparecer no payload tipado
    message: "secret user text",
    reply: "secret reply",
    email: "a@b.com",
  });
} finally {
  console.log = origLog;
}
assert.strictEqual(logged.length, 1);
const payload = logged[0][1];
assert.ok(payload.uid.includes("…") || payload.uid.includes("***"));
assert.strictEqual(payload.durationMs, 120);
assert.strictEqual(payload.model, "gemini-2.5-flash");
assert.strictEqual(payload.message, undefined);
assert.strictEqual(payload.reply, undefined);
assert.strictEqual(payload.email, undefined);

console.log("remi_usage.test.js: all tests passed");

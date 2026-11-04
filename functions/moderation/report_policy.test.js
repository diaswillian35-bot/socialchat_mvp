const test = require("node:test");
const assert = require("node:assert/strict");
const { decideReportAction, isCsamReport } = require("./report_policy");

const base = {
  fromUid: "reporter",
  reportedUid: "reported",
  reasonCode: "harassment",
};

test("uma denúncia CSAM de usuário não suspende; 3 denunciantes ou strikes sim", () => {
  const report = {
    ...base,
    reasonCode: "child_sexual_exploitation_or_abuse",
    requiresChildSafetyReview: true,
  };
  assert.equal(isCsamReport(report), true);
  const one = decideReportAction({
    report,
    reportedUid: "reported",
    dailyCount: 1,
    distinctReporters: 1,
    strikes: 0,
    config: {},
  });
  assert.equal(one.suspend, false);
  assert.equal(one.userCsam, true);
  assert.equal(one.priority, "critical");
  assert.equal(one.notify, true);
  assert.match(one.body, /motivo: child_sexual_exploitation_or_abuse/);
  assert.equal(one.body.includes("reporter"), false);

  const byReporters = decideReportAction({
    report,
    reportedUid: "reported",
    dailyCount: 1,
    distinctReporters: 3,
    strikes: 0,
    config: { autoActionThreshold: 3 },
  });
  assert.equal(byReporters.suspend, true);

  const byStrikes = decideReportAction({
    report,
    reportedUid: "reported",
    dailyCount: 1,
    distinctReporters: 1,
    strikes: 3,
    config: { strikeThreshold: 3 },
  });
  assert.equal(byStrikes.suspend, true);
});

test("CSAM detectado pelo sistema suspende na hora", () => {
  const decision = decideReportAction({
    report: {
      fromUid: "system",
      reportedUid: "reported",
      reasonCode: "csam",
    },
    reportedUid: "reported",
    dailyCount: 0,
    distinctReporters: 0,
    strikes: 0,
    config: {},
  });
  assert.equal(decision.suspend, true);
  assert.equal(decision.systemCsam, true);
});

test("CSAM de usuário acima do limite diário é ignorado", () => {
  const decision = decideReportAction({
    report: {
      ...base,
      reasonCode: "child_sexual_exploitation_or_abuse",
    },
    reportedUid: "reported",
    dailyCount: 21,
    distinctReporters: 1,
    strikes: 0,
    config: { reportDailyLimit: 20 },
  });
  assert.equal(decision.ignore, true);
  assert.equal(decision.notify, false);
  assert.equal(decision.suspend, false);
});

test("3 denunciantes distintos suspendem; 2 não", () => {
  const two = decideReportAction({
    report: base,
    reportedUid: "reported",
    dailyCount: 1,
    distinctReporters: 2,
    strikes: 0,
    config: { autoActionThreshold: 3 },
  });
  assert.equal(two.suspend, false);
  const three = decideReportAction({
    report: base,
    reportedUid: "reported",
    dailyCount: 1,
    distinctReporters: 3,
    strikes: 0,
    config: { autoActionThreshold: 3 },
  });
  assert.equal(three.suspend, true);
});

test("3 strikes automáticos suspendem", () => {
  const decision = decideReportAction({
    report: base,
    reportedUid: "reported",
    dailyCount: 1,
    distinctReporters: 1,
    strikes: 3,
    config: {},
  });
  assert.equal(decision.suspend, true);
});

test("acima de 20 denúncias no dia é ignorado", () => {
  const decision = decideReportAction({
    report: base,
    reportedUid: "reported",
    dailyCount: 21,
    distinctReporters: 5,
    strikes: 0,
    config: { reportDailyLimit: 20 },
  });
  assert.equal(decision.ignore, true);
  assert.equal(decision.notify, false);
  assert.equal(decision.suspend, false);
});

test("o corpo do aviso não leva texto de mensagem", () => {
  const decision = decideReportAction({
    report: { ...base, text: "segredo da mensagem", imageUrl: "https://x/a.jpg" },
    reportedUid: "reported",
    dailyCount: 1,
    distinctReporters: 1,
    strikes: 0,
    config: {},
  });
  assert.equal(decision.body.includes("segredo"), false);
  assert.equal(decision.body.includes("https://"), false);
});

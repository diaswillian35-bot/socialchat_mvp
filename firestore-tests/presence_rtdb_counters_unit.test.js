/**
 * Testes: admin gate, mirror retry, país vazio, zero countries, checkpoint.
 */
const assert = require('assert');
const {
  normalizeCountryCode,
  computeAtomicPresencePatch,
  applyCounterDeltas,
  simulateConcurrentPatches,
  countriesToZero,
  shouldMirrorAfterSync,
  parseReconcileCallArgs,
  evaluatePresenceReconcileAdmin,
  advanceReconcileCheckpoint,
  simulateMirrorFailureRetry,
} = require('../functions/presence_rtdb_counters_logic');

describe('admin reconcile gate', () => {
  it('sem login: negado', () => {
    const v = evaluatePresenceReconcileAdmin({ authenticated: false });
    assert.strictEqual(v.allowed, false);
    assert.strictEqual(v.code, 'unauthenticated');
  });

  it('usuário comum: negado', () => {
    const v = evaluatePresenceReconcileAdmin({
      authenticated: true,
      token: {},
      userData: { isPremium: false },
      adminDocExists: false,
    });
    assert.strictEqual(v.allowed, false);
    assert.strictEqual(v.code, 'permission-denied');
  });

  it('Premium comum: callable negada', () => {
    const v = evaluatePresenceReconcileAdmin({
      authenticated: true,
      token: {},
      userData: { isPremium: true },
      adminDocExists: false,
    });
    assert.strictEqual(v.allowed, false);
  });

  it('isAdmin forjado no doc: NÃO permite', () => {
    const v = evaluatePresenceReconcileAdmin({
      authenticated: true,
      token: {},
      userData: { isAdmin: true },
      adminDocExists: false,
    });
    assert.strictEqual(v.allowed, false);
  });

  it('isPlatformAdmin forjado: NÃO permite', () => {
    const v = evaluatePresenceReconcileAdmin({
      authenticated: true,
      token: {},
      userData: { isPlatformAdmin: true },
      adminDocExists: false,
    });
    assert.strictEqual(v.allowed, false);
  });

  it('role:admin forjado: NÃO permite', () => {
    const v = evaluatePresenceReconcileAdmin({
      authenticated: true,
      token: {},
      userData: { role: 'admin' },
      adminDocExists: false,
    });
    assert.strictEqual(v.allowed, false);
  });

  it('admin claim: permitido', () => {
    const v = evaluatePresenceReconcileAdmin({
      authenticated: true,
      token: { admin: true },
    });
    assert.strictEqual(v.allowed, true);
    assert.strictEqual(v.via, 'claim');
  });

  it('isMaster claim: permitido', () => {
    const v = evaluatePresenceReconcileAdmin({
      authenticated: true,
      token: { isMaster: true },
    });
    assert.strictEqual(v.allowed, true);
  });

  it('admins/{uid} real: permitido', () => {
    const v = evaluatePresenceReconcileAdmin({
      authenticated: true,
      token: {},
      userData: {},
      adminDocExists: true,
    });
    assert.strictEqual(v.allowed, true);
    assert.strictEqual(v.via, 'adminsDoc');
  });

  it('users.isMaster protegido: permitido', () => {
    const v = evaluatePresenceReconcileAdmin({
      authenticated: true,
      token: {},
      userData: { isMaster: true },
      adminDocExists: false,
    });
    assert.strictEqual(v.allowed, true);
    assert.strictEqual(v.via, 'isMaster');
  });
});

describe('parseReconcileCallArgs', () => {
  it('limita pageSize e rejeita cursor inválido', () => {
    const bad = parseReconcileCallArgs({ pageSize: 999, startAfterId: '../x' });
    assert.strictEqual(bad.ok, false);
    assert.ok(bad.pageSize <= 100);
    assert.strictEqual(bad.startAfterId, null);

    const good = parseReconcileCallArgs({
      pageSize: 40,
      startAfterId: 'uid_abc-123',
    });
    assert.strictEqual(good.ok, true);
    assert.strictEqual(good.pageSize, 40);
    assert.strictEqual(good.startAfterId, 'uid_abc-123');
  });
});

describe('país vazio ↔ válido', () => {
  it('vazio → br: move sem mudar world', () => {
    const p = computeAtomicPresencePatch({
      wasOnline: true,
      prevCountry: '',
      isOnline: true,
      nextCountry: 'br',
    });
    assert.strictEqual(p.op, 'country_move');
    assert.strictEqual(p.worldDelta, 0);
    assert.strictEqual(p.countryDeltas.br, 1);
    assert.ok(!p.countryDeltas['']);
  });

  it('br → vazio: remove br, world igual', () => {
    const p = computeAtomicPresencePatch({
      wasOnline: true,
      prevCountry: 'br',
      isOnline: true,
      nextCountry: '',
    });
    assert.strictEqual(p.op, 'country_move');
    assert.strictEqual(p.worldDelta, 0);
    assert.strictEqual(p.countryDeltas.br, -1);
  });

  it('br → ca', () => {
    const p = computeAtomicPresencePatch({
      wasOnline: true,
      prevCountry: 'br',
      isOnline: true,
      nextCountry: 'ca',
    });
    assert.strictEqual(p.worldDelta, 0);
    assert.strictEqual(p.countryDeltas.br, -1);
    assert.strictEqual(p.countryDeltas.ca, 1);
  });
});

describe('countriesToZero', () => {
  it('1→0 e 100→0', () => {
    assert.deepStrictEqual(
      countriesToZero(['br', 'us'], { us: 5 }),
      ['br']
    );
    assert.deepStrictEqual(
      countriesToZero(['br'], {}),
      ['br']
    );
  });
});

describe('mirror pending / retry sem duplicar', () => {
  it('shouldMirror quando mirrorPending mesmo em op none', () => {
    assert.strictEqual(
      shouldMirrorAfterSync({ op: 'none', changed: false, mirrorPending: true }),
      true
    );
    assert.strictEqual(
      shouldMirrorAfterSync({ op: 'none', changed: false, mirrorPending: false }),
      false
    );
  });

  for (const failAt of [
    'after_firestore',
    'after_world',
    'after_country',
    'after_presenceOnline',
  ]) {
    it(`retry após falha ${failAt} sem duplicar delta`, () => {
      const r = simulateMirrorFailureRetry({
        initialState: {
          online: false,
          country: '',
          world: 0,
          byCountry: {},
        },
        desiredOnline: true,
        country: 'br',
        failAt,
      });
      assert.strictEqual(r.firstOp, 'enter');
      assert.strictEqual(r.secondOp, 'none');
      assert.strictEqual(r.counters.world, 1);
      assert.strictEqual(r.counters.byCountry.br, 1);
      assert.strictEqual(r.mirrored.world, true);
      assert.strictEqual(r.state.mirrorPending, false);
    });
  }
});

describe('checkpoint paginação >100', () => {
  it('guarda cursor e só rebuild no fim', () => {
    const mid = advanceReconcileCheckpoint(
      { phase: 'sync', cursor: null },
      { nextPage: 'uid100', scanned: 100 },
      { maxPagesThisRun: 5, pagesDone: 1 }
    );
    assert.strictEqual(mid.phase, 'sync');
    assert.strictEqual(mid.cursor, 'uid100');
    assert.strictEqual(mid.readyForRebuild, false);

    const end = advanceReconcileCheckpoint(
      { phase: 'sync', cursor: 'uid100' },
      { nextPage: null, scanned: 50 },
      { maxPagesThisRun: 5, pagesDone: 2 }
    );
    assert.strictEqual(end.phase, 'rebuild');
    assert.strictEqual(end.readyForRebuild, true);
  });
});

describe('concorrência enter', () => {
  it('duas entradas simultâneas: um enter', () => {
    const r = simulateConcurrentPatches(
      { online: false, country: '', world: 0, byCountry: {} },
      [
        { isOnline: true, country: 'br' },
        { isOnline: true, country: 'br' },
      ]
    );
    assert.deepStrictEqual(r.applied, ['enter', 'none']);
    assert.strictEqual(r.counters.world, 1);
  });
});

/**
 * Unit tests for presence aggregate helper (no Emulator required).
 */
const assert = require('assert');
const {
  computeAggregateFromSessions,
  ONLINE_WINDOW_MS,
} = require('../functions/presence_aggregate_logic');

function fakeDoc(data) {
  return { data: () => data };
}

describe('computeAggregateFromSessions', () => {
  const now = Date.now();

  it('B online após A offline → agregado online', () => {
    const docs = [
      fakeDoc({
        isOnline: false,
        lastSeenAt: { toMillis: () => now - 1000 },
      }),
      fakeDoc({
        isOnline: true,
        lastSeenAt: { toMillis: () => now - 500 },
      }),
    ];
    const r = computeAggregateFromSessions(docs, now);
    assert.strictEqual(r.anyOnline, true);
  });

  it('todas expiradas → offline', () => {
    const docs = [
      fakeDoc({
        isOnline: true,
        lastSeenAt: { toMillis: () => now - ONLINE_WINDOW_MS - 1000 },
      }),
    ];
    const r = computeAggregateFromSessions(docs, now);
    assert.strictEqual(r.anyOnline, false);
  });

  it('mesmo UID várias sessões: uma fresca basta', () => {
    const docs = [
      fakeDoc({
        isOnline: true,
        lastSeenAt: { toMillis: () => now - ONLINE_WINDOW_MS - 5000 },
      }),
      fakeDoc({
        isOnline: true,
        lastSeenAt: { toMillis: () => now },
      }),
    ];
    assert.strictEqual(computeAggregateFromSessions(docs, now).anyOnline, true);
  });
});

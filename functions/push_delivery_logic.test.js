"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  isPermanentInvalidRegistrationCode,
  isTransientMessagingCode,
  collectPermanentInvalidTokens,
  badgeForImmediateMessagePush,
  ANDROID_HIGH_IMPORTANCE_CHANNEL_ID,
  buildAndroidMessageConfig,
  buildApnsMessageConfig,
  pushPolicyBlockCode,
} = require("./push_delivery_logic");

test("push skip reasons separate policy from a missing token", () => {
  assert.equal(
    pushPolicyBlockCode({ ageVerificationStatus: "pending" }, "chat"),
    "age_unverified",
  );
  assert.equal(
    pushPolicyBlockCode(
      { ageVerificationStatus: "verified", notifChat: false },
      "chat",
    ),
    "chat_pref_off",
  );
  assert.equal(
    pushPolicyBlockCode({ ageVerificationStatus: "verified" }, "chat"),
    null,
  );
  assert.equal(
    pushPolicyBlockCode(
      { ageVerificationStatus: "verified", notifEvents: false },
      "event",
    ),
    "event_pref_off",
  );
});

test("permanent registration failures are the only token deletions", () => {
  assert.equal(
    isPermanentInvalidRegistrationCode(
      "messaging/registration-token-not-registered",
    ),
    true,
  );
  assert.equal(
    isTransientMessagingCode("messaging/third-party-auth-error"),
    true,
  );
  assert.equal(
    isPermanentInvalidRegistrationCode("messaging/third-party-auth-error"),
    false,
  );
  const invalid = collectPermanentInvalidTokens(
    ["tok-a", "tok-b"],
    [
      { success: false, error: { code: "messaging/invalid-argument" } },
      {
        success: false,
        error: { code: "messaging/registration-token-not-registered" },
      },
    ],
  );
  assert.deepEqual(invalid, ["tok-b"]);
});

function sourceSlice(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start + startMarker.length);
  assert.ok(start >= 0 && end > start, startMarker);
  return source.slice(start, end);
}

test("DM, group, and event alerts do not wait on a full badge scan", () => {
  assert.equal(badgeForImmediateMessagePush(), 1);
  const index = fs.readFileSync(
    path.join(__dirname, "index.js"),
    "utf8",
  );
  const helper = sourceSlice(
    index,
    "async function sendPushToUids",
    "async function deleteInvalidTokens",
  );
  assert.equal(helper.includes("computeAppBadge"), false);
  assert.equal(helper.includes("badgeForImmediateMessagePush()"), true);
  assert.equal(helper.includes("collectTokenEntriesForUid(uid, prefKey)"), true);
  assert.equal(helper.includes("sendPush("), true);

  const delivery = sourceSlice(
    index,
    "async function sendPush(",
    "async function sendPushToUids",
  );
  assert.equal(delivery.includes("androidPushConfig(image)"), true);
  assert.equal(delivery.includes("apnsPushConfig(title, body, image, badge)"), true);

  const allowed = sourceSlice(
    index,
    "function pushAllowed",
    "async function collectTokenEntriesForUid",
  );
  assert.equal(allowed.includes("pushPolicyBlockCode(userData, kind)"), true);
  assert.equal(index.includes('tag: "push_targets"'), true);
  assert.equal(index.includes("no tokens / pushAllowed blocked"), false);

  const dm = sourceSlice(
    index,
    "exports.onPrivateMessageCreated",
    "exports.askRemi",
  );
  assert.equal(dm.includes('prefKey: "chat"'), true);
  assert.equal(dm.includes("sendPushToUids("), true);
  assert.equal(dm.includes("computeAppBadge"), false);

  const group = sourceSlice(
    index,
    "exports.onGroupMessageCreated",
    "exports.onPrivateMessageCreated",
  );
  assert.equal(group.includes('prefKey: "group"'), true);
  assert.equal(group.includes("sendPushToUids("), true);
  assert.equal(group.includes("computeAppBadge"), false);

  const comment = sourceSlice(
    index,
    "exports.createEventComment",
    "Curtir/descurtir evento",
  );
  assert.equal(comment.includes('prefKey: "event"'), true);
  assert.equal(comment.includes("sendPushToUids("), true);
  assert.equal(comment.includes('type = result.isReply ? "event_reply" : "event_comment"'), true);
  assert.equal(comment.includes("computeAppBadge"), false);

  const creator = sourceSlice(
    index,
    "async function notifyEventCreator",
    "exports.onEventUpdated",
  );
  assert.equal(creator.includes("sendPushToUids("), true);
  assert.equal(creator.includes('prefKey: "event"'), true);
  assert.equal(creator.includes("computeAppBadge"), false);

  const nearby = sourceSlice(
    index,
    "exports.onEventUpdated",
    "function normalizeGroupInviteCode",
  );
  assert.equal(nearby.includes("computeAppBadge"), false);
  assert.equal(nearby.includes("sendPush("), true);
  assert.equal(nearby.includes('type: "event"'), true);
});

test("background Android payload is high priority on the app channel", () => {
  const android = buildAndroidMessageConfig("");
  assert.equal(android.priority, "high");
  assert.equal(android.notification.channelId, ANDROID_HIGH_IMPORTANCE_CHANNEL_ID);
  assert.equal(android.notification.priority, "high");
  assert.equal(android.notification.sound, "default");
  assert.equal(android.notification.imageUrl, undefined);
});

test("background APNs payload is an immediate alert, not a silent push", () => {
  const apns = buildApnsMessageConfig("Ana", "oi", "", undefined);
  assert.equal(apns.headers["apns-priority"], "10");
  assert.equal(apns.headers["apns-push-type"], "alert");
  assert.equal(apns.payload.aps.sound, "default");
  assert.equal(apns.payload.aps.badge, 1);
  assert.deepEqual(apns.payload.aps.alert, { title: "Ana", body: "oi" });
  assert.equal(apns.payload.aps["content-available"], undefined);
  assert.equal(apns.payload.aps["mutable-content"], undefined);
});

test("explicit badge is preserved and a non-url image is not attached", () => {
  const apns = buildApnsMessageConfig(
    "Grupo",
    "foto",
    "https://cdn.example/a.png",
    4,
  );
  assert.equal(apns.payload.aps.badge, 4);
  assert.equal(apns.payload.aps["mutable-content"], 1);
  assert.equal(apns.fcmOptions.imageUrl, "https://cdn.example/a.png");

  const rejected = buildApnsMessageConfig("Grupo", "foto", "notaurl", 2);
  assert.equal(rejected.payload.aps["mutable-content"], undefined);
  assert.equal(rejected.fcmOptions, undefined);
});

test("FCM default channel meta-data is on the application, not the activity", () => {
  const manifest = fs.readFileSync(
    path.join(
      __dirname,
      "../android/app/src/main/AndroidManifest.xml",
    ),
    "utf8",
  );
  const activityStart = manifest.indexOf('android:name=".MainActivity"');
  const activityEnd = manifest.indexOf("</activity>", activityStart);
  const channelKey =
    "com.google.firebase.messaging.default_notification_channel_id";
  const channelAt = manifest.indexOf(channelKey);
  assert.ok(activityStart > 0);
  assert.ok(activityEnd > activityStart);
  assert.ok(channelAt > activityEnd);
  assert.equal(manifest.split(channelKey).length - 1, 1);
  const applicationEnd = manifest.indexOf("</application>");
  assert.ok(channelAt < applicationEnd);
});

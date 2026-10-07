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
} = require("./push_delivery_logic");

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

test("DM and group alerts do not wait on a full badge scan", () => {
  assert.equal(badgeForImmediateMessagePush(), 1);
  const index = fs.readFileSync(
    path.join(__dirname, "index.js"),
    "utf8",
  );
  const start = index.indexOf("async function sendPushToUids");
  const end = index.indexOf("async function deleteInvalidTokens");
  assert.ok(start > 0 && end > start);
  const fn = index.slice(start, end);
  assert.equal(fn.includes("computeAppBadge"), false);
  assert.equal(fn.includes("badgeForImmediateMessagePush()"), true);
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

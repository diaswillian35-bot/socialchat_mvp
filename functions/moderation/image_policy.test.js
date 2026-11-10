const test = require("node:test");
const assert = require("node:assert/strict");
const {
  decideSafeSearch,
  storagePathFromImageUrl,
  isModeratedImagePath,
  quarantinePath,
  uncheckedOutcome,
  isImageContentType,
  confirmedUploader,
  isTemporaryVisionError,
} = require("./image_policy");

test("thresholds de SafeSearch", () => {
  assert.deepEqual(
    decideSafeSearch({ adult: "LIKELY", racy: "UNLIKELY" }, {}),
    { action: "block", reason: "image_adult" },
  );
  assert.deepEqual(
    decideSafeSearch({ adult: "POSSIBLE", racy: "VERY_LIKELY" }, {}),
    { action: "block", reason: "image_racy" },
  );
  assert.deepEqual(
    decideSafeSearch({ adult: "UNLIKELY", racy: "LIKELY" }, {}),
    { action: "review", reason: "image_racy" },
  );
  assert.deepEqual(
    decideSafeSearch({ adult: "UNLIKELY", racy: "POSSIBLE" }, {}),
    { action: "allow", reason: "" },
  );
});

test("path de download e quarentena", () => {
  const url =
    "https://firebasestorage.googleapis.com/v0/b/socialchatmvp.firebasestorage.app/o/chat_images%2Fc1%2Fa.jpg?alt=media&token=secret";
  assert.equal(storagePathFromImageUrl(url), "chat_images/c1/a.jpg");
  assert.equal(isModeratedImagePath("chat_images/c1/a.jpg"), true);
  assert.equal(isModeratedImagePath("groups/g1/images/u1/a.jpg"), true);
  assert.equal(isModeratedImagePath("quarantine/chat_images/c1/a.jpg"), false);
  // b44: perfil/galeria também passam pelo SafeSearch.
  assert.equal(isModeratedImagePath("users/u1/a.jpg"), true);
  assert.equal(quarantinePath("chat_images/c1/a.jpg"), "quarantine/chat_images/c1/a.jpg");
  assert.equal(isImageContentType("image/jpeg"), true);
  assert.equal(isImageContentType("video/mp4"), false);
});

test("retentativa só para erro temporário da Vision", () => {
  assert.equal(uncheckedOutcome(1), "retry");
  assert.equal(uncheckedOutcome(3), "stop");
  assert.equal(isTemporaryVisionError({ code: 503 }), true);
  assert.equal(isTemporaryVisionError({ code: 400 }), false);
  assert.equal(isTemporaryVisionError({ message: "invalid image" }), false);
  assert.equal(confirmedUploader("chat_images/c1/a.jpg", {}), "");
  assert.equal(
    confirmedUploader("chat_images/c1/a.jpg", { fromUid: "u1" }),
    "u1",
  );
  assert.equal(
    confirmedUploader("groups/g1/images/u1/a.jpg", { fromUid: "u2" }),
    "",
  );
});

test("b44: perfil, evento, local e avatar de grupo entram no SafeSearch", () => {
  const p = require("./image_policy");
  assert.deepEqual(p.assetContextFromPath("users/u1/profile/a.jpg"), { kind: "profile", ownerUid: "u1", docId: "u1" });
  assert.equal(p.assetContextFromPath("events/e1/photos/a.jpg").kind, "event");
  assert.equal(p.assetContextFromPath("places/p1/photos/a.jpg").kind, "place");
  assert.equal(p.assetContextFromPath("places/p1/menu/a.jpg").kind, "place");
  assert.equal(p.assetContextFromPath("places/inbox/u1/a.jpg").kind, "");
  assert.equal(p.assetContextFromPath("groups/g1/avatar/a.jpg").kind, "group_avatar");
  assert.equal(p.isModeratedImagePath("posts/x/a.jpg"), false);
  assert.equal(p.confirmedUploader("users/u1/gallery/a.jpg", {}), "u1");
  assert.equal(p.confirmedUploader("events/e1/photos/a.jpg", { fromUid: "x" }), "");
});

test("b44: scrubPatch tira a foto bloqueada do doc", () => {
  const p = require("./image_policy");
  const url = "https://firebasestorage.googleapis.com/v0/b/x/o/users%2Fu1%2Fgallery%2Fb.jpg?alt=media";
  const other = "https://firebasestorage.googleapis.com/v0/b/x/o/users%2Fu1%2Fgallery%2Fc.jpg?alt=media";
  const patch = p.scrubPatch({ photoUrl: url, gallery: [url, other], name: "Ana", items: [{ url }, { url: other }] }, "users/u1/gallery/b.jpg");
  assert.deepEqual(patch, { photoUrl: "", gallery: [other], items: [{ url: other }] });
  assert.deepEqual(p.scrubPatch({ photoUrl: other }, "users/u1/gallery/b.jpg"), {});
});

"use strict";

const GROUP_BIO_MAX_LENGTH = 3000;

// UTF-16 code units, matching Dart String.length (not grapheme clusters).
function normalizeGroupBio(value) {
  const bio = (value || "").toString().trim();
  if (bio.length > GROUP_BIO_MAX_LENGTH) {
    const error = new Error("Bio too long.");
    error.code = "invalid-argument";
    throw error;
  }
  return bio;
}

module.exports = { GROUP_BIO_MAX_LENGTH, normalizeGroupBio };

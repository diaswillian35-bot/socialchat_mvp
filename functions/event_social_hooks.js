/**
 * Hooks de imagem social para createEvent / updateEvent.
 */
"use strict";

const {
  SOCIAL_TRIGGER_FIELDS,
  socialInputsChanged,
  scheduleSocialImageJob,
  ensureEventSocialImage,
} = require("./event_social_ensure");

module.exports = {
  SOCIAL_TRIGGER_FIELDS,
  socialInputsChanged,
  scheduleSocialImageJob,
  ensureEventSocialImage,
};

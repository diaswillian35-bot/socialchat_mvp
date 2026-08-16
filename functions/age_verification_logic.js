"use strict";

const MINIMUM_AGE = 18;
const MAXIMUM_AGE = 120;
const POLICY_VERSION = "18plus-2026-08-15";

function parseDateOfBirth(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return null;
  }
  const [year, month, day] = value.split("-").map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (parsed.getUTCFullYear() !== year ||
      parsed.getUTCMonth() !== month - 1 ||
      parsed.getUTCDate() !== day) return null;
  return parsed;
}

function calendarAge(dateOfBirth, today) {
  let age = today.getUTCFullYear() - dateOfBirth.getUTCFullYear();
  const beforeBirthday = today.getUTCMonth() < dateOfBirth.getUTCMonth() ||
    (today.getUTCMonth() === dateOfBirth.getUTCMonth() &&
      today.getUTCDate() < dateOfBirth.getUTCDate());
  if (beforeBirthday) age--;
  return age;
}

function validateAdultDate(value, now = new Date()) {
  const dateOfBirth = parseDateOfBirth(value);
  if (!dateOfBirth) return { valid: false, reason: "invalid-date" };
  const today = new Date(Date.UTC(
    now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const age = calendarAge(dateOfBirth, today);
  if (dateOfBirth > today || age > MAXIMUM_AGE) {
    return { valid: false, reason: "invalid-date" };
  }
  return {
    valid: true,
    adult: age >= MINIMUM_AGE,
    dateOfBirth,
  };
}

module.exports = {
  MINIMUM_AGE,
  MAXIMUM_AGE,
  POLICY_VERSION,
  parseDateOfBirth,
  calendarAge,
  validateAdultDate,
};

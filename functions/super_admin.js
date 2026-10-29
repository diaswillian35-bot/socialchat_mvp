"use strict";

/**
 * Administrador total do Remdy (somente a conta do Willian).
 *
 * Verificado pelo token do Firebase Auth: email exato + email_verified,
 * ou custom claim `admin: true`. Nunca libera conversas privadas (DMs):
 * sendDmMessage / conversations continuam exigindo participação.
 */
const SUPER_ADMIN_EMAILS = Object.freeze(["diaswillian35@gmail.com"]);

function isSuperAdminToken(token) {
  if (!token || typeof token !== "object") return false;
  if (token.admin === true) return true;
  const email = (token.email || "").toString().trim().toLowerCase();
  return token.email_verified === true && SUPER_ADMIN_EMAILS.includes(email);
}

function isSuperAdminAuth(auth) {
  return Boolean(auth && auth.uid && isSuperAdminToken(auth.token));
}

module.exports = { SUPER_ADMIN_EMAILS, isSuperAdminToken, isSuperAdminAuth };

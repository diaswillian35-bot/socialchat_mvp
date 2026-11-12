/**
 * Lógica pura: quando notificar admins de pedido de entrada em grupo.
 */

function normalizeStatus(raw) {
  return (raw || "").toString().trim().toLowerCase();
}

/**
 * @param {Record<string, unknown>|null|undefined} before
 * @param {Record<string, unknown>|null|undefined} after
 * @returns {boolean}
 */
function shouldNotifyJoinRequest(before, after) {
  if (!after || typeof after !== "object") return false;
  if (normalizeStatus(after.status) !== "pending") return false;
  if (!before || typeof before !== "object") return true;
  return normalizeStatus(before.status) !== "pending";
}

/**
 * Resolve destinatários admin (exclui o solicitante).
 * Inclui `admins[]` e, se válido, `ownerId` ausente da lista.
 */
function resolveJoinRequestAdminUids(groupData, requestUid) {
  const group = groupData && typeof groupData === "object" ? groupData : {};
  const admins = Array.isArray(group.admins)
    ? group.admins
        .map((u) => (u == null ? "" : String(u).trim()))
        .filter(Boolean)
    : [];
  const ownerId = (group.ownerId || group.createdBy || "").toString().trim();
  const set = new Set(admins);
  if (ownerId) set.add(ownerId);
  const requester = (requestUid || "").toString().trim();
  return [...set].filter((uid) => uid && uid !== requester);
}

const { t } = require("./i18n/serverTexts");

/**
 * Copy do push no idioma do destinatário (padrão pt-BR, compatível com os testes).
 * Título: Nova solicitação
 * Corpo: {nome} solicitou entrada no grupo {grupo}.
 */
function formatJoinRequestPushCopy(userName, groupName, lang, flags = {}) {
  const code = lang || "pt-BR";
  const rawName = (userName || "").toString().trim();
  const rawGroup = (groupName || "").toString().trim();
  const name =
    rawName && !flags.usedNameFallback
      ? rawName
      : t("push_someone", code);
  const group =
    rawGroup && !flags.usedGroupFallback
      ? rawGroup
      : t("push_group_fallback", code);
  return {
    title: t("push_join_request_title", code),
    body: t("push_join_request_body", code, { name, group }),
  };
}

module.exports = {
  normalizeStatus,
  shouldNotifyJoinRequest,
  resolveJoinRequestAdminUids,
  formatJoinRequestPushCopy,
};

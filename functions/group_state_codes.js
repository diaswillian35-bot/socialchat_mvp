"use strict";

/**
 * Sigla canônica de estado/província para a descoberta de grupos por estado.
 *
 * O Google Places devolve normalmente o short_name ("PR", "ON"), mas alguns
 * documentos e geocoders trazem o nome por extenso ("Paraná", "State of
 * Paraná", "Québec"). Aqui tudo vira a sigla em maiúsculas. Para países sem
 * tabela, uma sigla curta (2–3 letras) é aceita como veio; nomes longos são
 * mantidos dobrados (sem acento, maiúsculas) para ainda agrupar igual.
 */

function fold(value) {
  return (value || "")
    .toString()
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

const BR = {
  AC: "Acre", AL: "Alagoas", AP: "Amapa", AM: "Amazonas", BA: "Bahia",
  CE: "Ceara", DF: "Distrito Federal", ES: "Espirito Santo", GO: "Goias",
  MA: "Maranhao", MT: "Mato Grosso", MS: "Mato Grosso do Sul",
  MG: "Minas Gerais", PA: "Para", PB: "Paraiba", PR: "Parana",
  PE: "Pernambuco", PI: "Piaui", RJ: "Rio de Janeiro",
  RN: "Rio Grande do Norte", RS: "Rio Grande do Sul", RO: "Rondonia",
  RR: "Roraima", SC: "Santa Catarina", SP: "Sao Paulo", SE: "Sergipe",
  TO: "Tocantins",
};

const CA = {
  AB: ["Alberta"],
  BC: ["British Columbia", "Colombie Britannique", "Columbia Britanica"],
  MB: ["Manitoba"],
  NB: ["New Brunswick", "Nouveau Brunswick", "Nova Brunswick", "Nuevo Brunswick"],
  NL: ["Newfoundland and Labrador", "Terre Neuve et Labrador", "Terra Nova e Labrador", "Terranova y Labrador", "Newfoundland"],
  NS: ["Nova Scotia", "Nouvelle Ecosse", "Nova Escocia", "Nueva Escocia"],
  NT: ["Northwest Territories", "Territoires du Nord Ouest", "Territorios do Noroeste", "Territorios del Noroeste"],
  NU: ["Nunavut"],
  ON: ["Ontario"],
  PE: ["Prince Edward Island", "Ile du Prince Edouard", "Ilha do Principe Eduardo", "Isla del Principe Eduardo"],
  QC: ["Quebec"],
  SK: ["Saskatchewan"],
  YT: ["Yukon", "Yukon Territory"],
};

const TABLES = {};
(function build() {
  const br = {};
  for (const [code, name] of Object.entries(BR)) {
    br[fold(code)] = code;
    br[fold(name)] = code;
    br[fold(`Estado de ${name}`)] = code;
    br[fold(`Estado do ${name}`)] = code;
    br[fold(`Estado da ${name}`)] = code;
    br[fold(`State of ${name}`)] = code;
  }
  TABLES.br = br;
  const ca = {};
  for (const [code, names] of Object.entries(CA)) {
    ca[fold(code)] = code;
    for (const n of names) ca[fold(n)] = code;
  }
  TABLES.ca = ca;
})();

/**
 * @param {string} countryCode ISO-2 (qualquer caixa)
 * @param {string} raw stateName/administrativeArea
 * @returns {string} sigla em maiúsculas ou "" quando não há estado
 */
function normalizeStateCode(countryCode, raw) {
  const cc = (countryCode || "").toString().trim().toLowerCase();
  let value = (raw || "").toString().trim();
  if (!value) return "";
  // Legado "Cidade - UF".
  const cityUf = value.match(/^(.+?)\s*[-–]\s*([A-Za-z]{2})$/);
  if (cityUf) value = cityUf[2];
  const key = fold(value);
  if (!key) return "";
  const table = TABLES[cc];
  if (table) {
    return table[key] || "";
  }
  if (/^[a-z0-9]{1,3}$/.test(key)) return key.toUpperCase();
  return key.toUpperCase().replace(/\s+/g, "_").slice(0, 40);
}

/** "br-pr" — único por país, para consulta por igualdade. */
function stateKeyFor(countryCode, stateCode) {
  const cc = (countryCode || "").toString().trim().toLowerCase();
  const sc = (stateCode || "").toString().trim().toLowerCase();
  if (!cc || !sc) return "";
  return `${cc}-${sc}`;
}

module.exports = { normalizeStateCode, stateKeyFor };

/**
 * LEGADO — não implantar.
 * A função canônica onGroupMessageCreated vive em functions/index.js.
 * O codebase "groups" foi removido do firebase.json para evitar push duplicado.
 */
const { setGlobalOptions } = require("firebase-functions/v2");
setGlobalOptions({ region: "us-central1", maxInstances: 1 });

// Nenhum export ativo — evita colisão com functions/index.js.

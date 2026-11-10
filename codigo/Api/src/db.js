require('dotenv').config();
const sql = require('mssql');

const baseOptions = {
  encrypt: process.env.DB_ENCRYPT === 'true',
  trustServerCertificate: true
};

// connectionTimeout: si un nodo no responde, se rinde a los 15 s (ajustable con DB_CONNECT_TIMEOUT_MS en el .env)
function configNodo(port) {
  return {
    server: process.env.DB_SERVER || 'localhost',
    port,
    database: 'WideWorldImporters',
    user: 'sa',
    password: process.env.DB_PASSWORD || 'Proy2_Str0ng!Pass',
    options: baseOptions,
    connectionTimeout: Number(process.env.DB_CONNECT_TIMEOUT_MS || 15000),
    requestTimeout: 120000,
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  };
}

const configs = {
  sj: configNodo(1437),
  limon: configNodo(1435),
  corp: configNodo(1436)
};

// nombres aceptados para cada nodo, para no pelear con mayusculas/acentos
const alias = { sj: 'sj', limon: 'limon', corp: 'corp' };

const pools = {};

async function getConnection(nodo = 'corp') {
  const key = alias[nodo];
  if (!key) throw new Error(`Nodo desconocido: ${nodo}`);

  if (!pools[key]) {
    const pool = new sql.ConnectionPool(configs[key]);
    // Se guarda la PROMESA de la conexion: si llegan varias peticiones a la vez (por ejemplo al
    // arrancar), todas esperan la misma conexion en lugar de abrir una cada una.
    const conexion = pool.connect()
      .then(() => {
        console.log(`Conectado a nodo ${key}`);
        return pool;
      })
      .catch((error) => {
        if (pools[key] === conexion) delete pools[key];
        console.error(`Error conectando a nodo ${key}:`, error.message);
        throw error;
      });
    // Si el nodo se cae, se descarta el pool para volver a conectar en la siguiente peticion
    pool.on('error', (error) => {
      console.error(`Se perdio la conexion con el nodo ${key}:`, error.message);
      if (pools[key] === conexion) delete pools[key];
    });
    pools[key] = conexion;
  }
  return pools[key];
}

// Revisa los 3 nodos con una consulta minima (para /api/status)
async function estadoNodos() {
  const nodos = Object.keys(configs);
  const resultados = await Promise.all(nodos.map(async (nodo) => {
    try {
      const pool = await getConnection(nodo);
      await pool.request().query('SELECT 1 AS ok');
      return 'ok';
    } catch (error) {
      return 'caido';
    }
  }));
  return Object.fromEntries(nodos.map((nodo, i) => [nodo, resultados[i]]));
}

module.exports = { getConnection, estadoNodos, sql };
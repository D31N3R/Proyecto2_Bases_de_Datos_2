require('dotenv').config();
const sql = require('mssql');

const baseOptions = {
  encrypt: process.env.DB_ENCRYPT === 'true',
  trustServerCertificate: true
};

const configs = {
  sj: {
    server: process.env.DB_SERVER || 'localhost',
    port: 1437,
    database: 'WideWorldImporters',
    user: 'sa',
    password: process.env.DB_PASSWORD || 'Proy2_Str0ng!Pass',
    options: baseOptions,
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  },
  limon: {
    server: process.env.DB_SERVER || 'localhost',
    port: 1435,
    database: 'WideWorldImporters',
    user: 'sa',
    password: process.env.DB_PASSWORD || 'Proy2_Str0ng!Pass',
    options: baseOptions,
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  },
  corp: {
    server: process.env.DB_SERVER || 'localhost',
    port: 1436,
    database: 'WideWorldImporters',
    user: 'sa',
    password: process.env.DB_PASSWORD || 'Proy2_Str0ng!Pass',
    options: baseOptions,
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  }
};

// nombres aceptados para cada nodo, para no pelear con mayusculas/acentos
const alias = { sj: 'sj', SJ: 'sj', limon: 'limon', LIMON: 'limon', 'limón': 'limon', corp: 'corp', CORP: 'corp' };

const pools = {};

async function getConnection(nodo = 'corp') {
  const key = alias[nodo];
  if (!key) throw new Error(`Nodo desconocido: ${nodo}`);

  try {
    if (!pools[key]) {
      pools[key] = await sql.connect(configs[key]);
      // sql.connect() reusa la conexion global de mssql, asi que forzamos un pool propio:
      pools[key] = await new sql.ConnectionPool(configs[key]).connect();
      console.log(`Conectado a nodo ${key}`);
    }
    return pools[key];
  } catch (error) {
    console.error(`Error conectando a nodo ${key}:`, error.message);
    throw error;
  }
}

module.exports = { getConnection, sql };
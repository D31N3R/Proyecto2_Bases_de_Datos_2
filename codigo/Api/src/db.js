require('dotenv').config();
const sql = require('mssql');

const config = {
  server: process.env.DB_SERVER || 'localhost',
  port: parseInt(process.env.DB_PORT) || 1433,
  database: process.env.DB_DATABASE,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  options: {
    encrypt: process.env.DB_ENCRYPT === 'true',
    trustServerCertificate: process.env.DB_TRUST_CERT === 'true'
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000
  }
};

let pool;

async function getConnection() {
  try {
    if (!pool) {
      pool = await sql.connect(config);
      console.log('Conectado a SQL Server');
    }
    return pool;
  } catch (error) {
    console.error('Error conectando a SQL Server:', error.message);
    throw error;
  }
}

module.exports = { getConnection, sql };
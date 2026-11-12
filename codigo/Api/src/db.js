require('dotenv').config();
const sql = require('mssql');

const baseOptions = {
  encrypt: process.env.DB_ENCRYPT === 'true',
  trustServerCertificate: true
};

// ---- Identidad en la base de datos ----
// USAR_USUARIOS_BD=false (por defecto): la API se conecta como sa.
// USAR_USUARIOS_BD=true: cada rol de la aplicacion se conecta con su propio usuario de SQL Server
//   Administrador -> app_admin   (solo ejecuta procedimientos del esquema Api)
//   Corporativo   -> app_corp    (solo los reportes de estadisticas)
//   Sistema       -> app_auth    (login de usuarios y /status)
//   Refresco      -> app_refresh (solo el refresco del consolidado en Corp)
// Los usuarios se crean con Script_sql/_all_07_Seguridad.sql; las contrasenas van en .env
const { AsyncLocalStorage } = require('async_hooks');
const contextoUsuario = new AsyncLocalStorage(); // la middleware de autenticacion guarda aqui el rol de la peticion
const USAR_USUARIOS_BD = process.env.USAR_USUARIOS_BD === 'true';

const CUENTAS_BD = {
  Administrador: { user: 'app_admin', password: process.env.DB_PASS_ADMIN },
  Corporativo: { user: 'app_corp', password: process.env.DB_PASS_CORP },
  Sistema: { user: 'app_auth', password: process.env.DB_PASS_AUTH },
  Refresco: { user: 'app_refresh', password: process.env.DB_PASS_REFRESH }
};

function credenciales(rol) {
  if (!USAR_USUARIOS_BD) {
    return { rol: 'sa', user: 'sa', password: process.env.DB_PASSWORD || 'Proy2_Str0ng!Pass' };
  }
  const cuenta = CUENTAS_BD[rol] ? rol : 'Sistema';
  if (!CUENTAS_BD[cuenta].password) {
    throw new Error(`Falta la contraseña de ${CUENTAS_BD[cuenta].user} en el .env`);
  }
  return { rol: cuenta, ...CUENTAS_BD[cuenta] };
}

// connectionTimeout: si un nodo no responde, se rinde a los 15 s (ajustable con DB_CONNECT_TIMEOUT_MS en el .env)
function configNodo(port, cuenta) {
  return {
    server: process.env.DB_SERVER || 'localhost',
    port,
    database: 'WideWorldImporters',
    user: cuenta.user,
    password: cuenta.password,
    options: baseOptions,
    connectionTimeout: Number(process.env.DB_CONNECT_TIMEOUT_MS || 15000),
    requestTimeout: 120000,
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 }
  };
}

const puertos = { sj: 1437, limon: 1435, corp: 1436 };

// nombres aceptados para cada nodo, para no pelear con mayusculas/acentos
const alias = { sj: 'sj', limon: 'limon', corp: 'corp' };

const pools = {};

// Un pool por nodo y por rol. Sin rol explicito se usa el de la peticion en curso (o "Sistema").
async function getConnection(nodo = 'corp', rolForzado) {
  const key = alias[nodo];
  if (!key) throw new Error(`Nodo desconocido: ${nodo}`);

  const cuenta = credenciales(rolForzado || (contextoUsuario.getStore() || {}).rol || 'Sistema');
  const clave = `${key}:${cuenta.rol}`;

  if (!pools[clave]) {
    const pool = new sql.ConnectionPool(configNodo(puertos[key], cuenta));
    // Se guarda la PROMESA de la conexion: si llegan varias peticiones a la vez (por ejemplo al
    // arrancar), todas esperan la misma conexion en lugar de abrir una cada una.
    const conexion = pool.connect()
      .then(() => {
        console.log(`Conectado a nodo ${key} (${cuenta.user})`);
        return pool;
      })
      .catch((error) => {
        if (pools[clave] === conexion) delete pools[clave];
        console.error(`Error conectando a nodo ${key}:`, error.message);
        throw error;
      });
    // Si el nodo se cae, se descarta el pool para volver a conectar en la siguiente peticion
    pool.on('error', (error) => {
      console.error(`Se perdio la conexion con el nodo ${key}:`, error.message);
      if (pools[clave] === conexion) delete pools[clave];
    });
    pools[clave] = conexion;
  }
  return pools[clave];
}

// Revisa los 3 nodos con una consulta minima (para /api/status)
async function estadoNodos() {
  const nodos = Object.keys(puertos);
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

module.exports = { getConnection, estadoNodos, contextoUsuario, sql };
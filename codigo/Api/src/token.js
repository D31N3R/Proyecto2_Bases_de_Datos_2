// Token de sesion firmado con HMAC-SHA256 (sin librerias externas).
// Lleva el usuario, su rol y su sucursal; el servidor lo verifica en cada peticion,
// asi el rol y la sucursal ya no los decide el navegador.
const crypto = require('crypto');

// Si no hay TOKEN_SECRET en .env se usa uno aleatorio: los tokens dejan de valer al reiniciar la API
const SECRETO = process.env.TOKEN_SECRET || crypto.randomBytes(32).toString('hex');
const DURACION_MS = 8 * 60 * 60 * 1000; // 8 horas

const firmar = (texto) => crypto.createHmac('sha256', SECRETO).update(texto).digest('base64url');

function crearToken(datos) {
  const cuerpo = Buffer.from(JSON.stringify({ ...datos, exp: Date.now() + DURACION_MS })).toString('base64url');
  return `${cuerpo}.${firmar(cuerpo)}`;
}

// Devuelve los datos del token, o null si esta alterado o vencido
function leerToken(token) {
  const [cuerpo, firma] = String(token || '').split('.');
  if (!cuerpo || !firma) return null;

  const esperada = Buffer.from(firmar(cuerpo));
  const recibida = Buffer.from(firma);
  if (recibida.length !== esperada.length || !crypto.timingSafeEqual(recibida, esperada)) return null;

  try {
    const datos = JSON.parse(Buffer.from(cuerpo, 'base64url').toString());
    return datos.exp > Date.now() ? datos : null;
  } catch (error) {
    return null;
  }
}

module.exports = { crearToken, leerToken };

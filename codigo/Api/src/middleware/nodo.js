// Resuelve a que nodo conectarse segun el header X-Sucursal que manda el front
// despues del login ('SJ', 'LIMON' o 'CORP'; se aceptan acentos: 'Limón').
// Debe montarse ANTES de las rutas. /login y /status no necesitan sucursal.
const NODOS = { SJ: 'sj', LIMON: 'limon', CORP: 'corp' };
const PUBLICAS = ['/login', '/status'];

function normalizar(texto) {
  return String(texto || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toUpperCase();
}

function resolveNodo(req, res, next) {
  if (PUBLICAS.includes(req.path)) return next();

  const nodo = NODOS[normalizar(req.headers['x-sucursal'])];
  if (!nodo) {
    return res.status(400).json({ error: 'Sucursal no indicada o desconocida (header X-Sucursal)' });
  }
  req.nodo = nodo;
  next();
}

module.exports = resolveNodo;
module.exports.normalizar = normalizar;
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

// Errores que indican que el nodo no responde (y no un error de la consulta)
const FALLO_DE_NODO = /Failed to connect|Connection is closed|Connection lost|ECONNREFUSED|ECONNRESET|ESOCKET|ETIMEOUT|ETIMEDOUT|socket hang up/i;

function resolveNodo(req, res, next) {
  if (PUBLICAS.includes(req.path)) return next();

  let nodo = NODOS[normalizar(req.headers['x-sucursal'])];
  if (!nodo) {
    return res.status(400).json({ error: 'Sucursal no indicada o desconocida (header X-Sucursal)' });
  }

  // El Corporativo, en Estadisticas, puede filtrar por sucursal (?sucursal=sj o limon)
  // o ver la consolidada (cualquier otro valor): esa se consulta en Corp.
  if (nodo === 'corp' && req.path.startsWith('/estadisticas')) {
    const filtro = NODOS[normalizar(req.query.sucursal)];
    if (filtro === 'sj' || filtro === 'limon') nodo = filtro;
  }

  req.nodo = nodo;

  // Si la consulta fallo porque el nodo no responde, se contesta 503 (no 500) con un mensaje claro
  const json = res.json.bind(res);
  res.json = (cuerpo) => {
    if (res.statusCode === 500 && cuerpo && typeof cuerpo.error === 'string' && FALLO_DE_NODO.test(cuerpo.error)) {
      res.status(503);
      cuerpo = { error: `El nodo ${nodo.toUpperCase()} no está disponible por ahora. Intente de nuevo en unos minutos.`, nodo };
    }
    return json(cuerpo);
  };
  next();
}

module.exports = resolveNodo;
module.exports.normalizar = normalizar;
// Resuelve a que nodo conectarse segun el usuario del token (lo valida autenticar.js):
// el Administrador va al nodo de SU sucursal y el Corporativo a Corp. El navegador ya no elige.
// Debe montarse DESPUES de autenticar y ANTES de las rutas. /login y /status no necesitan nodo.
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

// Puerto de cada nodo, para decir en el aviso CUAL no responde (puede ser Corp aunque el usuario sea de SJ)
const NODO_POR_PUERTO = { 1437: 'SJ', 1435: 'LIMON', 1436: 'CORP' };

function resolveNodo(req, res, next) {
  if (PUBLICAS.includes(req.path)) return next();

  const usuario = req.usuario;
  if (!usuario) return res.status(401).json({ error: 'Sesión no válida o vencida. Inicie sesión de nuevo.' });

  let nodo = usuario.rol === 'Corporativo' ? 'corp' : NODOS[normalizar(usuario.sucursal)];
  if (!nodo) {
    return res.status(403).json({ error: 'El usuario no tiene una sucursal asignada.' });
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
      const puerto = (cuerpo.error.match(/:(14\d\d)\b/) || [])[1];
      const cual = NODO_POR_PUERTO[puerto] || nodo.toUpperCase();
      cuerpo = { error: `El nodo ${cual} no está disponible por ahora. Intente de nuevo en unos minutos.`, nodo: cual.toLowerCase() };
    }
    return json(cuerpo);
  };
  next();
}

module.exports = resolveNodo;
module.exports.normalizar = normalizar;
// Resuelve a que nodo conectarse, segun la sucursal que el front
// manda en el header X-Sucursal despues del login (SJ, LIMON o CORP)
function resolveNodo(req, res, next) {
  const sucursal = (req.headers['x-sucursal'] || '').toUpperCase();
  const map = { SJ: 'sj', LIMON: 'limon', CORP: 'corp' };
  req.nodo = map[sucursal] || 'sj';
  next();
}

module.exports = resolveNodo;
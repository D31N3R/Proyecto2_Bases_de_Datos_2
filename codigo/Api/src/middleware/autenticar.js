// Exige un token valido y revisa que el ROL del usuario pueda usar la ruta.
// Se monta ANTES de resolveNodo. /login y /status son publicas.
const { leerToken } = require('../token');
const { contextoUsuario } = require('../db');

const PUBLICAS = ['/login', '/status'];

// Que puede usar cada rol (ruta = prefijo; [metodo, ruta exacta] = solo ese metodo y esa ruta)
const PERMITIDAS = {
  Administrador: ['/clientes', '/proveedores', '/inventarios', '/ventas', '/estadisticas',
                  '/metodos-entrega', '/ciudades', '/personas'],
  // El Corporativo solo consulta estadisticas (y los listados que usan sus filtros)
  Corporativo: ['/estadisticas',
                ['GET', '/inventarios/grupos'], ['GET', '/proveedores'], ['GET', '/clientes/categorias']]
};

function puedeUsar(rol, metodo, ruta) {
  return (PERMITIDAS[rol] || []).some((permiso) => {
    if (Array.isArray(permiso)) return permiso[0] === metodo && permiso[1] === ruta;
    return ruta === permiso || ruta.startsWith(permiso + '/');
  });
}

function autenticar(req, res, next) {
  if (PUBLICAS.includes(req.path)) return next();

  const usuario = leerToken((req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
  if (!usuario) {
    return res.status(401).json({ error: 'Sesión no válida o vencida. Inicie sesión de nuevo.' });
  }
  if (!puedeUsar(usuario.rol, req.method, req.path)) {
    return res.status(403).json({ error: `El rol ${usuario.rol} no tiene permiso para esta operación.` });
  }

  req.usuario = usuario;
  // Desde aqui, getConnection() usa el usuario de BD que corresponde al rol
  contextoUsuario.run({ rol: usuario.rol }, next);
}

module.exports = autenticar;
module.exports.puedeUsar = puedeUsar;

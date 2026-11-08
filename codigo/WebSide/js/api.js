const API_URL = `http://${window.location.hostname}:4000`;

// ================== Sesión ==================
// No hay módulo de sesiones (el enunciado no lo pide): el login guarda el usuario
// en sessionStorage y cada petición manda su sucursal en el header X-Sucursal,
// que la API usa para elegir a qué nodo conectarse.
const ENLACE_BASE = window.location.pathname.includes('/pages/') ? '../' : '';

function getSesion() {
  try {
    return JSON.parse(sessionStorage.getItem('sesion'));
  } catch (e) {
    return null;
  }
}

function guardarSesion(usuario) {
  sessionStorage.setItem('sesion', JSON.stringify(usuario));
}

function irALogin() {
  window.location.replace(ENLACE_BASE + 'login.html');
}

function cerrarSesion() {
  sessionStorage.removeItem('sesion');
  sessionStorage.removeItem('sucursalEst');
  irALogin();
}

function esCorporativo() {
  const s = getSesion();
  return !!s && s.rol === 'Corporativo';
}

// Sucursal que el Corporativo eligió para las estadísticas: 'consolidada', 'sj' o 'limon'
function getSucursalEstadisticas() {
  return sessionStorage.getItem('sucursalEst') || 'consolidada';
}

function setSucursalEstadisticas(valor) {
  sessionStorage.setItem('sucursalEst', valor);
}

// Nodo con el que debe hablar la API para esta sesión: SJ, LIMON o CORP
function sucursalDeSesion() {
  const s = getSesion();
  if (!s) return '';
  if (s.rol === 'Corporativo') return 'CORP';
  return String(s.sucursal || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toUpperCase();
}

// Sin sesión no hay a dónde ir: se manda al login. El Corporativo solo ve estadísticas.
if (!window.PAGINA_PUBLICA) {
  const sesion = getSesion();
  const enPages = window.location.pathname.includes('/pages/');
  if (!sesion) {
    irALogin();
  } else if (sesion.rol === 'Corporativo' && enPages &&
             !/estadisticas(\.html)?$/.test(window.location.pathname)) {
    window.location.replace('../index.html');
  }
}

// Barra superior con el usuario y el botón para cerrar sesión
function mostrarBarraSesion() {
  const s = getSesion();
  if (!s || window.PAGINA_PUBLICA) return;

  const barra = document.createElement('div');
  barra.className = 'barra-sesion';

  const quien = document.createElement('span');
  const donde = s.rol === 'Corporativo' ? 'Corporativo' : `Sucursal ${s.sucursal}`;
  quien.textContent = `${s.fullname} · ${donde}`;

  const boton = document.createElement('button');
  boton.type = 'button';
  boton.className = 'btn-secondary';
  boton.textContent = 'Cerrar sesión';
  boton.addEventListener('click', cerrarSesion);

  barra.append(quien, boton);
  document.body.appendChild(barra);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', mostrarBarraSesion);
} else {
  mostrarBarraSesion();
}

// ================== Llamadas a la API ==================
async function pedir(metodo, path, body) {
  const sucursal = sucursalDeSesion();
  if (!sucursal) throw new Error('Sesión no iniciada');

  const opciones = { method: metodo, headers: { 'X-Sucursal': sucursal } };
  if (body !== undefined) {
    opciones.headers['Content-Type'] = 'application/json';
    opciones.body = JSON.stringify(body);
  }

  // Las estadísticas del Corporativo llevan el filtro de sucursal (o consolidada)
  let ruta = path;
  if (esCorporativo() && path.startsWith('/api/estadisticas')) {
    ruta += (path.includes('?') ? '&' : '?') + 'sucursal=' + encodeURIComponent(getSucursalEstadisticas());
  }

  const res = await fetch(API_URL + ruta, opciones);
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || `Error ${res.status}`);
  }
  return res.json();
}

function apiGet(path) {
  return pedir('GET', path);
}

function apiPost(path, body) {
  return pedir('POST', path, body);
}

function apiPut(path, body) {
  return pedir('PUT', path, body);
}

function apiDelete(path) {
  return pedir('DELETE', path);
}
// Muestra un mensaje flotante; tipo puede ser 'exito' o 'error'
function mostrarToast(mensaje, tipo = 'exito') {
  let contenedor = document.getElementById('toast-contenedor');
  if (!contenedor) {
    contenedor = document.createElement('div');
    contenedor.id = 'toast-contenedor';
    document.body.appendChild(contenedor);
  }

  const toast = document.createElement('div');
  toast.className = `toast ${tipo}`;
  toast.textContent = mensaje;
  contenedor.appendChild(toast);

  // Se quita solo a los 4 segundos
  setTimeout(() => toast.remove(), 4000);
}

// Guarda un mensaje para mostrarlo en la página siguiente (después de un redirect)
function guardarToast(mensaje, tipo = 'exito') {
  sessionStorage.setItem('toast', JSON.stringify({ mensaje, tipo }));
}

// Si hay un mensaje guardado, lo muestra una sola vez
function mostrarToastGuardado() {
  const guardado = sessionStorage.getItem('toast');
  if (!guardado) return;
  sessionStorage.removeItem('toast');
  const { mensaje, tipo } = JSON.parse(guardado);
  mostrarToast(mensaje, tipo);
}

mostrarToastGuardado();

// Muestra una ventana de confirmación dentro de la página.
// Devuelve una promesa: true si presiona "Eliminar", false si cancela.
function confirmarAccion(mensaje) {
  return new Promise((resolve) => {
    const fondo = document.createElement('div');
    fondo.className = 'confirmar-fondo';

    const caja = document.createElement('div');
    caja.className = 'confirmar-caja';

    const texto = document.createElement('p');
    texto.textContent = mensaje;

    const botones = document.createElement('div');
    botones.className = 'confirmar-botones';

    const btnCancelar = document.createElement('button');
    btnCancelar.type = 'button';
    btnCancelar.className = 'btn-secondary';
    btnCancelar.textContent = 'Cancelar';

    const btnAceptar = document.createElement('button');
    btnAceptar.type = 'button';
    btnAceptar.className = 'peligro';
    btnAceptar.textContent = 'Eliminar';

    // Cierra la ventana y entrega la respuesta
    function cerrar(respuesta) {
      fondo.remove();
      resolve(respuesta);
    }

    btnCancelar.addEventListener('click', () => cerrar(false));
    btnAceptar.addEventListener('click', () => cerrar(true));

    // Si hace clic en el fondo oscuro, también se cancela
    fondo.addEventListener('click', (e) => {
      if (e.target === fondo) cerrar(false);
    });

    botones.append(btnCancelar, btnAceptar);
    caja.append(texto, botones);
    fondo.appendChild(caja);
    document.body.appendChild(fondo);
  });
}
const API_URL = `http://${window.location.hostname}:4000`;

async function apiGet(path) {
  const res = await fetch(API_URL + path);
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || `Error ${res.status}`);
  }
  return res.json();
}

async function apiPost(path, body) {
  const res = await fetch(API_URL + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || `Error ${res.status}`);
  }
  return res.json();
}

async function apiPut(path, body) {
  const res = await fetch(API_URL + path, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || `Error ${res.status}`);
  }
  return res.json();
}

async function apiDelete(path) {
  const res = await fetch(API_URL + path, { method: 'DELETE' });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error || `Error ${res.status}`);
  }
  return res.json();
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
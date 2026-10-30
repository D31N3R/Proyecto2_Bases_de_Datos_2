const params = new URLSearchParams(window.location.search);
const id = params.get('id');
const detalleEl = document.getElementById('detalle');
const tituloEl = document.getElementById('titulo');

function valor(v) {
  return v !== null && v !== undefined && v !== '' ? v : '—';
}

async function cargarDetalle() {
  if (!id) {
    mostrarToast('Falta el ID del cliente en la URL', 'error');
    tituloEl.textContent = 'Error';
    return;
  }

  try {
    const c = await apiGet(`/api/clientes/${id}`);
    tituloEl.textContent = c.Nombre;

    const sitioWeb = c.SitioWeb
      ? `<a href="${c.SitioWeb}" target="_blank" rel="noopener">${c.SitioWeb}</a>`
      : '—';

    detalleEl.innerHTML = `
      <div class="card acciones">
        <button id="btn-editar">Editar</button>
        <button id="btn-eliminar" class="peligro">Eliminar</button>
      </div>

      <div class="card">
        <h2>Información general</h2>
        <p><strong>Nombre:</strong> ${valor(c.Nombre)}</p>
        <p><strong>Categoría:</strong> ${valor(c.Categoria)}</p>
        <p><strong>Grupo de compra:</strong> ${valor(c.GrupoCompra)}</p>
        <p><strong>Método de entrega:</strong> ${valor(c.MetodoEntrega)}</p>
        <p><strong>Cliente por facturar:</strong> ${valor(c.ClientePorFacturar)}</p>
        <p><strong>Días de gracia para pago:</strong> ${valor(c.DiasGraciaPago)}</p>
      </div>

      <div class="card">
        <h2>Contacto</h2>
        <p><strong>Contacto primario:</strong> ${valor(c.ContactoPrimario)}</p>
        <p><strong>Contacto alterno:</strong> ${valor(c.ContactoAlterno)}</p>
        <p><strong>Teléfono:</strong> ${valor(c.Telefono)}</p>
        <p><strong>Fax:</strong> ${valor(c.Fax)}</p>
        <p><strong>Sitio web:</strong> ${sitioWeb}</p>
      </div>

      <div class="card">
        <h2>Dirección de entrega</h2>
        <p>${valor(c.DireccionEntrega1)}</p>
        <p>${valor(c.DireccionEntrega2)}</p>
        <p><strong>Ciudad:</strong> ${valor(c.CiudadEntrega)}</p>
        <p><strong>Código postal:</strong> ${valor(c.CodigoPostal)}</p>
      </div>

      <div class="card">
        <h2>Dirección postal</h2>
        <p>${valor(c.DireccionPostal1)}</p>
        <p>${valor(c.DireccionPostal2)}</p>
      </div>

      <div class="card">
        <h2>Ubicación</h2>
        <div id="mapa" style="height: 350px; border-radius: 6px;"></div>
      </div>
    `;

    // Botones de accion
    document.getElementById('btn-editar').addEventListener('click', () => {
      window.location.href = `cliente_form?id=${id}`;
    });

    document.getElementById('btn-eliminar').addEventListener('click', async () => {
      const confirmar = await confirmarAccion('¿Seguro que quieres eliminar este cliente? Esta acción no se puede deshacer.');
      if (!confirmar) return;

      try {
        await apiDelete(`/api/clientes/${id}`);
        guardarToast('Cliente eliminado correctamente');
        window.location.href = 'clientes.html';
      } catch (e) {
        mostrarToast('Error al eliminar: ' + e.message, 'error');
      }
    });

    // Inicializar mapa
    const lat = parseFloat(c.Latitud);
    const lng = parseFloat(c.Longitud);

    if (!isNaN(lat) && !isNaN(lng)) {
      const mapa = L.map('mapa').setView([lat, lng], 13);
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap',
        maxZoom: 19
      }).addTo(mapa);

      L.marker([lat, lng])
        .addTo(mapa)
        .bindPopup(`<strong>${c.Nombre}</strong><br>${valor(c.CiudadEntrega)}`)
        .openPopup();
    } else {
      document.getElementById('mapa').innerHTML =
        '<p style="padding: 1rem; color: #7f8c8d;">Ubicación no disponible</p>';
    }
  } catch (e) {
    mostrarToast('Error: ' + e.message, 'error');
    tituloEl.textContent = 'Error';
  }
}

cargarDetalle();

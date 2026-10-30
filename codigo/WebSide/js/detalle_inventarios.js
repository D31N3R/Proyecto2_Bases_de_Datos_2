const params = new URLSearchParams(window.location.search);
const id = params.get('id');
const detalleEl = document.getElementById('detalle');
const tituloEl = document.getElementById('titulo');

function valor(v) {
  return v !== null && v !== undefined && v !== '' ? v : '—';
}

async function cargarDetalle() {
  if (!id) {
    mostrarToast('Falta el ID del producto en la URL', 'error');
    tituloEl.textContent = 'Error';
    return;
  }

  try {
    const c = await apiGet(`/api/inventarios/${id}`);
    tituloEl.textContent = c.Nombre;

    const proveedor = c.SupplierID
    ? `<a href="detalle_proveedores?id=${c.SupplierID}">${valor(c.NombreProveedor)}</a>`
    : '—';

    detalleEl.innerHTML = `
      <div class="card acciones">
        <button id="btn-editar">Editar</button>
        <button id="btn-eliminar" class="peligro">Eliminar</button>
      </div>

      <div class="card">
        <h2>Información general del producto</h2>
        <p><strong>Nombre:</strong> ${valor(c.Nombre)}</p>
        <p><strong>Marca:</strong> ${valor(c.Marca)}</p>
        <p><strong>Proveedor:</strong> ${valor(proveedor)}</p>
        <p><strong>Color:</strong> ${valor(c.Color)}</p>
        <p><strong>Talla:</strong> ${valor(c.Talla)}</p>
        <p><strong>Peso:</strong> ${valor(c.Peso)} <strong>kg</strong></p>
        <p><strong>Cantidad disponible:</strong> ${valor(c.CantidadDisponible)}</p>
        <p><strong>Palabras clave:</strong> ${valor(c.PalabrasClaves)}</p>
      </div>

      <div class="card">
        <h2>Informacion de empaquetamiento</h2>
        <p><strong>Unidad de empaquetamiento:</strong> ${valor(c.UnidadEmpaque)}</p>
        <p><strong>Empaquetamiento:</strong> ${valor(c.EmpaqueExterior)}</p>
        <p><strong>Cantidad de empaquetamiento:</strong> ${valor(c.CantidadEmpaque)}</p>
      </div>

      <div class="card">
        <h2>Informacion de venta</h2>
        <p><strong>Precio unitario:</strong> ${valor(c.PrecioUnitario)}</p>
        <p><strong>Precio de venta:</strong> ${valor(c.PrecioVenta)}</p>
        <p><strong>Impuesto:</strong> ${valor(c.Impuesto)}</p>
      </div>

      <div class="card">
        <h2>Ubicación</h2>
        <p>${valor(c.Ubicacion)}</p>
      </div>
    `;

    // Botones de accion
    document.getElementById('btn-editar').addEventListener('click', () => {
      window.location.href = `inventario_form?id=${id}`;
    });

    document.getElementById('btn-eliminar').addEventListener('click', async () => {
      const confirmar = await confirmarAccion('¿Seguro que quieres eliminar este producto? Esta acción no se puede deshacer.');
      if (!confirmar) return;

      try {
        await apiDelete(`/api/inventarios/${id}`);
        window.location.href = 'inventarios.html';
      } catch (e) {
        mostrarToast('Error al eliminar: ' + e.message, 'error');
      }
    });

  } catch (e) {
    mostrarToast('Error: ' + e.message, 'error');
    tituloEl.textContent = 'Error';
  }
}

cargarDetalle();

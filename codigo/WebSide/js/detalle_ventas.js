const params = new URLSearchParams(window.location.search);
const id = params.get('id');
const detalleEl = document.getElementById('detalle');
const tituloEl = document.getElementById('titulo');

function valor(v) {
  return v !== null && v !== undefined && v !== '' ? v : '—';
}

// Muestra un monto con separador de miles y 2 decimales
function dinero(v) {
  return Number(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

async function cargarDetalle() {
  if (!id) {
    mostrarToast('Falta el ID de la factura en la URL', 'error');
    tituloEl.textContent = 'Error';
    return;
  }

  try {
    const { encabezado: e, lineas } = await apiGet(`/api/ventas/${id}`);
    tituloEl.textContent = `Factura ${e.NumeroFactura}`;

    const filas = lineas.map(l => `
      <tr>
        <td><a href="detalle_inventarios?id=${l.StockItemID}">${valor(l.Producto)}</a></td>
        <td>${l.Cantidad}</td>
        <td>${dinero(l.PrecioUnitario)}</td>
        <td>${l.ImpuestoAplicado}%</td>
        <td>${dinero(l.MontoImpuesto)}</td>
        <td>${dinero(l.TotalLinea)}</td>
      </tr>
    `).join('');

    detalleEl.innerHTML = `
      <div class="card acciones">
        <button id="btn-editar">Editar</button>
      </div>

      <div class="card">
        <h2>Encabezado de la factura</h2>
        <p><strong>Número de factura:</strong> ${valor(e.NumeroFactura)}</p>
        <p><strong>Cliente:</strong> <a href="detalle_clientes?id=${e.CustomerID}">${valor(e.Cliente)}</a></p>
        <p><strong>Método de entrega:</strong> ${valor(e.MetodoEntrega)}</p>
        <p><strong>Número de orden:</strong> ${valor(e.NumeroOrden)}</p>
        <p><strong>Persona de contacto:</strong> ${valor(e.PersonaContacto)}</p>
        <p><strong>Vendedor:</strong> ${valor(e.Vendedor)}</p>
        <p><strong>Fecha de la factura:</strong> ${valor(e.Fecha)}</p>
        <p><strong>Instrucciones de entrega:</strong> ${valor(e.InstruccionesEntrega)}</p>
      </div>

      <div class="card">
        <h2>Detalle de la factura</h2>
        <table>
          <thead>
            <tr>
              <th>Producto</th>
              <th>Cantidad</th>
              <th>Precio unitario</th>
              <th>Impuesto aplicado</th>
              <th>Monto del impuesto</th>
              <th>Total por línea</th>
            </tr>
          </thead>
          <tbody>${filas}</tbody>
        </table>
      </div>
    `;
      // Las ventas se pueden editar pero no eliminar
  document.getElementById('btn-editar').addEventListener('click', () => {
    window.location.href = `venta_form?id=${id}`;
  });
  } catch (err) {
    mostrarToast('Error: ' + err.message, 'error');
    tituloEl.textContent = 'Error';
  }
}

cargarDetalle();
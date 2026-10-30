const params = new URLSearchParams(window.location.search);
const id = params.get('id');
const esEdicion = !!id;

const form = document.getElementById('form-venta');
const tituloEl = document.getElementById('titulo');
const btnGuardar = document.getElementById('btn-guardar');
const tbodyLineas = document.getElementById('lineas');

const selectCliente = document.getElementById('cliente');
const selectVendedor = document.getElementById('vendedor');
const selectMetodo = document.getElementById('metodoEntrega');
const inputFecha = document.getElementById('fecha');

let clientes = [];
let productos = [];
let cargandoInicial = true;

function llenarSelect(select, items, valueKey, textKey, textoVacio) {
  const vacio = document.createElement('option');
  vacio.value = '';
  vacio.textContent = textoVacio;
  select.appendChild(vacio);

  items.forEach(item => {
    const opt = document.createElement('option');
    opt.value = item[valueKey];
    opt.textContent = item[textKey];
    select.appendChild(opt);
  });
}

// Fecha de hoy (local) en formato yyyy-mm-dd, para no permitir facturas futuras
function hoy() {
  return new Date().toLocaleDateString('en-CA');
}

// ----- Líneas de la factura -----

function actualizarBotonesQuitar() {
  const filas = tbodyLineas.querySelectorAll('tr');
  filas.forEach(tr => {
    tr.querySelector('.quitar').disabled = filas.length === 1;
  });
}

// Crea una fila de producto. `datos` solo viene al editar una factura existente.
function agregarLinea(datos = {}) {
  const tr = document.createElement('tr');
  tr.dataset.lineaId = datos.InvoiceLineID ?? '';

  const tdProducto = document.createElement('td');
  const selectProducto = document.createElement('select');
  selectProducto.className = 'producto';
  selectProducto.required = true;
  llenarSelect(selectProducto, productos, 'StockItemID', 'StockItemName', 'Seleccione un producto');
  tdProducto.appendChild(selectProducto);

  const tdCantidad = document.createElement('td');
  const inputCantidad = document.createElement('input');
  inputCantidad.type = 'number';
  inputCantidad.className = 'cantidad';
  inputCantidad.min = '1';
  inputCantidad.max = '100000';
  inputCantidad.step = '1';
  inputCantidad.required = true;
  tdCantidad.appendChild(inputCantidad);

  const tdPrecio = document.createElement('td');
  const inputPrecio = document.createElement('input');
  inputPrecio.type = 'number';
  inputPrecio.className = 'precio';
  inputPrecio.min = '0';
  inputPrecio.step = '0.01';
  inputPrecio.required = true;
  tdPrecio.appendChild(inputPrecio);

  const tdQuitar = document.createElement('td');
  const btnQuitar = document.createElement('button');
  btnQuitar.type = 'button';
  btnQuitar.className = 'quitar peligro';
  btnQuitar.textContent = 'Quitar';
  btnQuitar.addEventListener('click', () => {
    tr.remove();
    actualizarBotonesQuitar();
  });
  tdQuitar.appendChild(btnQuitar);

  // Al elegir un producto se precarga su precio de lista (el usuario puede cambiarlo)
  selectProducto.addEventListener('change', () => {
    const p = productos.find(x => String(x.StockItemID) === selectProducto.value);
    inputPrecio.value = p ? p.UnitPrice : '';
  });

  tr.append(tdProducto, tdCantidad, tdPrecio, tdQuitar);
  tbodyLineas.appendChild(tr);

  if (datos.StockItemID !== undefined) {
    selectProducto.value = datos.StockItemID;
    inputCantidad.value = datos.Cantidad;
    inputPrecio.value = datos.PrecioUnitario;
  }
  actualizarBotonesQuitar();
}

document.getElementById('btn-agregar-linea').addEventListener('click', () => agregarLinea());

// Al cambiar de cliente se sugiere su método de entrega habitual
selectCliente.addEventListener('change', () => {
  if (cargandoInicial) return;
  const c = clientes.find(x => String(x.CustomerID) === selectCliente.value);
  if (c) selectMetodo.value = c.DeliveryMethodID ?? '';
});

// ----- Carga inicial -----

async function inicializar() {
  inputFecha.max = hoy();

  try {
    const [cs, vendedores, metodos, ps] = await Promise.all([
      apiGet('/api/ventas/clientes'),
      apiGet('/api/ventas/vendedores'),
      apiGet('/api/metodos-entrega'),
      apiGet('/api/ventas/productos')
    ]);
    clientes = cs;
    productos = ps;

    llenarSelect(selectCliente, clientes, 'CustomerID', 'CustomerName', 'Seleccione un cliente');
    llenarSelect(selectVendedor, vendedores, 'PersonID', 'FullName', 'Seleccione un vendedor');
    llenarSelect(selectMetodo, metodos, 'DeliveryMethodID', 'DeliveryMethodName', 'Seleccione un método');

    if (esEdicion) {
      tituloEl.textContent = `Editar factura ${id}`;
      document.getElementById('titulo-tab').textContent = `Editar factura ${id}`;

      const { encabezado: e, lineas } = await apiGet(`/api/ventas/${id}`);
      selectCliente.value = e.CustomerID ?? '';
      selectVendedor.value = e.SalespersonPersonID ?? '';
      selectMetodo.value = e.DeliveryMethodID ?? '';
      inputFecha.value = e.Fecha ?? '';
      document.getElementById('numeroOrden').value = e.NumeroOrden ?? '';
      document.getElementById('instrucciones').value = e.InstruccionesEntrega ?? '';
      lineas.forEach(l => agregarLinea(l));
    } else {
      inputFecha.value = hoy();
      agregarLinea();
    }
  } catch (e) {
    mostrarToast('Error cargando datos: ' + e.message, 'error');
  } finally {
    cargandoInicial = false;
  }
}

// ----- Guardar -----

form.addEventListener('submit', async (e) => {
  e.preventDefault();

  if (inputFecha.value > hoy()) {
    mostrarToast('La fecha de la factura no puede ser futura.', 'error');
    return;
  }

  const filas = [...tbodyLineas.querySelectorAll('tr')];
  if (filas.length === 0) {
    mostrarToast('La factura debe tener al menos un producto.', 'error');
    return;
  }

  const lineas = [];
  for (let i = 0; i < filas.length; i++) {
    const tr = filas[i];
    const producto = parseInt(tr.querySelector('.producto').value);
    const cantidad = Number(tr.querySelector('.cantidad').value);
    const precioTxt = tr.querySelector('.precio').value;
    const precio = parseFloat(precioTxt);

    if (Number.isNaN(producto)) {
      mostrarToast(`Línea ${i + 1}: seleccione un producto.`, 'error');
      return;
    }
    if (!Number.isInteger(cantidad) || cantidad < 1 || cantidad > 100000) {
      mostrarToast(`Línea ${i + 1}: la cantidad debe ser un entero entre 1 y 100000.`, 'error');
      return;
    }
    if (precioTxt === '' || Number.isNaN(precio) || precio < 0) {
      mostrarToast(`Línea ${i + 1}: el precio unitario no puede estar vacío ni ser negativo.`, 'error');
      return;
    }

    lineas.push({
      lineaId: tr.dataset.lineaId ? parseInt(tr.dataset.lineaId) : null,
      producto,
      cantidad,
      precioUnitario: precio
    });
  }

  const body = {
    cliente: parseInt(selectCliente.value),
    vendedor: parseInt(selectVendedor.value),
    fecha: inputFecha.value,
    metodoEntrega: parseInt(selectMetodo.value),
    numeroOrden: document.getElementById('numeroOrden').value.trim(),
    instrucciones: document.getElementById('instrucciones').value.trim(),
    lineas
  };

  btnGuardar.disabled = true;
  try {
    if (esEdicion) {
      await apiPut(`/api/ventas/${id}`, body);
      guardarToast('Factura modificada correctamente');
      window.location.href = `detalle_ventas?id=${id}`;
    } else {
      const resultado = await apiPost('/api/ventas', body);
      guardarToast('Factura creada correctamente');
      window.location.href = `detalle_ventas?id=${resultado.InvoiceID}`;
    }
  } catch (err) {
    mostrarToast('Error al guardar: ' + err.message, 'error');
    btnGuardar.disabled = false;
  }
});

inicializar();
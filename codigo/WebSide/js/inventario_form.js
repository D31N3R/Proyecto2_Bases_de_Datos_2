const params = new URLSearchParams(window.location.search);
const id = params.get('id');
const esEdicion = !!id;

const form = document.getElementById('form-inventario');
const tituloEl = document.getElementById('titulo');
const btnGuardar = document.getElementById('btn-guardar');

const selectProveedor = document.getElementById('proveedor');
const selectGrupo = document.getElementById('grupo');
const selectColor = document.getElementById('color');
const selectUnidad = document.getElementById('unidadEmpaque');
const selectEmpaque = document.getElementById('empaqueExterior');

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

// Pone el valor en un input; si viene null/undefined deja vacio
function ponerValor(elId, valor) {
  document.getElementById(elId).value = valor ?? '';
}

async function inicializar() {
  try {
    const [proveedores, grupos, colores, empaques] = await Promise.all([
      apiGet('/api/inventarios/proveedores'),
      apiGet('/api/inventarios/grupos'),
      apiGet('/api/inventarios/colores'),
      apiGet('/api/inventarios/tipos-empaque')
    ]);

    llenarSelect(selectProveedor, proveedores, 'SupplierID', 'SupplierName', 'Seleccione un proveedor');
    llenarSelect(selectGrupo, grupos, 'StockGroupID', 'StockGroupName', 'Seleccione un grupo');
    llenarSelect(selectUnidad, empaques, 'PackageTypeID', 'PackageTypeName', 'Seleccione una unidad');
    llenarSelect(selectEmpaque, empaques, 'PackageTypeID', 'PackageTypeName', 'Seleccione un empaque');
    llenarSelect(selectColor, colores, 'ColorID', 'ColorName', 'Sin color');

    if (esEdicion) {
      tituloEl.textContent = 'Editar producto';
      document.getElementById('titulo-tab').textContent = 'Editar producto';

      // El grupo solo se elige al crear (el procedimiento de modificar no lo toca)
      selectGrupo.disabled = true;
      document.getElementById('label-grupo').style.display = 'none';

      const p = await apiGet(`/api/inventarios/${id}`);
      ponerValor('nombre', p.Nombre);
      ponerValor('marca', p.Marca);
      ponerValor('talla', p.Talla);
      ponerValor('cantidadEmpaque', p.CantidadEmpaque);
      ponerValor('impuesto', p.Impuesto);
      ponerValor('precioUnitario', p.PrecioUnitario);
      ponerValor('precioVenta', p.PrecioVenta);
      ponerValor('peso', p.Peso);
      ponerValor('cantidad', p.CantidadDisponible);
      ponerValor('ubicacion', p.Ubicacion);

      // Los combos se preseleccionan por ID (el detalle ya los devuelve)
      selectProveedor.value = p.SupplierID ?? '';
      selectColor.value = p.ColorID ?? '';
      selectUnidad.value = p.UnitPackageID ?? '';
      selectEmpaque.value = p.OuterPackageID ?? '';
    }
  } catch (e) {
    mostrarToast('Error cargando datos: ' + e.message, 'error');
  }
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();

  const nombre = document.getElementById('nombre').value.trim();
  const ubicacion = document.getElementById('ubicacion').value.trim();
  const precioUnitario = parseFloat(document.getElementById('precioUnitario').value);
  const precioVentaTxt = document.getElementById('precioVenta').value;

  // Validaciones que el HTML no cubre
  if (!nombre) {
    mostrarToast('El nombre no puede estar vacío.', 'error');
    return;
  }
  if (!ubicacion) {
    mostrarToast('La ubicación no puede estar vacía.', 'error');
    return;
  }
  if (precioVentaTxt !== '' && parseFloat(precioVentaTxt) < precioUnitario) {
    mostrarToast('El precio de venta no puede ser menor al precio unitario.', 'error');
    return;
  }

  const body = {
    nombre,
    proveedor: parseInt(selectProveedor.value),
    color: selectColor.value ? parseInt(selectColor.value) : null,
    marca: document.getElementById('marca').value.trim(),
    talla: document.getElementById('talla').value.trim(),
    unidadEmpaque: parseInt(selectUnidad.value),
    empaqueExterior: parseInt(selectEmpaque.value),
    cantidadEmpaque: parseInt(document.getElementById('cantidadEmpaque').value),
    impuesto: parseFloat(document.getElementById('impuesto').value),
    precioUnitario,
    precioVenta: precioVentaTxt === '' ? null : parseFloat(precioVentaTxt),
    peso: parseFloat(document.getElementById('peso').value),
    cantidad: parseInt(document.getElementById('cantidad').value),
    ubicacion
  };

  if (!esEdicion) {
    body.grupo = parseInt(selectGrupo.value);
  }

  btnGuardar.disabled = true;
  try {
    if (esEdicion) {
      await apiPut(`/api/inventarios/${id}`, body);
      guardarToast('Producto modificado correctamente');
      window.location.href = `detalle_inventarios?id=${id}`;
    } else {
      const resultado = await apiPost('/api/inventarios', body);
      guardarToast('Producto creado correctamente');
      window.location.href = `detalle_inventarios?id=${resultado.StockItemID}`;
    }
  } catch (e) {
    mostrarToast('Error al guardar: ' + e.message, 'error');
    btnGuardar.disabled = false;
  }
});

inicializar();
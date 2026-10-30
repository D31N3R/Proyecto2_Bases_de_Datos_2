const params = new URLSearchParams(window.location.search);
const id = params.get('id');
const esEdicion = !!id;

const form = document.getElementById('form-cliente');
const tituloEl = document.getElementById('titulo');
const btnGuardar = document.getElementById('btn-guardar');

const selectCategoria = document.getElementById('categoria');
const selectGrupo = document.getElementById('grupoCompra');
const selectMetodo = document.getElementById('metodo');
const selectClienteFacturar = document.getElementById('clienteFacturar');
const selectContacto = document.getElementById('contacto');
const selectContactoAlterno = document.getElementById('contactoAlterno');
const selectCiudad = document.getElementById('ciudad');
const inputDiasPago = document.getElementById('diasPago');
const inputLatitud = document.getElementById('latitud');
const inputLongitud = document.getElementById('longitud');

// Devuelve el texto de un campo sin espacios al inicio ni al final
function texto(idCampo) {
  return document.getElementById(idCampo).value.trim();
}

// Llena un select; la primera opción es el texto de ayuda
function llenarSelect(select, items, valueKey, textKey, textoVacio) {
  const fragmento = document.createDocumentFragment();

  const vacio = document.createElement('option');
  vacio.value = '';
  vacio.textContent = textoVacio;
  fragmento.appendChild(vacio);

  items.forEach(item => {
    const opt = document.createElement('option');
    opt.value = item[valueKey];
    opt.textContent = item[textKey];
    fragmento.appendChild(opt);
  });

  select.appendChild(fragmento);
}

async function inicializar() {
  try {
    const [categorias, grupos, metodos, clientes, personas, ciudades] = await Promise.all([
      apiGet('/api/clientes/categorias'),
      apiGet('/api/clientes/grupos-compra'),
      apiGet('/api/metodos-entrega'),
      apiGet('/api/clientes/lista'),
      apiGet('/api/personas'),
      apiGet('/api/ciudades')
    ]);

    llenarSelect(selectCategoria, categorias, 'CustomerCategoryID', 'CustomerCategoryName', 'Seleccione una categoría');
    llenarSelect(selectGrupo, grupos, 'BuyingGroupID', 'BuyingGroupName', 'Sin grupo de compra');
    llenarSelect(selectMetodo, metodos, 'DeliveryMethodID', 'DeliveryMethodName', 'Seleccione un método');
    llenarSelect(selectClienteFacturar, clientes, 'CustomerID', 'CustomerName', 'Este mismo cliente');
    llenarSelect(selectContacto, personas, 'PersonID', 'FullName', 'Seleccione un contacto');
    llenarSelect(selectContactoAlterno, personas, 'PersonID', 'FullName', 'Sin contacto alterno');
    llenarSelect(selectCiudad, ciudades, 'CityID', 'CityName', 'Seleccione una ciudad');

    if (esEdicion) {
      tituloEl.textContent = 'Editar cliente';
      document.getElementById('titulo-tab').textContent = 'Editar cliente';

      const c = await apiGet(`/api/clientes/${id}`);
      document.getElementById('nombre').value = c.Nombre || '';
      selectCategoria.value = c.CustomerCategoryID;
      selectGrupo.value = c.BuyingGroupID ?? '';
      selectMetodo.value = c.DeliveryMethodID;
      // Si se factura a sí mismo se deja "Este mismo cliente"
      selectClienteFacturar.value = c.BillToCustomerID === c.CustomerID ? '' : c.BillToCustomerID;
      selectContacto.value = c.PrimaryContactPersonID;
      selectContactoAlterno.value = c.AlternateContactPersonID ?? '';
      inputDiasPago.value = c.DiasGraciaPago;
      document.getElementById('telefono').value = c.Telefono || '';
      document.getElementById('fax').value = c.Fax || '';
      document.getElementById('sitioWeb').value = c.SitioWeb || '';
      document.getElementById('direccionEntrega1').value = c.DireccionEntrega1 || '';
      document.getElementById('direccionEntrega2').value = c.DireccionEntrega2 || '';
      selectCiudad.value = c.DeliveryCityID;
      document.getElementById('codigoPostal').value = c.CodigoPostal || '';
      document.getElementById('direccionPostal1').value = c.DireccionPostal1 || '';
      document.getElementById('direccionPostal2').value = c.DireccionPostal2 || '';
      inputLatitud.value = c.Latitud ?? '';
      inputLongitud.value = c.Longitud ?? '';
    }
  } catch (e) {
    mostrarToast('Error cargando datos: ' + e.message, 'error');
  }
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();

  const latitudVacia = inputLatitud.value === '';
  const longitudVacia = inputLongitud.value === '';

  const body = {
    nombre: texto('nombre'),
    categoria: parseInt(selectCategoria.value),
    grupoCompra: selectGrupo.value ? parseInt(selectGrupo.value) : null,
    metodo: parseInt(selectMetodo.value),
    clienteFacturar: selectClienteFacturar.value ? parseInt(selectClienteFacturar.value) : null,
    contacto: parseInt(selectContacto.value),
    contactoAlterno: selectContactoAlterno.value ? parseInt(selectContactoAlterno.value) : null,
    diasPago: parseInt(inputDiasPago.value),
    telefono: texto('telefono'),
    fax: texto('fax'),
    sitioWeb: texto('sitioWeb'),
    direccionEntrega1: texto('direccionEntrega1'),
    direccionEntrega2: texto('direccionEntrega2'),
    ciudad: parseInt(selectCiudad.value),
    codigoPostal: texto('codigoPostal'),
    direccionPostal1: texto('direccionPostal1'),
    direccionPostal2: texto('direccionPostal2'),
    latitud: latitudVacia ? null : parseFloat(inputLatitud.value),
    longitud: longitudVacia ? null : parseFloat(inputLongitud.value)
  };

  // Validaciones
  if (!body.nombre || !body.telefono || !body.fax || !body.sitioWeb ||
      !body.direccionEntrega1 || !body.codigoPostal || !body.direccionPostal1) {
    mostrarToast('Complete todos los campos obligatorios (*).', 'error');
    return;
  }
  if (latitudVacia !== longitudVacia) {
    mostrarToast('La latitud y la longitud se deben indicar juntas.', 'error');
    return;
  }

  btnGuardar.disabled = true;

  try {
    if (esEdicion) {
      await apiPut(`/api/clientes/${id}`, body);
      guardarToast('Cliente modificado correctamente');
      window.location.href = `detalle_clientes?id=${id}`;
    } else {
      const resultado = await apiPost('/api/clientes', body);
      guardarToast('Cliente creado correctamente');
      window.location.href = `detalle_clientes?id=${resultado.CustomerID}`;
    }
  } catch (e) {
    mostrarToast('Error al guardar: ' + e.message, 'error');
    btnGuardar.disabled = false;
  }
});

inicializar();
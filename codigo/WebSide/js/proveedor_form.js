const params = new URLSearchParams(window.location.search);
const id = params.get('id');
const esEdicion = !!id;

const form = document.getElementById('form-proveedor');
const tituloEl = document.getElementById('titulo');
const btnGuardar = document.getElementById('btn-guardar');

const selectCategoria = document.getElementById('categoria');
const selectMetodo = document.getElementById('metodo');
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
    const [categorias, metodos, personas, ciudades] = await Promise.all([
      apiGet('/api/proveedores/categorias'),
      apiGet('/api/metodos-entrega'),
      apiGet('/api/personas'),
      apiGet('/api/ciudades')
    ]);

    llenarSelect(selectCategoria, categorias, 'SupplierCategoryID', 'SupplierCategoryName', 'Seleccione una categoría');
    llenarSelect(selectMetodo, metodos, 'DeliveryMethodID', 'DeliveryMethodName', 'Sin método de entrega');
    llenarSelect(selectContacto, personas, 'PersonID', 'FullName', 'Seleccione un contacto');
    llenarSelect(selectContactoAlterno, personas, 'PersonID', 'FullName', 'Seleccione un contacto alterno');
    llenarSelect(selectCiudad, ciudades, 'CityID', 'CityName', 'Seleccione una ciudad');

    if (esEdicion) {
      tituloEl.textContent = 'Editar proveedor';
      document.getElementById('titulo-tab').textContent = 'Editar proveedor';

      const p = await apiGet(`/api/proveedores/${id}`);
      document.getElementById('nombre').value = p.Nombre || '';
      document.getElementById('referencia').value = p.CodigoProveedor || '';
      selectCategoria.value = p.SupplierCategoryID;
      selectMetodo.value = p.DeliveryMethodID ?? '';
      inputDiasPago.value = p.DiasGraciaPago;
      selectContacto.value = p.PrimaryContactPersonID;
      selectContactoAlterno.value = p.AlternateContactPersonID ?? '';
      document.getElementById('telefono').value = p.Telefono || '';
      document.getElementById('fax').value = p.Fax || '';
      document.getElementById('sitioWeb').value = p.SitioWeb || '';
      document.getElementById('direccionEntrega1').value = p.DireccionEntrega1 || '';
      document.getElementById('direccionEntrega2').value = p.DireccionEntrega2 || '';
      selectCiudad.value = p.DeliveryCityID;
      document.getElementById('codigoPostal').value = p.CodigoPostal || '';
      document.getElementById('direccionPostal1').value = p.DireccionPostal1 || '';
      document.getElementById('direccionPostal2').value = p.DireccionPostal2 || '';
      document.getElementById('nombreBanco').value = p.NombreBanco || '';
      document.getElementById('numeroCuenta').value = p.NumeroCuenta || '';
      inputLatitud.value = p.Latitud ?? '';
      inputLongitud.value = p.Longitud ?? '';
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
    referencia: texto('referencia'),
    categoria: parseInt(selectCategoria.value),
    metodo: selectMetodo.value ? parseInt(selectMetodo.value) : null,
    diasPago: parseInt(inputDiasPago.value),
    contacto: parseInt(selectContacto.value),
    contactoAlterno: parseInt(selectContactoAlterno.value),
    telefono: texto('telefono'),
    fax: texto('fax'),
    sitioWeb: texto('sitioWeb'),
    direccionEntrega1: texto('direccionEntrega1'),
    direccionEntrega2: texto('direccionEntrega2'),
    ciudad: parseInt(selectCiudad.value),
    codigoPostal: texto('codigoPostal'),
    direccionPostal1: texto('direccionPostal1'),
    direccionPostal2: texto('direccionPostal2'),
    nombreBanco: texto('nombreBanco'),
    numeroCuenta: texto('numeroCuenta'),
    latitud: latitudVacia ? null : parseFloat(inputLatitud.value),
    longitud: longitudVacia ? null : parseFloat(inputLongitud.value)
  };

  // Validaciones
  if (!body.nombre || !body.telefono || !body.fax || !body.sitioWeb ||
      !body.direccionEntrega1 || !body.codigoPostal || !body.direccionPostal1) {
    mostrarToast('Complete todos los campos obligatorios (*).', 'error');
    return;
  }
  if (body.contacto === body.contactoAlterno) {
    mostrarToast('El contacto alterno debe ser distinto al contacto primario.', 'error');
    return;
  }
  if (latitudVacia !== longitudVacia) {
    mostrarToast('La latitud y la longitud se deben indicar juntas.', 'error');
    return;
  }

  btnGuardar.disabled = true;

  try {
    if (esEdicion) {
      await apiPut(`/api/proveedores/${id}`, body);
      guardarToast('Proveedor modificado correctamente');
      window.location.href = `detalle_proveedores?id=${id}`;
    } else {
      const resultado = await apiPost('/api/proveedores', body);
      guardarToast('Proveedor creado correctamente');
      window.location.href = `detalle_proveedores?id=${resultado.SupplierID}`;
    }
  } catch (e) {
    mostrarToast('Error al guardar: ' + e.message, 'error');
    btnGuardar.disabled = false;
  }
});

inicializar();
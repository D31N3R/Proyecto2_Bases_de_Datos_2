const tbody = document.querySelector('#tabla-ventas tbody');
const tabla = document.getElementById('tabla-ventas');
const cargando = document.getElementById('cargando');
const sinResultados = document.getElementById('sin-resultados');
const paginacion = document.getElementById('paginacion');
const infoPagina = document.getElementById('info-pagina');
const btnAnterior = document.getElementById('btn-anterior');
const btnSiguiente = document.getElementById('btn-siguiente');

const inputNombre = document.getElementById('filtro-nombre');
const selectMetodo = document.getElementById('filtro-metodo');
const inputDesde = document.getElementById('filtro-desde');
const inputHasta = document.getElementById('filtro-hasta');
const inputMontoMin = document.getElementById('filtro-monto-min');
const inputMontoMax = document.getElementById('filtro-monto-max');

const POR_PAGINA = 50;
let paginaActual = 1;

// Muestra un monto con separador de miles y 2 decimales
function dinero(v) {
  return Number(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// Cargar métodos de entrega al abrir la página
async function cargarFiltros() {
  try {
    const metodos = await apiGet('/api/metodos-entrega');

    metodos.forEach(m => {
      const opt = document.createElement('option');
      opt.value = m.DeliveryMethodID;
      opt.textContent = m.DeliveryMethodName;
      selectMetodo.appendChild(opt);
    });
  } catch (e) {
    console.error('Error cargando filtros:', e);
  }
}

// Validar los rangos antes de consultar
function validarFiltros() {
  if (inputDesde.value && inputHasta.value && inputDesde.value > inputHasta.value) {
    return 'La fecha "Desde" no puede ser mayor que la fecha "Hasta".';
  }
  if (inputMontoMin.value !== '' && parseFloat(inputMontoMin.value) < 0) {
    return 'El monto mínimo no puede ser negativo.';
  }
  if (inputMontoMin.value !== '' && inputMontoMax.value !== '' &&
      parseFloat(inputMontoMin.value) > parseFloat(inputMontoMax.value)) {
    return 'El monto mínimo no puede ser mayor que el monto máximo.';
  }
  return '';
}

// Cargar facturas aplicando filtros acumulativos y la página actual
async function cargarVentas() {

  const mensaje = validarFiltros();
  if (mensaje) {
    mostrarToast('Error: ' + mensaje, 'error');
    return;
  }

  tbody.innerHTML = '';
  sinResultados.hidden = true;
  paginacion.hidden = true;
  cargando.hidden = false;
  tabla.hidden = true;

  const params = new URLSearchParams();
  const nombre = inputNombre.value.trim();
  if (nombre) params.append('nombre', nombre);
  if (selectMetodo.value) params.append('metodoEntrega', selectMetodo.value);
  if (inputDesde.value) params.append('fechaDesde', inputDesde.value);
  if (inputHasta.value) params.append('fechaHasta', inputHasta.value);
  if (inputMontoMin.value !== '') params.append('montoMin', inputMontoMin.value);
  if (inputMontoMax.value !== '') params.append('montoMax', inputMontoMax.value);
  params.append('pagina', paginaActual);

  try {
    const ventas = await apiGet(`/api/ventas?${params.toString()}`);

    if (ventas.length === 0) {
      sinResultados.hidden = false;
    } else {
      ventas.forEach(v => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td><a href="detalle_ventas?id=${v.NumeroFactura}">${v.NumeroFactura}</a></td>
          <td>${v.Fecha}</td>
          <td>${v.Cliente}</td>
          <td>${v.MetodoEntrega}</td>
          <td>${dinero(v.Monto)}</td>
        `;
        tbody.appendChild(tr);
      });

      // El total de facturas viene en cada fila desde la base de datos
      const total = ventas[0].TotalRegistros;
      const totalPaginas = Math.ceil(total / POR_PAGINA);
      infoPagina.textContent = `Página ${paginaActual} de ${totalPaginas} (${total} facturas)`;
      btnAnterior.disabled = paginaActual <= 1;
      btnSiguiente.disabled = paginaActual >= totalPaginas;
      paginacion.hidden = false;
    }
  } catch (e) {
    mostrarToast('Error: ' + e.message, 'error');
  } finally {
    cargando.hidden = true;
    tabla.hidden = false;
  }
}

// Una búsqueda nueva siempre empieza en la página 1
function buscar() {
  paginaActual = 1;
  cargarVentas();
}

// Eventos
document.getElementById('btn-buscar').addEventListener('click', buscar);

[inputNombre, inputMontoMin, inputMontoMax].forEach(input => {
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') buscar();
  });
});

selectMetodo.addEventListener('change', buscar);
inputDesde.addEventListener('change', buscar);
inputHasta.addEventListener('change', buscar);

btnAnterior.addEventListener('click', () => {
  paginaActual--;
  cargarVentas();
  window.scrollTo(0, 0);
});

btnSiguiente.addEventListener('click', () => {
  paginaActual++;
  cargarVentas();
  window.scrollTo(0, 0);
});

document.getElementById('btn-restaurar').addEventListener('click', () => {
  inputNombre.value = '';
  selectMetodo.value = '';
  inputDesde.value = '';
  inputHasta.value = '';
  inputMontoMin.value = '';
  inputMontoMax.value = '';
  buscar();
});

// Inicializar
(async () => {
  await cargarFiltros();
  await cargarVentas();
})();
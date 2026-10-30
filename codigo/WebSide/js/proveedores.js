const tbody = document.querySelector('#tabla-proveedores tbody');
const tabla = document.getElementById('tabla-proveedores');
const cargando = document.getElementById('cargando');
const sinResultados = document.getElementById('sin-resultados');
const inputNombre = document.getElementById('filtro-nombre');
const selectCategoria = document.getElementById('filtro-categoria');
const selectMetodo = document.getElementById('filtro-metodo');
const paginacion = document.getElementById('paginacion');
const infoPagina = document.getElementById('info-pagina');
const btnAnterior = document.getElementById('btn-anterior');
const btnSiguiente = document.getElementById('btn-siguiente');

const POR_PAGINA = 50;
let paginaActual = 1;
// Cargar selects al abrir la página
async function cargarFiltros() {
  try {
    const categorias = await apiGet('/api/proveedores/categorias');

    categorias.forEach(c => {
      const opt = document.createElement('option');
      opt.value = c.SupplierCategoryID;
      opt.textContent = c.SupplierCategoryName;
      selectCategoria.appendChild(opt);
    });
  } catch (e) {
    console.error('Error cargando filtros:', e);
  }
}

// Cargar proveedores aplicando filtros acumulativos y la página actual
async function cargarProveedores() {
  tbody.innerHTML = '';
  sinResultados.hidden = true;
  paginacion.hidden = true;
  cargando.hidden = false;
  tabla.hidden = true;

  const params = new URLSearchParams();
  const nombre = inputNombre.value.trim();
  if (nombre) params.append('nombre', nombre);
  if (selectCategoria.value) params.append('categoria', selectCategoria.value);
  params.append('pagina', paginaActual);

  try {
    const proveedores = await apiGet(`/api/proveedores?${params.toString()}`);

    if (proveedores.length === 0) {
      sinResultados.hidden = false;
    } else {
      proveedores.forEach(c => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td><a href="detalle_proveedores?id=${c.SupplierID}">${c.Nombre}</a></td>
          <td>${c.Categoria}</td>
          <td>${c.MetodoEntrega}</td>
        `;
        tbody.appendChild(tr);
      });

      // El total de proveedores viene en cada fila desde la base de datos
      const total = proveedores[0].TotalRegistros;
      const totalPaginas = Math.ceil(total / POR_PAGINA);
      infoPagina.textContent = `Página ${paginaActual} de ${totalPaginas} (${total} proveedores)`;
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
  cargarProveedores();
}

// Eventos
document.getElementById('btn-buscar').addEventListener('click', buscar);

inputNombre.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') buscar();
});

selectCategoria.addEventListener('change', buscar);

btnAnterior.addEventListener('click', () => {
  paginaActual--;
  cargarProveedores();
  window.scrollTo(0, 0);
});

btnSiguiente.addEventListener('click', () => {
  paginaActual++;
  cargarProveedores();
  window.scrollTo(0, 0);
});

document.getElementById('btn-restaurar').addEventListener('click', () => {
  inputNombre.value = '';
  selectCategoria.value = '';
  buscar();
});

// Inicializar
(async () => {
  await cargarFiltros();
  await cargarProveedores();
})();
const tbody = document.querySelector('#tabla-inventarios tbody');
const tabla = document.getElementById('tabla-inventarios');
const cargando = document.getElementById('cargando');
const sinResultados = document.getElementById('sin-resultados');
const inputNombre = document.getElementById('filtro-nombre');
const selectGrupo = document.getElementById('filtro-grupo');
const paginacion = document.getElementById('paginacion');
const infoPagina = document.getElementById('info-pagina');
const btnAnterior = document.getElementById('btn-anterior');
const btnSiguiente = document.getElementById('btn-siguiente');

const POR_PAGINA = 50;
let paginaActual = 1;
// Cargar selects al abrir la página
async function cargarFiltros() {
  try {
    const [grupos] = await Promise.all([
      apiGet('/api/inventarios/grupos'),
    ]);

    grupos.forEach(c => {
      const opt = document.createElement('option');
      opt.value = c.StockGroupID;
      opt.textContent = c.StockGroupName;
      selectGrupo.appendChild(opt);
    });

  } catch (e) {
    console.error('Error cargando filtros:', e);
  }
}

// Cargar productos aplicando filtros acumulativos y la página actual
async function cargarProductos() {
  tbody.innerHTML = '';
  sinResultados.hidden = true;
  paginacion.hidden = true;
  cargando.hidden = false;
  tabla.hidden = true;

  const params = new URLSearchParams();
  const nombre = inputNombre.value.trim();
  if (nombre) params.append('nombre', nombre);
  if (selectGrupo.value) params.append('grupo', selectGrupo.value);
  params.append('pagina', paginaActual);

  try {
    const productos = await apiGet(`/api/inventarios?${params.toString()}`);

    if (productos.length === 0) {
      sinResultados.hidden = false;
    } else {
      productos.forEach(c => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td><a href="detalle_inventarios?id=${c.StockItemID}">${c.Nombre}</a></td>
          <td>${c.Grupo}</td>
          <td>${c.CantidadInventario}</td>
        `;
        tbody.appendChild(tr);
      });

      // El total de productos viene en cada fila desde la base de datos
      const total = productos[0].TotalRegistros;
      const totalPaginas = Math.ceil(total / POR_PAGINA);
      infoPagina.textContent = `Página ${paginaActual} de ${totalPaginas} (${total} productos)`;
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
  cargarProductos();
}
// Eventos
document.getElementById('btn-buscar').addEventListener('click', buscar);

inputNombre.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') buscar();
});

selectGrupo.addEventListener('change', buscar);

btnAnterior.addEventListener('click', () => {
  paginaActual--;
  cargarProductos();
  window.scrollTo(0, 0);
});

btnSiguiente.addEventListener('click', () => {
  paginaActual++;
  cargarProductos();
  window.scrollTo(0, 0);
});

document.getElementById('btn-restaurar').addEventListener('click', () => {
  inputNombre.value = '';
  selectGrupo.value = '';
  buscar();
});
// Inicializar
(async () => {
  await cargarFiltros();
  await cargarProductos();
})();
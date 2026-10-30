const express = require('express');
const { getConnection, sql } = require('../db');

const router = express.Router();

// ==================== AUXILIARES ====================

// GET /api/estadisticas/anios-ventas
router.get('/estadisticas/anios-ventas', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .execute('Api.usp_Estadisticas_AniosVentas');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/estadisticas/anios-compras
router.get('/estadisticas/anios-compras', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .execute('Api.usp_Estadisticas_AniosCompras');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/estadisticas/productos
router.get('/estadisticas/productos', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('StockGroupID', sql.Int, req.query.grupo ? parseInt(req.query.grupo) : null)
      .execute('Api.usp_Estadisticas_Productos');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/estadisticas/subgrupos?grupo=X
router.get('/estadisticas/subgrupos', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('StockGroupID', sql.Int, req.query.grupo ? parseInt(req.query.grupo) : null)
      .execute('Api.usp_Estadisticas_SubGrupos');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ==================== REPORTES ====================

// Reporte 1
// GET /api/estadisticas/compras-proveedores?categoria=X&proveedor=Y
router.get('/estadisticas/compras-proveedores', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('Categoria', sql.NVarChar(100), req.query.categoria || null)
      .input('Proveedor', sql.NVarChar(100), req.query.proveedor || null)
      .input('Pagina', sql.Int, req.query.pagina ? parseInt(req.query.pagina) : 1)
      .input('TamanoPagina', sql.Int, req.query.tamano ? parseInt(req.query.tamano) : 10)
      .execute('Api.usp_Estadisticas_ComprasProveedores');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Reporte 2
// GET /api/estadisticas/ventas-clientes?categoria=X&cliente=Y
router.get('/estadisticas/ventas-clientes', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('Categoria', sql.NVarChar(100), req.query.categoria || null)
      .input('Cliente', sql.NVarChar(100), req.query.cliente || null)
      .input('Pagina', sql.Int, req.query.pagina ? parseInt(req.query.pagina) : 1)
      .input('TamanoPagina', sql.Int, req.query.tamano ? parseInt(req.query.tamano) : 10)
      .execute('Api.usp_Estadisticas_VentasClientes');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Reporte 3
// GET /api/estadisticas/top-productos?anioDesde=X&anioHasta=Y
router.get('/estadisticas/top-productos', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('AnioDesde', sql.Int, req.query.anioDesde ? parseInt(req.query.anioDesde) : null)
      .input('AnioHasta', sql.Int, req.query.anioHasta ? parseInt(req.query.anioHasta) : null)
      .input('Pagina', sql.Int, req.query.pagina ? parseInt(req.query.pagina) : 1)
      .input('TamanoPagina', sql.Int, req.query.tamano ? parseInt(req.query.tamano) : 10)
      .execute('Api.usp_Estadisticas_TopProductos');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Reporte 4
// GET /api/estadisticas/top-clientes?anioDesde=X&anioHasta=Y
router.get('/estadisticas/top-clientes', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('AnioDesde', sql.Int, req.query.anioDesde ? parseInt(req.query.anioDesde) : null)
      .input('AnioHasta', sql.Int, req.query.anioHasta ? parseInt(req.query.anioHasta) : null)
      .input('Pagina', sql.Int, req.query.pagina ? parseInt(req.query.pagina) : 1)
      .input('TamanoPagina', sql.Int, req.query.tamano ? parseInt(req.query.tamano) : 10)
      .execute('Api.usp_Estadisticas_TopClientes');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Reporte 5
// GET /api/estadisticas/top-proveedores?anioDesde=X&anioHasta=Y
router.get('/estadisticas/top-proveedores', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('AnioDesde', sql.Int, req.query.anioDesde ? parseInt(req.query.anioDesde) : null)
      .input('AnioHasta', sql.Int, req.query.anioHasta ? parseInt(req.query.anioHasta) : null)
      .input('Pagina', sql.Int, req.query.pagina ? parseInt(req.query.pagina) : 1)
      .input('TamanoPagina', sql.Int, req.query.tamano ? parseInt(req.query.tamano) : 10)
      .execute('Api.usp_Estadisticas_TopProveedores');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Reporte 6
// GET /api/estadisticas/matriz-ventas
router.get('/estadisticas/matriz-ventas', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
    .input('Pagina', sql.Int, req.query.pagina ? parseInt(req.query.pagina) : 1)
    .input('TamanoPagina', sql.Int, req.query.tamano ? parseInt(req.query.tamano) : 10)  
    .execute('Api.usp_Estadisticas_MatrizVentas');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Reporte 7
// GET /api/estadisticas/seguimiento-clientes?anio=X&mes=Y&grupo=Z&producto=W&pagina=1&tamano=50
router.get('/estadisticas/seguimiento-clientes', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('Anio', sql.Int, req.query.anio ? parseInt(req.query.anio) : null)
      .input('Mes', sql.Int, req.query.mes ? parseInt(req.query.mes) : null)
      .input('StockGroupID', sql.Int, req.query.grupo ? parseInt(req.query.grupo) : null)
      .input('StockSubGroupID', sql.Int, req.query.subgrupo ? parseInt(req.query.subgrupo) : null)
      .input('Pagina', sql.Int, req.query.pagina ? parseInt(req.query.pagina) : 1)
      .input('TamanoPagina', sql.Int, req.query.tamano ? parseInt(req.query.tamano) : 50)
      .execute('Api.usp_Estadisticas_SeguimientoClientes');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Reporte 8
// GET /api/estadisticas/seguimiento-proveedores?anio=X&mes=Y&grupo=Z&producto=W&pagina=1&tamano=50
router.get('/estadisticas/seguimiento-proveedores', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('Anio', sql.Int, req.query.anio ? parseInt(req.query.anio) : null)
      .input('Mes', sql.Int, req.query.mes ? parseInt(req.query.mes) : null)
      .input('StockGroupID', sql.Int, req.query.grupo ? parseInt(req.query.grupo) : null)
      .input('StockSubGroupID', sql.Int, req.query.subgrupo ? parseInt(req.query.subgrupo) : null)
      .input('Pagina', sql.Int, req.query.pagina ? parseInt(req.query.pagina) : 1)
      .input('TamanoPagina', sql.Int, req.query.tamano ? parseInt(req.query.tamano) : 50)
      .execute('Api.usp_Estadisticas_SeguimientoProveedores');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Reporte 9
// GET /api/estadisticas/rotacion-inventario?grupo=X&anio=Y&proveedor=Z
router.get('/estadisticas/rotacion-inventario', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('StockGroupID', sql.Int, req.query.grupo ? parseInt(req.query.grupo) : null)
      .input('Anio', sql.Int, req.query.anio ? parseInt(req.query.anio) : null)
      .input('SupplierID', sql.Int, req.query.proveedor ? parseInt(req.query.proveedor) : null)
      .input('Pagina', sql.Int, req.query.pagina ? parseInt(req.query.pagina) : 1)
      .input('TamanoPagina', sql.Int, req.query.tamano ? parseInt(req.query.tamano) : 10)
      .execute('Api.usp_Estadisticas_RotacionInventario');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Reporte 10
// GET /api/estadisticas/metodo-envio-favorito?anio=X&mes=Y&categoriaCliente=Z&grupo=W&producto=V
router.get('/estadisticas/metodo-envio-favorito', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('Anio', sql.Int, req.query.anio ? parseInt(req.query.anio) : null)
      .input('Mes', sql.Int, req.query.mes ? parseInt(req.query.mes) : null)
      .input('CustomerCategoryID', sql.Int, req.query.categoriaCliente ? parseInt(req.query.categoriaCliente) : null)
      .input('StockGroupID', sql.Int, req.query.grupo ? parseInt(req.query.grupo) : null)
      .input('StockItemID', sql.Int, req.query.producto ? parseInt(req.query.producto) : null)
      .input('Pagina', sql.Int, req.query.pagina ? parseInt(req.query.pagina) : 1)
      .input('TamanoPagina', sql.Int, req.query.tamano ? parseInt(req.query.tamano) : 10)
      .execute('Api.usp_Estadisticas_MetodoEnvioFavorito');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
const express = require('express');
const { getConnection, sql } = require('../db');

const router = express.Router();

// Convierte '' / undefined en null (para campos opcionales)
const aNull = (v) => (v === '' || v === undefined ? null : v);

// GET /api/inventarios/grupos
router.get('/inventarios/grupos', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .execute('Api.usp_Inventario_Grupos');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/inventarios/colores
router.get('/inventarios/colores', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .execute('Api.usp_Inventario_Colores');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/inventarios/tipos-empaque
router.get('/inventarios/tipos-empaque', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .execute('Api.usp_Inventario_TiposEmpaque');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/inventarios/proveedores
router.get('/inventarios/proveedores', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .execute('Api.usp_Inventario_Proveedores');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/inventarios?nombre=X&grupo=Y
router.get('/inventarios', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('Nombre', sql.NVarChar(100), req.query.nombre || null)
      .input('StockGroupID', sql.Int, req.query.grupo ? parseInt(req.query.grupo) : null)
      .input('Pagina', sql.Int, parseInt(req.query.pagina) || 1)
      .execute('Api.usp_Inventario_Listar');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/inventarios/:id
router.get('/inventarios/:id', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('StockItemID', sql.Int, req.params.id)
      .execute('Api.usp_Inventario_Detalle');

    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Producto no encontrado' });
    }
    res.json(result.recordset[0]);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// POST /api/inventarios - crear
router.post('/inventarios', async (req, res) => {
  try {
    const b = req.body;
    const pool = await getConnection();
    const request = pool.request()
      .input('StockItemName', sql.NVarChar(100), b.nombre)
      .input('SupplierID', sql.Int, b.proveedor)
      .input('UnitPackageID', sql.Int, b.unidadEmpaque)
      .input('OuterPackageID', sql.Int, b.empaqueExterior)
      .input('QuantityPerOuter', sql.Int, b.cantidadEmpaque)
      .input('TaxRate', sql.Decimal(18, 3), b.impuesto)
      .input('UnitPrice', sql.Decimal(18, 2), b.precioUnitario)
      .input('TypicalWeightPerUnit', sql.Decimal(18, 3), b.peso)
      .input('StockGroupID', sql.Int, b.grupo)
      .input('BinLocation', sql.NVarChar(20), b.ubicacion)
      .input('ColorID', sql.Int, aNull(b.color))
      .input('Brand', sql.NVarChar(50), aNull(b.marca))
      .input('Size', sql.NVarChar(20), aNull(b.talla))
      .input('RecommendedRetailPrice', sql.Decimal(18, 2), aNull(b.precioVenta))
      .input('QuantityOnHand', sql.Int, aNull(b.cantidad) ?? 0)
      .output('NuevoStockItemID', sql.Int);

    const result = await request.execute('Api.usp_Inventario_Crear');
    res.status(201).json({ StockItemID: result.output.NuevoStockItemID });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// PUT /api/inventarios/:id - modificar
router.put('/inventarios/:id', async (req, res) => {
  try {
    const b = req.body;
    const pool = await getConnection();
    await pool.request()
      .input('StockItemID', sql.Int, req.params.id)
      .input('StockItemName', sql.NVarChar(100), b.nombre)
      .input('SupplierID', sql.Int, b.proveedor)
      .input('UnitPackageID', sql.Int, b.unidadEmpaque)
      .input('OuterPackageID', sql.Int, b.empaqueExterior)
      .input('QuantityPerOuter', sql.Int, b.cantidadEmpaque)
      .input('TaxRate', sql.Decimal(18, 3), b.impuesto)
      .input('UnitPrice', sql.Decimal(18, 2), b.precioUnitario)
      .input('TypicalWeightPerUnit', sql.Decimal(18, 3), b.peso)
      .input('BinLocation', sql.NVarChar(20), b.ubicacion)
      .input('ColorID', sql.Int, aNull(b.color))
      .input('Brand', sql.NVarChar(50), aNull(b.marca))
      .input('Size', sql.NVarChar(20), aNull(b.talla))
      .input('RecommendedRetailPrice', sql.Decimal(18, 2), aNull(b.precioVenta))
      .input('QuantityOnHand', sql.Int, aNull(b.cantidad) ?? 0)
      .execute('Api.usp_Inventario_Modificar');
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// DELETE /api/inventarios/:id - eliminar
router.delete('/inventarios/:id', async (req, res) => {
  try {
    const pool = await getConnection();
    await pool.request()
      .input('StockItemID', sql.Int, req.params.id)
      .execute('Api.usp_Inventario_Eliminar');
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
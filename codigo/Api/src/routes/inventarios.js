const express = require('express');
const { getConnection, sql } = require('../db');

const router = express.Router();

const aNull = (v) => (v === '' || v === undefined ? null : v);

// Lecturas: van al nodo del usuario logueado (el catalogo es igual en los 3)
router.get('/inventarios/grupos', async (req, res) => {
  try {
    const pool = await getConnection(req.nodo);
    const result = await pool.request().execute('Api.usp_Inventario_Grupos');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/inventarios/colores', async (req, res) => {
  try {
    const pool = await getConnection(req.nodo);
    const result = await pool.request().execute('Api.usp_Inventario_Colores');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/inventarios/tipos-empaque', async (req, res) => {
  try {
    const pool = await getConnection(req.nodo);
    const result = await pool.request().execute('Api.usp_Inventario_TiposEmpaque');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/inventarios/proveedores', async (req, res) => {
  try {
    const pool = await getConnection(req.nodo);
    const result = await pool.request().execute('Api.usp_Inventario_Proveedores');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.get('/inventarios', async (req, res) => {
  try {
    const pool = await getConnection(req.nodo);
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

router.get('/inventarios/:id', async (req, res) => {
  try {
    const pool = await getConnection(req.nodo);
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

// Escrituras de productos: SIEMPRE van a Corp, sin importar la sucursal
// del usuario. Corp las replica automaticamente a sj y limon.
router.post('/inventarios', async (req, res) => {
  try {
    const b = req.body;
    const pool = await getConnection('corp');
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

router.put('/inventarios/:id', async (req, res) => {
  try {
    const b = req.body;
    const pool = await getConnection('corp');
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

router.delete('/inventarios/:id', async (req, res) => {
  try {
    const pool = await getConnection('corp');
    await pool.request()
      .input('StockItemID', sql.Int, req.params.id)
      .execute('Api.usp_Inventario_Eliminar');
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
const express = require('express');
const { getConnection, sql } = require('../db');

const router = express.Router();

const aNull = (v) => (v === '' || v === undefined ? null : v);

// El catalogo (nombre, precio...) vive en Corp, pero la cantidad y la ubicacion son
// inventario PROPIO de cada sucursal: se guardan en el nodo del usuario logueado.
// Un producto recien creado en Corp tarda unos segundos en replicarse a la sucursal
// (error 50073), asi que al crear se reintenta unos segundos.
async function guardarInventario(nodo, id, b, esperarReplicacion) {
  if (nodo === 'corp') return; // Corp no guarda inventario
  const pool = await getConnection(nodo);
  const intentos = esperarReplicacion ? 10 : 1;

  for (let i = 1; i <= intentos; i++) {
    try {
      await pool.request()
        .input('StockItemID', sql.Int, id)
        .input('QuantityOnHand', sql.Int, aNull(b.cantidad) ?? 0)
        .input('BinLocation', sql.NVarChar(20), b.ubicacion)
        .execute('Api.usp_Inventario_AjustarCantidad');
      return;
    } catch (error) {
      if (error.number !== 50073 || i === intentos) throw error;
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }
}

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
    const id = result.output.NuevoStockItemID;

    try {
      await guardarInventario(req.nodo, id, b, true);
    } catch (error) {
      return res.status(503).json({
        error: `El producto se creó en el catálogo, pero no se pudo guardar su inventario en esta sucursal (${error.message}). Edítelo para ingresar la cantidad.`
      });
    }

    res.status(201).json({ StockItemID: id });
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
      .input('Version', sql.VarChar(27), aNull(b.version))
      .execute('Api.usp_Inventario_Modificar');

    try {
      await guardarInventario(req.nodo, req.params.id, b, false);
    } catch (error) {
      return res.status(503).json({
        error: `El producto se actualizó, pero no se pudo guardar su inventario en esta sucursal (${error.message}). Vuelva a guardar.`
      });
    }

    res.json({ ok: true });
  } catch (error) {
    // 50080 = otro usuario modifico el producto despues de que se cargo el formulario
    res.status(error.number === 50080 ? 409 : 500).json({ error: error.message });
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
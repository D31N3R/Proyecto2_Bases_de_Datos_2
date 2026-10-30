const express = require('express');
const { getConnection, sql } = require('../db');

const router = express.Router();
// Convierte '' / undefined en null (para campos opcionales)
const aNull = (v) => (v === '' || v === undefined ? null : v);

// Errores de reglas de negocio (THROW 5xxxx en los SP) -> 400; el resto -> 500
const estado = (error) => (error.number >= 50000 ? 400 : 500);

// Arma el JSON de líneas que recibe el procedimiento almacenado
function armarLineas(lineas) {
  return JSON.stringify(lineas.map(l => ({
    InvoiceLineID: aNull(l.lineaId),
    StockItemID: l.producto,
    Quantity: l.cantidad,
    UnitPrice: aNull(l.precioUnitario)
  })));
}

// Parámetros comunes de crear y modificar
function parametrosVenta(request, b) {
  return request
    .input('CustomerID', sql.Int, b.cliente)
    .input('SalespersonPersonID', sql.Int, b.vendedor)
    .input('InvoiceDate', sql.VarChar(10), b.fecha)
    .input('DeliveryMethodID', sql.Int, aNull(b.metodoEntrega))
    .input('CustomerPurchaseOrderNumber', sql.NVarChar(20), aNull(b.numeroOrden))
    .input('DeliveryInstructions', sql.NVarChar(sql.MAX), aNull(b.instrucciones))
    .input('Lineas', sql.NVarChar(sql.MAX), armarLineas(b.lineas));
}

// GET /api/ventas/clientes
router.get('/ventas/clientes', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request().execute('Api.usp_Ventas_Clientes');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/ventas/vendedores
router.get('/ventas/vendedores', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request().execute('Api.usp_Ventas_Vendedores');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/ventas/productos
router.get('/ventas/productos', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request().execute('Api.usp_Ventas_Productos');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/ventas?nombre=X&metodoEntrega=Y&fechaDesde=Z&fechaHasta=W&montoMin=A&montoMax=B&pagina=N
router.get('/ventas', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('Nombre', sql.NVarChar(100), req.query.nombre || null)
      .input('DeliveryMethodID', sql.Int, req.query.metodoEntrega ? parseInt(req.query.metodoEntrega) : null)
      .input('FechaDesde', sql.VarChar(10), req.query.fechaDesde || null)
      .input('FechaHasta', sql.VarChar(10), req.query.fechaHasta || null)
      .input('MontoMin', sql.Decimal(18, 2), req.query.montoMin ? parseFloat(req.query.montoMin) : null)
      .input('MontoMax', sql.Decimal(18, 2), req.query.montoMax ? parseFloat(req.query.montoMax) : null)
      .input('Pagina', sql.Int, parseInt(req.query.pagina) || 1)
      .execute('Api.usp_Ventas_Listar');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/ventas/:id
router.get('/ventas/:id', async (req, res) => {
  try {
    const pool = await getConnection();

    const encabezado = await pool.request()
      .input('InvoiceID', sql.Int, req.params.id)
      .execute('Api.usp_Ventas_Detalle');

    if (encabezado.recordset.length === 0) {
      return res.status(404).json({ error: 'Factura no encontrada' });
    }

    const lineas = await pool.request()
      .input('InvoiceID', sql.Int, req.params.id)
      .execute('Api.usp_Ventas_Lineas');

    res.json({
      encabezado: encabezado.recordset[0],
      lineas: lineas.recordset
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// POST /api/ventas - crear (encabezado + líneas en una transacción)
router.post('/ventas', async (req, res) => {
  try {
    const b = req.body;
    if (!Array.isArray(b.lineas)) {
      return res.status(400).json({ error: 'Debe enviar la lista de líneas de la factura.' });
    }
    const pool = await getConnection();
    const request = parametrosVenta(pool.request(), b)
      .output('NuevoInvoiceID', sql.Int);

    const result = await request.execute('Api.usp_Ventas_Crear');
    res.status(201).json({ InvoiceID: result.output.NuevoInvoiceID });
  } catch (error) {
    res.status(estado(error)).json({ error: error.message });
  }
});

// PUT /api/ventas/:id - modificar (no existe DELETE: las ventas no se eliminan)
router.put('/ventas/:id', async (req, res) => {
  try {
    const b = req.body;
    if (!Array.isArray(b.lineas)) {
      return res.status(400).json({ error: 'Debe enviar la lista de líneas de la factura.' });
    }
    const pool = await getConnection();
    await parametrosVenta(pool.request(), b)
      .input('InvoiceID', sql.Int, req.params.id)
      .execute('Api.usp_Ventas_Modificar');
    res.json({ ok: true });
  } catch (error) {
    res.status(estado(error)).json({ error: error.message });
  }
});

module.exports = router;
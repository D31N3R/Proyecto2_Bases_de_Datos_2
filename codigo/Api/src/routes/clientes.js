const express = require('express');
const { getConnection, sql } = require('../db');

const router = express.Router();

// Devuelve null si el campo viene vacío; el 0 sí se deja pasar (por ejemplo, una latitud en el ecuador)
function opcional(valor) {
  return valor === undefined || valor === null || valor === '' ? null : valor;
}

// Agrega los parámetros que comparten Crear y Modificar
function agregarCampos(request, body) {
  return request
    .input('CustomerName', sql.NVarChar(100), body.nombre)
    .input('CustomerCategoryID', sql.Int, body.categoria)
    .input('BuyingGroupID', sql.Int, opcional(body.grupoCompra))
    .input('DeliveryMethodID', sql.Int, body.metodo)
    .input('BillToCustomerID', sql.Int, opcional(body.clienteFacturar))
    .input('PrimaryContactPersonID', sql.Int, body.contacto)
    .input('AlternateContactPersonID', sql.Int, opcional(body.contactoAlterno))
    .input('PaymentDays', sql.Int, body.diasPago)
    .input('PhoneNumber', sql.NVarChar(20), body.telefono)
    .input('FaxNumber', sql.NVarChar(20), body.fax)
    .input('WebsiteURL', sql.NVarChar(256), body.sitioWeb)
    .input('DeliveryAddressLine1', sql.NVarChar(60), body.direccionEntrega1)
    .input('DeliveryAddressLine2', sql.NVarChar(60), body.direccionEntrega2 || null)
    .input('DeliveryCityID', sql.Int, body.ciudad)
    .input('DeliveryPostalCode', sql.NVarChar(10), body.codigoPostal)
    .input('PostalAddressLine1', sql.NVarChar(60), body.direccionPostal1)
    .input('PostalAddressLine2', sql.NVarChar(60), body.direccionPostal2 || null)
    .input('Latitud', sql.Decimal(9, 6), opcional(body.latitud))
    .input('Longitud', sql.Decimal(9, 6), opcional(body.longitud));
}

// GET /api/clientes/categorias
router.get('/clientes/categorias', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .execute('Api.usp_Clientes_Categorias');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/clientes/grupos-compra
router.get('/clientes/grupos-compra', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .execute('Api.usp_Clientes_GruposCompra');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/clientes/lista - ID y nombre de todos los clientes (para el combo de cliente por facturar)
router.get('/clientes/lista', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .execute('Api.usp_Clientes_ListarSimple');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/clientes?nombre=X&categoria=Y&metodo=Z
router.get('/clientes', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('Nombre', sql.NVarChar(100), req.query.nombre || null)
      .input('CustomerCategoryID', sql.Int, req.query.categoria ? parseInt(req.query.categoria) : null)
      .input('DeliveryMethodID', sql.Int, req.query.metodo ? parseInt(req.query.metodo) : null)
      .input('Pagina', sql.Int, parseInt(req.query.pagina) || 1)
      .execute('Api.usp_Clientes_Listar');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/clientes/:id
router.get('/clientes/:id', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('CustomerID', sql.Int, req.params.id)
      .execute('Api.usp_Clientes_Detalle');

    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Cliente no encontrado' });
    }
    res.json(result.recordset[0]);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// POST /api/clientes - crear
router.post('/clientes', async (req, res) => {
  try {
    const pool = await getConnection();
    const request = agregarCampos(pool.request(), req.body)
      .output('NuevoCustomerID', sql.Int);

    const result = await request.execute('Api.usp_Clientes_Crear');
    res.status(201).json({ CustomerID: result.output.NuevoCustomerID });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// PUT /api/clientes/:id - modificar
router.put('/clientes/:id', async (req, res) => {
  try {
    const pool = await getConnection();
    const request = agregarCampos(pool.request(), req.body)
      .input('CustomerID', sql.Int, req.params.id);

    await request.execute('Api.usp_Clientes_Modificar');
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// DELETE /api/clientes/:id - eliminar
router.delete('/clientes/:id', async (req, res) => {
  try {
    const pool = await getConnection();
    await pool.request()
      .input('CustomerID', sql.Int, req.params.id)
      .execute('Api.usp_Clientes_Eliminar');
      res.json({ ok: true });
    } catch (error) {
      res.status(500).json({ error: error.message || 'Error interno al eliminar el cliente' });
  }
});

module.exports = router;
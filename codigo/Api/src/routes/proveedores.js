const express = require('express');
const { getConnection, sql } = require('../db');

const router = express.Router();
function opcional(valor) {
  return valor === undefined || valor === null || valor === '' ? null : valor;
}

function agregarCampos(request, body) {
  return request
    .input('SupplierName', sql.NVarChar(100), req.body.nombre)
    .input('SupplierReference', sql.NVarChar(20), req.body.referencia || null)
    .input('SupplierCategoryID', sql.Int, req.body.categoria)
    .input('DeliveryMethodID', sql.Int, req.body.metodo)
    .input('PrimaryContactPersonID', sql.Int, req.body.contacto)
    .input('AlternateContactPersonID', sql.Int, req.body.contactoAlterno)
    .input('PaymentDays', sql.Int, req.body.diasPago)
    .input('PhoneNumber', sql.NVarChar(20), req.body.telefono)
    .input('FaxNumber', sql.NVarChar(20), req.body.fax)
    .input('WebsiteURL', sql.NVarChar(256), req.body.sitioWeb)
    .input('DeliveryAddressLine1', sql.NVarChar(60), req.body.direccionEntrega1)
    .input('DeliveryAddressLine2', sql.NVarChar(60), req.body.direccionEntrega2 || null)
    .input('DeliveryCityID', sql.Int, req.body.ciudad)
    .input('DeliveryPostalCode', sql.NVarChar(10), req.body.codigoPostal)
    .input('PostalAddressLine1', sql.NVarChar(60), req.body.direccionPostal1)
    .input('PostalAddressLine2', sql.NVarChar(60), req.body.direccionPostal2 || null)
    .input('Latitud', sql.Decimal(9, 6), req.body.latitud)
    .input('Longitud', sql.Decimal(9, 6), req.body.longitud)
    .input('BankAccountName', sql.NVarChar(50), req.body.nombreBanco || null)
    .input('BankAccountNumber', sql.NVarChar(20), req.body.numeroCuenta || null)
}
// GET /api/proveedores/categorias
router.get('/proveedores/categorias', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .execute('Api.usp_Proveedores_Categorias');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/proveedores?nombre=X&categoria=Y
router.get('/proveedores', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('Nombre', sql.NVarChar(100), req.query.nombre || null)
      .input('SupplierCategoryID', sql.Int, req.query.categoria ? parseInt(req.query.categoria) : null)
      .input('Pagina', sql.Int, parseInt(req.query.pagina) || 1)
      .execute('Api.usp_Proveedores_Listar');
    res.json(result.recordset);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/proveedores/:id
router.get('/proveedores/:id', async (req, res) => {
  try {
    const pool = await getConnection();
    const result = await pool.request()
      .input('SupplierID', sql.Int, req.params.id)
      .execute('Api.usp_Proveedores_Detalle');

    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Proveedor no encontrado' });
    }
    res.json(result.recordset[0]);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// POST /api/proveedores - crear
router.post('/proveedores', async (req, res) => {
  try {
    const pool = await getConnection();
    const request = pool.request()
      .input('SupplierName', sql.NVarChar(100), req.body.nombre)
      .input('SupplierReference', sql.NVarChar(20), req.body.referencia || null)
      .input('SupplierCategoryID', sql.Int, req.body.categoria)
      .input('DeliveryMethodID', sql.Int, req.body.metodo || null)
      .input('PrimaryContactPersonID', sql.Int, req.body.contacto)
      .input('AlternateContactPersonID', sql.Int, req.body.contactoAlterno)
      .input('PaymentDays', sql.Int, req.body.diasPago)
      .input('PhoneNumber', sql.NVarChar(20), req.body.telefono)
      .input('FaxNumber', sql.NVarChar(20), req.body.fax)
      .input('WebsiteURL', sql.NVarChar(256), req.body.sitioWeb)
      .input('DeliveryAddressLine1', sql.NVarChar(60), req.body.direccionEntrega1)
      .input('DeliveryAddressLine2', sql.NVarChar(60), req.body.direccionEntrega2 || null)
      .input('DeliveryCityID', sql.Int, req.body.ciudad)
      .input('DeliveryPostalCode', sql.NVarChar(10), req.body.codigoPostal)
      .input('PostalAddressLine1', sql.NVarChar(60), req.body.direccionPostal1)
      .input('PostalAddressLine2', sql.NVarChar(60), req.body.direccionPostal2 || null)
      .input('Latitud', sql.Decimal(9, 6), req.body.latitud)
      .input('Longitud', sql.Decimal(9, 6), req.body.longitud)
      .input('BankAccountName', sql.NVarChar(50), req.body.nombreBanco || null)
      .input('BankAccountNumber', sql.NVarChar(20), req.body.numeroCuenta || null)
      .output('NuevoSupplierID', sql.Int);

    const result = await request.execute('Api.usp_Proveedores_Crear');
    res.status(201).json({ SupplierID: result.output.NuevoSupplierID });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// PUT /api/proveedores/:id - modificar
router.put('/proveedores/:id', async (req, res) => {
  try {
    const pool = await getConnection();
    await pool.request()
      .input('SupplierID', sql.Int, req.params.id)
      .input('SupplierName', sql.NVarChar(100), req.body.nombre)
      .input('SupplierReference', sql.NVarChar(20), req.body.referencia || null)
      .input('SupplierCategoryID', sql.Int, req.body.categoria)
      .input('DeliveryMethodID', sql.Int, req.body.metodo || null)
      .input('PrimaryContactPersonID', sql.Int, req.body.contacto)
      .input('AlternateContactPersonID', sql.Int, req.body.contactoAlterno)
      .input('PaymentDays', sql.Int, req.body.diasPago)
      .input('PhoneNumber', sql.NVarChar(20), req.body.telefono)
      .input('FaxNumber', sql.NVarChar(20), req.body.fax)
      .input('WebsiteURL', sql.NVarChar(256), req.body.sitioWeb)
      .input('DeliveryAddressLine1', sql.NVarChar(60), req.body.direccionEntrega1)
      .input('DeliveryAddressLine2', sql.NVarChar(60), req.body.direccionEntrega2 || null)
      .input('DeliveryCityID', sql.Int, req.body.ciudad)
      .input('DeliveryPostalCode', sql.NVarChar(10), req.body.codigoPostal)
      .input('PostalAddressLine1', sql.NVarChar(60), req.body.direccionPostal1)
      .input('PostalAddressLine2', sql.NVarChar(60), req.body.direccionPostal2 || null)
      .input('Latitud', sql.Decimal(9, 6), req.body.latitud)
      .input('Longitud', sql.Decimal(9, 6), req.body.longitud)
      .input('BankAccountName', sql.NVarChar(50), req.body.nombreBanco || null)
      .input('BankAccountNumber', sql.NVarChar(20), req.body.numeroCuenta || null)
      .execute('Api.usp_Proveedores_Modificar');
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// DELETE /api/proveedores/:id - eliminar
router.delete('/proveedores/:id', async (req, res) => {
  try {
    const pool = await getConnection();
    await pool.request()
      .input('SupplierID', sql.Int, req.params.id)
      .execute('Api.usp_Proveedores_Eliminar');
    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;

const express = require('express');
const { getConnection, sql } = require('../db');

const router = express.Router();
function opcional(valor) {
  return valor === undefined || valor === null || valor === '' ? null : valor;
}

// Teléfono, direcciones y datos del banco se guardan solo en Corp
async function leerContacto(id) {
  const corp = await getConnection('corp');
  const result = await corp.request()
    .input('SupplierID', sql.Int, id)
    .execute('Api.usp_ProveedoresContacto_Obtener');
  return result.recordset[0] || {};
}

async function guardarContacto(id, body) {
  const corp = await getConnection('corp');
  await corp.request()
    .input('SupplierID', sql.Int, id)
    .input('PhoneNumber', sql.NVarChar(20), body.telefono)
    .input('FaxNumber', sql.NVarChar(20), body.fax)
    .input('WebsiteURL', sql.NVarChar(256), body.sitioWeb)
    .input('DeliveryAddressLine1', sql.NVarChar(60), body.direccionEntrega1)
    .input('DeliveryAddressLine2', sql.NVarChar(60), body.direccionEntrega2 || null)
    .input('DeliveryPostalCode', sql.NVarChar(10), body.codigoPostal)
    .input('PostalAddressLine1', sql.NVarChar(60), body.direccionPostal1)
    .input('PostalAddressLine2', sql.NVarChar(60), body.direccionPostal2 || null)
    .input('Latitud', sql.Decimal(9, 6), opcional(body.latitud))
    .input('Longitud', sql.Decimal(9, 6), opcional(body.longitud))
    .input('BankAccountName', sql.NVarChar(50), body.nombreBanco || null)
    .input('BankAccountNumber', sql.NVarChar(20), body.numeroCuenta || null)
    .execute('Api.usp_ProveedoresContacto_Guardar');
}

// GET /api/proveedores/categorias
router.get('/proveedores/categorias', async (req, res) => {
  try {
    const pool = await getConnection(req.nodo);
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
    const pool = await getConnection(req.nodo);
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
    const pool = await getConnection(req.nodo);
    const result = await pool.request()
      .input('SupplierID', sql.Int, req.params.id)
      .execute('Api.usp_Proveedores_Detalle');

    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Proveedor no encontrado' });
    }

    const proveedor = result.recordset[0];
    // El contacto y el banco vienen de Corp; si Corp no responde se muestra el resto
    try {
      Object.assign(proveedor, await leerContacto(req.params.id));
      proveedor.contactoDisponible = true;
    } catch (error) {
      proveedor.contactoDisponible = false;
    }
    res.json(proveedor);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// POST /api/proveedores - crear
router.post('/proveedores', async (req, res) => {
  try {
    const pool = await getConnection(req.nodo);
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
    const id = result.output.NuevoSupplierID;

    try {
      await guardarContacto(id, req.body);
    } catch (error) {
      // Sin contacto en Corp no se deja el proveedor: se deshace el alta
      await pool.request()
        .input('SupplierID', sql.Int, id)
        .execute('Api.usp_Proveedores_Eliminar')
        .catch(() => {});
      return res.status(503).json({
        error: `No se pudo guardar el contacto en Corp (${error.message}). El proveedor no se creó, intente de nuevo.`
      });
    }

    res.status(201).json({ SupplierID: id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// PUT /api/proveedores/:id - modificar
router.put('/proveedores/:id', async (req, res) => {
  try {
    const pool = await getConnection(req.nodo);
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

    try {
      await guardarContacto(req.params.id, req.body);
    } catch (error) {
      return res.status(503).json({
        error: `Los datos generales se guardaron, pero no el contacto: Corp no respondió (${error.message}). Vuelva a guardar.`
      });
    }

    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// DELETE /api/proveedores/:id - eliminar
router.delete('/proveedores/:id', async (req, res) => {
  try {
    const pool = await getConnection(req.nodo);
    await pool.request()
      .input('SupplierID', sql.Int, req.params.id)
      .execute('Api.usp_Proveedores_Eliminar');

    // El contacto de Corp se borra después; si Corp no responde queda sin usar y no estorba
    try {
      const corp = await getConnection('corp');
      await corp.request()
        .input('SupplierID', sql.Int, req.params.id)
        .execute('Api.usp_ProveedoresContacto_Eliminar');
    } catch (error) {
      console.error('No se pudo borrar el contacto en Corp:', error.message);
    }

    res.json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;

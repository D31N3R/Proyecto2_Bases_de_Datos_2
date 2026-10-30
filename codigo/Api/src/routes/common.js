const express = require('express');
const { getConnection } = require('../db');

const router = express.Router();

// Estos catálogos casi nunca cambian, así que se consultan una sola vez
// y después se responde desde memoria (se limpia al reiniciar el servidor).
const guardado = {};

async function catalogo(nombre, procedimiento) {
  if (!guardado[nombre]) {
    const pool = await getConnection();
    const result = await pool.request().execute(procedimiento);
    guardado[nombre] = result.recordset;
  }
  return guardado[nombre];
}

// GET /api/metodos-entrega
router.get('/metodos-entrega', async (req, res) => {
  try {
    res.json(await catalogo('metodos', 'Api.usp_MetodosEntrega_Listar'));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/ciudades
router.get('/ciudades', async (req, res) => {
  try {
    res.json(await catalogo('ciudades', 'Api.usp_Ciudades_Listar'));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/personas
router.get('/personas', async (req, res) => {
  try {
    res.json(await catalogo('personas', 'Api.usp_Personas_Listar'));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Se cargan al arrancar para que la primera persona que abra un formulario no espere
catalogo('metodos', 'Api.usp_MetodosEntrega_Listar').catch(() => {});
catalogo('ciudades', 'Api.usp_Ciudades_Listar').catch(() => {});
catalogo('personas', 'Api.usp_Personas_Listar').catch(() => {});

module.exports = router;
const express = require('express');
const { getConnection } = require('../db');

const router = express.Router();

// Estos catálogos casi nunca cambian, así que se consultan una sola vez
// y después se responde desde memoria (se limpia al reiniciar el servidor).
const guardado = {};

// Cada sucursal usa su propio nodo: si Corp se cae, los formularios de SJ y Limon siguen funcionando.
async function catalogo(nodo, nombre, procedimiento) {
  const clave = `${nodo}:${nombre}`;
  if (!guardado[clave]) {
    const pool = await getConnection(nodo);
    const result = await pool.request().execute(procedimiento);
    guardado[clave] = result.recordset;
  }
  return guardado[clave];
}

// GET /api/metodos-entrega
router.get('/metodos-entrega', async (req, res) => {
  try {
    res.json(await catalogo(req.nodo, 'metodos', 'Api.usp_MetodosEntrega_Listar'));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/ciudades
router.get('/ciudades', async (req, res) => {
  try {
    res.json(await catalogo(req.nodo, 'ciudades', 'Api.usp_Ciudades_Listar'));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET /api/personas
router.get('/personas', async (req, res) => {
  try {
    res.json(await catalogo(req.nodo, 'personas', 'Api.usp_Personas_Listar'));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Se cargan al arrancar para que la primera persona que abra un formulario no espere
for (const nodo of ['sj', 'limon', 'corp']) {
  catalogo(nodo, 'metodos', 'Api.usp_MetodosEntrega_Listar').catch(() => {});
  catalogo(nodo, 'ciudades', 'Api.usp_Ciudades_Listar').catch(() => {});
  catalogo(nodo, 'personas', 'Api.usp_Personas_Listar').catch(() => {});
}

module.exports = router;
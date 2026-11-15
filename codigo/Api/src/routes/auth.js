const express = require('express');
const { getConnection, sql } = require('../db');
const { crearToken } = require('../token');

const router = express.Router();

// POST /api/login  { username, password }
router.post('/login', async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ error: 'username y password son requeridos' });
  }

  try {
    const pool = await getConnection('corp');
    const result = await pool.request()
      .input('Username', sql.NVarChar(50), username)
      .input('Password', sql.NVarChar(100), password)
      .execute('dbo.usp_Users_Login');

    const row = result.recordset[0];
    if (!row.valido) {
      return res.status(401).json({ error: row.mensaje });
    }

    // El token firmado lleva el rol y la sucursal; la API los lee de ahi en cada peticion
    res.json({
      iduser: row.iduser,
      fullname: row.fullname,
      rol: row.rol,
      sucursal: row.sucursal,
      token: crearToken({ iduser: row.iduser, rol: row.rol, sucursal: row.sucursal })
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const commonRouter = require('./routes/common');
const clientesRouter = require('./routes/clientes');
const proveedoresRouter = require('./routes/proveedores');
const inventariosRouter = require('./routes/inventarios');
const ventasRouter = require('./routes/ventas');
const estadisticasRouter = require('./routes/estadisticas');
const authRouter = require('./routes/auth');
const resolveNodo = require('./middleware/nodo');

const app = express();
const PORT = process.env.PORT || 4000;

app.use(cors({ origin: process.env.WEBSIDE_URL || '*' }));
app.use(express.json());

app.get('/api/status', (req, res) => {
  res.json({ status: 'activo' });
});

// El nodo se resuelve ANTES de las rutas (lee el header X-Sucursal).
// /api/login es publico; todas las demas rutas necesitan sucursal.
app.use('/api', resolveNodo);

app.use('/api', authRouter);
app.use('/api', commonRouter);
app.use('/api', clientesRouter);
app.use('/api', proveedoresRouter);
app.use('/api', inventariosRouter);
app.use('/api', ventasRouter);
app.use('/api', estadisticasRouter);

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Servidor corriendo en http://localhost:${PORT}`);
});
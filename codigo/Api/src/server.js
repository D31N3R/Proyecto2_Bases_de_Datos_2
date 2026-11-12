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
const autenticar = require('./middleware/autenticar');
const resolveNodo = require('./middleware/nodo');
const { estadoNodos } = require('./db');

const app = express();
const PORT = process.env.PORT || 4000;

app.use(cors({ origin: process.env.WEBSIDE_URL || '*' }));
app.use(express.json());

// La API siempre responde; "nodos" dice cuales bases de datos estan arriba
app.get('/api/status', async (req, res) => {
  const nodos = await estadoNodos();
  const todosArriba = Object.values(nodos).every((estado) => estado === 'ok');
  res.json({ status: todosArriba ? 'activo' : 'degradado', nodos });
});

// Primero se valida el token y el rol, despues se elige el nodo; ambos van ANTES de las rutas.
// /api/login y /api/status son publicas.
app.use('/api', autenticar);
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
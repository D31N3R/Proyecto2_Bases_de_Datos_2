const fs = require('fs');
const path = require('path');
const { getConnection } = require('./src/db');

async function main() {
  const archivo = process.argv[2];
  if (!archivo) { console.error('Falta la ruta del archivo .sql'); process.exit(1); }

  const texto = fs.readFileSync(path.resolve(archivo), 'utf8');
  const bloques = texto.split(/^\s*GO\s*$/gim).map(b => b.trim()).filter(Boolean);

  const pool = await getConnection();
  for (let i = 0; i < bloques.length; i++) {
    try {
      await pool.request().batch(bloques[i]);
    } catch (e) {
      console.error(`Error en el bloque ${i + 1}: ${e.message}`);
      process.exit(1);
    }
  }
  console.log(`Listo: ${bloques.length} bloques ejecutados`);
  await pool.close();
}

main();

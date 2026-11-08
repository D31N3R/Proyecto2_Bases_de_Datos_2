USE WideWorldImporters;
GO

/* ============================================================
   CONCURRENCIA

   1. Edicion de productos (catalogo replicado): control OPTIMISTA.
      Basado en Database System Concepts, 18.6 (protocolos basados en
      validacion). Api.usp_Inventario_Detalle devuelve una "Version" del
      producto (su ValidFrom como texto, con los 7 decimales). Al guardar,
      la aplicacion devuelve esa misma version a Api.usp_Inventario_Modificar,
      que la compara DENTRO del UPDATE:

          UPDATE ... SET ..., ValidFrom = SYSUTCDATETIME()
          WHERE StockItemID = @id AND version actual = @Version

      Es una comparacion y cambio atomicos (una sola sentencia): si dos
      administradores de sucursales distintas editan a la vez, el segundo
      encuentra otra version, no se actualiza ninguna fila y recibe el error
      50080 en vez de pisar el cambio del primero (lost update).

   2. Catalogo editable solo en Corp (error 50070 en las sucursales): las
      modificaciones de todas las sucursales se serializan en un unico punto
      y luego se replican, asi nunca hay dos copias editandose a la vez.

   3. Borrado de productos: se revisan las ventas de las sucursales antes de
      borrar (errores 50031 y 50032), para no atascar la replicacion.

   4. Generacion de IDs (facturas, lineas, clientes): UPDLOCK + HOLDLOCK
      sobre el MAX(ID) para que dos sesiones del mismo nodo no tomen el mismo.

   Aqui antes habia un prototipo (Api.usp_Productos_Actualizar) con un error
   de sintaxis que nunca llego a crearse; el control optimista quedo integrado
   en Api.usp_Inventario_Modificar, que es el que usa la aplicacion.
   ============================================================ */

DROP PROCEDURE IF EXISTS Api.usp_Productos_Actualizar;
GO

PRINT 'Concurrencia: control optimista integrado en Api.usp_Inventario_Modificar (@Version)';
GO
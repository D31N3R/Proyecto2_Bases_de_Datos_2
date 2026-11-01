
USE WideWorldImporters;
GO

/* ============================================================
   REPLICACION - Prerequisito
   Warehouse.StockItems es una tabla temporal (system-versioned).
   SQL Server no permite replicar tablas temporales directamente,
   asi que se desactiva el versionado y ValidFrom pasa a ser una
   columna normal, actualizada manualmente desde el procedure de
   concurrencia (Api.usp_Productos_Actualizar).
   ============================================================ */

IF EXISTS (
    SELECT 1 FROM sys.tables
    WHERE object_id = OBJECT_ID('Warehouse.StockItems')
      AND temporal_type = 2
)
BEGIN
    ALTER TABLE Warehouse.StockItems SET (SYSTEM_VERSIONING = OFF);
    PRINT 'StockItems: versionado de sistema desactivado (requisito para replicacion)';
END
ELSE
    PRINT 'StockItems: ya no tiene versionado de sistema';
GO

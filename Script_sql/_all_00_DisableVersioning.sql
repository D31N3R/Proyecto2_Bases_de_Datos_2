USE WideWorldImporters;
GO

/* ============================================================
   REPLICACION - Prerequisito (corre en los 3 nodos)

   Warehouse.StockItems es una tabla temporal (system-versioned).
   La replicacion necesita insertar valores explicitos en ValidFrom
   y ValidTo, pero mientras exista el PERIODO de sistema esas columnas
   son GENERATED ALWAYS y el Distribution Agent falla con:
     "Cannot insert an explicit value into a GENERATED ALWAYS column".

   Por eso se hacen DOS cosas, en este orden:
     1. SYSTEM_VERSIONING = OFF
     2. DROP PERIOD FOR SYSTEM_TIME
   y despues se agregan DEFAULTs, para que los INSERT de los procedures
   (que no listan ValidFrom/ValidTo) sigan funcionando.
   ============================================================ */

IF EXISTS (
    SELECT 1 FROM sys.tables
    WHERE object_id = OBJECT_ID('Warehouse.StockItems')
      AND temporal_type = 2
)
BEGIN
    ALTER TABLE Warehouse.StockItems SET (SYSTEM_VERSIONING = OFF);
    PRINT 'StockItems: versionado de sistema desactivado';
END
ELSE
    PRINT 'StockItems: ya no tiene versionado de sistema';
GO

IF EXISTS (
    SELECT 1 FROM sys.periods
    WHERE object_id = OBJECT_ID('Warehouse.StockItems')
)
BEGIN
    ALTER TABLE Warehouse.StockItems DROP PERIOD FOR SYSTEM_TIME;
    PRINT 'StockItems: periodo de sistema eliminado (ValidFrom/ValidTo ahora son columnas normales)';
END
ELSE
    PRINT 'StockItems: ya no tiene periodo de sistema';
GO

-- DEFAULTs para que los INSERT sin ValidFrom/ValidTo sigan funcionando
IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('Warehouse.StockItems')
      AND parent_column_id = COLUMNPROPERTY(OBJECT_ID('Warehouse.StockItems'), 'ValidFrom', 'ColumnId')
)
BEGIN
    ALTER TABLE Warehouse.StockItems
        ADD CONSTRAINT DF_StockItems_ValidFrom DEFAULT (SYSUTCDATETIME()) FOR ValidFrom;
    PRINT 'StockItems: DEFAULT agregado a ValidFrom';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('Warehouse.StockItems')
      AND parent_column_id = COLUMNPROPERTY(OBJECT_ID('Warehouse.StockItems'), 'ValidTo', 'ColumnId')
)
BEGIN
    ALTER TABLE Warehouse.StockItems
        ADD CONSTRAINT DF_StockItems_ValidTo DEFAULT ('9999-12-31 23:59:59.9999999') FOR ValidTo;
    PRINT 'StockItems: DEFAULT agregado a ValidTo';
END
GO

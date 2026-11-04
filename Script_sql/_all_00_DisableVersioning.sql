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

/* Tablas de referencia de producto que tambien se replican: Colors, PackageTypes,
   StockGroups. Son temporales igual que StockItems, mismo problema, mismo arreglo. */
DECLARE @t TABLE (Esq SYSNAME, Tab SYSNAME);
INSERT @t VALUES (N'Warehouse', N'Colors'), (N'Warehouse', N'PackageTypes'), (N'Warehouse', N'StockGroups');
DECLARE @e SYSNAME, @n SYSNAME, @full NVARCHAR(300), @sql NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Esq, Tab FROM @t;
OPEN c; FETCH NEXT FROM c INTO @e, @n;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @full = QUOTENAME(@e) + N'.' + QUOTENAME(@n);

    IF EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID(@full) AND temporal_type = 2)
    BEGIN
        SET @sql = N'ALTER TABLE ' + @full + N' SET (SYSTEM_VERSIONING = OFF);';
        EXEC sp_executesql @sql;
    END

    IF EXISTS (SELECT 1 FROM sys.periods WHERE object_id = OBJECT_ID(@full))
    BEGIN
        SET @sql = N'ALTER TABLE ' + @full + N' DROP PERIOD FOR SYSTEM_TIME;';
        EXEC sp_executesql @sql;
    END

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@full) AND name = 'ValidFrom')
       AND NOT EXISTS (SELECT 1 FROM sys.default_constraints
                       WHERE parent_object_id = OBJECT_ID(@full)
                         AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(@full), 'ValidFrom', 'ColumnId'))
    BEGIN
        SET @sql = N'ALTER TABLE ' + @full + N' ADD CONSTRAINT ' + QUOTENAME(N'DF_' + @n + N'_ValidFrom')
                 + N' DEFAULT (SYSUTCDATETIME()) FOR ValidFrom;';
        EXEC sp_executesql @sql;
    END

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@full) AND name = 'ValidTo')
       AND NOT EXISTS (SELECT 1 FROM sys.default_constraints
                       WHERE parent_object_id = OBJECT_ID(@full)
                         AND parent_column_id = COLUMNPROPERTY(OBJECT_ID(@full), 'ValidTo', 'ColumnId'))
    BEGIN
        SET @sql = N'ALTER TABLE ' + @full + N' ADD CONSTRAINT ' + QUOTENAME(N'DF_' + @n + N'_ValidTo')
                 + N' DEFAULT (''9999-12-31 23:59:59.9999999'') FOR ValidTo;';
        EXEC sp_executesql @sql;
    END

    PRINT CONCAT(@full, ': listo para replicacion');
    FETCH NEXT FROM c INTO @e, @n;
END
CLOSE c; DEALLOCATE c;
GO
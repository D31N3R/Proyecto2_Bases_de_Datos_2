USE WideWorldImporters;
GO

SET NOCOUNT ON;
GO

ALTER TABLE Sales.Customers           DISABLE TRIGGER ALL;
ALTER TABLE Sales.Invoices            DISABLE TRIGGER ALL;
ALTER TABLE Sales.Orders              DISABLE TRIGGER ALL;
ALTER TABLE Purchasing.PurchaseOrders DISABLE TRIGGER ALL;
ALTER TABLE Warehouse.StockItems      DISABLE TRIGGER ALL;
GO

-- A. Deshabilitar TODAS las FKs
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N' NOCHECK CONSTRAINT ALL;' + CHAR(13)
FROM sys.tables t
WHERE EXISTS (SELECT 1 FROM sys.foreign_keys fk WHERE fk.parent_object_id = t.object_id AND fk.is_disabled = 0);
EXEC sp_executesql @sql;
GO

-- B. Fragmentar (SJ conserva pares)
DELETE FROM Sales.InvoiceLines WHERE InvoiceID % 2 <> 0;
DELETE FROM Sales.Invoices WHERE InvoiceID % 2 <> 0;
DELETE FROM Sales.OrderLines WHERE OrderID % 2 <> 0;
DELETE FROM Sales.Orders WHERE OrderID % 2 <> 0;
DELETE FROM Purchasing.PurchaseOrderLines WHERE PurchaseOrderID % 2 <> 0;
DELETE FROM Purchasing.PurchaseOrders WHERE PurchaseOrderID % 2 <> 0;
DELETE FROM Warehouse.StockItemHoldings WHERE StockItemID % 2 <> 0;
DELETE FROM Warehouse.StockItemTransactions WHERE StockItemTransactionID % 2 <> 0;
DELETE FROM Sales.CustomerTransactions WHERE CustomerTransactionID % 2 <> 0;
DELETE FROM Purchasing.SupplierTransactions WHERE SupplierTransactionID % 2 <> 0;
DELETE FROM Sales.SpecialDeals WHERE SpecialDealID % 2 <> 0;
PRINT 'SJ - fragmentacion aplicada';
GO

-- C. Limpieza dinámica de huérfanas
DECLARE @iter INT = 1, @total_borradas INT = 0;

WHILE @iter <= 10
BEGIN
    DECLARE @deleted_this_iter INT = 0;
    DECLARE @fk_schema SYSNAME, @fk_table SYSNAME, @fk_col SYSNAME;
    DECLARE @parent_schema SYSNAME, @parent_table SYSNAME, @parent_col SYSNAME;
    DECLARE @sql_orphan NVARCHAR(MAX);
    DECLARE @rows INT;

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT OBJECT_SCHEMA_NAME(fkc.parent_object_id), OBJECT_NAME(fkc.parent_object_id),
               COL_NAME(fkc.parent_object_id, fkc.parent_column_id),
               OBJECT_SCHEMA_NAME(fkc.referenced_object_id), OBJECT_NAME(fkc.referenced_object_id),
               COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id)
        FROM sys.foreign_key_columns fkc;

    OPEN cur;
    FETCH NEXT FROM cur INTO @fk_schema, @fk_table, @fk_col, @parent_schema, @parent_table, @parent_col;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql_orphan = N'
            DELETE c FROM ' + QUOTENAME(@fk_schema) + N'.' + QUOTENAME(@fk_table) + N' c
            WHERE c.' + QUOTENAME(@fk_col) + N' IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM ' + QUOTENAME(@parent_schema) + N'.' + QUOTENAME(@parent_table) + N' p
                              WHERE p.' + QUOTENAME(@parent_col) + N' = c.' + QUOTENAME(@fk_col) + N');';
        BEGIN TRY
            EXEC sp_executesql @sql_orphan;
            SET @rows = @@ROWCOUNT;
            IF @rows > 0
            BEGIN
                PRINT CONCAT('  ', @fk_table, '.', @fk_col, ': ', @rows, ' huerfanas');
                SET @deleted_this_iter += @rows;
            END
        END TRY
        BEGIN CATCH
            PRINT CONCAT('  ERROR ', @fk_table, '.', @fk_col, ': ', ERROR_MESSAGE());
        END CATCH
        FETCH NEXT FROM cur INTO @fk_schema, @fk_table, @fk_col, @parent_schema, @parent_table, @parent_col;
    END
    CLOSE cur; DEALLOCATE cur;

    PRINT CONCAT('Iteracion ', @iter, ': ', @deleted_this_iter);
    SET @total_borradas += @deleted_this_iter;
    IF @deleted_this_iter = 0 BREAK;
    SET @iter += 1;
END
PRINT CONCAT('Total huerfanas: ', @total_borradas);
GO

-- D. Reactivar FKs
DECLARE @sql2 NVARCHAR(MAX) = N'';
SELECT @sql2 += N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N' WITH CHECK CHECK CONSTRAINT ALL;' + CHAR(13)
FROM sys.tables t
WHERE EXISTS (SELECT 1 FROM sys.foreign_keys fk WHERE fk.parent_object_id = t.object_id);
EXEC sp_executesql @sql2;
GO

ALTER TABLE Sales.Customers           ENABLE TRIGGER ALL;
ALTER TABLE Sales.Invoices            ENABLE TRIGGER ALL;
ALTER TABLE Sales.Orders              ENABLE TRIGGER ALL;
ALTER TABLE Purchasing.PurchaseOrders ENABLE TRIGGER ALL;
ALTER TABLE Warehouse.StockItems      ENABLE TRIGGER ALL;
GO

SELECT 'SJ' AS Nodo,
    (SELECT COUNT(*) FROM Sales.Invoices)                  AS Invoices,
    (SELECT COUNT(*) FROM Sales.InvoiceLines)              AS InvoiceLines,
    (SELECT COUNT(*) FROM Sales.Orders)                    AS Orders,
    (SELECT COUNT(*) FROM Purchasing.PurchaseOrders)       AS PurchaseOrders,
    (SELECT COUNT(*) FROM Purchasing.SupplierTransactions) AS SupplierTx,
    (SELECT COUNT(*) FROM Sales.CustomerTransactions)      AS CustomerTx,
    (SELECT COUNT(*) FROM Warehouse.StockItemHoldings)     AS StockHoldings,
    (SELECT COUNT(*) FROM Sales.Customers)                 AS Clientes
GO

USE WideWorldImporters;
GO
IF NOT EXISTS (SELECT 1 FROM dbo.NodoConfig)
    INSERT INTO dbo.NodoConfig (Nodo, Paridad) VALUES (N'SJ', 0);
GO
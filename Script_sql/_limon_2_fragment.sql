USE WideWorldImporters;
GO

SET NOCOUNT ON;
GO

/* ============================================================
   FRAGMENTACIÓN HORIZONTAL - LIMÓN (conserva ID IMPAR)

   Facturas y órdenes de compra: PRIMARIA, por paridad de su propio ID.
   Todo lo demás es DERIVADO: sigue al registro del que depende, así
   ninguna referencia queda apuntando a una fila que vive en el otro nodo.

     Facturas (InvoiceID)                -> impar aquí, par en San José
     Líneas de factura                   -> con su factura
     Pedidos (Sales.Orders)              -> con la factura que los cubre;
                                            si no tienen factura, por OrderID
     Líneas de pedido                    -> con su pedido
     Órdenes de compra (PurchaseOrderID) -> impar aquí, par en San José
     Líneas de orden de compra           -> con su orden
     Transacciones de cliente/inventario/proveedor
                                         -> con su factura u orden de compra;
                                            si no tienen, por su propio ID

   Antes se fragmentaba cada tabla por la paridad de SU PROPIO ID y luego
   se borraban las filas "huérfanas": una factura par cuyo pedido era impar
   se perdía en los dos nodos. Con el fragmentado derivado no se pierde nada:
   la verificación del final comprueba que cada factura quedó en su nodo.

   Las referencias opcionales que apuntan al otro nodo (por ejemplo, el
   pedido pendiente "BackorderOrderID") se ponen en NULL; no se borra la fila.
   ============================================================ */

IF OBJECT_ID('tempdb..#Cfg') IS NOT NULL DROP TABLE #Cfg;
SELECT CAST(1 AS INT) AS Paridad, CAST(N'LIMON' AS NVARCHAR(10)) AS Nodo INTO #Cfg;
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
PRINT 'FKs deshabilitadas';
GO

-- B1. Foto de lo que hay ANTES de borrar (para verificar al final que no se perdió nada)
DECLARE @p INT = (SELECT Paridad FROM #Cfg);

IF OBJECT_ID('tempdb..#Chequeo') IS NOT NULL DROP TABLE #Chequeo;
SELECT (SELECT COUNT(*) FROM Sales.Invoices)                             AS FacturasAntes,
       (SELECT COUNT(*) FROM Sales.Invoices WHERE InvoiceID % 2 = @p)    AS FacturasQueLeCorresponden,
       (SELECT COUNT(*) FROM Sales.Orders)                               AS PedidosAntes
INTO #Chequeo;
GO

-- B2. Decidir ANTES de borrar qué filas dependientes se quedan en este nodo
DECLARE @p INT = (SELECT Paridad FROM #Cfg);

-- Pedido: va con la factura que lo cubre (la de menor InvoiceID); sin factura, por su OrderID
IF OBJECT_ID('tempdb..#PedidosLocales') IS NOT NULL DROP TABLE #PedidosLocales;
SELECT o.OrderID
INTO #PedidosLocales
FROM Sales.Orders o
OUTER APPLY (SELECT MIN(i.InvoiceID) AS InvoiceID
             FROM Sales.Invoices i
             WHERE i.OrderID = o.OrderID) f
WHERE ISNULL(f.InvoiceID, o.OrderID) % 2 = @p;
CREATE UNIQUE CLUSTERED INDEX IX_PedidosLocales ON #PedidosLocales (OrderID);

-- Transacción de cliente: con su factura; si no tiene (pagos), por su propio ID
IF OBJECT_ID('tempdb..#TxClienteLocales') IS NOT NULL DROP TABLE #TxClienteLocales;
SELECT ct.CustomerTransactionID
INTO #TxClienteLocales
FROM Sales.CustomerTransactions ct
WHERE ISNULL(ct.InvoiceID, ct.CustomerTransactionID) % 2 = @p;
CREATE UNIQUE CLUSTERED INDEX IX_TxClienteLocales ON #TxClienteLocales (CustomerTransactionID);

-- Movimiento de inventario: con su factura, o con su orden de compra, o por su propio ID
IF OBJECT_ID('tempdb..#TxInventarioLocales') IS NOT NULL DROP TABLE #TxInventarioLocales;
SELECT sit.StockItemTransactionID
INTO #TxInventarioLocales
FROM Warehouse.StockItemTransactions sit
WHERE COALESCE(sit.InvoiceID, sit.PurchaseOrderID, sit.StockItemTransactionID) % 2 = @p;
CREATE UNIQUE CLUSTERED INDEX IX_TxInventarioLocales ON #TxInventarioLocales (StockItemTransactionID);

-- Transacción de proveedor: con su orden de compra; si no tiene, por su propio ID
IF OBJECT_ID('tempdb..#TxProveedorLocales') IS NOT NULL DROP TABLE #TxProveedorLocales;
SELECT st.SupplierTransactionID
INTO #TxProveedorLocales
FROM Purchasing.SupplierTransactions st
WHERE ISNULL(st.PurchaseOrderID, st.SupplierTransactionID) % 2 = @p;
CREATE UNIQUE CLUSTERED INDEX IX_TxProveedorLocales ON #TxProveedorLocales (SupplierTransactionID);
GO

-- B3. Fragmentar (Limón conserva impares)
DECLARE @p INT = (SELECT Paridad FROM #Cfg);

DELETE FROM Sales.InvoiceLines WHERE InvoiceID % 2 <> @p;
PRINT CONCAT('Limon - InvoiceLines borradas: ', @@ROWCOUNT);

DELETE FROM Sales.Invoices WHERE InvoiceID % 2 <> @p;
PRINT CONCAT('Limon - Invoices borradas: ', @@ROWCOUNT);

DELETE ol FROM Sales.OrderLines ol
WHERE NOT EXISTS (SELECT 1 FROM #PedidosLocales x WHERE x.OrderID = ol.OrderID);
PRINT CONCAT('Limon - OrderLines borradas: ', @@ROWCOUNT);

DELETE o FROM Sales.Orders o
WHERE NOT EXISTS (SELECT 1 FROM #PedidosLocales x WHERE x.OrderID = o.OrderID);
PRINT CONCAT('Limon - Orders borrados: ', @@ROWCOUNT);

DELETE FROM Purchasing.PurchaseOrderLines WHERE PurchaseOrderID % 2 <> @p;
PRINT CONCAT('Limon - PurchaseOrderLines borradas: ', @@ROWCOUNT);

DELETE FROM Purchasing.PurchaseOrders WHERE PurchaseOrderID % 2 <> @p;
PRINT CONCAT('Limon - PurchaseOrders borradas: ', @@ROWCOUNT);

-- StockItemHoldings NO se fragmenta: cada sucursal guarda el inventario de todos los productos
DELETE sit FROM Warehouse.StockItemTransactions sit
WHERE NOT EXISTS (SELECT 1 FROM #TxInventarioLocales x WHERE x.StockItemTransactionID = sit.StockItemTransactionID);
PRINT CONCAT('Limon - StockItemTransactions borradas: ', @@ROWCOUNT);

DELETE ct FROM Sales.CustomerTransactions ct
WHERE NOT EXISTS (SELECT 1 FROM #TxClienteLocales x WHERE x.CustomerTransactionID = ct.CustomerTransactionID);
PRINT CONCAT('Limon - CustomerTransactions borradas: ', @@ROWCOUNT);

DELETE st FROM Purchasing.SupplierTransactions st
WHERE NOT EXISTS (SELECT 1 FROM #TxProveedorLocales x WHERE x.SupplierTransactionID = st.SupplierTransactionID);
PRINT CONCAT('Limon - SupplierTransactions borradas: ', @@ROWCOUNT);

DELETE FROM Sales.SpecialDeals WHERE SpecialDealID % 2 <> @p;
PRINT CONCAT('Limon - SpecialDeals borradas: ', @@ROWCOUNT);
PRINT 'Limon - fragmentacion aplicada';
GO

-- C. Referencias que quedaron apuntando al otro nodo.
--    Si la columna acepta NULL (p. ej. BackorderOrderID) se pone en NULL; si no, la fila dependiente
--    se borra. Con el fragmentado derivado esto casi no encuentra nada: lo que imprima aquí es lo que
--    cambió. Si aparecen facturas o líneas borradas, revisar.
DECLARE @iter INT = 1, @total_cambiadas INT = 0;

WHILE @iter <= 10
BEGIN
    DECLARE @cambiadas_iter INT = 0;
    DECLARE @fk_schema SYSNAME, @fk_table SYSNAME, @fk_col SYSNAME, @acepta_null BIT;
    DECLARE @parent_schema SYSNAME, @parent_table SYSNAME, @parent_col SYSNAME;
    DECLARE @sql_orphan NVARCHAR(MAX);
    DECLARE @rows INT;

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT OBJECT_SCHEMA_NAME(fkc.parent_object_id), OBJECT_NAME(fkc.parent_object_id),
               COL_NAME(fkc.parent_object_id, fkc.parent_column_id), col.is_nullable,
               OBJECT_SCHEMA_NAME(fkc.referenced_object_id), OBJECT_NAME(fkc.referenced_object_id),
               COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id)
        FROM sys.foreign_key_columns fkc
        JOIN sys.columns col
          ON col.object_id = fkc.parent_object_id AND col.column_id = fkc.parent_column_id;

    OPEN cur;
    FETCH NEXT FROM cur INTO @fk_schema, @fk_table, @fk_col, @acepta_null, @parent_schema, @parent_table, @parent_col;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @acepta_null = 1
            SET @sql_orphan = N'
                UPDATE c SET c.' + QUOTENAME(@fk_col) + N' = NULL
                FROM ' + QUOTENAME(@fk_schema) + N'.' + QUOTENAME(@fk_table) + N' c
                WHERE c.' + QUOTENAME(@fk_col) + N' IS NOT NULL
                  AND NOT EXISTS (SELECT 1 FROM ' + QUOTENAME(@parent_schema) + N'.' + QUOTENAME(@parent_table) + N' p
                                  WHERE p.' + QUOTENAME(@parent_col) + N' = c.' + QUOTENAME(@fk_col) + N');';
        ELSE
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
                PRINT CONCAT('  ', @fk_table, '.', @fk_col, CASE WHEN @acepta_null = 1 THEN ' puesto en NULL: ' ELSE ' filas borradas: ' END, @rows);
                SET @cambiadas_iter += @rows;
            END
        END TRY
        BEGIN CATCH
            PRINT CONCAT('  ERROR ', @fk_table, '.', @fk_col, ': ', ERROR_MESSAGE());
        END CATCH
        FETCH NEXT FROM cur INTO @fk_schema, @fk_table, @fk_col, @acepta_null, @parent_schema, @parent_table, @parent_col;
    END
    CLOSE cur; DEALLOCATE cur;

    PRINT CONCAT('Iteracion ', @iter, ': ', @cambiadas_iter);
    SET @total_cambiadas += @cambiadas_iter;
    IF @cambiadas_iter = 0 BREAK;
    SET @iter += 1;
END
PRINT CONCAT('Total de referencias corregidas: ', @total_cambiadas);
GO

-- D. Reactivar FKs
DECLARE @sql2 NVARCHAR(MAX) = N'';
SELECT @sql2 += N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N' WITH CHECK CHECK CONSTRAINT ALL;' + CHAR(13)
FROM sys.tables t
WHERE EXISTS (SELECT 1 FROM sys.foreign_keys fk WHERE fk.parent_object_id = t.object_id);
EXEC sp_executesql @sql2;
PRINT 'FKs reactivadas';
GO

ALTER TABLE Sales.Customers           ENABLE TRIGGER ALL;
ALTER TABLE Sales.Invoices            ENABLE TRIGGER ALL;
ALTER TABLE Sales.Orders              ENABLE TRIGGER ALL;
ALTER TABLE Purchasing.PurchaseOrders ENABLE TRIGGER ALL;
ALTER TABLE Warehouse.StockItems      ENABLE TRIGGER ALL;
GO

-- E. Verificación: no se perdió ninguna factura que le correspondía a este nodo
DECLARE @p INT = (SELECT Paridad FROM #Cfg);
DECLARE @esperadas INT, @antes INT, @ahora INT, @msg NVARCHAR(400);
SELECT @esperadas = FacturasQueLeCorresponden, @antes = FacturasAntes FROM #Chequeo;
SET @ahora = (SELECT COUNT(*) FROM Sales.Invoices);

IF @ahora <> @esperadas OR EXISTS (SELECT 1 FROM Sales.Invoices WHERE InvoiceID % 2 <> @p)
BEGIN
    SET @msg = CONCAT(N'Fragmentacion incorrecta: se esperaban ', @esperadas, N' facturas y hay ', @ahora, N'.');
    THROW 50099, @msg, 1;
END
PRINT CONCAT('Verificacion OK: ', @ahora, ' de ', @antes, ' facturas quedan en este nodo (las demas son del otro nodo).');
GO

SELECT 'Limon' AS Nodo,
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
    INSERT INTO dbo.NodoConfig (Nodo, Paridad) VALUES (N'LIMON', 1);
GO
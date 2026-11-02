USE WideWorldImporters;
GO
SET QUOTED_IDENTIFIER ON;
GO
/* ============================================================
   FRAGMENTACIÓN HORIZONTAL - CORPORATIVO
   Descubre dinámicamente TODAS las FKs, las deshabilita,
   borra todo, reactiva.
   ============================================================ */

SET NOCOUNT ON;
GO

-- Asegurar triggers activos (por si intento previo falló)
EXEC sp_MSforeachtable 'ALTER TABLE ? ENABLE TRIGGER ALL';
GO

-- Desactivar triggers de auditoría de WWI
ALTER TABLE Sales.Customers           DISABLE TRIGGER ALL;
ALTER TABLE Sales.Invoices            DISABLE TRIGGER ALL;
ALTER TABLE Sales.Orders              DISABLE TRIGGER ALL;
ALTER TABLE Purchasing.PurchaseOrders DISABLE TRIGGER ALL;
ALTER TABLE Warehouse.StockItems      DISABLE TRIGGER ALL;
GO

-- ---------- 1. Deshabilitar TODAS las FKs de la base ----------
DECLARE @sql_disable NVARCHAR(MAX) = N'';
SELECT @sql_disable += N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N' NOCHECK CONSTRAINT ALL;' + CHAR(13)
FROM sys.tables t
WHERE EXISTS (SELECT 1 FROM sys.foreign_keys fk WHERE fk.parent_object_id = t.object_id);

EXEC sp_executesql @sql_disable;
PRINT 'Corp - Todas las FKs deshabilitadas temporalmente';
GO

-- ---------- 2. DELETE de TODAS las transaccionales (FKs off, orden no importa) ----------
DELETE FROM Purchasing.SupplierTransactions;
PRINT CONCAT('Corp - SupplierTransactions: ', @@ROWCOUNT);

DELETE FROM Purchasing.PurchaseOrderLines;
PRINT CONCAT('Corp - PurchaseOrderLines: ', @@ROWCOUNT);

DELETE FROM Purchasing.PurchaseOrders;
PRINT CONCAT('Corp - PurchaseOrders: ', @@ROWCOUNT);

DELETE FROM Sales.CustomerTransactions;
PRINT CONCAT('Corp - CustomerTransactions: ', @@ROWCOUNT);

DELETE FROM Sales.InvoiceLines;
PRINT CONCAT('Corp - InvoiceLines: ', @@ROWCOUNT);

DELETE FROM Sales.Invoices;
PRINT CONCAT('Corp - Invoices: ', @@ROWCOUNT);

DELETE FROM Sales.OrderLines;
PRINT CONCAT('Corp - OrderLines: ', @@ROWCOUNT);

DELETE FROM Sales.Orders;
PRINT CONCAT('Corp - Orders: ', @@ROWCOUNT);

DELETE FROM Sales.SpecialDeals;
PRINT CONCAT('Corp - SpecialDeals: ', @@ROWCOUNT);

DELETE FROM Warehouse.StockItemTransactions;
PRINT CONCAT('Corp - StockItemTransactions: ', @@ROWCOUNT);

DELETE FROM Warehouse.StockItemHoldings;
PRINT CONCAT('Corp - StockItemHoldings: ', @@ROWCOUNT);
GO

-- ---------- 3. Reactivar TODAS las FKs (con verificación) ----------
DECLARE @sql_enable NVARCHAR(MAX) = N'';
SELECT @sql_enable += N'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N' WITH CHECK CHECK CONSTRAINT ALL;' + CHAR(13)
FROM sys.tables t
WHERE EXISTS (SELECT 1 FROM sys.foreign_keys fk WHERE fk.parent_object_id = t.object_id);

EXEC sp_executesql @sql_enable;
PRINT 'Corp - Todas las FKs reactivadas';
GO

-- Reactivar triggers
ALTER TABLE Sales.Customers           ENABLE TRIGGER ALL;
ALTER TABLE Sales.Invoices            ENABLE TRIGGER ALL;
ALTER TABLE Sales.Orders              ENABLE TRIGGER ALL;
ALTER TABLE Purchasing.PurchaseOrders ENABLE TRIGGER ALL;
ALTER TABLE Warehouse.StockItems      ENABLE TRIGGER ALL;
GO

SELECT 'Corp' AS Nodo,
    (SELECT COUNT(*) FROM Sales.Invoices)              AS Invoices,
    (SELECT COUNT(*) FROM Sales.InvoiceLines)          AS InvoiceLines,
    (SELECT COUNT(*) FROM Sales.Orders)                AS Orders,
    (SELECT COUNT(*) FROM Purchasing.PurchaseOrders)   AS PurchaseOrders,
    (SELECT COUNT(*) FROM Purchasing.SupplierTransactions) AS SupplierTransactions,
    (SELECT COUNT(*) FROM Warehouse.StockItemHoldings) AS StockItemHoldings,
    (SELECT COUNT(*) FROM Sales.Customers)             AS Clientes_Catalogo
GO

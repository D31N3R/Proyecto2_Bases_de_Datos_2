USE WideWorldImporters;
GO

/* ============================================================
   ESTADISTICAS CONSOLIDADAS (solo Corp) - vistas materializadas

   Corp no guarda facturas ni ordenes de compra: viven en las sucursales
   (fragmentacion). Para consultarlas en conjunto, Corp mantiene una COPIA
   MATERIALIZADA en el esquema Consolidado (solo las columnas que usan los
   reportes, mas la columna Sucursal). Se vuelve a llenar con
   Api.usp_Estadisticas_Refrescar.

   Los sinonimos Syn.* de esas 4 tablas apuntan al consolidado en Corp, asi
   los mismos procedimientos de reportes (_all_05) funcionan en Corp sin
   cambios.

   El filtro por sucursal lo resuelve la API: SJ y Limon se consultan en vivo
   en su propio nodo; la consolidada se consulta aqui, en Corp.
   ============================================================ */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Consolidado')
    EXEC('CREATE SCHEMA Consolidado');
GO

-- Tablas vacias con las mismas columnas que las originales, para que todo exista
-- desde la instalacion (se llenan al refrescar, cuando las sucursales ya estan fragmentadas)
IF OBJECT_ID('Consolidado.Invoices', 'U') IS NULL
    SELECT CAST(N'' AS NVARCHAR(10)) AS Sucursal,
           InvoiceID, CustomerID, BillToCustomerID, OrderID, DeliveryMethodID,
           SalespersonPersonID, InvoiceDate
    INTO Consolidado.Invoices
    FROM Sales.Invoices WHERE 1 = 0;
GO

IF OBJECT_ID('Consolidado.InvoiceLines', 'U') IS NULL
    SELECT CAST(N'' AS NVARCHAR(10)) AS Sucursal,
           InvoiceLineID, InvoiceID, StockItemID, Quantity, UnitPrice, TaxAmount,
           LineProfit, ExtendedPrice
    INTO Consolidado.InvoiceLines
    FROM Sales.InvoiceLines WHERE 1 = 0;
GO

IF OBJECT_ID('Consolidado.PurchaseOrders', 'U') IS NULL
    SELECT CAST(N'' AS NVARCHAR(10)) AS Sucursal,
           PurchaseOrderID, SupplierID, OrderDate, DeliveryMethodID,
           ExpectedDeliveryDate, IsOrderFinalized
    INTO Consolidado.PurchaseOrders
    FROM Purchasing.PurchaseOrders WHERE 1 = 0;
GO

IF OBJECT_ID('Consolidado.PurchaseOrderLines', 'U') IS NULL
    SELECT CAST(N'' AS NVARCHAR(10)) AS Sucursal,
           PurchaseOrderLineID, PurchaseOrderID, StockItemID, OrderedOuters,
           ReceivedOuters, ExpectedUnitPricePerOuter
    INTO Consolidado.PurchaseOrderLines
    FROM Purchasing.PurchaseOrderLines WHERE 1 = 0;
GO

-- Existencias de las dos sucursales sumadas (una fila por producto).
-- Corp no guarda inventario propio: el reporte de rotacion lo necesita en conjunto.
IF OBJECT_ID('Consolidado.StockItemHoldings', 'U') IS NULL
    SELECT StockItemID, QuantityOnHand
    INTO Consolidado.StockItemHoldings
    FROM Warehouse.StockItemHoldings WHERE 1 = 0;
GO

-- En Corp, los reportes leen el consolidado
DROP SYNONYM IF EXISTS Syn.Invoices;
CREATE SYNONYM Syn.Invoices FOR Consolidado.Invoices;
DROP SYNONYM IF EXISTS Syn.InvoiceLines;
CREATE SYNONYM Syn.InvoiceLines FOR Consolidado.InvoiceLines;
DROP SYNONYM IF EXISTS Syn.PurchaseOrders;
CREATE SYNONYM Syn.PurchaseOrders FOR Consolidado.PurchaseOrders;
DROP SYNONYM IF EXISTS Syn.PurchaseOrderLines;
CREATE SYNONYM Syn.PurchaseOrderLines FOR Consolidado.PurchaseOrderLines;
DROP SYNONYM IF EXISTS Syn.StockItemHoldings;
CREATE SYNONYM Syn.StockItemHoldings FOR Consolidado.StockItemHoldings;
GO

-- Resumen mensual materializado (ventas por sucursal, anio y mes)
IF OBJECT_ID('dbo.Estadisticas_Ventas', 'U') IS NOT NULL
    DROP TABLE dbo.Estadisticas_Ventas;
GO

CREATE TABLE dbo.Estadisticas_Ventas (
    Sucursal            NVARCHAR(10)  NOT NULL,
    Anio                INT           NOT NULL,
    Mes                 INT           NOT NULL,
    TotalFacturas       INT           NOT NULL,
    TotalVentas         DECIMAL(18,2) NOT NULL,
    UltimaActualizacion DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Estadisticas_Ventas PRIMARY KEY (Sucursal, Anio, Mes)
);
GO

/* Copia los datos de ambas sucursales a Consolidado.* y recalcula el resumen mensual.
   Sin transaccion explicita: una transaccion que lee de linked servers pide MSDTC. */
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_Refrescar
AS
BEGIN
    SET NOCOUNT ON;

    -- Facturas
    DROP TABLE IF EXISTS Consolidado.Invoices;
    SELECT CAST(N'SJ' AS NVARCHAR(10)) AS Sucursal,
           InvoiceID, CustomerID, BillToCustomerID, OrderID, DeliveryMethodID,
           SalespersonPersonID, InvoiceDate
    INTO Consolidado.Invoices
    FROM [sj].WideWorldImporters.Sales.Invoices;

    INSERT INTO Consolidado.Invoices
        (Sucursal, InvoiceID, CustomerID, BillToCustomerID, OrderID, DeliveryMethodID,
         SalespersonPersonID, InvoiceDate)
    SELECT N'LIMON', InvoiceID, CustomerID, BillToCustomerID, OrderID, DeliveryMethodID,
           SalespersonPersonID, InvoiceDate
    FROM [limon].WideWorldImporters.Sales.Invoices;

    -- Lineas de factura
    DROP TABLE IF EXISTS Consolidado.InvoiceLines;
    SELECT CAST(N'SJ' AS NVARCHAR(10)) AS Sucursal,
           InvoiceLineID, InvoiceID, StockItemID, Quantity, UnitPrice, TaxAmount,
           LineProfit, ExtendedPrice
    INTO Consolidado.InvoiceLines
    FROM [sj].WideWorldImporters.Sales.InvoiceLines;

    INSERT INTO Consolidado.InvoiceLines
        (Sucursal, InvoiceLineID, InvoiceID, StockItemID, Quantity, UnitPrice, TaxAmount,
         LineProfit, ExtendedPrice)
    SELECT N'LIMON', InvoiceLineID, InvoiceID, StockItemID, Quantity, UnitPrice, TaxAmount,
           LineProfit, ExtendedPrice
    FROM [limon].WideWorldImporters.Sales.InvoiceLines;

    -- Ordenes de compra
    DROP TABLE IF EXISTS Consolidado.PurchaseOrders;
    SELECT CAST(N'SJ' AS NVARCHAR(10)) AS Sucursal,
           PurchaseOrderID, SupplierID, OrderDate, DeliveryMethodID,
           ExpectedDeliveryDate, IsOrderFinalized
    INTO Consolidado.PurchaseOrders
    FROM [sj].WideWorldImporters.Purchasing.PurchaseOrders;

    INSERT INTO Consolidado.PurchaseOrders
        (Sucursal, PurchaseOrderID, SupplierID, OrderDate, DeliveryMethodID,
         ExpectedDeliveryDate, IsOrderFinalized)
    SELECT N'LIMON', PurchaseOrderID, SupplierID, OrderDate, DeliveryMethodID,
           ExpectedDeliveryDate, IsOrderFinalized
    FROM [limon].WideWorldImporters.Purchasing.PurchaseOrders;

    -- Lineas de ordenes de compra
    DROP TABLE IF EXISTS Consolidado.PurchaseOrderLines;
    SELECT CAST(N'SJ' AS NVARCHAR(10)) AS Sucursal,
           PurchaseOrderLineID, PurchaseOrderID, StockItemID, OrderedOuters,
           ReceivedOuters, ExpectedUnitPricePerOuter
    INTO Consolidado.PurchaseOrderLines
    FROM [sj].WideWorldImporters.Purchasing.PurchaseOrderLines;

    INSERT INTO Consolidado.PurchaseOrderLines
        (Sucursal, PurchaseOrderLineID, PurchaseOrderID, StockItemID, OrderedOuters,
         ReceivedOuters, ExpectedUnitPricePerOuter)
    SELECT N'LIMON', PurchaseOrderLineID, PurchaseOrderID, StockItemID, OrderedOuters,
           ReceivedOuters, ExpectedUnitPricePerOuter
    FROM [limon].WideWorldImporters.Purchasing.PurchaseOrderLines;

    -- Existencias: suma de lo que tiene cada sucursal, por producto
    DROP TABLE IF EXISTS Consolidado.StockItemHoldings;
    SELECT StockItemID, CAST(SUM(QuantityOnHand) AS INT) AS QuantityOnHand
    INTO Consolidado.StockItemHoldings
    FROM (
        SELECT StockItemID, QuantityOnHand FROM [sj].WideWorldImporters.Warehouse.StockItemHoldings
        UNION ALL
        SELECT StockItemID, QuantityOnHand FROM [limon].WideWorldImporters.Warehouse.StockItemHoldings
    ) AS x
    GROUP BY StockItemID;

    -- Resumen mensual, calculado desde el consolidado
    TRUNCATE TABLE dbo.Estadisticas_Ventas;

    INSERT INTO dbo.Estadisticas_Ventas (Sucursal, Anio, Mes, TotalFacturas, TotalVentas)
    SELECT i.Sucursal, YEAR(i.InvoiceDate), MONTH(i.InvoiceDate),
           COUNT(DISTINCT i.InvoiceID), SUM(il.ExtendedPrice)
    FROM Consolidado.Invoices i
    JOIN Consolidado.InvoiceLines il
      ON il.InvoiceID = i.InvoiceID AND il.Sucursal = i.Sucursal
    GROUP BY i.Sucursal, YEAR(i.InvoiceDate), MONTH(i.InvoiceDate);
END
GO

-- Consulta del resumen mensual materializado (@Sucursal NULL = consolidado)
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_Consultar
    @Sucursal NVARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @Sucursal IS NULL
        SELECT Anio, Mes, SUM(TotalFacturas) AS TotalFacturas, SUM(TotalVentas) AS TotalVentas
        FROM dbo.Estadisticas_Ventas
        GROUP BY Anio, Mes
        ORDER BY Anio, Mes;
    ELSE
        SELECT Anio, Mes, TotalFacturas, TotalVentas
        FROM dbo.Estadisticas_Ventas
        WHERE Sucursal = @Sucursal
        ORDER BY Anio, Mes;
END
GO
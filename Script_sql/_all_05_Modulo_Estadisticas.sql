USE WideWorldImporters;
GO

/* ============================================================
   PROCEDURES DE ESTADÍSTICAS
   ============================================================ */

-- Reporte 1: montos de compras por categoría y proveedor con ROLLUP
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_ComprasProveedores
    @Categoria NVARCHAR(100) = NULL,
    @Proveedor NVARCHAR(100) = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 10;

    SELECT
        CASE WHEN GROUPING(sc.SupplierCategoryName) = 1 THEN 'Total general'
             ELSE sc.SupplierCategoryName END AS Categoria,
        CASE WHEN GROUPING(sc.SupplierCategoryName) = 1 THEN NULL
             WHEN GROUPING(s.SupplierName) = 1 THEN 'Total de la categoría'
             ELSE s.SupplierName END AS Proveedor,
        MAX(m.Monto) AS MontoMaximo,
        MIN(m.Monto) AS MontoMinimo,
        CAST(AVG(m.Monto) AS DECIMAL(18,2)) AS MontoPromedio,
        GROUPING(sc.SupplierCategoryName) + GROUPING(s.SupplierName) AS Nivel,
        COUNT(*) OVER() AS TotalRegistros
    FROM Syn.PurchaseOrders po
    INNER JOIN (
        SELECT PurchaseOrderID, SUM(OrderedOuters * ExpectedUnitPricePerOuter) AS Monto
        FROM Syn.PurchaseOrderLines
        GROUP BY PurchaseOrderID
    ) m ON m.PurchaseOrderID = po.PurchaseOrderID
    INNER JOIN Syn.Suppliers s ON s.SupplierID = po.SupplierID
    INNER JOIN Syn.SupplierCategories sc ON sc.SupplierCategoryID = s.SupplierCategoryID
    WHERE (@Categoria IS NULL OR sc.SupplierCategoryName LIKE '%' + @Categoria + '%')
      AND (@Proveedor IS NULL OR s.SupplierName LIKE '%' + @Proveedor + '%')
    GROUP BY ROLLUP (sc.SupplierCategoryName, s.SupplierName)
    ORDER BY GROUPING(sc.SupplierCategoryName), sc.SupplierCategoryName,
             GROUPING(s.SupplierName), s.SupplierName
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO


-- Reporte 2: montos de ventas por categoría y cliente con ROLLUP
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_VentasClientes
    @Categoria NVARCHAR(100) = NULL,
    @Cliente NVARCHAR(100) = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 10;

    SELECT
        CASE WHEN GROUPING(cc.CustomerCategoryName) = 1 THEN 'Total general'
             ELSE cc.CustomerCategoryName END AS Categoria,
        CASE WHEN GROUPING(cc.CustomerCategoryName) = 1 THEN NULL
             WHEN GROUPING(c.CustomerName) = 1 THEN 'Total de la categoría'
             ELSE c.CustomerName END AS Cliente,
        MAX(m.Monto) AS MontoMaximo,
        MIN(m.Monto) AS MontoMinimo,
        CAST(AVG(m.Monto) AS DECIMAL(18,2)) AS MontoPromedio,
        GROUPING(cc.CustomerCategoryName) + GROUPING(c.CustomerName) AS Nivel,
        COUNT(*) OVER() AS TotalRegistros
    FROM Syn.Invoices i
    INNER JOIN (
        SELECT InvoiceID, SUM(ExtendedPrice) AS Monto
        FROM Syn.InvoiceLines
        GROUP BY InvoiceID
    ) m ON m.InvoiceID = i.InvoiceID
    INNER JOIN Syn.Customers c ON c.CustomerID = i.CustomerID
    INNER JOIN Syn.CustomerCategories cc ON cc.CustomerCategoryID = c.CustomerCategoryID
    WHERE (@Categoria IS NULL OR cc.CustomerCategoryName LIKE '%' + @Categoria + '%')
      AND (@Cliente IS NULL OR c.CustomerName LIKE '%' + @Cliente + '%')
    GROUP BY ROLLUP (cc.CustomerCategoryName, c.CustomerName)
    ORDER BY GROUPING(cc.CustomerCategoryName), cc.CustomerCategoryName,
             GROUPING(c.CustomerName), c.CustomerName
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

-- Años válidos de ventas
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_AniosVentas
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DISTINCT YEAR(InvoiceDate) AS Anio
    FROM Syn.Invoices
    ORDER BY Anio;
END
GO

-- Años válidos de compras
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_AniosCompras
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DISTINCT YEAR(OrderDate) AS Anio
    FROM Syn.PurchaseOrders
    ORDER BY Anio;
END
GO

-- Reporte 3: top 5 de productos con más ganancia por año con DENSE_RANK
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_TopProductos
    @AnioDesde INT = NULL,
    @AnioHasta INT = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 10;

    SELECT r.Anio, r.Posicion, si.StockItemName AS Producto, r.Ganancia,
           COUNT(*) OVER() AS TotalRegistros
    FROM (
        SELECT g.Anio, g.StockItemID, g.Ganancia,
               DENSE_RANK() OVER (PARTITION BY g.Anio ORDER BY g.Ganancia DESC) AS Posicion
        FROM (
            SELECT YEAR(i.InvoiceDate) AS Anio, il.StockItemID, SUM(il.LineProfit) AS Ganancia
            FROM Syn.InvoiceLines il
            INNER JOIN Syn.Invoices i ON i.InvoiceID = il.InvoiceID
            WHERE (@AnioDesde IS NULL OR YEAR(i.InvoiceDate) >= @AnioDesde)
              AND (@AnioHasta IS NULL OR YEAR(i.InvoiceDate) <= @AnioHasta)
            GROUP BY YEAR(i.InvoiceDate), il.StockItemID
        ) g
    ) r
    INNER JOIN Syn.StockItems si ON si.StockItemID = r.StockItemID
    WHERE r.Posicion <= 5
    ORDER BY r.Anio, r.Posicion, si.StockItemName, si.StockItemID
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

-- Reporte 4: top 5 de clientes con más facturas por año con DENSE_RANK
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_TopClientes
    @AnioDesde INT = NULL,
    @AnioHasta INT = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 10;

    SELECT r.Anio, r.Posicion, c.CustomerName AS Cliente, r.CantidadFacturas, r.MontoTotal,
           COUNT(*) OVER() AS TotalRegistros
    FROM (
        SELECT g.Anio, g.CustomerID, g.CantidadFacturas, g.MontoTotal,
               DENSE_RANK() OVER (PARTITION BY g.Anio ORDER BY g.CantidadFacturas DESC, g.MontoTotal DESC) AS Posicion
        FROM (
            SELECT YEAR(i.InvoiceDate) AS Anio, i.CustomerID,
                   COUNT(*) AS CantidadFacturas, SUM(m.Monto) AS MontoTotal
            FROM Syn.Invoices i
            INNER JOIN (
                SELECT InvoiceID, SUM(ExtendedPrice) AS Monto
                FROM Syn.InvoiceLines
                GROUP BY InvoiceID
            ) m ON m.InvoiceID = i.InvoiceID
            WHERE (@AnioDesde IS NULL OR YEAR(i.InvoiceDate) >= @AnioDesde)
              AND (@AnioHasta IS NULL OR YEAR(i.InvoiceDate) <= @AnioHasta)
            GROUP BY YEAR(i.InvoiceDate), i.CustomerID
        ) g
    ) r
    INNER JOIN Syn.Customers c ON c.CustomerID = r.CustomerID
    WHERE r.Posicion <= 5
    ORDER BY r.Anio, r.Posicion, c.CustomerName, c.CustomerID
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

-- Reporte 5: top 5 de proveedores con más órdenes de compra por año con DENSE_RANK
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_TopProveedores
    @AnioDesde INT = NULL,
    @AnioHasta INT = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 10;

    SELECT r.Anio, r.Posicion, s.SupplierName AS Proveedor, r.CantidadOrdenes, r.MontoTotal,
           COUNT(*) OVER() AS TotalRegistros
    FROM (
        SELECT g.Anio, g.SupplierID, g.CantidadOrdenes, g.MontoTotal,
               DENSE_RANK() OVER (PARTITION BY g.Anio ORDER BY g.CantidadOrdenes DESC, g.MontoTotal DESC) AS Posicion
        FROM (
            SELECT YEAR(po.OrderDate) AS Anio, po.SupplierID,
                   COUNT(*) AS CantidadOrdenes, SUM(m.Monto) AS MontoTotal
            FROM Syn.PurchaseOrders po
            INNER JOIN (
                SELECT PurchaseOrderID, SUM(OrderedOuters * ExpectedUnitPricePerOuter) AS Monto
                FROM Syn.PurchaseOrderLines
                GROUP BY PurchaseOrderID
            ) m ON m.PurchaseOrderID = po.PurchaseOrderID
            WHERE (@AnioDesde IS NULL OR YEAR(po.OrderDate) >= @AnioDesde)
              AND (@AnioHasta IS NULL OR YEAR(po.OrderDate) <= @AnioHasta)
            GROUP BY YEAR(po.OrderDate), po.SupplierID
        ) g
    ) r
    INNER JOIN Syn.Suppliers s ON s.SupplierID = r.SupplierID
    WHERE r.Posicion <= 5
    ORDER BY r.Anio, r.Posicion, s.SupplierName, s.SupplierID
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO


-- Reporte 6: matriz de ventas por categoría de producto y año
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_MatrizVentas
    @Pagina INT = 1,
    @TamanoPagina INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 10;

    SELECT
        StockGroupName AS Categoria,
        ISNULL([2013], 0) AS [2013],
        ISNULL([2014], 0) AS [2014],
        ISNULL([2015], 0) AS [2015],
        ISNULL([2016], 0) AS [2016],
        ISNULL([2013], 0) + ISNULL([2014], 0) + ISNULL([2015], 0) + ISNULL([2016], 0) AS Total,
        COUNT(*) OVER() AS TotalRegistros
    FROM (
        SELECT
            sg.StockGroupName,
            YEAR(i.InvoiceDate) AS Anio,
            il.ExtendedPrice AS Monto
        FROM Syn.InvoiceLines il
        INNER JOIN Syn.Invoices i ON i.InvoiceID = il.InvoiceID
        INNER JOIN Syn.StockItemStockGroups sisg ON sisg.StockItemID = il.StockItemID
        INNER JOIN Syn.StockGroups sg ON sg.StockGroupID = sisg.StockGroupID
    ) AS SourceTable
    PIVOT (
        SUM(Monto)
        FOR Anio IN ([2013], [2014], [2015], [2016])
    ) AS PivotTable
    ORDER BY StockGroupName
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO


-- Productos para el filtro de productos
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_Productos
    @StockGroupID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT si.StockItemID, si.StockItemName
    FROM Syn.StockItems si
    WHERE @StockGroupID IS NULL
       OR EXISTS (SELECT 1 FROM Syn.StockItemStockGroups sg
                  WHERE sg.StockItemID = si.StockItemID AND sg.StockGroupID = @StockGroupID)
    ORDER BY si.StockItemName;
END
GO

-- Categorias para el filtro de subcategorias
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_SubGrupos
    @StockGroupID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Si no se pasa grupo, devuelve todos los grupos
    IF @StockGroupID IS NULL
    BEGIN
        SELECT StockGroupID, StockGroupName
        FROM Syn.StockGroups
        ORDER BY StockGroupName;
        RETURN;
    END

    -- Si se pasa grupo, devuelve solo los grupos que comparten
    -- al menos un producto con el grupo dado (excluyendo el mismo)
    SELECT DISTINCT sg.StockGroupID, sg.StockGroupName
    FROM Syn.StockGroups sg
    WHERE sg.StockGroupID <> @StockGroupID
      AND EXISTS (
          SELECT 1
          FROM Syn.StockItemStockGroups sisg1
          INNER JOIN Syn.StockItemStockGroups sisg2
              ON sisg2.StockItemID = sisg1.StockItemID
          WHERE sisg1.StockGroupID = @StockGroupID
            AND sisg2.StockGroupID = sg.StockGroupID
      )
    ORDER BY sg.StockGroupName;
END
GO

-- Reporte 7: seguimiento mensual de compras de clientes con paginación
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_SeguimientoClientes
    @Anio INT = NULL,
    @Mes INT = NULL,
    @StockGroupID INT = NULL,
    @StockSubGroupID INT = NULL,
    @StockItemID INT = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 50;

    SELECT
        c.CustomerName AS Cliente,
        g.Anio,
        g.Mes,
        g.MontoTotal,
        CONVERT(VARCHAR(10), g.PrimeraFactura, 23) AS PrimeraFactura,
        CONVERT(VARCHAR(10), g.UltimaFactura, 23) AS UltimaFactura,
        g.CantidadTotal,
        g.CantidadMinima,
        g.CantidadMaxima,
        COUNT(*) OVER() AS TotalRegistros
    FROM (
        SELECT i.CustomerID,
               YEAR(i.InvoiceDate) AS Anio,
               MONTH(i.InvoiceDate) AS Mes,
               SUM(il.ExtendedPrice) AS MontoTotal,
               MIN(i.InvoiceDate) AS PrimeraFactura,
               MAX(i.InvoiceDate) AS UltimaFactura,
               SUM(il.Quantity) AS CantidadTotal,
               MIN(il.Quantity) AS CantidadMinima,
               MAX(il.Quantity) AS CantidadMaxima
        FROM Syn.InvoiceLines il
        INNER JOIN Syn.Invoices i ON i.InvoiceID = il.InvoiceID
        WHERE (@Anio IS NULL OR YEAR(i.InvoiceDate) = @Anio)
          AND (@Mes IS NULL OR MONTH(i.InvoiceDate) = @Mes)
          AND (@StockItemID IS NULL OR il.StockItemID = @StockItemID)
          AND (@StockGroupID IS NULL OR EXISTS (
                SELECT 1 FROM Syn.StockItemStockGroups sg
                WHERE sg.StockItemID = il.StockItemID AND sg.StockGroupID = @StockGroupID))
          AND (@StockSubGroupID IS NULL OR EXISTS (
                SELECT 1 FROM Syn.StockItemStockGroups sg
                WHERE sg.StockItemID = il.StockItemID AND sg.StockGroupID = @StockSubGroupID))
        GROUP BY i.CustomerID, YEAR(i.InvoiceDate), MONTH(i.InvoiceDate)
    ) g
    INNER JOIN Syn.Customers c ON c.CustomerID = g.CustomerID
    ORDER BY c.CustomerName, g.CustomerID, g.Anio, g.Mes
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

-- Reporte 8: seguimiento mensual de compras a proveedores con paginación
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_SeguimientoProveedores
    @Anio INT = NULL,
    @Mes INT = NULL,
    @StockGroupID INT = NULL,
    @StockSubGroupID INT = NULL,
    @StockItemID INT = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 50;

    SELECT
        s.SupplierName AS Proveedor,
        g.Anio,
        g.Mes,
        g.MontoTotal,
        CONVERT(VARCHAR(10), g.PrimeraOrden, 23) AS PrimeraOrden,
        CONVERT(VARCHAR(10), g.UltimaOrden, 23) AS UltimaOrden,
        g.CantidadTotal,
        g.CantidadMinima,
        g.CantidadMaxima,
        COUNT(*) OVER() AS TotalRegistros
    FROM (
        SELECT po.SupplierID,
               YEAR(po.OrderDate) AS Anio,
               MONTH(po.OrderDate) AS Mes,
               SUM(pol.OrderedOuters * pol.ExpectedUnitPricePerOuter) AS MontoTotal,
               MIN(po.OrderDate) AS PrimeraOrden,
               MAX(po.OrderDate) AS UltimaOrden,
               SUM(pol.OrderedOuters) AS CantidadTotal,
               MIN(pol.OrderedOuters) AS CantidadMinima,
               MAX(pol.OrderedOuters) AS CantidadMaxima
        FROM Syn.PurchaseOrderLines pol
        INNER JOIN Syn.PurchaseOrders po ON po.PurchaseOrderID = pol.PurchaseOrderID
        WHERE (@Anio IS NULL OR YEAR(po.OrderDate) = @Anio)
          AND (@Mes IS NULL OR MONTH(po.OrderDate) = @Mes)
          AND (@StockItemID IS NULL OR pol.StockItemID = @StockItemID)
          AND (@StockGroupID IS NULL OR EXISTS (
                SELECT 1 FROM Syn.StockItemStockGroups sg
                WHERE sg.StockItemID = pol.StockItemID AND sg.StockGroupID = @StockGroupID))
          AND (@StockSubGroupID IS NULL OR EXISTS (
                SELECT 1 FROM Syn.StockItemStockGroups sg
                WHERE sg.StockItemID = pol.StockItemID AND sg.StockGroupID = @StockSubGroupID))
        GROUP BY po.SupplierID, YEAR(po.OrderDate), MONTH(po.OrderDate)
    ) g
    INNER JOIN Syn.Suppliers s ON s.SupplierID = g.SupplierID
    ORDER BY s.SupplierName, g.SupplierID, g.Anio, g.Mes
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

-- Reporte 9: rotacion promedio (en dias) del inventario por producto
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_RotacionInventario
    @StockGroupID INT = NULL,
    @Anio INT = NULL,
    @SupplierID INT = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 20;

    SELECT
        si.StockItemID,
        si.StockItemName AS Producto,
        sup.SupplierName AS Proveedor,
        STUFF((
            SELECT ', ' + sg.StockGroupName
            FROM Syn.StockItemStockGroups sisg
            INNER JOIN Syn.StockGroups sg ON sg.StockGroupID = sisg.StockGroupID
            WHERE sisg.StockItemID = si.StockItemID
            FOR XML PATH('')
        ), 1, 2, '') AS Categoria,
        ISNULL(sih.QuantityOnHand, 0) AS CantidadEnMano,
        ISNULL(SUM(il.Quantity), 0) AS CantidadVendida,
        ISNULL(SUM(il.LineProfit), 0) AS GananciaTotal,
        CASE
        WHEN ISNULL(SUM(il.Quantity), 0) = 0 THEN NULL
        ELSE CAST(
            ISNULL(sih.QuantityOnHand, 0) * 
            DATEDIFF(DAY, MIN(i.InvoiceDate), MAX(i.InvoiceDate)) * 1.0
            / SUM(il.Quantity)
        AS DECIMAL(10, 2))
    END AS DiasRotacion,
        COUNT(*) OVER() AS TotalRegistros
    FROM Syn.StockItems si
    LEFT JOIN Syn.StockItemHoldings sih ON sih.StockItemID = si.StockItemID
    LEFT JOIN Syn.Suppliers sup ON sup.SupplierID = si.SupplierID
    LEFT JOIN Syn.InvoiceLines il ON il.StockItemID = si.StockItemID
    LEFT JOIN Syn.Invoices i ON i.InvoiceID = il.InvoiceID
    WHERE (@SupplierID IS NULL OR si.SupplierID = @SupplierID)
      AND (@Anio IS NULL OR i.InvoiceDate IS NULL OR YEAR(i.InvoiceDate) = @Anio)
      AND (@StockGroupID IS NULL OR EXISTS (
            SELECT 1 FROM Syn.StockItemStockGroups sg2
            WHERE sg2.StockItemID = si.StockItemID AND sg2.StockGroupID = @StockGroupID))
    GROUP BY si.StockItemID, si.StockItemName, sup.SupplierName, sih.QuantityOnHand
    HAVING ISNULL(SUM(il.Quantity), 0) > 0
    ORDER BY DiasRotacion ASC, si.StockItemName, si.StockItemID
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

-- Reporte 10: Metodo de envio favorito por ubicacion
CREATE OR ALTER PROCEDURE Api.usp_Estadisticas_MetodoEnvioFavorito
    @Anio INT = NULL,
    @Mes INT = NULL,
    @CustomerCategoryID INT = NULL,
    @StockGroupID INT = NULL,
    @StockItemID INT = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 20;

    WITH VentasFiltradas AS (
        SELECT
            i.InvoiceID,
            i.DeliveryMethodID,
            c.DeliveryCityID,
            il.StockItemID
        FROM Syn.Invoices i
        INNER JOIN Syn.InvoiceLines il ON il.InvoiceID = i.InvoiceID
        INNER JOIN Syn.Customers c ON c.CustomerID = i.CustomerID
        WHERE (@Anio IS NULL OR YEAR(i.InvoiceDate) = @Anio)
          AND (@Mes IS NULL OR MONTH(i.InvoiceDate) = @Mes)
          AND (@CustomerCategoryID IS NULL OR c.CustomerCategoryID = @CustomerCategoryID)
          AND (@StockItemID IS NULL OR il.StockItemID = @StockItemID)
          AND (@StockGroupID IS NULL OR EXISTS (
                SELECT 1 FROM Syn.StockItemStockGroups sg
                WHERE sg.StockItemID = il.StockItemID AND sg.StockGroupID = @StockGroupID))
    ),
    Conteo AS (
        SELECT
            v.DeliveryCityID,
            v.DeliveryMethodID,
            COUNT(DISTINCT v.InvoiceID) AS CantidadVentas,
            DENSE_RANK() OVER (
                PARTITION BY v.DeliveryCityID
                ORDER BY COUNT(DISTINCT v.InvoiceID) DESC
            ) AS Posicion
        FROM VentasFiltradas v
        GROUP BY v.DeliveryCityID, v.DeliveryMethodID
    )
    SELECT
        city.CityName AS Ciudad,
        sp.StateProvinceName AS Estado,
        dm.DeliveryMethodName AS MetodoEnvio,
        c.CantidadVentas,
        c.Posicion,
        COUNT(*) OVER() AS TotalRegistros
    FROM Conteo c
    INNER JOIN Syn.Cities city ON city.CityID = c.DeliveryCityID
    LEFT JOIN Application.StateProvinces sp ON sp.StateProvinceID = city.StateProvinceID
    INNER JOIN Syn.DeliveryMethods dm ON dm.DeliveryMethodID = c.DeliveryMethodID
    WHERE c.Posicion = 1
    ORDER BY c.CantidadVentas DESC, city.CityName, c.DeliveryCityID, c.DeliveryMethodID
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

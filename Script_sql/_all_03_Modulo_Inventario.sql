USE WideWorldImporters;
GO

/* ============================================================
   SINÓNIMOS PARA INVENTARIO
   ============================================================ */

IF OBJECT_ID('Syn.StockItems', 'SN') IS NOT NULL DROP SYNONYM Syn.StockItems;
CREATE SYNONYM Syn.StockItems FOR Warehouse.StockItems;
GO

IF OBJECT_ID('Syn.StockGroups', 'SN') IS NOT NULL DROP SYNONYM Syn.StockGroups;
CREATE SYNONYM Syn.StockGroups FOR Warehouse.StockGroups;
GO

IF OBJECT_ID('Syn.StockItemStockGroups', 'SN') IS NOT NULL DROP SYNONYM Syn.StockItemStockGroups;
CREATE SYNONYM Syn.StockItemStockGroups FOR Warehouse.StockItemStockGroups;
GO

IF OBJECT_ID('Syn.StockItemHoldings', 'SN') IS NOT NULL DROP SYNONYM Syn.StockItemHoldings;
CREATE SYNONYM Syn.StockItemHoldings FOR Warehouse.StockItemHoldings;
GO

IF OBJECT_ID('Syn.Colors', 'SN') IS NOT NULL DROP SYNONYM Syn.Colors;
CREATE SYNONYM Syn.Colors FOR Warehouse.Colors;
GO

IF OBJECT_ID('Syn.PackageTypes', 'SN') IS NOT NULL DROP SYNONYM Syn.PackageTypes;
CREATE SYNONYM Syn.PackageTypes FOR Warehouse.PackageTypes;
GO

IF OBJECT_ID('Syn.OrderLines', 'SN') IS NOT NULL DROP SYNONYM Syn.OrderLines;
CREATE SYNONYM Syn.OrderLines FOR Sales.OrderLines;
GO

IF OBJECT_ID('Syn.InvoiceLines', 'SN') IS NOT NULL DROP SYNONYM Syn.InvoiceLines;
CREATE SYNONYM Syn.InvoiceLines FOR Sales.InvoiceLines;
GO

IF OBJECT_ID('Syn.PurchaseOrderLines', 'SN') IS NOT NULL DROP SYNONYM Syn.PurchaseOrderLines;
CREATE SYNONYM Syn.PurchaseOrderLines FOR Purchasing.PurchaseOrderLines;
GO

/* ============================================================
   PROCEDURES DE INVENTARIO
   ============================================================ */

-- Listar grupos de productos
CREATE OR ALTER PROCEDURE Api.usp_Inventario_Grupos
AS
BEGIN
    SET NOCOUNT ON;
    SELECT StockGroupID, StockGroupName
    FROM Syn.StockGroups
    ORDER BY StockGroupName;
END
GO


-- Listar productos con filtros acumulativos
CREATE OR ALTER PROCEDURE Api.usp_Inventario_Listar
    @Nombre NVARCHAR(100) = NULL,
    @StockGroupID INT = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 50;

    -- Primero se filtra y pagina; los grupos se arman solo para esas filas
    WITH Pagina AS (
        SELECT
            si.StockItemID,
            si.StockItemName,
            ISNULL(sih.QuantityOnHand, 0) AS CantidadInventario,
            COUNT(*) OVER() AS TotalRegistros
        FROM Syn.StockItems si
        LEFT JOIN Syn.StockItemHoldings sih ON sih.StockItemID = si.StockItemID
        WHERE (@Nombre IS NULL OR si.StockItemName LIKE '%' + @Nombre + '%')
          AND (@StockGroupID IS NULL OR EXISTS (
              SELECT 1
              FROM Syn.StockItemStockGroups sisg2
              WHERE sisg2.StockItemID = si.StockItemID
                AND sisg2.StockGroupID = @StockGroupID
          ))
        ORDER BY si.StockItemName ASC, si.StockItemID ASC
        OFFSET CAST(@Pagina - 1 AS BIGINT) * @TamanoPagina ROWS
        FETCH NEXT @TamanoPagina ROWS ONLY
    )
    SELECT
        p.StockItemID,
        p.StockItemName AS Nombre,
        STUFF((
            SELECT ', ' + sg.StockGroupName
            FROM Syn.StockItemStockGroups sisg
            INNER JOIN Syn.StockGroups sg ON sg.StockGroupID = sisg.StockGroupID
            WHERE sisg.StockItemID = p.StockItemID
            FOR XML PATH('')
        ), 1, 2, '') AS Grupo,
        p.CantidadInventario,
        p.TotalRegistros
    FROM Pagina p
    ORDER BY p.StockItemName ASC, p.StockItemID ASC;
END
GO

-- Detalle completo del producto
CREATE OR ALTER PROCEDURE Api.usp_Inventario_Detalle
    @StockItemID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        si.StockItemID,
        si.StockItemName AS Nombre,
        si.SupplierID,
        sup.SupplierName AS NombreProveedor,
        si.ColorID,
        col.ColorName AS Color,
        si.UnitPackageID,
        upt.PackageTypeName AS UnidadEmpaque,
        si.OuterPackageID,
        opt.PackageTypeName AS EmpaqueExterior,
        si.QuantityPerOuter AS CantidadEmpaque,
        si.Brand AS Marca,
        si.Size AS Talla,
        si.TaxRate AS Impuesto,
        si.UnitPrice AS PrecioUnitario,
        si.RecommendedRetailPrice AS PrecioVenta,
        si.TypicalWeightPerUnit AS Peso,
        REPLACE(si.SearchDetails, ' ', ', ') AS PalabrasClaves,
        ISNULL(sih.QuantityOnHand, 0) AS CantidadDisponible,
        sih.BinLocation AS Ubicacion
    FROM Syn.StockItems si
    LEFT JOIN Syn.Suppliers sup ON sup.SupplierID = si.SupplierID
    LEFT JOIN Syn.Colors col ON col.ColorID = si.ColorID
    LEFT JOIN Syn.PackageTypes upt ON upt.PackageTypeID = si.UnitPackageID
    LEFT JOIN Syn.PackageTypes opt ON opt.PackageTypeID = si.OuterPackageID
    LEFT JOIN Syn.StockItemHoldings sih ON sih.StockItemID = si.StockItemID
    WHERE si.StockItemID = @StockItemID;
END
GO

-- Combos para el formulario
CREATE OR ALTER PROCEDURE Api.usp_Inventario_Colores
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ColorID, ColorName
    FROM Syn.Colors
    ORDER BY ColorName;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Inventario_TiposEmpaque
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PackageTypeID, PackageTypeName
    FROM Syn.PackageTypes
    ORDER BY PackageTypeName;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Inventario_Proveedores
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SupplierID, SupplierName
    FROM Syn.Suppliers
    ORDER BY SupplierName;
END
GO


-- Crear producto (3 tablas en una sola transaccion)
CREATE OR ALTER PROCEDURE Api.usp_Inventario_Crear
    @StockItemName NVARCHAR(100),
    @SupplierID INT,
    @UnitPackageID INT,
    @OuterPackageID INT,
    @QuantityPerOuter INT,
    @TaxRate DECIMAL(18,3),
    @UnitPrice DECIMAL(18,2),
    @TypicalWeightPerUnit DECIMAL(18,3),
    @StockGroupID INT,
    @BinLocation NVARCHAR(20),
    @ColorID INT = NULL,
    @Brand NVARCHAR(50) = NULL,
    @Size NVARCHAR(20) = NULL,
    @RecommendedRetailPrice DECIMAL(18,2) = NULL,
    @QuantityOnHand INT = 0,
    @NuevoStockItemID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM Syn.StockItems WHERE StockItemName = @StockItemName)
            THROW 50021, 'Ya existe un producto con ese nombre.', 1;

        IF NOT EXISTS (SELECT 1 FROM Syn.Suppliers WHERE SupplierID = @SupplierID)
            THROW 50022, 'El proveedor no existe.', 1;

        IF NOT EXISTS (SELECT 1 FROM Syn.StockGroups WHERE StockGroupID = @StockGroupID)
            THROW 50023, 'El grupo de producto no existe.', 1;

        DECLARE @SistemaPersonID INT = (SELECT MIN(PersonID) FROM Syn.People);
        DECLARE @NextItemID INT = (SELECT ISNULL(MAX(StockItemID), 0) + 1 FROM Syn.StockItems);
        DECLARE @NextLinkID INT = (SELECT ISNULL(MAX(StockItemStockGroupID), 0) + 1 FROM Syn.StockItemStockGroups);

        INSERT INTO Syn.StockItems (
            StockItemID, StockItemName, SupplierID, ColorID,
            UnitPackageID, OuterPackageID, Brand, Size,
            LeadTimeDays, QuantityPerOuter, IsChillerStock,
            TaxRate, UnitPrice, RecommendedRetailPrice,
            TypicalWeightPerUnit, LastEditedBy
        )
        VALUES (
            @NextItemID, @StockItemName, @SupplierID, @ColorID,
            @UnitPackageID, @OuterPackageID, @Brand, @Size,
            7, @QuantityPerOuter, 0,
            @TaxRate, @UnitPrice, @RecommendedRetailPrice,
            @TypicalWeightPerUnit, @SistemaPersonID
        );

        INSERT INTO Syn.StockItemHoldings (
            StockItemID, QuantityOnHand, BinLocation,
            LastStocktakeQuantity, LastCostPrice,
            ReorderLevel, TargetStockLevel, LastEditedBy
        )
        VALUES (
            @NextItemID, @QuantityOnHand, @BinLocation,
            @QuantityOnHand, @UnitPrice,
            0, 0, @SistemaPersonID
        );

        INSERT INTO Syn.StockItemStockGroups (
            StockItemStockGroupID, StockItemID, StockGroupID, LastEditedBy
        )
        VALUES (@NextLinkID, @NextItemID, @StockGroupID, @SistemaPersonID);

        SET @NuevoStockItemID = @NextItemID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


-- Modificar producto (no toca los grupos)
CREATE OR ALTER PROCEDURE Api.usp_Inventario_Modificar
    @StockItemID INT,
    @StockItemName NVARCHAR(100),
    @SupplierID INT,
    @UnitPackageID INT,
    @OuterPackageID INT,
    @QuantityPerOuter INT,
    @TaxRate DECIMAL(18,3),
    @UnitPrice DECIMAL(18,2),
    @TypicalWeightPerUnit DECIMAL(18,3),
    @BinLocation NVARCHAR(20),
    @ColorID INT = NULL,
    @Brand NVARCHAR(50) = NULL,
    @Size NVARCHAR(20) = NULL,
    @RecommendedRetailPrice DECIMAL(18,2) = NULL,
    @QuantityOnHand INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM Syn.StockItems WHERE StockItemID = @StockItemID)
            THROW 50024, 'El producto no existe.', 1;

        IF EXISTS (SELECT 1 FROM Syn.StockItems
                   WHERE StockItemName = @StockItemName AND StockItemID <> @StockItemID)
            THROW 50021, 'Ya existe otro producto con ese nombre.', 1;

        IF NOT EXISTS (SELECT 1 FROM Syn.Suppliers WHERE SupplierID = @SupplierID)
            THROW 50022, 'El proveedor no existe.', 1;

        DECLARE @SistemaPersonID INT = (SELECT MIN(PersonID) FROM Syn.People);

        UPDATE Syn.StockItems
        SET StockItemName = @StockItemName,
            SupplierID = @SupplierID,
            ColorID = @ColorID,
            UnitPackageID = @UnitPackageID,
            OuterPackageID = @OuterPackageID,
            QuantityPerOuter = @QuantityPerOuter,
            Brand = @Brand,
            Size = @Size,
            TaxRate = @TaxRate,
            UnitPrice = @UnitPrice,
            RecommendedRetailPrice = @RecommendedRetailPrice,
            TypicalWeightPerUnit = @TypicalWeightPerUnit,
            LastEditedBy = @SistemaPersonID
        WHERE StockItemID = @StockItemID;

        UPDATE Syn.StockItemHoldings
        SET QuantityOnHand = @QuantityOnHand,
            BinLocation = @BinLocation,
            LastEditedBy = @SistemaPersonID
        WHERE StockItemID = @StockItemID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


-- Eliminar producto (primero valida, luego borra hijos y despues el producto)
CREATE OR ALTER PROCEDURE Api.usp_Inventario_Eliminar
    @StockItemID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM Syn.StockItems WHERE StockItemID = @StockItemID)
            THROW 50025, 'El producto no existe.', 1;

        IF EXISTS (SELECT 1 FROM Syn.OrderLines WHERE StockItemID = @StockItemID)
            THROW 50026, 'No se puede eliminar: el producto tiene ordenes de venta asociadas.', 1;

        IF EXISTS (SELECT 1 FROM Syn.InvoiceLines WHERE StockItemID = @StockItemID)
            THROW 50027, 'No se puede eliminar: el producto tiene facturas asociadas.', 1;

        IF EXISTS (SELECT 1 FROM Syn.PurchaseOrderLines WHERE StockItemID = @StockItemID)
            THROW 50028, 'No se puede eliminar: el producto tiene ordenes de compra asociadas.', 1;

        IF EXISTS (SELECT 1 FROM Syn.StockItemTransactions WHERE StockItemID = @StockItemID)
            THROW 50029, 'No se puede eliminar: el producto tiene movimientos de inventario asociados.', 1;

        IF EXISTS (SELECT 1 FROM Syn.SpecialDeals WHERE StockItemID = @StockItemID)
            THROW 50030, 'No se puede eliminar: el producto tiene ofertas especiales asociadas.', 1;

        DELETE FROM Syn.StockItemHoldings WHERE StockItemID = @StockItemID;
        DELETE FROM Syn.StockItemStockGroups WHERE StockItemID = @StockItemID;
        DELETE FROM Syn.StockItems WHERE StockItemID = @StockItemID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

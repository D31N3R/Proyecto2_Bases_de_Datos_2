USE WideWorldImporters;
GO

/* ============================================================
   SINÓNIMOS PARA PROVEEDORES
   ============================================================ */
IF OBJECT_ID('Syn.Suppliers', 'SN') IS NOT NULL DROP SYNONYM Syn.Suppliers;
CREATE SYNONYM Syn.Suppliers FOR Purchasing.Suppliers;
GO

IF OBJECT_ID('Syn.SupplierCategories', 'SN') IS NOT NULL DROP SYNONYM Syn.SupplierCategories;
CREATE SYNONYM Syn.SupplierCategories FOR Purchasing.SupplierCategories;
GO

IF OBJECT_ID('Syn.PurchaseOrders', 'SN') IS NOT NULL DROP SYNONYM Syn.PurchaseOrders;
CREATE SYNONYM Syn.PurchaseOrders FOR Purchasing.PurchaseOrders;
GO

IF OBJECT_ID('Syn.SupplierTransactions', 'SN') IS NOT NULL DROP SYNONYM Syn.SupplierTransactions;
CREATE SYNONYM Syn.SupplierTransactions FOR Purchasing.SupplierTransactions;
GO

IF OBJECT_ID('Syn.StockItems', 'SN') IS NOT NULL DROP SYNONYM Syn.StockItems;
CREATE SYNONYM Syn.StockItems FOR Warehouse.StockItems;
GO

CREATE OR ALTER PROCEDURE Api.usp_Proveedores_Categorias
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SupplierCategoryID, SupplierCategoryName
    FROM Syn.SupplierCategories
    ORDER BY SupplierCategoryName;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Proveedores_Listar
    @Nombre NVARCHAR(100) = NULL,
    @SupplierCategoryID INT = NULL,
    @DeliveryMethodID INT = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 50;

    SELECT
        s.SupplierID,
        s.SupplierName AS Nombre,
        sc.SupplierCategoryName AS Categoria,
        dm.DeliveryMethodName AS MetodoEntrega,
        COUNT(*) OVER() AS TotalRegistros
    FROM Syn.Suppliers s
    LEFT JOIN Syn.SupplierCategories sc ON sc.SupplierCategoryID = s.SupplierCategoryID
    LEFT JOIN Syn.DeliveryMethods dm ON dm.DeliveryMethodID = s.DeliveryMethodID
    WHERE (@Nombre IS NULL OR s.SupplierName LIKE '%' + @Nombre + '%')
      AND (@SupplierCategoryID IS NULL OR s.SupplierCategoryID = @SupplierCategoryID)
    ORDER BY s.SupplierName ASC, s.SupplierID ASC
    OFFSET CAST(@Pagina - 1 AS BIGINT) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Proveedores_Detalle
    @SupplierID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        s.SupplierID,
        s.SupplierCategoryID,
        s.DeliveryMethodID,
        s.PrimaryContactPersonID,
        s.AlternateContactPersonID,
        s.DeliveryCityID,
        s.SupplierReference AS CodigoProveedor,
        s.SupplierName AS Nombre,
        sc.SupplierCategoryName AS Categoria,
        pc.FullName AS ContactoPrimario,
        ac.FullName AS ContactoAlterno,
        dm.DeliveryMethodName AS MetodoEntrega,
        city.CityName AS CiudadEntrega,
        s.DeliveryPostalCode AS CodigoPostal,
        s.PhoneNumber AS Telefono,
        s.FaxNumber AS Fax,
        s.WebsiteURL AS SitioWeb,
        s.DeliveryAddressLine1 AS DireccionEntrega1,
        s.DeliveryAddressLine2 AS DireccionEntrega2,
        s.PostalAddressLine1 AS DireccionPostal1,
        s.PostalAddressLine2 AS DireccionPostal2,
        s.DeliveryLocation.Lat AS Latitud,
        s.DeliveryLocation.Long AS Longitud,
        s.BankAccountName AS NombreBanco,
        s.BankAccountNumber AS NumeroCuenta,
        s.PaymentDays AS DiasGraciaPago
    FROM Syn.Suppliers s
    LEFT JOIN Syn.SupplierCategories sc ON sc.SupplierCategoryID = s.SupplierCategoryID
    LEFT JOIN Syn.People pc ON pc.PersonID = s.PrimaryContactPersonID
    LEFT JOIN Syn.People ac ON ac.PersonID = s.AlternateContactPersonID
    LEFT JOIN Syn.DeliveryMethods dm ON dm.DeliveryMethodID = s.DeliveryMethodID
    LEFT JOIN Syn.Cities city ON city.CityID = s.DeliveryCityID
    WHERE s.SupplierID = @SupplierID;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Proveedores_Crear
    @SupplierName NVARCHAR(100),
    @SupplierReference NVARCHAR(20) = NULL,
    @SupplierCategoryID INT,
    @DeliveryMethodID INT = NULL,
    @PrimaryContactPersonID INT,
    @AlternateContactPersonID INT,
    @PaymentDays INT,
    @PhoneNumber NVARCHAR(20),
    @FaxNumber NVARCHAR(20),
    @WebsiteURL NVARCHAR(256),
    @DeliveryAddressLine1 NVARCHAR(60),
    @DeliveryAddressLine2 NVARCHAR(60) = NULL,
    @DeliveryCityID INT,
    @DeliveryPostalCode NVARCHAR(10),
    @PostalAddressLine1 NVARCHAR(60),
    @PostalAddressLine2 NVARCHAR(60) = NULL,
    @Latitud DECIMAL(9,6) = NULL,
    @Longitud DECIMAL(9,6) = NULL,
    @BankAccountName NVARCHAR(50) = NULL,
    @BankAccountNumber NVARCHAR(20) = NULL,
    @NuevoSupplierID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM Syn.Suppliers WHERE SupplierName = @SupplierName)
            THROW 50035, 'Ya existe un proveedor con ese nombre.', 1;

        IF (@Latitud IS NULL AND @Longitud IS NOT NULL)
           OR (@Latitud IS NOT NULL AND @Longitud IS NULL)
            THROW 50036, 'La latitud y la longitud se deben indicar juntas.', 1;

        IF @Latitud NOT BETWEEN -90 AND 90 OR @Longitud NOT BETWEEN -180 AND 180
            THROW 50037, 'La latitud debe estar entre -90 y 90 y la longitud entre -180 y 180.', 1;

        DECLARE @SistemaPersonID INT = (SELECT MIN(PersonID) FROM Syn.People);
        DECLARE @NextID INT = (SELECT ISNULL(MAX(SupplierID), 0) + 1 FROM Syn.Suppliers);

        INSERT INTO Syn.Suppliers (
            SupplierID, SupplierName, SupplierCategoryID,
            PrimaryContactPersonID, AlternateContactPersonID, DeliveryMethodID,
            DeliveryCityID, PostalCityID, SupplierReference,
            BankAccountName, BankAccountNumber, PaymentDays,
            PhoneNumber, FaxNumber, WebsiteURL,
            DeliveryAddressLine1, DeliveryAddressLine2, DeliveryPostalCode, DeliveryLocation,
            PostalAddressLine1, PostalAddressLine2, PostalPostalCode, LastEditedBy
        )
        VALUES (
            @NextID, @SupplierName, @SupplierCategoryID,
            @PrimaryContactPersonID, @AlternateContactPersonID, @DeliveryMethodID,
            @DeliveryCityID, @DeliveryCityID, @SupplierReference,
            @BankAccountName, @BankAccountNumber, @PaymentDays,
            @PhoneNumber, @FaxNumber, @WebsiteURL,
            @DeliveryAddressLine1, @DeliveryAddressLine2, @DeliveryPostalCode,
            CASE WHEN @Latitud IS NULL THEN NULL
                 ELSE geography::Point(@Latitud, @Longitud, 4326) END,
            @PostalAddressLine1, @PostalAddressLine2, @DeliveryPostalCode, @SistemaPersonID
        );

        SET @NuevoSupplierID = @NextID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Proveedores_Modificar
    @SupplierID INT,
    @SupplierName NVARCHAR(100),
    @SupplierReference NVARCHAR(20) = NULL,
    @SupplierCategoryID INT,
    @DeliveryMethodID INT = NULL,
    @PrimaryContactPersonID INT,
    @AlternateContactPersonID INT,
    @PaymentDays INT,
    @PhoneNumber NVARCHAR(20),
    @FaxNumber NVARCHAR(20),
    @WebsiteURL NVARCHAR(256),
    @DeliveryAddressLine1 NVARCHAR(60),
    @DeliveryAddressLine2 NVARCHAR(60) = NULL,
    @DeliveryCityID INT,
    @DeliveryPostalCode NVARCHAR(10),
    @PostalAddressLine1 NVARCHAR(60),
    @PostalAddressLine2 NVARCHAR(60) = NULL,
    @Latitud DECIMAL(9,6) = NULL,
    @Longitud DECIMAL(9,6) = NULL,
    @BankAccountName NVARCHAR(50) = NULL,
    @BankAccountNumber NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM Syn.Suppliers WHERE SupplierID = @SupplierID)
            THROW 50003, 'El proveedor no existe.', 1;

        IF EXISTS (SELECT 1 FROM Syn.Suppliers
                   WHERE SupplierName = @SupplierName AND SupplierID <> @SupplierID)
            THROW 50035, 'Ya existe otro proveedor con ese nombre.', 1;

        IF (@Latitud IS NULL AND @Longitud IS NOT NULL)
           OR (@Latitud IS NOT NULL AND @Longitud IS NULL)
            THROW 50036, 'La latitud y la longitud se deben indicar juntas.', 1;

        IF @Latitud NOT BETWEEN -90 AND 90 OR @Longitud NOT BETWEEN -180 AND 180
            THROW 50037, 'La latitud debe estar entre -90 y 90 y la longitud entre -180 y 180.', 1;

        UPDATE Syn.Suppliers
        SET SupplierName = @SupplierName,
            SupplierReference = @SupplierReference,
            SupplierCategoryID = @SupplierCategoryID,
            DeliveryMethodID = @DeliveryMethodID,
            PrimaryContactPersonID = @PrimaryContactPersonID,
            AlternateContactPersonID = @AlternateContactPersonID,
            PaymentDays = @PaymentDays,
            PhoneNumber = @PhoneNumber,
            FaxNumber = @FaxNumber,
            WebsiteURL = @WebsiteURL,
            DeliveryAddressLine1 = @DeliveryAddressLine1,
            DeliveryAddressLine2 = @DeliveryAddressLine2,
            DeliveryCityID = @DeliveryCityID,
            DeliveryPostalCode = @DeliveryPostalCode,
            DeliveryLocation = CASE WHEN @Latitud IS NULL THEN NULL
                                    ELSE geography::Point(@Latitud, @Longitud, 4326) END,
            PostalAddressLine1 = @PostalAddressLine1,
            PostalAddressLine2 = @PostalAddressLine2,
            BankAccountName = @BankAccountName,
            BankAccountNumber = @BankAccountNumber,
            LastEditedBy = (SELECT MIN(PersonID) FROM Syn.People)
        WHERE SupplierID = @SupplierID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
CREATE OR ALTER PROCEDURE Api.usp_Proveedores_Eliminar
    @SupplierID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM Syn.Suppliers WHERE SupplierID = @SupplierID)
            THROW 50004, 'El proveedor no existe.', 1;

        IF EXISTS (SELECT 1 FROM Syn.PurchaseOrders WHERE SupplierID = @SupplierID)
            THROW 50011, 'No se puede eliminar: el proveedor tiene ordenes de compra asociadas.', 1;

        IF EXISTS (SELECT 1 FROM Syn.SupplierTransactions WHERE SupplierID = @SupplierID)
            THROW 50012, 'No se puede eliminar: el proveedor tiene transacciones asociadas.', 1;

        IF EXISTS (SELECT 1 FROM Syn.StockItems WHERE SupplierID = @SupplierID)
            THROW 50013, 'No se puede eliminar: el proveedor tiene productos asociados.', 1;

        IF EXISTS (SELECT 1 FROM Syn.StockItemTransactions WHERE SupplierID = @SupplierID)
            THROW 50014, 'No se puede eliminar: el proveedor tiene movimientos de inventario asociados.', 1;

        DELETE FROM Syn.Suppliers WHERE SupplierID = @SupplierID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
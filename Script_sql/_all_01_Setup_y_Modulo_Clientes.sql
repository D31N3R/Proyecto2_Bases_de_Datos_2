USE WideWorldImporters;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Syn')
    EXEC('CREATE SCHEMA Syn');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Api')
    EXEC('CREATE SCHEMA Api');
GO
/* ============================================================
   SINÓNIMOS PARA CLIENTES
   ============================================================ */
IF OBJECT_ID('Syn.Customers', 'SN') IS NOT NULL DROP SYNONYM Syn.Customers;
CREATE SYNONYM Syn.Customers FOR Sales.Customers;
GO
 
IF OBJECT_ID ('Syn.CustomerCategories', 'SN') IS NOT NULL DROP SYNONYM Syn.CustomerCategories;
CREATE SYNONYM Syn.CustomerCategories FOR Sales.CustomerCategories;
GO

IF OBJECT_ID ('Syn.BuyingGroups', 'SN') IS NOT NULL DROP SYNONYM Syn.BuyingGroups;
CREATE SYNONYM Syn.BuyingGroups FOR Sales.BuyingGroups;
GO

IF OBJECT_ID ('Syn.People', 'SN') IS NOT NULL DROP SYNONYM Syn.People;
CREATE SYNONYM Syn.People FOR Application.People;
GO

IF OBJECT_ID ('Syn.DeliveryMethods', 'SN') IS NOT NULL DROP SYNONYM Syn.DeliveryMethods;
CREATE SYNONYM Syn.DeliveryMethods FOR Application.DeliveryMethods;
GO

IF OBJECT_ID ('Syn.Cities', 'SN') IS NOT NULL DROP SYNONYM Syn.Cities;
CREATE SYNONYM Syn.Cities FOR Application.Cities;
GO

IF OBJECT_ID ('Syn.CustomerTransactions', 'SN') IS NOT NULL DROP SYNONYM Syn.CustomerTransactions;
CREATE SYNONYM Syn.CustomerTransactions FOR Sales.CustomerTransactions;
GO

IF OBJECT_ID ('Syn.StockItemTransactions', 'SN') IS NOT NULL DROP SYNONYM Syn.StockItemTransactions;
CREATE SYNONYM Syn.StockItemTransactions FOR Warehouse.StockItemTransactions;
GO

IF OBJECT_ID ('Syn.Orders', 'SN') IS NOT NULL DROP SYNONYM Syn.Orders;
CREATE SYNONYM Syn.Orders FOR Sales.Orders;
GO

IF OBJECT_ID ('Syn.Invoices', 'SN') IS NOT NULL DROP SYNONYM Syn.Invoices;
CREATE SYNONYM Syn.Invoices FOR Sales.Invoices;
GO

IF OBJECT_ID ('Syn.SpecialDeals', 'SN') IS NOT NULL DROP SYNONYM Syn.SpecialDeals;
CREATE SYNONYM Syn.SpecialDeals FOR Sales.SpecialDeals;
GO

IF OBJECT_ID ('Syn.StateProvinces', 'SN') IS NOT NULL DROP SYNONYM Syn.StateProvinces;
CREATE SYNONYM Syn.StateProvinces FOR Application.StateProvinces;
GO

CREATE OR ALTER PROCEDURE Api.usp_Clientes_Categorias
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CustomerCategoryID, CustomerCategoryName
    FROM Syn.CustomerCategories
    ORDER BY CustomerCategoryName;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Clientes_Listar
    @Nombre NVARCHAR(100) = NULL,
    @CustomerCategoryID INT = NULL,
    @DeliveryMethodID INT = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 50;

    SELECT
        c.CustomerID,
        c.CustomerName AS Nombre,
        cc.CustomerCategoryName AS Categoria,
        dm.DeliveryMethodName AS MetodoEntrega,
        COUNT(*) OVER() AS TotalRegistros
    FROM Syn.Customers c
    INNER JOIN Syn.CustomerCategories cc ON cc.CustomerCategoryID = c.CustomerCategoryID
    INNER JOIN Syn.DeliveryMethods dm ON dm.DeliveryMethodID = c.DeliveryMethodID
    WHERE (@Nombre IS NULL OR c.CustomerName LIKE '%' + @Nombre + '%')
      AND (@CustomerCategoryID IS NULL OR c.CustomerCategoryID = @CustomerCategoryID)
      AND (@DeliveryMethodID IS NULL OR c.DeliveryMethodID = @DeliveryMethodID)
    ORDER BY c.CustomerName ASC, c.CustomerID ASC
    OFFSET CAST(@Pagina - 1 AS BIGINT) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Clientes_Detalle
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        c.CustomerID,
        c.CustomerCategoryID,
        c.BuyingGroupID,
        c.DeliveryMethodID,
        c.BillToCustomerID,
        c.PrimaryContactPersonID,
        c.AlternateContactPersonID,
        c.DeliveryCityID,
        c.CustomerName AS Nombre,
        cc.CustomerCategoryName AS Categoria,
        bg.BuyingGroupName AS GrupoCompra,
        pc.FullName AS ContactoPrimario,
        ac.FullName AS ContactoAlterno,
        bill.CustomerName AS ClientePorFacturar,
        dm.DeliveryMethodName AS MetodoEntrega,
        city.CityName AS CiudadEntrega,
        c.DeliveryPostalCode AS CodigoPostal,
        c.PhoneNumber AS Telefono,
        c.WebsiteURL AS SitioWeb,
        c.FaxNumber AS Fax,
        c.PaymentDays AS DiasGraciaPago,
        c.DeliveryAddressLine1 AS DireccionEntrega1,
        c.DeliveryAddressLine2 AS DireccionEntrega2,
        c.PostalAddressLine1 AS DireccionPostal1,
        c.PostalAddressLine2 AS DireccionPostal2,
        c.DeliveryLocation.Lat AS Latitud,
        c.DeliveryLocation.Long AS Longitud
    FROM Syn.Customers c
    INNER JOIN Syn.CustomerCategories cc
        ON cc.CustomerCategoryID = c.CustomerCategoryID
    LEFT JOIN Syn.BuyingGroups bg
        ON bg.BuyingGroupID = c.BuyingGroupID
    LEFT JOIN Syn.People pc
        ON pc.PersonID = c.PrimaryContactPersonID
    LEFT JOIN Syn.People ac
        ON ac.PersonID = c.AlternateContactPersonID
    LEFT JOIN Syn.Customers bill
        ON bill.CustomerID = c.BillToCustomerID
    INNER JOIN Syn.DeliveryMethods dm
        ON dm.DeliveryMethodID = c.DeliveryMethodID
    LEFT JOIN Syn.Cities city
        ON city.CityID = c.DeliveryCityID
    WHERE c.CustomerID = @CustomerID;
END
GO
CREATE OR ALTER PROCEDURE Api.usp_Clientes_GruposCompra
AS
BEGIN
    SET NOCOUNT ON;
    SELECT BuyingGroupID, BuyingGroupName
    FROM Syn.BuyingGroups
    ORDER BY BuyingGroupName;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Clientes_ListarSimple
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CustomerID, CustomerName
    FROM Syn.Customers
    ORDER BY CustomerName;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Clientes_Crear
    @CustomerName NVARCHAR(100),
    @CustomerCategoryID INT,
    @BuyingGroupID INT = NULL,
    @DeliveryMethodID INT,
    @BillToCustomerID INT = NULL,
    @PrimaryContactPersonID INT,
    @AlternateContactPersonID INT = NULL,
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
    @NuevoCustomerID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF EXISTS (SELECT 1 FROM Syn.Customers WHERE CustomerName = @CustomerName)
            THROW 50031, 'Ya existe un cliente con ese nombre.', 1;

        IF (@Latitud IS NULL AND @Longitud IS NOT NULL)
           OR (@Latitud IS NOT NULL AND @Longitud IS NULL)
            THROW 50032, 'La latitud y la longitud se deben indicar juntas.', 1;

        IF @Latitud NOT BETWEEN -90 AND 90 OR @Longitud NOT BETWEEN -180 AND 180
            THROW 50033, 'La latitud debe estar entre -90 y 90 y la longitud entre -180 y 180.', 1;

        IF @BillToCustomerID IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM Syn.Customers WHERE CustomerID = @BillToCustomerID)
            THROW 50034, 'El cliente por facturar no existe.', 1;

        DECLARE @SistemaPersonID INT = (SELECT MIN(PersonID) FROM Syn.People);
        DECLARE @NextID INT = (SELECT ISNULL(MAX(CustomerID), 0) + 1 FROM Syn.Customers);

        INSERT INTO Syn.Customers (
            CustomerID, CustomerName, BillToCustomerID, CustomerCategoryID, BuyingGroupID,
            PrimaryContactPersonID, AlternateContactPersonID, DeliveryMethodID,
            DeliveryCityID, PostalCityID, AccountOpenedDate, StandardDiscountPercentage,
            IsStatementSent, IsOnCreditHold, PaymentDays,
            PhoneNumber, FaxNumber, WebsiteURL,
            DeliveryAddressLine1, DeliveryAddressLine2, DeliveryPostalCode, DeliveryLocation,
            PostalAddressLine1, PostalAddressLine2, PostalPostalCode, LastEditedBy
        )
        VALUES (
            @NextID, @CustomerName, ISNULL(@BillToCustomerID, @NextID), @CustomerCategoryID, @BuyingGroupID,
            @PrimaryContactPersonID, @AlternateContactPersonID, @DeliveryMethodID,
            @DeliveryCityID, @DeliveryCityID, CAST(GETDATE() AS DATE), 0,
            0, 0, @PaymentDays,
            @PhoneNumber, @FaxNumber, @WebsiteURL,
            @DeliveryAddressLine1, @DeliveryAddressLine2, @DeliveryPostalCode,
            CASE WHEN @Latitud IS NULL THEN NULL
                 ELSE geography::Point(@Latitud, @Longitud, 4326) END,
            @PostalAddressLine1, @PostalAddressLine2, @DeliveryPostalCode, @SistemaPersonID
        );

        SET @NuevoCustomerID = @NextID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
 
-- ============================================
-- CLIENTES: Modificar
-- ============================================
CREATE OR ALTER PROCEDURE Api.usp_Clientes_Modificar
    @CustomerID INT,
    @CustomerName NVARCHAR(100),
    @CustomerCategoryID INT,
    @BuyingGroupID INT = NULL,
    @DeliveryMethodID INT,
    @BillToCustomerID INT = NULL,
    @PrimaryContactPersonID INT,
    @AlternateContactPersonID INT = NULL,
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
    @Longitud DECIMAL(9,6) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM Syn.Customers WHERE CustomerID = @CustomerID)
            THROW 50001, 'El cliente no existe.', 1;

        IF EXISTS (SELECT 1 FROM Syn.Customers
                   WHERE CustomerName = @CustomerName AND CustomerID <> @CustomerID)
            THROW 50031, 'Ya existe otro cliente con ese nombre.', 1;

        IF (@Latitud IS NULL AND @Longitud IS NOT NULL)
           OR (@Latitud IS NOT NULL AND @Longitud IS NULL)
            THROW 50032, 'La latitud y la longitud se deben indicar juntas.', 1;

        IF @Latitud NOT BETWEEN -90 AND 90 OR @Longitud NOT BETWEEN -180 AND 180
            THROW 50033, 'La latitud debe estar entre -90 y 90 y la longitud entre -180 y 180.', 1;

        IF @BillToCustomerID IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM Syn.Customers WHERE CustomerID = @BillToCustomerID)
            THROW 50034, 'El cliente por facturar no existe.', 1;

        UPDATE Syn.Customers
        SET CustomerName = @CustomerName,
            CustomerCategoryID = @CustomerCategoryID,
            BuyingGroupID = @BuyingGroupID,
            DeliveryMethodID = @DeliveryMethodID,
            BillToCustomerID = ISNULL(@BillToCustomerID, @CustomerID),
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
            LastEditedBy = (SELECT MIN(PersonID) FROM Syn.People)
        WHERE CustomerID = @CustomerID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Clientes_Eliminar
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM Syn.Customers WHERE CustomerID = @CustomerID)
            THROW 50001, 'El cliente no existe.', 1;

        IF EXISTS (SELECT 1 FROM Syn.CustomerTransactions WHERE CustomerID = @CustomerID)
            THROW 50002, 'No se puede eliminar: el cliente tiene transacciones asociadas.', 1;

        IF EXISTS (SELECT 1 FROM Syn.StockItemTransactions WHERE CustomerID = @CustomerID)
            THROW 50003, 'No se puede eliminar: el cliente tiene movimientos de inventario asociados.', 1;

        IF EXISTS (SELECT 1 FROM Syn.Orders WHERE CustomerID = @CustomerID)
            THROW 50004, 'No se puede eliminar: el cliente tiene ordenes asociadas.', 1;

        IF EXISTS (SELECT 1 FROM Syn.Invoices WHERE CustomerID = @CustomerID)
            THROW 50005, 'No se puede eliminar: el cliente tiene facturas asociadas.', 1;

        IF EXISTS (SELECT 1 FROM Syn.Invoices WHERE BillToCustomerID = @CustomerID)
            THROW 50006, 'No se puede eliminar: el cliente aparece como facturador en facturas.', 1;

        IF EXISTS (SELECT 1 FROM Syn.SpecialDeals WHERE CustomerID = @CustomerID)
            THROW 50007, 'No se puede eliminar: el cliente tiene ofertas especiales asociadas.', 1;

        IF EXISTS (SELECT 1 FROM Syn.Customers WHERE BillToCustomerID = @CustomerID AND CustomerID <> @CustomerID)
            THROW 50008, 'No se puede eliminar: otros clientes facturan a este cliente.', 1;
        
        DELETE FROM Syn.Customers WHERE CustomerID = @CustomerID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
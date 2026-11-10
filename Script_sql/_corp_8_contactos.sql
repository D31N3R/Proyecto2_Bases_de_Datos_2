USE WideWorldImporters;
GO

/* Contacto sensible de clientes y proveedores: vive solo en Corp.
   La API usa estos procedimientos para leerlo, guardarlo y borrarlo. */

CREATE OR ALTER PROCEDURE Api.usp_ClientesContacto_Obtener
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PhoneNumber AS Telefono, FaxNumber AS Fax, WebsiteURL AS SitioWeb,
           DeliveryPostalCode AS CodigoPostal,
           DeliveryAddressLine1 AS DireccionEntrega1, DeliveryAddressLine2 AS DireccionEntrega2,
           PostalAddressLine1 AS DireccionPostal1, PostalAddressLine2 AS DireccionPostal2,
           Latitud, Longitud
    FROM dbo.Customers_Contact
    WHERE CustomerID = @CustomerID;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_ClientesContacto_Guardar
    @CustomerID INT,
    @PhoneNumber NVARCHAR(20),
    @FaxNumber NVARCHAR(20),
    @WebsiteURL NVARCHAR(256),
    @DeliveryAddressLine1 NVARCHAR(60),
    @DeliveryAddressLine2 NVARCHAR(60) = NULL,
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

        -- Si el contacto existe se actualiza y si no se inserta.
        -- UPDLOCK + HOLDLOCK evita que dos guardados a la vez inserten dos veces.
        UPDATE dbo.Customers_Contact WITH (UPDLOCK, HOLDLOCK)
        SET PhoneNumber = @PhoneNumber, FaxNumber = @FaxNumber, WebsiteURL = @WebsiteURL,
            DeliveryAddressLine1 = @DeliveryAddressLine1, DeliveryAddressLine2 = @DeliveryAddressLine2,
            DeliveryPostalCode = @DeliveryPostalCode,
            PostalAddressLine1 = @PostalAddressLine1, PostalAddressLine2 = @PostalAddressLine2,
            PostalPostalCode = @DeliveryPostalCode,
            Latitud = @Latitud, Longitud = @Longitud
        WHERE CustomerID = @CustomerID;

        IF @@ROWCOUNT = 0
            INSERT INTO dbo.Customers_Contact (
                CustomerID, PhoneNumber, FaxNumber, WebsiteURL,
                DeliveryAddressLine1, DeliveryAddressLine2, DeliveryPostalCode,
                PostalAddressLine1, PostalAddressLine2, PostalPostalCode, Latitud, Longitud)
            VALUES (
                @CustomerID, @PhoneNumber, @FaxNumber, @WebsiteURL,
                @DeliveryAddressLine1, @DeliveryAddressLine2, @DeliveryPostalCode,
                @PostalAddressLine1, @PostalAddressLine2, @DeliveryPostalCode, @Latitud, @Longitud);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE Api.usp_ClientesContacto_Eliminar
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.Customers_Contact WHERE CustomerID = @CustomerID;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_ProveedoresContacto_Obtener
    @SupplierID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PhoneNumber AS Telefono, FaxNumber AS Fax, WebsiteURL AS SitioWeb,
           DeliveryPostalCode AS CodigoPostal,
           DeliveryAddressLine1 AS DireccionEntrega1, DeliveryAddressLine2 AS DireccionEntrega2,
           PostalAddressLine1 AS DireccionPostal1, PostalAddressLine2 AS DireccionPostal2,
           Latitud, Longitud,
           BankAccountName AS NombreBanco, BankAccountNumber AS NumeroCuenta
    FROM dbo.Suppliers_Contact
    WHERE SupplierID = @SupplierID;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_ProveedoresContacto_Guardar
    @SupplierID INT,
    @PhoneNumber NVARCHAR(20),
    @FaxNumber NVARCHAR(20),
    @WebsiteURL NVARCHAR(256),
    @DeliveryAddressLine1 NVARCHAR(60),
    @DeliveryAddressLine2 NVARCHAR(60) = NULL,
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

        UPDATE dbo.Suppliers_Contact WITH (UPDLOCK, HOLDLOCK)
        SET PhoneNumber = @PhoneNumber, FaxNumber = @FaxNumber, WebsiteURL = @WebsiteURL,
            DeliveryAddressLine1 = @DeliveryAddressLine1, DeliveryAddressLine2 = @DeliveryAddressLine2,
            DeliveryPostalCode = @DeliveryPostalCode,
            PostalAddressLine1 = @PostalAddressLine1, PostalAddressLine2 = @PostalAddressLine2,
            PostalPostalCode = @DeliveryPostalCode,
            Latitud = @Latitud, Longitud = @Longitud,
            BankAccountName = @BankAccountName, BankAccountNumber = @BankAccountNumber
        WHERE SupplierID = @SupplierID;

        IF @@ROWCOUNT = 0
            INSERT INTO dbo.Suppliers_Contact (
                SupplierID, PhoneNumber, FaxNumber, WebsiteURL,
                DeliveryAddressLine1, DeliveryAddressLine2, DeliveryPostalCode,
                PostalAddressLine1, PostalAddressLine2, PostalPostalCode, Latitud, Longitud,
                BankAccountName, BankAccountNumber)
            VALUES (
                @SupplierID, @PhoneNumber, @FaxNumber, @WebsiteURL,
                @DeliveryAddressLine1, @DeliveryAddressLine2, @DeliveryPostalCode,
                @PostalAddressLine1, @PostalAddressLine2, @DeliveryPostalCode, @Latitud, @Longitud,
                @BankAccountName, @BankAccountNumber);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE Api.usp_ProveedoresContacto_Eliminar
    @SupplierID INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.Suppliers_Contact WHERE SupplierID = @SupplierID;
END
GO

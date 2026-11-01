USE WideWorldImporters;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ============================================================
   FRAGMENTACIÓN VERTICAL - CORPORATIVO
   1. Crea tablas de contacto aisladas
   2. Copia datos sensibles
   3. NULLea las columnas en las tablas originales
   4. Re-escribe usp_Clientes_Detalle / usp_Proveedores_Detalle
      para que lean de la unión (esto solo aplica en Corp)
   ============================================================ */

-- ---------- 1. Tablas de contacto aisladas ----------

IF OBJECT_ID('Customers_Contact') IS NULL
CREATE TABLE Customers_Contact (
    CustomerID              INT PRIMARY KEY,
    PhoneNumber             NVARCHAR(20),
    FaxNumber               NVARCHAR(20),
    EmailAddress            NVARCHAR(256),
    WebsiteURL              NVARCHAR(256),
    DeliveryAddressLine1    NVARCHAR(60),
    DeliveryAddressLine2    NVARCHAR(60),
    DeliveryPostalCode      NVARCHAR(10),
    PostalAddressLine1      NVARCHAR(60),
    PostalAddressLine2      NVARCHAR(60),
    PostalPostalCode        NVARCHAR(10),
    Latitud                 DECIMAL(9,6),
    Longitud                DECIMAL(9,6),
    RowGuid                 UNIQUEIDENTIFIER ROWGUIDCOL NOT NULL DEFAULT NEWID()
);

IF OBJECT_ID('Suppliers_Contact') IS NULL
CREATE TABLE Suppliers_Contact (
    SupplierID              INT PRIMARY KEY,
    PhoneNumber             NVARCHAR(20),
    FaxNumber               NVARCHAR(20),
    EmailAddress            NVARCHAR(256),
    WebsiteURL              NVARCHAR(256),
    DeliveryAddressLine1    NVARCHAR(60),
    DeliveryAddressLine2    NVARCHAR(60),
    DeliveryPostalCode      NVARCHAR(10),
    PostalAddressLine1      NVARCHAR(60),
    PostalAddressLine2      NVARCHAR(60),
    PostalPostalCode        NVARCHAR(10),
    Latitud                 DECIMAL(9,6),
    Longitud                DECIMAL(9,6),
    BankAccountName         NVARCHAR(50),
    BankAccountNumber       NVARCHAR(20),
    RowGuid                 UNIQUEIDENTIFIER ROWGUIDCOL NOT NULL DEFAULT NEWID()
);
GO

-- ---------- 2. Copiar datos (idempotente) ----------

IF NOT EXISTS (SELECT 1 FROM Customers_Contact)
BEGIN
    INSERT INTO Customers_Contact (
        CustomerID, PhoneNumber, FaxNumber, WebsiteURL,
        DeliveryAddressLine1, DeliveryAddressLine2, DeliveryPostalCode,
        PostalAddressLine1, PostalAddressLine2, PostalPostalCode,
        Latitud, Longitud
    )
    SELECT
        c.CustomerID, c.PhoneNumber, c.FaxNumber, c.WebsiteURL,
        c.DeliveryAddressLine1, c.DeliveryAddressLine2, c.DeliveryPostalCode,
        c.PostalAddressLine1, c.PostalAddressLine2, c.PostalPostalCode,
        c.DeliveryLocation.Lat, c.DeliveryLocation.Long
    FROM Sales.Customers c
    WHERE NOT EXISTS (SELECT 1 FROM Customers_Contact cc WHERE cc.CustomerID = c.CustomerID);

    PRINT CONCAT('Customers_Contact: ', @@ROWCOUNT, ' filas copiadas');
END
ELSE
    PRINT 'Customers_Contact ya tiene datos, se omite.';
GO

IF NOT EXISTS (SELECT 1 FROM Suppliers_Contact)
BEGIN
    INSERT INTO Suppliers_Contact (
        SupplierID, PhoneNumber, FaxNumber, WebsiteURL,
        DeliveryAddressLine1, DeliveryAddressLine2, DeliveryPostalCode,
        PostalAddressLine1, PostalAddressLine2, PostalPostalCode,
        Latitud, Longitud, BankAccountName, BankAccountNumber
    )
    SELECT
        s.SupplierID, s.PhoneNumber, s.FaxNumber, s.WebsiteURL,
        s.DeliveryAddressLine1, s.DeliveryAddressLine2, s.DeliveryPostalCode,
        s.PostalAddressLine1, s.PostalAddressLine2, s.PostalPostalCode,
        s.DeliveryLocation.Lat, s.DeliveryLocation.Long,
        s.BankAccountName, s.BankAccountNumber
    FROM Purchasing.Suppliers s
    WHERE NOT EXISTS (SELECT 1 FROM Suppliers_Contact sc WHERE sc.SupplierID = s.SupplierID);

    PRINT CONCAT('Suppliers_Contact: ', @@ROWCOUNT, ' filas copiadas');
END
ELSE
    PRINT 'Suppliers_Contact ya tiene datos, se omite.';
GO

-- ---------- 3. "Vaciar" columnas sensibles en Corp ----------
-- Se usa '' (string vacío) en TODAS las columnas sensibles.
-- Motivo: en esta versión del .bak, PhoneNumber, PostalAddressLine1, etc.
-- son NOT NULL. '' funciona tanto en NULL como en NOT NULL, y el frontend
-- lo interpreta como "sin dato" igual que NULL.

ALTER TABLE Sales.Customers DISABLE TRIGGER ALL;
ALTER TABLE Purchasing.Suppliers DISABLE TRIGGER ALL;
GO

UPDATE Sales.Customers
SET PhoneNumber          = '',
    FaxNumber            = '',
    WebsiteURL           = '',
    DeliveryAddressLine1 = '',
    DeliveryAddressLine2 = '',
    DeliveryPostalCode   = '',
    PostalAddressLine1   = '',
    PostalAddressLine2   = '',
    PostalPostalCode     = '',
    DeliveryLocation     = NULL
WHERE PhoneNumber <> ''
   OR DeliveryAddressLine1 <> '';
PRINT CONCAT('Sales.Customers (Corp): ', @@ROWCOUNT, ' filas saneadas');
GO

UPDATE Purchasing.Suppliers
SET PhoneNumber          = '',
    FaxNumber            = '',
    WebsiteURL           = '',
    DeliveryAddressLine1 = '',
    DeliveryAddressLine2 = '',
    DeliveryPostalCode   = '',
    PostalAddressLine1   = '',
    PostalAddressLine2   = '',
    PostalPostalCode     = '',
    DeliveryLocation     = NULL,
    BankAccountName      = '',
    BankAccountNumber    = ''
WHERE PhoneNumber <> ''
   OR DeliveryAddressLine1 <> '';
PRINT CONCAT('Purchasing.Suppliers (Corp): ', @@ROWCOUNT, ' filas saneadas');
GO

ALTER TABLE Sales.Customers ENABLE TRIGGER ALL;
ALTER TABLE Purchasing.Suppliers ENABLE TRIGGER ALL;
GO

-- ---------- 4. Re-escribir usp_Clientes_Detalle solo en Corp ----------
-- Este SP sobreescribe el de _all_02. Es válido porque _corp_20 corre
-- después (orden alfabético 20 > 05).

CREATE OR ALTER PROCEDURE Api.usp_Clientes_Detalle
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        c.CustomerID, c.CustomerCategoryID, c.BuyingGroupID, c.DeliveryMethodID,
        c.BillToCustomerID, c.PrimaryContactPersonID, c.AlternateContactPersonID,
        c.DeliveryCityID,
        c.CustomerName AS Nombre,
        cc.CustomerCategoryName AS Categoria,
        bg.BuyingGroupName AS GrupoCompra,
        pc.FullName AS ContactoPrimario,
        ac.FullName AS ContactoAlterno,
        bill.CustomerName AS ClientePorFacturar,
        dm.DeliveryMethodName AS MetodoEntrega,
        city.CityName AS CiudadEntrega,
        -- Sensibles desde Customers_Contact
        ccnt.DeliveryPostalCode AS CodigoPostal,
        ccnt.PhoneNumber        AS Telefono,
        ccnt.WebsiteURL         AS SitioWeb,
        ccnt.FaxNumber          AS Fax,
        c.PaymentDays           AS DiasGraciaPago,
        ccnt.DeliveryAddressLine1 AS DireccionEntrega1,
        ccnt.DeliveryAddressLine2 AS DireccionEntrega2,
        ccnt.PostalAddressLine1   AS DireccionPostal1,
        ccnt.PostalAddressLine2   AS DireccionPostal2,
        ccnt.Latitud            AS Latitud,
        ccnt.Longitud           AS Longitud
    FROM Syn.Customers c
    INNER JOIN Syn.CustomerCategories cc ON cc.CustomerCategoryID = c.CustomerCategoryID
    LEFT JOIN Syn.BuyingGroups bg  ON bg.BuyingGroupID = c.BuyingGroupID
    LEFT JOIN Syn.People pc        ON pc.PersonID = c.PrimaryContactPersonID
    LEFT JOIN Syn.People ac        ON ac.PersonID = c.AlternateContactPersonID
    LEFT JOIN Syn.Customers bill   ON bill.CustomerID = c.BillToCustomerID
    INNER JOIN Syn.DeliveryMethods dm ON dm.DeliveryMethodID = c.DeliveryMethodID
    LEFT JOIN Syn.Cities city      ON city.CityID = c.DeliveryCityID
    LEFT JOIN Customers_Contact ccnt ON ccnt.CustomerID = c.CustomerID  -- ← JOIN clave
    WHERE c.CustomerID = @CustomerID;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Proveedores_Detalle
    @SupplierID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.SupplierID, s.SupplierCategoryID, s.DeliveryMethodID,
        s.PrimaryContactPersonID, s.AlternateContactPersonID, s.DeliveryCityID,
        s.SupplierReference AS CodigoProveedor,
        s.SupplierName AS Nombre,
        sc.SupplierCategoryName AS Categoria,
        pc.FullName AS ContactoPrimario,
        ac.FullName AS ContactoAlterno,
        dm.DeliveryMethodName AS MetodoEntrega,
        city.CityName AS CiudadEntrega,
        -- Sensibles desde Suppliers_Contact
        sct.DeliveryPostalCode AS CodigoPostal,
        sct.PhoneNumber AS Telefono,
        sct.FaxNumber AS Fax,
        sct.WebsiteURL AS SitioWeb,
        sct.DeliveryAddressLine1 AS DireccionEntrega1,
        sct.DeliveryAddressLine2 AS DireccionEntrega2,
        sct.PostalAddressLine1 AS DireccionPostal1,
        sct.PostalAddressLine2 AS DireccionPostal2,
        sct.Latitud AS Latitud,
        sct.Longitud AS Longitud,
        sct.BankAccountName AS NombreBanco,
        sct.BankAccountNumber AS NumeroCuenta,
        s.PaymentDays AS DiasGraciaPago
    FROM Syn.Suppliers s
    LEFT JOIN Syn.SupplierCategories sc ON sc.SupplierCategoryID = s.SupplierCategoryID
    LEFT JOIN Syn.People pc ON pc.PersonID = s.PrimaryContactPersonID
    LEFT JOIN Syn.People ac ON ac.PersonID = s.AlternateContactPersonID
    LEFT JOIN Syn.DeliveryMethods dm ON dm.DeliveryMethodID = s.DeliveryMethodID
    LEFT JOIN Syn.Cities city ON city.CityID = s.DeliveryCityID
    LEFT JOIN Suppliers_Contact sct ON sct.SupplierID = s.SupplierID  -- ← JOIN clave
    WHERE s.SupplierID = @SupplierID;
END
GO

PRINT 'Módulo sensible + procedimientos Corp actualizados';
GO
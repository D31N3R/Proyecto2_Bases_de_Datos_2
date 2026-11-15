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
    -- Los proveedores se dan de alta SOLO en Corp y se replican a las sucursales (igual que los productos).
    IF ISNULL((SELECT Nodo FROM dbo.NodoConfig), N'') <> N'CORP'
        THROW 50063, 'Los proveedores se administran en el nodo Corporativo; se replican a las sucursales.', 1;

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
        -- Un unico nodo (Corp) asigna los IDs, asi que no hay choques entre sucursales.
        -- UPDLOCK + HOLDLOCK: dos altas simultaneas no toman el mismo ID
        DECLARE @NextID INT = (SELECT ISNULL(MAX(SupplierID), 0) + 1 FROM Syn.Suppliers WITH (UPDLOCK, HOLDLOCK));

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
            '', '', @PaymentDays,
            '', '', '',
            '', '', '', NULL,
            '', '', '', @SistemaPersonID
        );

        SET @NuevoSupplierID = @NextID;

        -- Telefono, direcciones, datos del banco y demas datos sensibles: solo en Corp, en la misma transaccion
        EXEC Api.usp_ProveedoresContacto_Guardar
            @SupplierID = @NextID, @PhoneNumber = @PhoneNumber, @FaxNumber = @FaxNumber, @WebsiteURL = @WebsiteURL,
            @DeliveryAddressLine1 = @DeliveryAddressLine1, @DeliveryAddressLine2 = @DeliveryAddressLine2,
            @DeliveryPostalCode = @DeliveryPostalCode,
            @PostalAddressLine1 = @PostalAddressLine1, @PostalAddressLine2 = @PostalAddressLine2,
            @Latitud = @Latitud, @Longitud = @Longitud,
            @BankAccountName = @BankAccountName, @BankAccountNumber = @BankAccountNumber;

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
    -- Los proveedores se modifican SOLO en Corp y se replican a las sucursales (igual que los productos).
    IF ISNULL((SELECT Nodo FROM dbo.NodoConfig), N'') <> N'CORP'
        THROW 50063, 'Los proveedores se administran en el nodo Corporativo; se replican a las sucursales.', 1;

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
            DeliveryCityID = @DeliveryCityID,
            LastEditedBy = (SELECT MIN(PersonID) FROM Syn.People)
        WHERE SupplierID = @SupplierID;
        -- Telefono, direcciones, datos del banco y demas datos sensibles: solo en Corp, en la misma transaccion
        EXEC Api.usp_ProveedoresContacto_Guardar
            @SupplierID = @SupplierID, @PhoneNumber = @PhoneNumber, @FaxNumber = @FaxNumber, @WebsiteURL = @WebsiteURL,
            @DeliveryAddressLine1 = @DeliveryAddressLine1, @DeliveryAddressLine2 = @DeliveryAddressLine2,
            @DeliveryPostalCode = @DeliveryPostalCode,
            @PostalAddressLine1 = @PostalAddressLine1, @PostalAddressLine2 = @PostalAddressLine2,
            @Latitud = @Latitud, @Longitud = @Longitud,
            @BankAccountName = @BankAccountName, @BankAccountNumber = @BankAccountNumber;

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
    -- Los proveedores se eliminan SOLO en Corp y se replican a las sucursales (igual que los productos).
    IF ISNULL((SELECT Nodo FROM dbo.NodoConfig), N'') <> N'CORP'
        THROW 50063, 'Los proveedores se administran en el nodo Corporativo; se replican a las sucursales.', 1;

    IF NOT EXISTS (SELECT 1 FROM Syn.Suppliers WHERE SupplierID = @SupplierID)
        THROW 50004, 'El proveedor no existe.', 1;

    -- El catalogo de productos es igual en todos los nodos, asi que esto se revisa aqui
    IF EXISTS (SELECT 1 FROM Syn.StockItems WHERE SupplierID = @SupplierID)
        THROW 50013, 'No se puede eliminar: el proveedor tiene productos asociados.', 1;

    -- Las ordenes de compra y transacciones viven en las sucursales (fragmentacion), no en Corp.
    -- Hay que revisarlas alla ANTES de borrar: si no, el DELETE replicado fallaria en la
    -- sucursal y dejaria atascada su replicacion. Va fuera de la transaccion porque una
    -- transaccion con linked servers pide MSDTC.
    DECLARE @sucursales TABLE (Servidor SYSNAME, Etiqueta NVARCHAR(10));
    INSERT @sucursales VALUES (N'sj', N'SJ'), (N'limon', N'Limón');

    DECLARE @dep TABLE (Esquema SYSNAME, Tabla SYSNAME, Columna SYSNAME, Descripcion NVARCHAR(60));
    INSERT @dep VALUES (N'Purchasing', N'PurchaseOrders', N'SupplierID', N'órdenes de compra'),
                       (N'Purchasing', N'SupplierTransactions', N'SupplierID', N'transacciones'),
                       (N'Warehouse', N'StockItemTransactions', N'SupplierID', N'movimientos de inventario');

    DECLARE @srv SYSNAME, @etq NVARCHAR(10), @esq SYSNAME, @tab SYSNAME, @col SYSNAME, @desc NVARCHAR(60);
    DECLARE @sqlDin NVARCHAR(MAX), @cnt INT, @msg NVARCHAR(400);

    DECLARE cur_dep CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.Servidor, s.Etiqueta, t.Esquema, t.Tabla, t.Columna, t.Descripcion
        FROM @sucursales s CROSS JOIN @dep t;
    OPEN cur_dep;
    FETCH NEXT FROM cur_dep INTO @srv, @etq, @esq, @tab, @col, @desc;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @cnt = NULL;
        SET @sqlDin = N'SELECT @n = COUNT(*) FROM ' + QUOTENAME(@srv) + N'.WideWorldImporters.'
                    + QUOTENAME(@esq) + N'.' + QUOTENAME(@tab) + N' WHERE ' + QUOTENAME(@col) + N' = @id';
        BEGIN TRY
            EXEC sp_executesql @sqlDin, N'@id INT, @n INT OUTPUT', @id = @SupplierID, @n = @cnt OUTPUT;
        END TRY
        BEGIN CATCH
            CLOSE cur_dep; DEALLOCATE cur_dep;
            SET @msg = CONCAT(N'No se puede verificar si el proveedor tiene movimientos: la sucursal ', @etq,
                              N' no responde (', ERROR_MESSAGE(), N'). Intente más tarde.');
            THROW 50075, @msg, 1;
        END CATCH

        IF @cnt > 0
        BEGIN
            CLOSE cur_dep; DEALLOCATE cur_dep;
            SET @msg = CONCAT(N'No se puede eliminar: el proveedor tiene ', @desc, N' en la sucursal ', @etq, N'.');
            THROW 50011, @msg, 1;
        END

        FETCH NEXT FROM cur_dep INTO @srv, @etq, @esq, @tab, @col, @desc;
    END
    CLOSE cur_dep; DEALLOCATE cur_dep;

    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE FROM dbo.Suppliers_Contact WHERE SupplierID = @SupplierID;
        DELETE FROM Syn.Suppliers WHERE SupplierID = @SupplierID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
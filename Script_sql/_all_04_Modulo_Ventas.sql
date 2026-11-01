USE WideWorldImporters;
GO

/* ============================================================
   SINÓNIMOS PARA VENTAS
   ============================================================ */

IF OBJECT_ID('Syn.InvoiceLines', 'SN') IS NOT NULL DROP SYNONYM Syn.InvoiceLines;
CREATE SYNONYM Syn.InvoiceLines FOR Sales.InvoiceLines;
GO

/* ============================================================
   PROCEDURES DE VENTAS
   ============================================================ */

-- Listar facturas con filtros acumulativos y paginación
CREATE OR ALTER PROCEDURE Api.usp_Ventas_Listar
    @Nombre NVARCHAR(100) = NULL,
    @DeliveryMethodID INT = NULL,
    @FechaDesde DATE = NULL,
    @FechaHasta DATE = NULL,
    @MontoMin DECIMAL(18,2) = NULL,
    @MontoMax DECIMAL(18,2) = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pagina < 1 SET @Pagina = 1;
    IF @TamanoPagina < 1 SET @TamanoPagina = 50;

    SELECT
        i.InvoiceID AS NumeroFactura,
        i.CustomerID,
        c.CustomerName AS Cliente,
        CONVERT(VARCHAR(10), i.InvoiceDate, 23) AS Fecha,
        dm.DeliveryMethodName AS MetodoEntrega,
        m.Monto,
        COUNT(*) OVER() AS TotalRegistros
    FROM Syn.Invoices i
    INNER JOIN (
        SELECT InvoiceID, SUM(ExtendedPrice) AS Monto
        FROM Syn.InvoiceLines
        GROUP BY InvoiceID
    ) m ON m.InvoiceID = i.InvoiceID
    INNER JOIN Syn.Customers c ON c.CustomerID = i.CustomerID
    INNER JOIN Syn.DeliveryMethods dm ON dm.DeliveryMethodID = i.DeliveryMethodID
    WHERE (@Nombre IS NULL OR c.CustomerName LIKE '%' + @Nombre + '%')
      AND (@DeliveryMethodID IS NULL OR i.DeliveryMethodID = @DeliveryMethodID)
      AND (@FechaDesde IS NULL OR i.InvoiceDate >= @FechaDesde)
      AND (@FechaHasta IS NULL OR i.InvoiceDate <= @FechaHasta)
      AND (@MontoMin IS NULL OR m.Monto >= @MontoMin)
      AND (@MontoMax IS NULL OR m.Monto <= @MontoMax)
    ORDER BY c.CustomerName ASC, i.InvoiceID ASC
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

-- Encabezado de la factura
CREATE OR ALTER PROCEDURE Api.usp_Ventas_Detalle
    @InvoiceID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        i.InvoiceID AS NumeroFactura,
        i.CustomerID,
        c.CustomerName AS Cliente,
        i.DeliveryMethodID,
        dm.DeliveryMethodName AS MetodoEntrega,
        i.CustomerPurchaseOrderNumber AS NumeroOrden,
        i.SalespersonPersonID,
        contacto.FullName AS PersonaContacto,
        vendedor.FullName AS Vendedor,
        CONVERT(VARCHAR(10), i.InvoiceDate, 23) AS Fecha,
        i.DeliveryInstructions AS InstruccionesEntrega
    FROM Syn.Invoices i
    INNER JOIN Syn.Customers c ON c.CustomerID = i.CustomerID
    INNER JOIN Syn.DeliveryMethods dm ON dm.DeliveryMethodID = i.DeliveryMethodID
    LEFT JOIN Syn.People contacto ON contacto.PersonID = i.ContactPersonID
    LEFT JOIN Syn.People vendedor ON vendedor.PersonID = i.SalespersonPersonID
    WHERE i.InvoiceID = @InvoiceID;
END
GO

-- Líneas de la factura
CREATE OR ALTER PROCEDURE Api.usp_Ventas_Lineas
    @InvoiceID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        il.InvoiceLineID,
        il.StockItemID,
        si.StockItemName AS Producto,
        il.Quantity AS Cantidad,
        il.UnitPrice AS PrecioUnitario,
        il.TaxRate AS ImpuestoAplicado,
        il.TaxAmount AS MontoImpuesto,
        il.ExtendedPrice AS TotalLinea
    FROM Syn.InvoiceLines il
    INNER JOIN Syn.StockItems si ON si.StockItemID = il.StockItemID
    WHERE il.InvoiceID = @InvoiceID
    ORDER BY il.InvoiceLineID ASC;
END
GO

/* ============================================================
   CATÁLOGOS PARA EL FORMULARIO DE VENTAS
   ============================================================ */

CREATE OR ALTER PROCEDURE Api.usp_Ventas_Clientes
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CustomerID, CustomerName, DeliveryMethodID
    FROM Syn.Customers
    ORDER BY CustomerName;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Ventas_Vendedores
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PersonID, FullName
    FROM Syn.People
    WHERE IsSalesperson = 1
    ORDER BY FullName;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Ventas_Productos
AS
BEGIN
    SET NOCOUNT ON;
    SELECT StockItemID, StockItemName, UnitPrice
    FROM Syn.StockItems
    ORDER BY StockItemName;
END
GO

/* ============================================================
   CREAR / MODIFICAR VENTAS (no hay eliminar)
   ============================================================ */

-- Uso interno: deja las líneas de la factura como vienen en @Lineas (JSON)
-- No abre transacción propia: la abre quien la llama.
CREATE OR ALTER PROCEDURE Api.usp_Ventas_GuardarLineas
    @InvoiceID INT,
    @Lineas NVARCHAR(MAX),
    @EditorPersonID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Lineas IS NULL OR ISJSON(@Lineas) = 0
        THROW 50041, 'Las líneas de la factura no tienen un formato válido.', 1;

    DECLARE @L TABLE (
        InvoiceLineID INT NULL,
        StockItemID INT NULL,
        Quantity INT NULL,
        UnitPrice DECIMAL(18,2) NULL
    );

    INSERT INTO @L (InvoiceLineID, StockItemID, Quantity, UnitPrice)
    SELECT InvoiceLineID, StockItemID, Quantity, UnitPrice
    FROM OPENJSON(@Lineas)
    WITH (
        InvoiceLineID INT           '$.InvoiceLineID',
        StockItemID   INT           '$.StockItemID',
        Quantity      INT           '$.Quantity',
        UnitPrice     DECIMAL(18,2) '$.UnitPrice'
    );

    IF NOT EXISTS (SELECT 1 FROM @L)
        THROW 50042, 'La factura debe tener al menos una línea.', 1;

    IF EXISTS (SELECT 1 FROM @L WHERE StockItemID IS NULL OR Quantity IS NULL)
        THROW 50043, 'Cada línea debe indicar el producto y la cantidad.', 1;

    IF EXISTS (SELECT 1 FROM @L WHERE Quantity < 1 OR Quantity > 100000)
        THROW 50044, 'La cantidad de cada línea debe estar entre 1 y 100000.', 1;

    IF EXISTS (SELECT 1 FROM @L WHERE UnitPrice < 0)
        THROW 50045, 'El precio unitario no puede ser negativo.', 1;

    IF EXISTS (SELECT 1 FROM @L l
               WHERE NOT EXISTS (SELECT 1 FROM Syn.StockItems si WHERE si.StockItemID = l.StockItemID))
        THROW 50046, 'Alguno de los productos no existe.', 1;

    IF EXISTS (SELECT 1 FROM @L l
               WHERE l.InvoiceLineID IS NOT NULL
                 AND NOT EXISTS (SELECT 1 FROM Syn.InvoiceLines il
                                 WHERE il.InvoiceLineID = l.InvoiceLineID
                                   AND il.InvoiceID = @InvoiceID))
        THROW 50047, 'Alguna de las líneas no pertenece a esta factura.', 1;

    IF EXISTS (SELECT 1 FROM @L WHERE InvoiceLineID IS NOT NULL
               GROUP BY InvoiceLineID HAVING COUNT(*) > 1)
        THROW 50048, 'Una misma línea viene repetida.', 1;

    DECLARE @Calc TABLE (
        InvoiceLineID INT NULL,
        StockItemID INT NOT NULL,
        Description NVARCHAR(100) NOT NULL,
        PackageTypeID INT NOT NULL,
        Quantity INT NOT NULL,
        UnitPrice DECIMAL(18,2) NOT NULL,
        TaxRate DECIMAL(18,3) NOT NULL,
        TaxAmount DECIMAL(18,2) NOT NULL,
        LineProfit DECIMAL(18,2) NOT NULL,
        ExtendedPrice DECIMAL(18,2) NOT NULL
    );

    INSERT INTO @Calc (InvoiceLineID, StockItemID, Description, PackageTypeID, Quantity,
                       UnitPrice, TaxRate, TaxAmount, LineProfit, ExtendedPrice)
    SELECT
        l.InvoiceLineID,
        l.StockItemID,
        si.StockItemName,
        si.UnitPackageID,
        l.Quantity,
        p.Precio,
        si.TaxRate,
        ROUND(l.Quantity * p.Precio * si.TaxRate / 100, 2),
        ROUND(l.Quantity * (p.Precio - ISNULL(h.LastCostPrice, 0)), 2),
        ROUND(l.Quantity * p.Precio, 2) + ROUND(l.Quantity * p.Precio * si.TaxRate / 100, 2)
    FROM @L l
    INNER JOIN Syn.StockItems si ON si.StockItemID = l.StockItemID
    LEFT JOIN Syn.StockItemHoldings h ON h.StockItemID = l.StockItemID
    CROSS APPLY (SELECT ISNULL(l.UnitPrice, si.UnitPrice) AS Precio) p;

    -- Líneas existentes: solo se recalculan las que realmente cambiaron
    UPDATE il
    SET StockItemID   = c.StockItemID,
        Description   = c.Description,
        PackageTypeID = c.PackageTypeID,
        Quantity      = c.Quantity,
        UnitPrice     = c.UnitPrice,
        TaxRate       = c.TaxRate,
        TaxAmount     = c.TaxAmount,
        LineProfit    = c.LineProfit,
        ExtendedPrice = c.ExtendedPrice,
        LastEditedBy  = @EditorPersonID,
        LastEditedWhen = SYSDATETIME()
    FROM Syn.InvoiceLines il
    INNER JOIN @Calc c ON c.InvoiceLineID = il.InvoiceLineID
    WHERE il.InvoiceID = @InvoiceID
      AND (il.StockItemID <> c.StockItemID
           OR il.Quantity <> c.Quantity
           OR ISNULL(il.UnitPrice, -1) <> c.UnitPrice);

    -- Líneas que ya no vienen en la lista
    DELETE il
    FROM Syn.InvoiceLines il
    WHERE il.InvoiceID = @InvoiceID
      AND NOT EXISTS (SELECT 1 FROM @Calc c WHERE c.InvoiceLineID = il.InvoiceLineID);

    -- Líneas nuevas
    DECLARE @BaseLineID INT =
        (SELECT ISNULL(MAX(InvoiceLineID), 0) FROM Syn.InvoiceLines WITH (UPDLOCK, HOLDLOCK));

    INSERT INTO Syn.InvoiceLines (
        InvoiceLineID, InvoiceID, StockItemID, Description, PackageTypeID,
        Quantity, UnitPrice, TaxRate, TaxAmount, LineProfit, ExtendedPrice, LastEditedBy
    )
    SELECT
        @BaseLineID + ROW_NUMBER() OVER (ORDER BY c.StockItemID),
        @InvoiceID, c.StockItemID, c.Description, c.PackageTypeID,
        c.Quantity, c.UnitPrice, c.TaxRate, c.TaxAmount, c.LineProfit, c.ExtendedPrice,
        @EditorPersonID
    FROM @Calc c
    WHERE c.InvoiceLineID IS NULL;

    -- Totales del encabezado (artículos secos y refrigerados)
    UPDATE i
    SET TotalDryItems     = ISNULL(t.Secos, 0),
        TotalChillerItems = ISNULL(t.Frios, 0)
    FROM Syn.Invoices i
    OUTER APPLY (
        SELECT
            SUM(CASE WHEN si.IsChillerStock = 0 THEN il.Quantity END) AS Secos,
            SUM(CASE WHEN si.IsChillerStock = 1 THEN il.Quantity END) AS Frios
        FROM Syn.InvoiceLines il
        INNER JOIN Syn.StockItems si ON si.StockItemID = il.StockItemID
        WHERE il.InvoiceID = i.InvoiceID
    ) t
    WHERE i.InvoiceID = @InvoiceID;
END
GO

-- Crear una venta (encabezado + líneas) en una sola transacción
CREATE OR ALTER PROCEDURE Api.usp_Ventas_Crear
    @CustomerID INT,
    @SalespersonPersonID INT,
    @InvoiceDate DATE,
    @DeliveryMethodID INT = NULL,
    @CustomerPurchaseOrderNumber NVARCHAR(20) = NULL,
    @DeliveryInstructions NVARCHAR(MAX) = NULL,
    @Lineas NVARCHAR(MAX),
    @NuevoInvoiceID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @BillToCustomerID INT, @ContactPersonID INT, @MetodoCliente INT;

        SELECT @BillToCustomerID = BillToCustomerID,
               @ContactPersonID  = PrimaryContactPersonID,
               @MetodoCliente    = DeliveryMethodID
        FROM Syn.Customers
        WHERE CustomerID = @CustomerID;

        IF @BillToCustomerID IS NULL
            THROW 50049, 'El cliente no existe.', 1;

        IF NOT EXISTS (SELECT 1 FROM Syn.People WHERE PersonID = @SalespersonPersonID AND IsSalesperson = 1)
            THROW 50050, 'El vendedor no existe.', 1;

        IF @InvoiceDate IS NULL
            THROW 50051, 'La fecha de la factura es obligatoria.', 1;

        IF @InvoiceDate > CAST(GETDATE() AS DATE)
            THROW 50052, 'La fecha de la factura no puede ser futura.', 1;

        SET @DeliveryMethodID = ISNULL(@DeliveryMethodID, @MetodoCliente);

        IF NOT EXISTS (SELECT 1 FROM Syn.DeliveryMethods WHERE DeliveryMethodID = @DeliveryMethodID)
            THROW 50053, 'El método de entrega no existe.', 1;

        DECLARE @AccountsPersonID INT = ISNULL(
            (SELECT PrimaryContactPersonID FROM Syn.Customers WHERE CustomerID = @BillToCustomerID),
            @ContactPersonID);

        DECLARE @SistemaPersonID INT = (SELECT MIN(PersonID) FROM Syn.People);
        DECLARE @NextID INT =
            (SELECT ISNULL(MAX(InvoiceID), 0) + 1 FROM Syn.Invoices WITH (UPDLOCK, HOLDLOCK));

        INSERT INTO Syn.Invoices (
            InvoiceID, CustomerID, BillToCustomerID, OrderID, DeliveryMethodID,
            ContactPersonID, AccountsPersonID, SalespersonPersonID, PackedByPersonID,
            InvoiceDate, CustomerPurchaseOrderNumber, IsCreditNote,
            DeliveryInstructions, TotalDryItems, TotalChillerItems, LastEditedBy
        )
        VALUES (
            @NextID, @CustomerID, @BillToCustomerID, NULL, @DeliveryMethodID,
            @ContactPersonID, @AccountsPersonID, @SalespersonPersonID, @SalespersonPersonID,
            @InvoiceDate, NULLIF(LTRIM(RTRIM(@CustomerPurchaseOrderNumber)), ''), 0,
            NULLIF(LTRIM(RTRIM(@DeliveryInstructions)), ''), 0, 0, @SistemaPersonID
        );

        EXEC Api.usp_Ventas_GuardarLineas
            @InvoiceID = @NextID,
            @Lineas = @Lineas,
            @EditorPersonID = @SistemaPersonID;

        SET @NuevoInvoiceID = @NextID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- Modificar una venta (encabezado + líneas) en una sola transacción
CREATE OR ALTER PROCEDURE Api.usp_Ventas_Modificar
    @InvoiceID INT,
    @CustomerID INT,
    @SalespersonPersonID INT,
    @InvoiceDate DATE,
    @DeliveryMethodID INT = NULL,
    @CustomerPurchaseOrderNumber NVARCHAR(20) = NULL,
    @DeliveryInstructions NVARCHAR(MAX) = NULL,
    @Lineas NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @ClienteAnterior INT =
            (SELECT CustomerID FROM Syn.Invoices WHERE InvoiceID = @InvoiceID);

        IF @ClienteAnterior IS NULL
            THROW 50054, 'La factura no existe.', 1;

        DECLARE @BillToCustomerID INT, @ContactPersonID INT, @MetodoCliente INT;

        SELECT @BillToCustomerID = BillToCustomerID,
               @ContactPersonID  = PrimaryContactPersonID,
               @MetodoCliente    = DeliveryMethodID
        FROM Syn.Customers
        WHERE CustomerID = @CustomerID;

        IF @BillToCustomerID IS NULL
            THROW 50049, 'El cliente no existe.', 1;

        IF NOT EXISTS (SELECT 1 FROM Syn.People WHERE PersonID = @SalespersonPersonID AND IsSalesperson = 1)
            THROW 50050, 'El vendedor no existe.', 1;

        IF @InvoiceDate IS NULL
            THROW 50051, 'La fecha de la factura es obligatoria.', 1;

        IF @InvoiceDate > CAST(GETDATE() AS DATE)
            THROW 50052, 'La fecha de la factura no puede ser futura.', 1;

        SET @DeliveryMethodID = ISNULL(@DeliveryMethodID, @MetodoCliente);

        IF NOT EXISTS (SELECT 1 FROM Syn.DeliveryMethods WHERE DeliveryMethodID = @DeliveryMethodID)
            THROW 50053, 'El método de entrega no existe.', 1;

        DECLARE @AccountsPersonID INT = ISNULL(
            (SELECT PrimaryContactPersonID FROM Syn.Customers WHERE CustomerID = @BillToCustomerID),
            @ContactPersonID);

        DECLARE @SistemaPersonID INT = (SELECT MIN(PersonID) FROM Syn.People);

        -- Si el cliente no cambió se conservan facturar-a y contactos originales
        UPDATE Syn.Invoices
        SET CustomerID = @CustomerID,
            BillToCustomerID = CASE WHEN @ClienteAnterior = @CustomerID THEN BillToCustomerID ELSE @BillToCustomerID END,
            ContactPersonID  = CASE WHEN @ClienteAnterior = @CustomerID THEN ContactPersonID  ELSE @ContactPersonID END,
            AccountsPersonID = CASE WHEN @ClienteAnterior = @CustomerID THEN AccountsPersonID ELSE @AccountsPersonID END,
            DeliveryMethodID = @DeliveryMethodID,
            SalespersonPersonID = @SalespersonPersonID,
            InvoiceDate = @InvoiceDate,
            CustomerPurchaseOrderNumber = NULLIF(LTRIM(RTRIM(@CustomerPurchaseOrderNumber)), ''),
            DeliveryInstructions = NULLIF(LTRIM(RTRIM(@DeliveryInstructions)), ''),
            LastEditedBy = @SistemaPersonID,
            LastEditedWhen = SYSDATETIME()
        WHERE InvoiceID = @InvoiceID;

        EXEC Api.usp_Ventas_GuardarLineas
            @InvoiceID = @InvoiceID,
            @Lineas = @Lineas,
            @EditorPersonID = @SistemaPersonID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
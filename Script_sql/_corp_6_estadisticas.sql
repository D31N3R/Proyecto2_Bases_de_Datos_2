USE WideWorldImporters;
GO

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

IF OBJECT_ID('Api.usp_Estadisticas_Refrescar', 'P') IS NOT NULL
    DROP PROCEDURE Api.usp_Estadisticas_Refrescar;
GO

CREATE PROCEDURE Api.usp_Estadisticas_Refrescar
AS
BEGIN
    SET NOCOUNT ON;
    TRUNCATE TABLE dbo.Estadisticas_Ventas;

    INSERT INTO dbo.Estadisticas_Ventas (Sucursal, Anio, Mes, TotalFacturas, TotalVentas)
    SELECT 'SJ', r.Anio, r.Mes, r.TotalFacturas, r.TotalVentas
    FROM OPENQUERY([sj], '
        SELECT YEAR(i.InvoiceDate) AS Anio, MONTH(i.InvoiceDate) AS Mes,
               COUNT(DISTINCT i.InvoiceID) AS TotalFacturas,
               SUM(il.ExtendedPrice) AS TotalVentas
        FROM Sales.Invoices i
        JOIN Sales.InvoiceLines il ON il.InvoiceID = i.InvoiceID
        GROUP BY YEAR(i.InvoiceDate), MONTH(i.InvoiceDate)
    ') r;

    INSERT INTO dbo.Estadisticas_Ventas (Sucursal, Anio, Mes, TotalFacturas, TotalVentas)
    SELECT 'LIMON', r.Anio, r.Mes, r.TotalFacturas, r.TotalVentas
    FROM OPENQUERY([limon], '
        SELECT YEAR(i.InvoiceDate) AS Anio, MONTH(i.InvoiceDate) AS Mes,
               COUNT(DISTINCT i.InvoiceID) AS TotalFacturas,
               SUM(il.ExtendedPrice) AS TotalVentas
        FROM Sales.Invoices i
        JOIN Sales.InvoiceLines il ON il.InvoiceID = i.InvoiceID
        GROUP BY YEAR(i.InvoiceDate), MONTH(i.InvoiceDate)
    ') r;
END
GO

IF OBJECT_ID('Api.usp_Estadisticas_Consultar', 'P') IS NOT NULL
    DROP PROCEDURE Api.usp_Estadisticas_Consultar;
GO

CREATE PROCEDURE Api.usp_Estadisticas_Consultar
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
USE WideWorldImporters;
GO

-- Corp no emite facturas: este procedimiento reemplaza al de las sucursales
-- (el de _all_04 no compila en Corp porque Syn.Invoices apunta a Consolidado).
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
    THROW 50060, 'Este nodo no maneja facturas: solo las sucursales (SJ y Limón) las crean.', 1;
END
GO

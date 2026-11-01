USE WideWorldImporters;
GO

/* ============================================================
   CONCURRENCIA - Control optimista para edicion de productos
   Basado en Database System Concepts, 18.6 (Validation-Based
   Protocols): el cliente lee el producto junto con su
   ValidFrom, y al guardar debe enviar ese mismo valor.
   Si alguien mas lo modifico mientras tanto, se rechaza el
   update en vez de sobreescribir en silencio (lost update).
   ============================================================ */

IF OBJECT_ID('Api.usp_Productos_Actualizar', 'P') IS NOT NULL
    DROP PROCEDURE Api.usp_Productos_Actualizar;
GO

CREATE PROCEDURE Api.usp_Productos_Actualizar
    @StockItemID INT,
    @StockItemName NVARCHAR(100),
    @UnitPrice DECIMAL(18,2),
    @ValidFromEsperado DATETIME2,
    @Exito BIT OUTPUT,
    @Mensaje NVARCHAR(200) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Exito = 0;

    DECLARE @ActualLastEdited DATETIME2;

    SELECT @ActualLastEdited = ValidFrom
    FROM Warehouse.StockItems
    WHERE StockItemID = @StockItemID;

    IF @ActualLastEdited IS NULL
    BEGIN
        SET @Mensaje = 'Producto no encontrado';
        RETURN;
    END

    IF @ActualLastEdited <> @ValidFromEsperado
    BEGIN
        SET @Mensaje = 'El producto fue modificado por otro usuario, recargue los datos antes de guardar';
        RETURN;
    END

    UPDATE Warehouse.StockItems
    SET StockItemName = @StockItemName,
        UnitPrice = @UnitPrice
    WHERE StockItemID = @StockItemID
      AND ValidFrom = @ValidFromEsperado;

    IF @@ROWCOUNT = 1
    BEGIN
        SET @Exito = 1;
        SET @Mensaje = 'Actualizado correctamente';
    END
    ELSE
    BEGIN
        SET @Mensaje = 'Conflicto de concurrencia, intente de nuevo';
    END
END
GO

PRINT 'Procedure Api.usp_Productos_Actualizar creado';
GO

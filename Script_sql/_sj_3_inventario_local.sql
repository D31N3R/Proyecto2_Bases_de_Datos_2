USE WideWorldImporters;
GO

/* ============================================================
   INVENTARIO PROPIO DE LA SUCURSAL (San José)
   - Cada sucursal guarda el inventario de TODOS los productos del catalogo.
   - Si faltan filas (porque antes el inventario se fragmentaba por paridad
     del producto), se crean con cantidad 0.
   - Se puede volver a ejecutar sin problema.
   ============================================================ */

INSERT INTO Warehouse.StockItemHoldings (
    StockItemID, QuantityOnHand, BinLocation,
    LastStocktakeQuantity, LastCostPrice,
    ReorderLevel, TargetStockLevel, LastEditedBy
)
SELECT si.StockItemID, 0, N'Sin asignar',
       0, si.UnitPrice,
       0, 0, (SELECT MIN(PersonID) FROM Application.People)
FROM Warehouse.StockItems si
WHERE NOT EXISTS (SELECT 1 FROM Warehouse.StockItemHoldings h WHERE h.StockItemID = si.StockItemID);
PRINT CONCAT('San José - filas de inventario creadas: ', @@ROWCOUNT);
GO

/* Cuando Corp borra un producto, la replicacion lo borra aqui. Como ahora cada producto
   tiene su fila de inventario en la sucursal, la llave foranea debe borrar esa fila en
   cascada; si no, el borrado replicado falla y la replicacion se atasca. */
DECLARE @fk SYSNAME = (
    SELECT TOP 1 fk.name
    FROM sys.foreign_keys fk
    WHERE fk.parent_object_id = OBJECT_ID('Warehouse.StockItemHoldings')
      AND fk.referenced_object_id = OBJECT_ID('Warehouse.StockItems')
      AND fk.delete_referential_action = 0);

IF @fk IS NOT NULL
BEGIN
    DECLARE @cmd NVARCHAR(MAX) = N'ALTER TABLE Warehouse.StockItemHoldings DROP CONSTRAINT ' + QUOTENAME(@fk);
    EXEC (@cmd);
    ALTER TABLE Warehouse.StockItemHoldings
        ADD CONSTRAINT FK_Warehouse_StockItemHoldings_StockItemID_Warehouse_StockItems
        FOREIGN KEY (StockItemID) REFERENCES Warehouse.StockItems (StockItemID) ON DELETE CASCADE;
    PRINT 'Llave foranea de inventario ahora borra en cascada';
END
GO

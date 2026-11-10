USE WideWorldImporters;
GO

/* Sinonimos propios de Corp: los reportes leen el consolidado en lugar de las tablas de las sucursales.
   Los scripts _all_* vuelven a crear estos sinonimos apuntando a las tablas locales (vacias en Corp),
   asi que si se ejecuta un _all_* en Corp a mano, hay que correr este script despues.
   (init-nodes.sh ya ejecuta _corp_6 despues de los _all_*.) */
DROP SYNONYM IF EXISTS Syn.Invoices;
CREATE SYNONYM Syn.Invoices FOR Consolidado.Invoices;
DROP SYNONYM IF EXISTS Syn.InvoiceLines;
CREATE SYNONYM Syn.InvoiceLines FOR Consolidado.InvoiceLines;
DROP SYNONYM IF EXISTS Syn.PurchaseOrders;
CREATE SYNONYM Syn.PurchaseOrders FOR Consolidado.PurchaseOrders;
DROP SYNONYM IF EXISTS Syn.PurchaseOrderLines;
CREATE SYNONYM Syn.PurchaseOrderLines FOR Consolidado.PurchaseOrderLines;
DROP SYNONYM IF EXISTS Syn.StockItemHoldings;
CREATE SYNONYM Syn.StockItemHoldings FOR Consolidado.StockItemHoldings;
GO

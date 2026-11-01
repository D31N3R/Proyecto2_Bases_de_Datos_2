USE WideWorldImporters;
GO

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

PRINT CONCAT('Limón - Sales.Customers sensibles saneados: ', @@ROWCOUNT, ' filas');
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

PRINT CONCAT('Limón - Purchasing.Suppliers sensibles saneados: ', @@ROWCOUNT, ' filas');
GO

ALTER TABLE Sales.Customers ENABLE TRIGGER ALL;
ALTER TABLE Purchasing.Suppliers ENABLE TRIGGER ALL;
GO

PRINT 'Limón: datos sensibles saneados';
GO
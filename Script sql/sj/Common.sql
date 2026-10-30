USE WideWorldImporters;
GO

CREATE OR ALTER PROCEDURE Api.usp_MetodosEntrega_Listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DeliveryMethodID, DeliveryMethodName
    FROM Syn.DeliveryMethods
    ORDER BY DeliveryMethodName;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Ciudades_Listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        c.CityID,
        c.CityName + ', ' + sp.StateProvinceName AS CityName
    FROM Syn.Cities c
    INNER JOIN Syn.StateProvinces sp ON sp.StateProvinceID = c.StateProvinceID
    WHERE c.LatestRecordedPopulation IS NOT NULL
    ORDER BY sp.StateProvinceName, c.CityName;
END
GO

CREATE OR ALTER PROCEDURE Api.usp_Personas_Listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PersonID, FullName
    FROM Syn.People
    WHERE IsEmployee = 0
    ORDER BY FullName;
END
GO
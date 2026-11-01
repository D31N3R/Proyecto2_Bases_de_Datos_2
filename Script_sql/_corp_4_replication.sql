USE master;
GO

/* ============================================================
   REPLICACION - Corp publica Warehouse.StockItems
   Se vuelve su propio distribuidor local y se suscribe por
   push a las publicaciones de SJ y Limon.
   ============================================================ */

DECLARE @pwd NVARCHAR(50) = N'Proy2_Str0ng!Pass';

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'distribution')
BEGIN
    EXEC sp_adddistributor @distributor = @@SERVERNAME, @password = @pwd;
    EXEC sp_adddistributiondb @database = N'distribution', @security_mode = 0,
         @login = N'sa', @password = @pwd;
    PRINT 'Corp - distribuidor local creado';
END
ELSE
    PRINT 'Corp - distribuidor ya existia';
GO

BEGIN TRY
    EXEC sp_adddistpublisher @publisher = @@SERVERNAME,
         @distribution_db = N'distribution', @security_mode = 0,
         @login = N'sa', @password = N'Proy2_Str0ng!Pass',
         @working_directory = N'/var/opt/mssql/ReplData';
    PRINT 'Corp - publisher habilitado';
END TRY
BEGIN CATCH
    PRINT CONCAT('Corp - publisher ya existia: ', ERROR_MESSAGE());
END CATCH
GO

USE WideWorldImporters;
EXEC sp_replicationdboption @dbname = N'WideWorldImporters', @optname = N'publish', @value = N'true';
GO

IF NOT EXISTS (SELECT 1 FROM syspublications WHERE name = N'Pub_Productos_Corp')
BEGIN
    EXEC sp_addpublication @publication = N'Pub_Productos_Corp', @status = N'active',
         @sync_method = N'concurrent', @repl_freq = N'continuous',
         @allow_push = N'true', @allow_pull = N'true', @immediate_sync = N'true', @independent_agent = N'true';

    BEGIN TRY
        EXEC sp_addpublication_snapshot @publication = N'Pub_Productos_Corp', @frequency_type = 1;
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Corp - snapshot agent: ', ERROR_MESSAGE());
    END CATCH

    PRINT 'Corp - publicacion creada';
END
ELSE
    PRINT 'Corp - publicacion ya existia';
GO

IF NOT EXISTS (SELECT 1 FROM sysarticles WHERE name = N'StockItems')
BEGIN
    EXEC sp_addarticle @publication = N'Pub_Productos_Corp', @article = N'StockItems',
         @source_owner = N'Warehouse', @source_object = N'StockItems',
         @destination_table = N'StockItems', @destination_owner = N'Warehouse',
         @type = N'logbased';
    PRINT 'Corp - articulo StockItems agregado';
END
ELSE
    PRINT 'Corp - articulo ya existia';
GO

BEGIN TRY
    EXEC sp_addsubscription @publication = N'Pub_Productos_Corp', @subscriber = N'sj',
         @destination_db = N'WideWorldImporters', @subscription_type = N'Push',
         @sync_type = N'automatic';
    EXEC sp_addpushsubscription_agent @publication = N'Pub_Productos_Corp', @subscriber = N'sj',
         @subscriber_db = N'WideWorldImporters', @subscriber_security_mode = 0,
         @subscriber_login = N'sa',

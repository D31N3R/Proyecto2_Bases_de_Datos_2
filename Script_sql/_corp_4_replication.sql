USE master;
GO

/* ============================================================
   REPLICACION - Corp publica el catalogo: productos, clientes y proveedores
   Corp es su propio distribuidor local y se suscribe por push
   a SJ y Limon (hostnames de la red docker: sj, limon).

   Los suscriptores ya tienen estas tablas idénticas (vienen del .bak),
   por eso: @pre_creation_cmd = none y sync_type = replication support only.
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
        EXEC sp_addpublication_snapshot @publication = N'Pub_Productos_Corp', @frequency_type = 1,
             @publisher_security_mode = 0, @publisher_login = N'sa',
             @publisher_password = N'Proy2_Str0ng!Pass';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Corp - snapshot agent: ', ERROR_MESSAGE());
    END CATCH

    PRINT 'Corp - publicacion creada';
END
ELSE
    PRINT 'Corp - publicacion ya existia';
GO

-- Catalogo: productos y sus tablas relacionadas, clientes y proveedores.
-- El inventario por sucursal (StockItemHoldings) NO se replica. Los datos sensibles de clientes y
-- proveedores tampoco viajan: en Corp estas tablas ya estan saneadas y el contacto vive aparte.
DECLARE @art TABLE (Esquema SYSNAME, Tabla SYSNAME);
INSERT @art VALUES (N'Warehouse', N'StockItems'),
                   (N'Warehouse', N'StockItemStockGroups'),
                   (N'Warehouse', N'StockGroups'),
                   (N'Warehouse', N'Colors'),
                   (N'Warehouse', N'PackageTypes'),
                   (N'Sales', N'Customers'),
                   (N'Purchasing', N'Suppliers');
DECLARE @e SYSNAME, @t SYSNAME;
DECLARE ca CURSOR LOCAL FAST_FORWARD FOR SELECT Esquema, Tabla FROM @art;
OPEN ca; FETCH NEXT FROM ca INTO @e, @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sysarticles WHERE name = @t)
    BEGIN
        EXEC sp_addarticle @publication = N'Pub_Productos_Corp', @article = @t,
             @source_owner = @e, @source_object = @t,
             @destination_table = @t, @destination_owner = @e,
             @type = N'logbased', @pre_creation_cmd = N'none';
        -- La columna geography (DeliveryLocation) no se puede replicar con procedimientos personalizados
        -- (error 206: "image is incompatible with geography") y ademas es dato sensible: no viaja a las sucursales.
        IF @t IN (N'Customers', N'Suppliers')
            EXEC sp_articlecolumn @publication = N'Pub_Productos_Corp', @article = @t,
                 @column = N'DeliveryLocation', @operation = N'drop',
                 @force_invalidate_snapshot = 1, @force_reinit_subscription = 1;
        PRINT CONCAT('Corp - articulo ', @t, ' agregado');
    END
    ELSE
        PRINT CONCAT('Corp - articulo ', @t, ' ya existia');
    FETCH NEXT FROM ca INTO @e, @t;
END
CLOSE ca; DEALLOCATE ca;
GO

-- ---------- Suscripcion SJ ----------
IF NOT EXISTS (SELECT 1 FROM syssubscriptions WHERE srvname = N'sj')
BEGIN
    BEGIN TRY
        EXEC sp_addsubscription @publication = N'Pub_Productos_Corp', @subscriber = N'sj',
             @destination_db = N'WideWorldImporters', @subscription_type = N'Push',
             @sync_type = N'replication support only';
        EXEC sp_addpushsubscription_agent @publication = N'Pub_Productos_Corp', @subscriber = N'sj',
             @subscriber_db = N'WideWorldImporters', @subscriber_security_mode = 0,
             @subscriber_login = N'sa', @subscriber_password = N'Proy2_Str0ng!Pass',
             @frequency_type = 64;
        PRINT 'Corp - suscripcion SJ creada';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Corp - ERROR suscripcion SJ: ', ERROR_MESSAGE());
    END CATCH
END
ELSE
    PRINT 'Corp - suscripcion SJ ya existia';
GO

-- ---------- Suscripcion Limon ----------
IF NOT EXISTS (SELECT 1 FROM syssubscriptions WHERE srvname = N'limon')
BEGIN
    BEGIN TRY
        EXEC sp_addsubscription @publication = N'Pub_Productos_Corp', @subscriber = N'limon',
             @destination_db = N'WideWorldImporters', @subscription_type = N'Push',
             @sync_type = N'replication support only';
        EXEC sp_addpushsubscription_agent @publication = N'Pub_Productos_Corp', @subscriber = N'limon',
             @subscriber_db = N'WideWorldImporters', @subscriber_security_mode = 0,
             @subscriber_login = N'sa', @subscriber_password = N'Proy2_Str0ng!Pass',
             @frequency_type = 64;
        PRINT 'Corp - suscripcion Limon creada';
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Corp - ERROR suscripcion Limon: ', ERROR_MESSAGE());
    END CATCH
END
ELSE
    PRINT 'Corp - suscripcion Limon ya existia';
GO

PRINT 'Corp - replicacion configurada';
GO
-- Desactivar triggers DDL de replicacion: WWI tiene tablas memory-optimized,
-- incompatibles con triggers DDL a nivel de base de datos. No se necesita
-- rastrear cambios de esquema, solo de datos.
IF EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'tr_MStran_altertable' AND parent_class_desc = 'DATABASE')
BEGIN
    DISABLE TRIGGER tr_MStran_altertable ON DATABASE;
    DISABLE TRIGGER tr_MStran_alterview ON DATABASE;
    DISABLE TRIGGER tr_MStran_alterschemaonly ON DATABASE;
    DISABLE TRIGGER tr_MStran_altertrigger ON DATABASE;
    DISABLE TRIGGER tr_MStran_droptable ON DATABASE;
    PRINT 'Corp: triggers DDL de replicacion desactivados (incompatibles con memory-optimized tables)';
END
GO
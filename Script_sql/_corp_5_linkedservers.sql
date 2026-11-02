USE master;
GO

/* ============================================================
   VISTAS MATERIALIZADAS - Prerequisito: linked servers
   'sj' y 'limon' ya existen en sys.servers porque la replicacion
   los registro como suscriptores. No se borran, solo se les
   agrega el login y las opciones necesarias para usarlos con
   OPENQUERY.
   ============================================================ */

IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = 'sj')
    EXEC sp_addlinkedserver @server = N'sj', @srvproduct = N'SQL Server';
GO

IF EXISTS (SELECT 1 FROM sys.linked_logins ll JOIN sys.servers s ON ll.server_id = s.server_id WHERE s.name = 'sj' AND ll.remote_name = 'sa')
    EXEC sp_droplinkedsrvlogin @rmtsrvname = N'sj', @locallogin = NULL;
EXEC sp_addlinkedsrvlogin @rmtsrvname = N'sj', @useself = N'FALSE',
     @locallogin = NULL, @rmtuser = N'sa', @rmtpassword = N'Proy2_Str0ng!Pass';
EXEC sp_serveroption N'sj', 'rpc', 'true';
EXEC sp_serveroption N'sj', 'rpc out', 'true';
EXEC sp_serveroption N'sj', 'data access', 'true';
GO

IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = 'limon')
    EXEC sp_addlinkedserver @server = N'limon', @srvproduct = N'SQL Server';
GO

IF EXISTS (SELECT 1 FROM sys.linked_logins ll JOIN sys.servers s ON ll.server_id = s.server_id WHERE s.name = 'limon' AND ll.remote_name = 'sa')
    EXEC sp_droplinkedsrvlogin @rmtsrvname = N'limon', @locallogin = NULL;
EXEC sp_addlinkedsrvlogin @rmtsrvname = N'limon', @useself = N'FALSE',
     @locallogin = NULL, @rmtuser = N'sa', @rmtpassword = N'Proy2_Str0ng!Pass';
EXEC sp_serveroption N'limon', 'rpc', 'true';
EXEC sp_serveroption N'limon', 'rpc out', 'true';
EXEC sp_serveroption N'limon', 'data access', 'true';
GO

PRINT 'Corp: linked servers a sj y limon configurados';
GO
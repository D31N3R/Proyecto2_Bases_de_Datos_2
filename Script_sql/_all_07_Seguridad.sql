/* ============================================================
   SEGURIDAD: usuarios y roles de SQL Server para la aplicacion

   La aplicacion tiene 2 roles (Administrador y Corporativo). Para que el rol se
   respete tambien en la BASE DE DATOS (no solo en la API), cada rol se conecta
   con su propio usuario de SQL Server y solo puede ejecutar procedimientos:

     rol de la aplicacion   login        rol de BD            puede
     --------------------   ----------   ------------------   -----------------------------------
     Administrador          app_admin    rol_administrador    EXECUTE sobre los procedimientos del esquema Api
     Corporativo            app_corp     rol_corporativo      EXECUTE solo sobre los reportes (Api.usp_Estadisticas_*)
     (login de la app)      app_auth     -                    EXECUTE dbo.usp_Users_Login (solo en Corp)
     (refresco de Corp)     app_refresh  db_owner (solo Corp) refrescar el consolidado (recrea tablas)

   Nadie, salvo sa, tiene permiso directo sobre las tablas: los procedimientos acceden a
   ellas por "encadenamiento de propiedad" (procedimientos, sinonimos y tablas son de dbo).

   Para usarlo: ejecutar este script en los 3 nodos y poner USAR_USUARIOS_BD=true en el .env
   de la API, con las contrasenas DB_PASS_ADMIN, DB_PASS_CORP, DB_PASS_AUTH y DB_PASS_REFRESH.
   Cambiar las contrasenas de abajo antes de usarlo fuera de clase.
   Se puede volver a ejecutar sin problema.
   Lo que depende de objetos que solo existen en Corp (login de usuarios, consolidado)
   esta en _corp_9_seguridad.sql, que init-nodes.sh ejecuta despues.
   ============================================================ */

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_admin')
    CREATE LOGIN app_admin WITH PASSWORD = 'Proy2_Admin!2026', CHECK_POLICY = OFF;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_corp')
    CREATE LOGIN app_corp WITH PASSWORD = 'Proy2_Corp!2026', CHECK_POLICY = OFF;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_auth')
    CREATE LOGIN app_auth WITH PASSWORD = 'Proy2_Auth!2026', CHECK_POLICY = OFF;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_refresh')
    CREATE LOGIN app_refresh WITH PASSWORD = 'Proy2_Refresh!2026', CHECK_POLICY = OFF;
GO

USE WideWorldImporters;
GO

IF DATABASE_PRINCIPAL_ID('app_admin') IS NULL   CREATE USER app_admin   FOR LOGIN app_admin;
IF DATABASE_PRINCIPAL_ID('app_corp') IS NULL    CREATE USER app_corp    FOR LOGIN app_corp;
IF DATABASE_PRINCIPAL_ID('app_auth') IS NULL    CREATE USER app_auth    FOR LOGIN app_auth;
IF DATABASE_PRINCIPAL_ID('app_refresh') IS NULL CREATE USER app_refresh FOR LOGIN app_refresh;

IF DATABASE_PRINCIPAL_ID('rol_administrador') IS NULL CREATE ROLE rol_administrador;
IF DATABASE_PRINCIPAL_ID('rol_corporativo') IS NULL   CREATE ROLE rol_corporativo;
GO

ALTER ROLE rol_administrador ADD MEMBER app_admin;
ALTER ROLE rol_corporativo   ADD MEMBER app_corp;
GO

-- Administrador: ejecuta los procedimientos de la aplicacion
GRANT EXECUTE ON SCHEMA::Api TO rol_administrador;

-- Corporativo: solo reportes, mas los 3 listados que usan los filtros de sus estadisticas
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'GRANT EXECUTE ON Api.' + QUOTENAME(name) + N' TO rol_corporativo;' + CHAR(10)
FROM sys.procedures
WHERE schema_id = SCHEMA_ID('Api')
  AND (name LIKE N'usp[_]Estadisticas[_]%'
       OR name IN (N'usp_Inventario_Grupos', N'usp_Proveedores_Listar', N'usp_Clientes_Categorias'));
EXEC sys.sp_executesql @sql;
GO

-- El Administrador no refresca el consolidado (lo hace el Corporativo)
IF OBJECT_ID('Api.usp_Estadisticas_Refrescar', 'P') IS NOT NULL
    DENY EXECUTE ON Api.usp_Estadisticas_Refrescar TO rol_administrador;
GO

-- Ningun rol toca las tablas directamente
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Sales      TO rol_administrador, rol_corporativo;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Purchasing TO rol_administrador, rol_corporativo;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Warehouse  TO rol_administrador, rol_corporativo;
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::Application TO rol_administrador, rol_corporativo;
GO

USE WideWorldImporters;
GO

/* ============================================================
   SEGURIDAD - parte de Corp (se ejecuta despues de _all_07 y de los demas _corp_*)

   Aqui existen ya el procedimiento de login, la llave de las contrasenas y el consolidado,
   por eso los permisos que dependen de ellos van en este script.
   Se puede volver a ejecutar sin problema.
   ============================================================ */

-- Corporativo: reportes de Corp (usp_Estadisticas_Consultar y Refrescar nacen en _corp_6)
DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'GRANT EXECUTE ON Api.' + QUOTENAME(name) + N' TO rol_corporativo;' + CHAR(10)
FROM sys.procedures
WHERE schema_id = SCHEMA_ID('Api')
  AND (name LIKE N'usp[_]Estadisticas[_]%'
       OR name IN (N'usp_Inventario_Grupos', N'usp_Proveedores_Listar', N'usp_Clientes_Categorias'));
EXEC sys.sp_executesql @sql;
GO

-- El Administrador no refresca el consolidado
IF OBJECT_ID('Api.usp_Estadisticas_Refrescar', 'P') IS NOT NULL
    DENY EXECUTE ON Api.usp_Estadisticas_Refrescar TO rol_administrador;
GO

-- Login de la aplicacion: ejecuta dbo.usp_Users_Login, que abre la llave simetrica de las contrasenas
IF OBJECT_ID('dbo.usp_Users_Login', 'P') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.usp_Users_Login TO app_auth;
    GRANT VIEW DEFINITION ON SYMMETRIC KEY::SK_Users TO app_auth;
    GRANT CONTROL ON CERTIFICATE::Cert_Users TO app_auth;
END
GO

-- Cuenta de servicio del refresco del consolidado: recrea tablas del esquema Consolidado
IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Consolidado')
    ALTER ROLE db_owner ADD MEMBER app_refresh;
GO

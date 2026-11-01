USE WideWorldImporters;
GO

/* ============================================================
   TABLA DE USUARIOS (solo Corp)
   Password almacenada como HASHBYTES SHA2_256 + salt aleatorio
   Esta es la forma correcta en SQL Server: no se "encripta" la
   contraseña (reversible), se hashea (irreversible) con salt único
   por usuario para evitar rainbow tables.
   ============================================================ */

IF OBJECT_ID('Users') IS NULL
CREATE TABLE Users (
    iduser        INT IDENTITY(1,1) PRIMARY KEY,
    username      NVARCHAR(50)  NOT NULL UNIQUE,
    password_hash VARBINARY(32) NOT NULL,
    password_salt VARBINARY(16) NOT NULL,
    fullname      NVARCHAR(100) NOT NULL,
    email         NVARCHAR(256) NULL,
    active        BIT           NOT NULL DEFAULT 1,
    rol           NVARCHAR(20)  NOT NULL CHECK (rol IN ('Administrador', 'Corporativo')),
    sucursal      NVARCHAR(20)  NULL     CHECK (sucursal IN ('SJ', 'Limón')),
    hiredate      DATE          NULL,
    created_at    DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
    last_login    DATETIME2     NULL
);
GO

/* ------------------------------------------------------------
   Validación: un Administrador debe tener sucursal asignada,
   un Corporativo NO debe tener sucursal.
   ------------------------------------------------------------ */
IF OBJECT_ID('TR_Users_ValidarSucursal', 'TR') IS NOT NULL
    DROP TRIGGER TR_Users_ValidarSucursal;
GO

CREATE TRIGGER TR_Users_ValidarSucursal
ON Users
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1 FROM inserted
        WHERE rol = 'Administrador' AND sucursal IS NULL
    )
    BEGIN
        THROW 51002, 'Un Administrador debe tener una sucursal asignada (SJ o Limón).', 1;
    END

    IF EXISTS (
        SELECT 1 FROM inserted
        WHERE rol = 'Corporativo' AND sucursal IS NOT NULL
    )
    BEGIN
        THROW 51003, 'Un usuario Corporativo no debe tener sucursal asignada.', 1;
    END
END
GO

/* ============================================================
   SP: crear usuario
   Genera salt aleatorio, hashea password, inserta.
   ============================================================ */

CREATE OR ALTER PROCEDURE usp_Users_Crear
    @username NVARCHAR(50),
    @password NVARCHAR(100),
    @fullname NVARCHAR(100),
    @email    NVARCHAR(256) = NULL,
    @rol      NVARCHAR(20),
    @sucursal NVARCHAR(20) = NULL,
    @hiredate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM Users WHERE username = @username)
        THROW 51001, 'El nombre de usuario ya existe.', 1;

    DECLARE @salt VARBINARY(16) = CRYPT_GEN_RANDOM(16);
    DECLARE @hash VARBINARY(32) = HASHBYTES('SHA2_256',
        @salt + CAST(@password AS VARBINARY(MAX)));

    INSERT INTO Users
        (username, password_hash, password_salt, fullname, email, rol, sucursal, hiredate)
    VALUES
        (@username, @hash, @salt, @fullname, @email, @rol, @sucursal, @hiredate);
END
GO

/* ============================================================
   SP: login
   Recalcula el hash con el salt guardado y lo compara.
   Devuelve una fila con los datos necesarios para que el
   backend genere el JWT: iduser, fullname, rol, sucursal.
   ============================================================ */

CREATE OR ALTER PROCEDURE usp_Users_Login
    @username NVARCHAR(50),
    @password NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @salt VARBINARY(16);
    DECLARE @hashGuardado VARBINARY(32);
    DECLARE @iduser INT;

    SELECT @salt = password_salt,
           @hashGuardado = password_hash,
           @iduser = iduser
    FROM Users
    WHERE username = @username AND active = 1;

    -- Usuario no existe o está inactivo
    IF @salt IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS valido, NULL AS iduser, NULL AS fullname,
               NULL AS rol, NULL AS sucursal, 'Usuario o contraseña incorrectos' AS mensaje;
        RETURN;
    END

    DECLARE @hashIngresado VARBINARY(32) = HASHBYTES('SHA2_256',
        @salt + CAST(@password AS VARBINARY(MAX)));

    IF @hashIngresado = @hashGuardado
    BEGIN
        UPDATE Users SET last_login = SYSDATETIME() WHERE iduser = @iduser;

        SELECT CAST(1 AS BIT) AS valido, iduser, fullname, rol, sucursal,
               'Login exitoso' AS mensaje
        FROM Users WHERE iduser = @iduser;
    END
    ELSE
    BEGIN
        SELECT CAST(0 AS BIT) AS valido, NULL AS iduser, NULL AS fullname,
               NULL AS rol, NULL AS sucursal, 'Usuario o contraseña incorrectos' AS mensaje;
    END
END
GO

/* ============================================================
   SP: cambiar contraseña
   ============================================================ */

CREATE OR ALTER PROCEDURE usp_Users_CambiarPassword
    @username NVARCHAR(50),
    @passwordActual NVARCHAR(100),
    @passwordNueva NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    -- Verificar que la contraseña actual es correcta (reutiliza la lógica del login)
    DECLARE @salt VARBINARY(16), @hashGuardado VARBINARY(32);

    SELECT @salt = password_salt, @hashGuardado = password_hash
    FROM Users WHERE username = @username AND active = 1;

    IF @salt IS NULL
        THROW 51004, 'Usuario no existe o está inactivo.', 1;

    DECLARE @hashActual VARBINARY(32) = HASHBYTES('SHA2_256',
        @salt + CAST(@passwordActual AS VARBINARY(MAX)));

    IF @hashActual <> @hashGuardado
        THROW 51005, 'La contraseña actual es incorrecta.', 1;

    -- Generar nuevo salt y hash
    DECLARE @saltNuevo VARBINARY(16) = CRYPT_GEN_RANDOM(16);
    DECLARE @hashNuevo VARBINARY(32) = HASHBYTES('SHA2_256',
        @saltNuevo + CAST(@passwordNueva AS VARBINARY(MAX)));

    UPDATE Users
    SET password_hash = @hashNuevo, password_salt = @saltNuevo
    WHERE username = @username;
END
GO

/* ============================================================
   SP: desactivar usuario
   ============================================================ */

CREATE OR ALTER PROCEDURE usp_Users_Desactivar
    @username NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Users WHERE username = @username)
        THROW 51006, 'Usuario no existe.', 1;

    UPDATE Users SET active = 0 WHERE username = @username;
END
GO

/* ============================================================
   SP: listar usuarios (para el dashboard Corporativo)
   ============================================================ */

CREATE OR ALTER PROCEDURE usp_Users_Listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT iduser, username, fullname, email, active, rol, sucursal,
           hiredate, created_at, last_login
    FROM Users
    ORDER BY rol, sucursal, username;
END
GO

/* ============================================================
   SEED: usuarios iniciales
   Solo si la tabla está vacía (para no duplicar al re-ejecutar)
   ============================================================ */

IF NOT EXISTS (SELECT 1 FROM Users)
BEGIN
    EXEC usp_Users_Crear 'admin_sj',    'Admin123!', 'Admin San José',      'admin.sj@wwi.com',    'Administrador', 'SJ',    '2026-01-15';
    EXEC usp_Users_Crear 'admin_limon', 'Admin123!', 'Admin Limón',         'admin.limon@wwi.com', 'Administrador', 'Limón', '2026-01-15';
    EXEC usp_Users_Crear 'corp',        'Corp123!',  'Usuario Corporativo', 'corp@wwi.com',        'Corporativo',   NULL,    '2026-01-15';
    PRINT 'Usuarios iniciales creados: admin_sj, admin_limon, corp';
END
ELSE
    PRINT 'La tabla Users ya tiene datos, se omite el seed.';
GO

PRINT 'Módulo Users inicializado en Corp';
GO
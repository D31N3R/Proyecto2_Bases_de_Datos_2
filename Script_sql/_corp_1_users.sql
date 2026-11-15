USE WideWorldImporters;
GO

/* ============================================================
   TABLA DE USUARIOS (solo Corp)

   La columna de contraseña (password_enc) esta ENCRIPTADA con los
   servicios de cifrado nativos de SQL Server:

     clave maestra de la base (DMK)
        -> certificado (Cert_Users)
           -> llave simetrica AES-256 (SK_Users)

   Lo que se cifra es el hash SHA2_256 de (sal + contraseña): la
   contraseña nunca se guarda en claro ni de forma reversible, y el
   hash guardado ademas esta cifrado. Se usa el username como
   "authenticator", asi un valor cifrado no sirve en otra fila.
   ============================================================ */

-- Servicios de cifrado: clave maestra -> certificado -> llave simetrica AES-256
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Proy2_Master!Key_2026';
GO

IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'Cert_Users')
    CREATE CERTIFICATE Cert_Users WITH SUBJECT = 'Cifrado de contrasenas de usuarios';
GO

IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = 'SK_Users')
    CREATE SYMMETRIC KEY SK_Users
        WITH ALGORITHM = AES_256
        ENCRYPTION BY CERTIFICATE Cert_Users;
GO

-- Version anterior (hash sin cifrar): se recrea la tabla y se vuelven a sembrar los usuarios
IF OBJECT_ID('Users') IS NOT NULL AND COL_LENGTH('Users', 'password_enc') IS NULL
    DROP TABLE Users;
GO

IF OBJECT_ID('Users') IS NULL
CREATE TABLE Users (
    iduser        INT IDENTITY(1,1) PRIMARY KEY,
    username      NVARCHAR(50)  NOT NULL UNIQUE,
    password_enc  VARBINARY(MAX) NOT NULL,   -- hash de la contraseña, cifrado con AES-256
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

    IF NOT EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'SK_Users')
        OPEN SYMMETRIC KEY SK_Users DECRYPTION BY CERTIFICATE Cert_Users;

    INSERT INTO Users
        (username, password_enc, password_salt, fullname, email, rol, sucursal, hiredate)
    VALUES
        (@username,
         ENCRYPTBYKEY(KEY_GUID('SK_Users'), @hash, 1, CAST(@username AS NVARCHAR(50))),
         @salt, @fullname, @email, @rol, @sucursal, @hiredate);

    IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'SK_Users')
        CLOSE SYMMETRIC KEY SK_Users;
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
    DECLARE @cifrado VARBINARY(MAX);
    DECLARE @usuarioBD NVARCHAR(50);
    DECLARE @iduser INT;

    SELECT @salt = password_salt,
           @cifrado = password_enc,
           @usuarioBD = username,
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

    -- Descifrar el hash guardado (el authenticator es el username tal como esta en la tabla)
    IF NOT EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'SK_Users')
        OPEN SYMMETRIC KEY SK_Users DECRYPTION BY CERTIFICATE Cert_Users;
    DECLARE @hashGuardado VARBINARY(32) =
        CAST(DECRYPTBYKEY(@cifrado, 1, CAST(@usuarioBD AS NVARCHAR(50))) AS VARBINARY(32));
    IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'SK_Users')
        CLOSE SYMMETRIC KEY SK_Users;

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
    DECLARE @salt VARBINARY(16), @cifrado VARBINARY(MAX), @usuarioBD NVARCHAR(50);

    SELECT @salt = password_salt, @cifrado = password_enc, @usuarioBD = username
    FROM Users WHERE username = @username AND active = 1;

    IF @salt IS NULL
        THROW 51004, 'Usuario no existe o está inactivo.', 1;

    IF NOT EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'SK_Users')
        OPEN SYMMETRIC KEY SK_Users DECRYPTION BY CERTIFICATE Cert_Users;

    DECLARE @hashGuardado VARBINARY(32) =
        CAST(DECRYPTBYKEY(@cifrado, 1, CAST(@usuarioBD AS NVARCHAR(50))) AS VARBINARY(32));

    DECLARE @hashActual VARBINARY(32) = HASHBYTES('SHA2_256',
        @salt + CAST(@passwordActual AS VARBINARY(MAX)));

    IF @hashGuardado IS NULL OR @hashActual <> @hashGuardado
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'SK_Users')
            CLOSE SYMMETRIC KEY SK_Users;
        THROW 51005, 'La contraseña actual es incorrecta.', 1;
    END

    -- Generar nuevo salt y hash, y guardarlo cifrado
    DECLARE @saltNuevo VARBINARY(16) = CRYPT_GEN_RANDOM(16);
    DECLARE @hashNuevo VARBINARY(32) = HASHBYTES('SHA2_256',
        @saltNuevo + CAST(@passwordNueva AS VARBINARY(MAX)));

    UPDATE Users
    SET password_enc = ENCRYPTBYKEY(KEY_GUID('SK_Users'), @hashNuevo, 1, CAST(@usuarioBD AS NVARCHAR(50))),
        password_salt = @saltNuevo
    WHERE username = @username;

    IF EXISTS (SELECT 1 FROM sys.openkeys WHERE key_name = 'SK_Users')
        CLOSE SYMMETRIC KEY SK_Users;
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
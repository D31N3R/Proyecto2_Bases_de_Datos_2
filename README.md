# Wide World Importers – Base de datos distribuida (Proyecto 2, Bases de Datos II)

### Nombre y carné de los integrantes:
- [Completar]
- [Completar]

### Enlace del video:
[Completar: el video debe ser público]

---

## 1. Estado del proyecto

**Terminado**
- 3 nodos SQL Server en Docker (San José, Limón y Corporativo) con la base WideWorldImporters.
- Fragmentación horizontal de facturación y compras, fragmentación vertical de los datos sensibles y asignación a cada nodo (sección 3).
- Replicación transaccional del catálogo (productos, clientes y proveedores) Corp → San José y Limón.
- Tabla de usuarios con contraseña cifrada con los servicios nativos de SQL Server (AES-256).
- Estadísticas con filtro por sucursal o consolidadas, con copia materializada en Corp.
- Control de concurrencia en el catálogo y en la generación de IDs.
- Sistema web (HTML/JS) y API (Node.js/Express) que reutilizan la arquitectura del Proyecto 1.
- Respuesta ante la caída de un nodo (sección 8).

**Limitaciones conocidas**
- Corp es punto único de falla para editar el catálogo (productos, clientes y proveedores) e iniciar sesión nueva. Los clientes y proveedores recién creados tardan unos segundos en aparecer en las sucursales (replicación).
- Las contraseñas de los usuarios de SQL Server y de `sa` de los scripts son de clase; en un entorno real irían en un gestor de secretos.

## 2. Arquitectura

| Nodo | Contenedor | Puerto | Contenido |
|---|---|---|---|
| San José | `nodo_sj` | 1437 | Facturación y compras con ID par, inventario propio, catálogo replicado |
| Limón | `nodo_limon` | 1435 | Facturación y compras con ID impar, inventario propio, catálogo replicado |
| Corporativo | `nodo_corp` | 1436 | Catálogo maestro de productos, datos sensibles, usuarios, consolidado |

- **API** Node.js + Express (puerto 4000). Todo el acceso a datos es por procedimientos almacenados `Api.usp_*`.
- **Web** HTML + JS puro. Roles: *Administrador* (clientes, proveedores, productos, facturas de su sucursal) y *Corporativo* (estadísticas).
- La API se conecta al nodo de la sucursal del usuario (lo decide el token, no el navegador); el Corporativo se conecta a Corp.

## 3. Fragmentación y asignación (justificación)

| Datos | Fragmentación | Asignación | Por qué |
|---|---|---|---|
| Facturas, líneas, pedidos, órdenes de compra y transacciones | **Horizontal por paridad del ID** (SJ pares, Limón impares) | Sucursales | Cada sucursal factura de forma independiente: las consultas del día a día son locales y no compiten entre sí. La paridad es simple, determinista y reparte parejo (SJ 16 677 facturas, Limón 16 641). Los IDs nuevos respetan la paridad del nodo, así que nunca chocan al consolidar. |
| Clientes y proveedores (datos generales) | **Replicación** completa | Corp (maestro) → SJ y Limón | El enunciado pide el mismo catálogo en ambas sucursales. Se administra en un solo lugar (Corp), igual que los productos, y se lee localmente en cada venta y compra. Un solo nodo asigna los IDs, así que no hay choques. |
| Datos sensibles de clientes y proveedores (teléfono, fax, web, direcciones, ubicación, cuenta bancaria) | **Vertical** (columnas sensibles aparte) | Solo Corp (`Customers_Contact`, `Suppliers_Contact`) | Privacidad: la forma de contacto y los datos bancarios no deben vivir en las sucursales (requisito del enunciado). El alta o modificación los guarda en Corp en la misma transacción y la API los lee desde ahí. |
| Productos y tablas relacionadas | **Replicación** completa | Corp (maestro) → SJ y Limón | El catálogo es igual en todos los nodos y casi no cambia: se lee localmente (rápido) y se escribe en un solo lugar (Corp), lo que evita conflictos. |
| Inventario (`StockItemHoldings`) | Una fila por producto en cada sucursal | Cada sucursal (Corp no guarda) | Cada sucursal maneja su propio inventario, aunque comparta el catálogo. |
| Usuarios | Sin fragmentar | Corp | Un único lugar para autenticar y administrar usuarios. |
| Estadísticas | Copia materializada | Corp (`Consolidado.*`, `Estadisticas_Ventas`) | El Corporativo necesita ver ambas sucursales sin recorrerlas en vivo cada vez. |

## 4. Replicación

Publicación **transaccional continua** `Pub_Productos_Corp` en Corp (publicador y distribuidor), con San José y Limón como suscriptores. Artículos: `Warehouse.StockItems`, `StockItemStockGroups`, `StockGroups`, `Colors`, `PackageTypes`, `Sales.Customers` y `Purchasing.Suppliers`. Altas, cambios y borrados de productos, clientes y proveedores hechos en Corp llegan a ambas sucursales. El inventario y los datos sensibles no se replican.

Como el catálogo solo se edita en Corp, SJ y Limón rechazan crear o borrar productos (error 50070) y crear, modificar o eliminar clientes y proveedores (errores 50062 y 50063). Antes de borrar, Corp revisa en ambas sucursales: un producto no se elimina si tiene ventas, órdenes, movimientos o **existencias** en alguna sucursal; un cliente, si tiene facturas, órdenes o transacciones; un proveedor, si tiene órdenes de compra o transacciones. Si una sucursal no responde, no se puede verificar y no se borra. La llave foránea del inventario en las sucursales borra en cascada, para que el borrado replicado no se atasque.

## 5. Concurrencia

- **Control optimista en productos**: cada producto tiene una versión (`ValidFrom`); si dos personas lo editan, la segunda recibe el error 50080 (HTTP 409) y debe recargar. Nadie pisa el cambio del otro.
- **IDs por paridad** en facturas (cada sucursal genera los suyos) y un único nodo (Corp) asignando los IDs de clientes y proveedores, siempre con bloqueo (`UPDLOCK, HOLDLOCK`): dos altas simultáneas no repiten ID.
- **Escritura única del catálogo** (Corp) evita conflictos de replicación.
- Las operaciones que guardan contacto (upsert en Corp) e inventario (upsert en la sucursal) usan `UPDLOCK, HOLDLOCK`.

## 6. Seguridad y encriptación

- Contraseñas: `dbo.Users.password_enc` guarda el hash SHA2-256 de (sal + contraseña) **cifrado con AES-256** usando clave maestra → certificado → llave simétrica (`SK_Users`). Nunca se guarda en claro.
- La API entrega un **token firmado (HMAC-SHA256)** con usuario, rol y sucursal. Cada ruta valida el token y el rol: el Corporativo solo usa estadísticas; un Administrador solo llega al nodo de su sucursal.
- **Usuarios de base de datos por rol** (opcional, `USAR_USUARIOS_BD=true`): `app_admin` y `app_corp` solo pueden ejecutar procedimientos (`rol_administrador`, `rol_corporativo`) y no tienen permiso directo sobre las tablas. Se crean con `Script_sql/_all_07_Seguridad.sql` y `_corp_9_seguridad.sql`.
- Los datos sensibles de clientes y proveedores solo se guardan en Corp.

## 7. Vistas materializadas (Corporativo)

Corp mantiene `Consolidado.Invoices`, `InvoiceLines`, `PurchaseOrders`, `PurchaseOrderLines` y `StockItemHoldings` (copias de ambas sucursales con la columna `Sucursal`) y el resumen mensual `dbo.Estadisticas_Ventas`. `Api.usp_Estadisticas_Refrescar` las recalcula; la API lo hace sola si la copia tiene más de 5 minutos (`CONSOLIDADO_MINUTOS`) o con el botón de la pantalla de estadísticas. Los mismos reportes funcionan en cada sucursal (en vivo) y en Corp (consolidado) gracias a los sinónimos `Syn.*`.

## 8. Respuesta ante la falla de un nodo

`GET /api/status` revisa los tres nodos. Si un nodo no responde, la API contesta HTTP 503 con un mensaje claro (no un error técnico) y descarta la conexión para reconectar sola cuando vuelva.

| Si cae… | Qué sigue funcionando | Qué se afecta |
|---|---|---|
| **San José** | Limón y Corp completos. Corp muestra el consolidado con su última copia (marcado como desactualizado). | Los administradores de SJ reciben el aviso de nodo no disponible. |
| **Limón** | Igual que arriba, con San José. | Los administradores de Limón reciben el aviso. |
| **Corp** | Las sucursales siguen facturando, consultando clientes, proveedores y productos (copias locales) y manejando su inventario; sesiones ya iniciadas siguen vigentes. | No se crean ni editan productos, clientes ni proveedores, no se ven los datos de contacto, no se inicia sesión nueva y no hay estadísticas consolidadas. |

Mientras una sucursal está caída, la replicación de productos le queda en cola en el distribuidor y se aplica sola al volver. Al regresar un nodo, basta volver a intentar: la API reconecta sin reiniciar.

## 9. Cómo ejecutarlo

1. Descargar la base de ejemplo en `docker/backups/` (`curl -L -o docker/backups/WideWorldImporters-Full.bak https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak`) y levantar los contenedores: `cd docker && docker compose up -d`.
2. Inicializar los nodos: `./init-nodes.sh` (restaura la base y ejecuta los scripts por prefijo: `_all_`, `_corp_`, `_sj_`, `_limon_`).
3. API: `cd codigo/Api && cp .env.example .env && npm install && npm start`.
4. Web: abrir `codigo/WebSide/login.html` con un servidor estático.
5. Usuarios de prueba (definidos en `Script_sql/_corp_1_users.sql`): `admin_sj` y `admin_limon` (Administrador) y `corp` (Corporativo). Se pueden crear más con `usp_Users_Crear` en Corp.

## 10. Pruebas

Las pruebas se hacen en la demostración: (1) un cliente o proveedor creado por `admin_sj` aparece en `admin_limon` y su contacto sensible solo existe en Corp; (2) un producto creado desde la web llega a ambas sucursales; (3) las sucursales rechazan crear o borrar el catálogo directamente; (4) un producto con existencias o ventas no se puede borrar; (5) las estadísticas del Corporativo funcionan por sucursal y consolidadas; (6) al apagar un nodo, la API responde con un aviso claro. Durante el desarrollo se corrió además una batería automática de 99 comprobaciones, todas correctas.

## 11. Estructura del repositorio

- `Script_sql/`: scripts de los nodos. Prefijos: `_all_` (los 3), `_corp_`, `_sj_`, `_limon_`.
- `codigo/Api/`: API (Node.js/Express).
- `codigo/WebSide/`: sitio web.
- `docker/`: `docker-compose.yml` e `init-nodes.sh`.

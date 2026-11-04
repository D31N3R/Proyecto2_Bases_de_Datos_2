#!/bin/bash
# ============================================================
# verificar.sh - Prueba end-to-end de los 3 nodos
#   1. Nodos arriba         4. Usuarios en Corp
#   2. Catalogo replicado   5. Agentes de replicacion
#   3. Fragmentacion        6. Replicacion UPDATE / INSERT / DELETE
# Solo deja cambios temporales en productos y los revierte al final.
# ============================================================

SA='Proy2_Str0ng!Pass'
DB='WideWorldImporters'
SQLCMD='/opt/mssql-tools18/bin/sqlcmd'
ORIGINAL_NAME='USB missile launcher (Green)'

PASS=0
FAIL=0

# Ejecuta una consulta y devuelve el resultado sin espacios ni encabezados
sql() {
  local nodo=$1; shift
  docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA" -C -I -d "$DB" -h -1 -W \
    -Q "SET NOCOUNT ON; $*" 2>&1
}
# Igual, pero solo la ultima linea numerica
sql_num() {
  sql "$@" | grep -E '^-?[0-9]+$' | tail -1
}

ok()   { echo "  [OK]    $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FALLA] $1"; FAIL=$((FAIL+1)); }

check_eq() {  # descripcion, obtenido, esperado
  if [ "$2" = "$3" ]; then ok "$1 (= $2)"; else bad "$1 (obtenido: '$2', esperado: '$3')"; fi
}
check_gt0() { # descripcion, obtenido
  if [ -n "$2" ] && [ "$2" -gt 0 ] 2>/dev/null; then ok "$1 (= $2)"; else bad "$1 (obtenido: '$2', esperado > 0)"; fi
}

# Espera hasta que una consulta en un nodo devuelva el valor esperado (max 90 s)
wait_for() { # nodo, consulta, esperado
  local t=0
  while [ $t -lt 90 ]; do
    local v
    v=$(sql "$1" "$2" | head -1)
    [ "$v" = "$3" ] && return 0
    sleep 3; t=$((t+3))
  done
  return 1
}

echo "=== 1. Nodos arriba ==="
for n in nodo_sj nodo_limon nodo_corp; do
  check_eq "$n responde" "$(sql_num $n 'SELECT 1')" "1"
done

echo
echo "=== 2. Catalogo de productos (Warehouse.StockItems) ==="
for n in nodo_sj nodo_limon nodo_corp; do
  check_eq "$n tiene 227 productos" "$(sql_num $n 'SELECT COUNT(*) FROM Warehouse.StockItems')" "227"
done

echo
echo "=== 3. Fragmentacion ==="
SJ_INV=$(sql_num nodo_sj  'SELECT COUNT(*) FROM Sales.Invoices')
LI_INV=$(sql_num nodo_limon 'SELECT COUNT(*) FROM Sales.Invoices')
check_gt0 "SJ tiene facturas" "$SJ_INV"
check_gt0 "Limon tiene facturas" "$LI_INV"
check_eq  "SJ solo tiene facturas pares"   "$(sql_num nodo_sj    'SELECT COUNT(*) FROM Sales.Invoices WHERE InvoiceID % 2 <> 0')" "0"
check_eq  "Limon solo tiene facturas impares" "$(sql_num nodo_limon 'SELECT COUNT(*) FROM Sales.Invoices WHERE InvoiceID % 2 = 0')" "0"
check_eq  "Corp no guarda facturas" "$(sql_num nodo_corp 'SELECT COUNT(*) FROM Sales.Invoices')" "0"
check_eq  "Corp no guarda pedidos"  "$(sql_num nodo_corp 'SELECT COUNT(*) FROM Sales.Orders')" "0"
check_gt0 "Clientes en SJ"    "$(sql_num nodo_sj    'SELECT COUNT(*) FROM Sales.Customers')"
check_gt0 "Clientes en Limon" "$(sql_num nodo_limon 'SELECT COUNT(*) FROM Sales.Customers')"

echo
echo "=== 3b. Datos sensibles separados ==="
check_eq  "SJ sin telefonos de clientes"    "$(sql_num nodo_sj    "SELECT COUNT(*) FROM Sales.Customers WHERE PhoneNumber <> ''")" "0"
check_eq  "Limon sin telefonos de clientes" "$(sql_num nodo_limon "SELECT COUNT(*) FROM Sales.Customers WHERE PhoneNumber <> ''")" "0"
check_eq  "SJ sin cuentas bancarias de proveedores"    "$(sql_num nodo_sj    "SELECT COUNT(*) FROM Purchasing.Suppliers WHERE BankAccountNumber <> ''")" "0"
check_eq  "Limon sin cuentas bancarias de proveedores" "$(sql_num nodo_limon "SELECT COUNT(*) FROM Purchasing.Suppliers WHERE BankAccountNumber <> ''")" "0"
check_gt0 "Corp guarda contactos de clientes"    "$(sql_num nodo_corp 'SELECT COUNT(*) FROM Customers_Contact')"
check_gt0 "Corp guarda contactos de proveedores" "$(sql_num nodo_corp 'SELECT COUNT(*) FROM Suppliers_Contact')"

echo
echo "=== 4. Usuarios (Corp) ==="
check_gt0 "Usuarios registrados en dbo.Users" "$(sql_num nodo_corp 'SELECT COUNT(*) FROM dbo.Users')"
LOGIN=$(sql nodo_corp "EXEC dbo.usp_Users_Login 'admin_sj', 'Admin123!'" | head -1)
check_eq  "Login admin_sj correcto" "${LOGIN%% *}" "1"

echo
echo "=== 5. Agentes de replicacion ==="
AG=$(sql_num nodo_corp "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_agents a CROSS APPLY (SELECT TOP 1 h.runstatus FROM distribution.dbo.MSdistribution_history h WHERE h.agent_id = a.id ORDER BY h.time DESC) h WHERE (a.name LIKE '%-SJ-%' OR a.name LIKE '%-LIMON-%') AND h.runstatus IN (2,3,4)")
check_eq  "Agentes SJ y Limon sanos" "$AG" "2"

echo
echo "=== 6. Replicacion Corp -> SJ y Limon ==="
TAG="REPL_TEST_$(date +%s)"

# 6a UPDATE
sql nodo_corp "UPDATE Warehouse.StockItems SET StockItemName = N'$TAG' WHERE StockItemID = 1" > /dev/null
for n in nodo_sj nodo_limon; do
  if wait_for $n "SELECT StockItemName FROM Warehouse.StockItems WHERE StockItemID = 1" "$TAG"; then
    ok "UPDATE replicado a $n"
  else
    bad "UPDATE NO llego a $n en 90 s"
  fi
done

# 6b INSERT (mediante el procedure real de la API, ejecutado en Corp)
PNAME="ZZ_TEST_$(date +%s)"
NEWID=$(docker exec -i nodo_corp "$SQLCMD" -S localhost -U sa -P "$SA" -C -I -d "$DB" -h -1 -W -Q "
SET NOCOUNT ON;
DECLARE @s INT = (SELECT MIN(SupplierID) FROM Purchasing.Suppliers),
        @p INT = (SELECT MIN(PackageTypeID) FROM Warehouse.PackageTypes),
        @g INT = (SELECT MIN(StockGroupID) FROM Warehouse.StockGroups),
        @id INT;
EXEC Api.usp_Inventario_Crear @StockItemName = N'$PNAME', @SupplierID = @s,
     @UnitPackageID = @p, @OuterPackageID = @p, @QuantityPerOuter = 1,
     @TaxRate = 15, @UnitPrice = 10, @TypicalWeightPerUnit = 0.1,
     @StockGroupID = @g, @BinLocation = N'TEST-01', @NuevoStockItemID = @id OUTPUT;
SELECT @id;" 2>&1)
NEWID_NUM=$(echo "$NEWID" | grep -E '^[0-9]+$' | tail -1)

if [ -z "$NEWID_NUM" ]; then
  bad "INSERT: usp_Inventario_Crear fallo en Corp -> $(echo "$NEWID" | head -3 | tr '\n' ' ')"
else
  ok "Producto de prueba creado en Corp (ID $NEWID_NUM)"
  for n in nodo_sj nodo_limon; do
    if wait_for $n "SELECT COUNT(*) FROM Warehouse.StockItems WHERE StockItemID = $NEWID_NUM" "1"; then
      ok "INSERT replicado a $n"
    else
      bad "INSERT NO llego a $n en 90 s"
    fi
  done

  # 6c DELETE
  sql nodo_corp "DELETE FROM Warehouse.StockItemStockGroups WHERE StockItemID = $NEWID_NUM;
                 DELETE FROM Warehouse.StockItemHoldings   WHERE StockItemID = $NEWID_NUM;
                 DELETE FROM Warehouse.StockItems          WHERE StockItemID = $NEWID_NUM;" > /dev/null
  for n in nodo_sj nodo_limon; do
    if wait_for $n "SELECT COUNT(*) FROM Warehouse.StockItems WHERE StockItemID = $NEWID_NUM" "0"; then
      ok "DELETE replicado a $n"
    else
      bad "DELETE NO llego a $n en 90 s"
    fi
  done
fi

# Restaurar el nombre original del producto 1
sql nodo_corp "UPDATE Warehouse.StockItems SET StockItemName = N'$ORIGINAL_NAME' WHERE StockItemID = 1" > /dev/null
for n in nodo_sj nodo_limon; do
  wait_for $n "SELECT StockItemName FROM Warehouse.StockItems WHERE StockItemID = 1" "$ORIGINAL_NAME" \
    && ok "Nombre original restaurado en $n" || bad "No se restauro el nombre en $n"
done

echo
echo "=========================================="
echo "  OK: $PASS    FALLAS: $FAIL"
echo "=========================================="
[ $FAIL -eq 0 ]

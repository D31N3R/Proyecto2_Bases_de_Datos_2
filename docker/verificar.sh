#!/bin/bash
# ============================================================
# verificar.sh - Prueba end-to-end de los 3 nodos
#   1.  Nodos arriba              5.  Agentes de replicacion
#   1b. Configuracion de nodo     6.  Replicacion de productos (UPDATE/INSERT/DELETE)
#   2.  Catalogo replicado        6b. Tablas de referencia replicadas
#   3.  Fragmentacion             7.  Catalogo solo editable en Corp
#   3b. Datos sensibles
#   3c. IDs nuevos con paridad
#   4.  Usuarios en Corp
# Solo deja cambios temporales y los revierte al final.
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

# Crea una factura de prueba con el procedure real; imprime "InvoiceID LineID"
crear_factura() {
  docker exec -i "$1" "$SQLCMD" -S localhost -U sa -P "$SA" -C -I -d "$DB" -h -1 -W -Q "
SET NOCOUNT ON;
DECLARE @c INT = (SELECT MIN(CustomerID) FROM Sales.Customers),
        @v INT = (SELECT MIN(PersonID) FROM Application.People WHERE IsSalesperson = 1),
        @id INT;
EXEC Api.usp_Ventas_Crear @CustomerID = @c, @SalespersonPersonID = @v,
     @InvoiceDate = '$(date -u +%F)',
     @Lineas = N'[{\"StockItemID\":1,\"Quantity\":1}]', @NuevoInvoiceID = @id OUTPUT;
SELECT CONCAT(@id, ' ', (SELECT MAX(InvoiceLineID) FROM Sales.InvoiceLines WHERE InvoiceID = @id));" 2>&1
}

# Cambia el primer registro de una tabla de referencia en Corp y comprueba que llega a las sucursales
repl_ref() {  # tabla columna_nombre columna_id
  local tab=$1 col=$2 idc=$3 tag="ZZ_$(date +%s)"
  local orig
  orig=$(sql nodo_corp "SELECT $col FROM Warehouse.$tab WHERE $idc = (SELECT MIN($idc) FROM Warehouse.$tab)" | head -1)
  sql nodo_corp "UPDATE Warehouse.$tab SET $col = N'$tag' WHERE $idc = (SELECT MIN($idc) FROM Warehouse.$tab)" > /dev/null
  for n in nodo_sj nodo_limon; do
    if wait_for $n "SELECT $col FROM Warehouse.$tab WHERE $idc = (SELECT MIN($idc) FROM Warehouse.$tab)" "$tag"; then
      ok "Warehouse.$tab replicada a $n"
    else
      bad "Warehouse.$tab NO llego a $n en 90 s"
    fi
  done
  sql nodo_corp "UPDATE Warehouse.$tab SET $col = N'$orig' WHERE $idc = (SELECT MIN($idc) FROM Warehouse.$tab)" > /dev/null
  for n in nodo_sj nodo_limon; do
    wait_for $n "SELECT $col FROM Warehouse.$tab WHERE $idc = (SELECT MIN($idc) FROM Warehouse.$tab)" "$orig" \
      || bad "No se restauro Warehouse.$tab en $n"
  done
}

echo "=== 1. Nodos arriba ==="
for n in nodo_sj nodo_limon nodo_corp; do
  check_eq "$n responde" "$(sql_num $n 'SELECT 1')" "1"
done

echo
echo "=== 1b. Configuracion de nodo ==="
check_eq "SJ: paridad 0 (pares)"      "$(sql_num nodo_sj    'SELECT Paridad FROM dbo.NodoConfig')" "0"
check_eq "Limon: paridad 1 (impares)" "$(sql_num nodo_limon 'SELECT Paridad FROM dbo.NodoConfig')" "1"
check_eq "Corp: nodo CORP"            "$(sql nodo_corp 'SELECT Nodo FROM dbo.NodoConfig' | head -1)" "CORP"

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
echo "=== 3c. IDs nuevos respetan la paridad del nodo ==="
declare -A FID FLN
for par in "nodo_sj:0:SJ" "nodo_limon:1:Limon"; do
  IFS=: read nodo p etiqueta <<< "$par"
  R=$(crear_factura "$nodo")
  P=$(echo "$R" | grep -E '^[0-9]+ [0-9]+$' | tail -1)
  if [ -z "$P" ]; then
    bad "$etiqueta: no se pudo crear la factura -> $(echo "$R" | head -3 | tr '\n' ' ')"
    continue
  fi
  ID=${P% *}; LN=${P#* }
  FID[$nodo]=$ID; FLN[$nodo]=$LN
  check_eq "$etiqueta: factura nueva $ID tiene la paridad del nodo" "$((ID % 2))" "$p"
  check_eq "$etiqueta: linea nueva $LN tiene la paridad del nodo"   "$((LN % 2))" "$p"
  if [ "$LN" -ge 1000000 ]; then
    ok "$etiqueta: linea nueva por encima de los IDs historicos"
  else
    bad "$etiqueta: linea nueva $LN es menor a 1000000"
  fi
  # Limpiar la factura de prueba
  sql "$nodo" "DELETE FROM Sales.InvoiceLines WHERE InvoiceID = $ID; DELETE FROM Sales.Invoices WHERE InvoiceID = $ID;" > /dev/null
done
if [ -n "${FID[nodo_sj]}" ] && [ -n "${FID[nodo_limon]}" ]; then
  if [ "${FID[nodo_sj]}" != "${FID[nodo_limon]}" ] && [ "${FLN[nodo_sj]}" != "${FLN[nodo_limon]}" ]; then
    ok "Sin IDs repetidos entre SJ y Limon"
  else
    bad "IDs repetidos entre SJ y Limon"
  fi
fi
R=$(crear_factura nodo_corp)
if echo "$R" | grep -q "50060"; then ok "Corp rechaza crear facturas (error 50060)"; else bad "Corp permitio crear una factura"; fi

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
echo "=== 6. Replicacion de productos Corp -> SJ y Limon ==="
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
    if wait_for $n "SELECT COUNT(*) FROM Warehouse.StockItemStockGroups WHERE StockItemID = $NEWID_NUM" "1"; then
      ok "Grupo del producto replicado a $n"
    else
      bad "Grupo del producto NO llego a $n en 90 s"
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
echo "=== 6b. Tablas de referencia de producto replicadas ==="
repl_ref Colors ColorName ColorID
repl_ref PackageTypes PackageTypeName PackageTypeID
repl_ref StockGroups StockGroupName StockGroupID

echo
echo "=== 7. Catalogo solo editable en Corp ==="
for n in nodo_sj nodo_limon; do
  G=$(docker exec -i $n "$SQLCMD" -S localhost -U sa -P "$SA" -C -I -d "$DB" -h -1 -W -Q "
DECLARE @id INT;
EXEC Api.usp_Inventario_Crear @StockItemName = N'NO_DEBE_CREARSE', @SupplierID = 1, @UnitPackageID = 1,
     @OuterPackageID = 1, @QuantityPerOuter = 1, @TaxRate = 15, @UnitPrice = 1,
     @TypicalWeightPerUnit = 1, @StockGroupID = 1, @BinLocation = N'X', @NuevoStockItemID = @id OUTPUT;" 2>&1)
  if echo "$G" | grep -q "50070"; then ok "$n rechaza crear productos (error 50070)"; else bad "$n permitio crear un producto"; fi
  E=$(sql $n "EXEC Api.usp_Inventario_Eliminar @StockItemID = 1")
  if echo "$E" | grep -q "50070"; then ok "$n rechaza eliminar productos (error 50070)"; else bad "$n permitio eliminar un producto"; fi
  check_eq "$n conserva sus 227 productos" "$(sql_num $n 'SELECT COUNT(*) FROM Warehouse.StockItems')" "227"
done

echo
echo "=== 9. Concurrencia y borrado de productos ==="
CPROD="ZZ_CONC_$(date +%s)"
CID=$(docker exec -i nodo_corp "$SQLCMD" -S localhost -U sa -P "$SA" -C -I -d "$DB" -h -1 -W -Q "
SET NOCOUNT ON;
DECLARE @s INT = (SELECT MIN(SupplierID) FROM Purchasing.Suppliers),
        @p INT = (SELECT MIN(PackageTypeID) FROM Warehouse.PackageTypes),
        @g INT = (SELECT MIN(StockGroupID) FROM Warehouse.StockGroups), @id INT;
EXEC Api.usp_Inventario_Crear @StockItemName = N'$CPROD', @SupplierID = @s, @UnitPackageID = @p,
     @OuterPackageID = @p, @QuantityPerOuter = 1, @TaxRate = 15, @UnitPrice = 10,
     @TypicalWeightPerUnit = 0.1, @StockGroupID = @g, @BinLocation = N'TEST-01', @NuevoStockItemID = @id OUTPUT;
SELECT @id;" 2>&1 | grep -E '^[0-9]+$' | tail -1)

if [ -z "$CID" ]; then
  bad "No se pudo crear el producto de prueba para la concurrencia"
else
  # Dos editores con la misma version: el primero guarda, el segundo debe ser rechazado
  MODIF=$(docker exec -i nodo_corp "$SQLCMD" -S localhost -U sa -P "$SA" -C -I -d "$DB" -h -1 -W -Q "
DECLARE @v VARCHAR(27) = (SELECT CONVERT(VARCHAR(27), ValidFrom, 121) FROM Warehouse.StockItems WHERE StockItemID = $CID);
DECLARE @s INT, @u INT, @o INT, @q INT, @t DECIMAL(18,3), @p DECIMAL(18,2), @w DECIMAL(18,3);
SELECT @s = SupplierID, @u = UnitPackageID, @o = OuterPackageID, @q = QuantityPerOuter,
       @t = TaxRate, @p = UnitPrice, @w = TypicalWeightPerUnit
FROM Warehouse.StockItems WHERE StockItemID = $CID;
EXEC Api.usp_Inventario_Modificar @StockItemID = $CID, @StockItemName = N'${CPROD}_A', @SupplierID = @s,
     @UnitPackageID = @u, @OuterPackageID = @o, @QuantityPerOuter = @q, @TaxRate = @t, @UnitPrice = @p,
     @TypicalWeightPerUnit = @w, @BinLocation = N'TEST-01', @Version = @v;
PRINT 'PRIMERA_EDICION_OK';
EXEC Api.usp_Inventario_Modificar @StockItemID = $CID, @StockItemName = N'${CPROD}_B', @SupplierID = @s,
     @UnitPackageID = @u, @OuterPackageID = @o, @QuantityPerOuter = @q, @TaxRate = @t, @UnitPrice = @p,
     @TypicalWeightPerUnit = @w, @BinLocation = N'TEST-01', @Version = @v;
PRINT 'SEGUNDA_EDICION_SIN_ERROR';" 2>&1)
  if echo "$MODIF" | grep -q "PRIMERA_EDICION_OK"; then ok "Edicion con la version vigente se aplica"; else bad "La primera edicion fallo -> $(echo "$MODIF" | head -3 | tr '\n' ' ')"; fi
  if echo "$MODIF" | grep -q "50080" && ! echo "$MODIF" | grep -q "SEGUNDA_EDICION_SIN_ERROR"; then ok "Segunda edicion con la version vieja se rechaza (error 50080)"; else bad "La segunda edicion con version vieja NO se rechazo"; fi
  check_eq "El segundo editor no piso el cambio del primero" "$(sql nodo_corp "SELECT StockItemName FROM Warehouse.StockItems WHERE StockItemID = $CID" | head -1)" "${CPROD}_A"

  # Borrado: el producto tiene una factura en SJ, asi que Corp debe negarse
  if wait_for nodo_sj "SELECT COUNT(*) FROM Warehouse.StockItems WHERE StockItemID = $CID" "1"; then
    FAC=$(docker exec -i nodo_sj "$SQLCMD" -S localhost -U sa -P "$SA" -C -I -d "$DB" -h -1 -W -Q "
SET NOCOUNT ON;
DECLARE @c INT = (SELECT MIN(CustomerID) FROM Sales.Customers),
        @v INT = (SELECT MIN(PersonID) FROM Application.People WHERE IsSalesperson = 1), @id INT;
EXEC Api.usp_Ventas_Crear @CustomerID = @c, @SalespersonPersonID = @v,
     @InvoiceDate = '$(date -u +%F)',
     @Lineas = N'[{\"StockItemID\":$CID,\"Quantity\":1}]', @NuevoInvoiceID = @id OUTPUT;
SELECT @id;" 2>&1 | grep -E '^[0-9]+$' | tail -1)
    if [ -z "$FAC" ]; then
      bad "No se pudo crear la factura de prueba en SJ"
    else
      E1=$(sql nodo_corp "EXEC Api.usp_Inventario_Eliminar @StockItemID = $CID")
      if echo "$E1" | grep -q -E "5003[12]"; then ok "Corp rechaza borrar un producto con ventas en una sucursal"; else bad "Corp permitio borrar un producto con ventas en SJ -> $(echo "$E1" | head -2 | tr '\n' ' ')"; fi
      check_eq "El producto sigue existiendo en Corp" "$(sql_num nodo_corp "SELECT COUNT(*) FROM Warehouse.StockItems WHERE StockItemID = $CID")" "1"
      sql nodo_sj "DELETE FROM Sales.InvoiceLines WHERE InvoiceID = $FAC; DELETE FROM Sales.Invoices WHERE InvoiceID = $FAC;" > /dev/null
    fi
  else
    bad "El producto de prueba no llego a SJ; se omite la prueba de borrado con ventas"
  fi

  # Sin ventas, el borrado si procede y se replica a las sucursales
  E2=$(sql nodo_corp "EXEC Api.usp_Inventario_Eliminar @StockItemID = $CID")
  if echo "$E2" | grep -q "Msg"; then bad "Eliminar un producto sin ventas fallo -> $(echo "$E2" | head -2 | tr '\n' ' ')"; else ok "Corp elimina un producto sin ventas"; fi
  for n in nodo_sj nodo_limon; do
    if wait_for $n "SELECT COUNT(*) FROM Warehouse.StockItems WHERE StockItemID = $CID" "0"; then ok "El borrado llego a $n"; else bad "El borrado NO llego a $n en 90 s"; fi
  done
fi


echo
echo "=========================================="
echo "  OK: $PASS    FALLAS: $FAIL"
echo "=========================================="
[ $FAIL -eq 0 ]
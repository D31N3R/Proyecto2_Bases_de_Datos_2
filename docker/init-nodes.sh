#!/bin/bash
# ============================================================
# init-nodes.sh
#
# Inicializa SQL en los 3 nodos YA CORRIENDO:
#   1. Valida prerequisitos (Docker, archivos, contenedores up)
#   2. Verifica que SQL Server responda en cada nodo
#   3. Restaura WideWorldImporters (.bak) si no existe
#   4. Ejecuta scripts SQL por prefijo (_all_, _sj_, _limon_, _corp_)
#   5. Verifica el estado final
#
# NO inicia contenedores. Asume que ya están corriendo.
# Es IDEMPOTENTE: se puede ejecutar múltiples veces sin romper nada.
# Si algo falla, se detiene y muestra el error real.
# ============================================================

set -euo pipefail

# ---------- Rutas absolutas (funciona desde cualquier directorio) ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$(cd "$SCRIPT_DIR/../Script_sql" 2>/dev/null && pwd || echo "$SCRIPT_DIR/../Script_sql")"
BAK_FILE="$SCRIPT_DIR/backups/WideWorldImporters-Full.bak"

# ---------- Configuración ----------
SA_PASSWORD="Proy2_Str0ng!Pass"
DB_NAME="WideWorldImporters"
SQLCMD="/opt/mssql-tools18/bin/sqlcmd"

# Nodos: nombre:puerto_host
NODES=(
  "nodo_sj:1437"
  "nodo_limon:1435"
  "nodo_corp:1436"
)

# ---------- Colores ----------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}==> $1${NC}"; }

# ---------- Helpers ----------

# Ejecuta sqlcmd dentro de un contenedor con contexto de DB forzado
run_sql() {
  local nodo=$1
  shift
  docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -I -d "$DB_NAME" "$@"
}

# Espera a que SQL Server responda (timeout 180s)
wait_for_node() {
  local nodo=$1
  local intentos=0
  local max=90
  while [ $intentos -lt $max ]; do
    if docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -Q "SELECT 1" >/dev/null 2>&1; then
      return 0
    fi
    intentos=$((intentos + 1))
    sleep 2
  done
  return 1
}

# Verifica si la base de datos existe en un nodo
db_exists() {
  local nodo=$1
  local count
  count=$(docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -h -1 -Q \
    "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = '$DB_NAME'" 2>/dev/null | tr -d '[:space:]')
  [ "$count" = "1" ]
}

# ============================================================
# PASO 0: Precondiciones
# ============================================================
log_step "PASO 0: Verificando precondiciones"

if ! command -v docker >/dev/null 2>&1; then
  log_error "Docker no está instalado."
  exit 1
fi

if [ ! -f "$BAK_FILE" ]; then
  log_error "No se encontró $BAK_FILE"
  log_error "Descárgalo con:"
  echo "    cd $SCRIPT_DIR/backups"
  echo "    curl -L -o WideWorldImporters-Full.bak 'https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak'"
  exit 1
fi
log_info "backups/WideWorldImporters-Full.bak encontrado ($(du -h "$BAK_FILE" | cut -f1))"

if [ ! -d "$SQL_DIR" ]; then
  log_error "No se encontró la carpeta de scripts SQL en $SQL_DIR"
  exit 1
fi
sql_count=$(ls -1 "$SQL_DIR"/*.sql 2>/dev/null | wc -l)
log_info "Carpeta de scripts encontrada ($sql_count archivos .sql)"

# ============================================================
# PASO 1: Verificar que los 3 contenedores estén corriendo
# NO los inicia. Solo verifica.
# ============================================================
log_step "PASO 1: Verificando contenedores (no se inician, deben estar up)"

for entry in "${NODES[@]}"; do
  nodo="${entry%%:*}"
  if ! docker ps --format '{{.Names}}' | grep -q "^${nodo}$"; then
    log_error "$nodo NO está corriendo."
    log_error "Inícialo manualmente con: cd $SCRIPT_DIR && docker compose up -d"
    exit 1
  fi
  log_info "$nodo está corriendo"
done

# ============================================================
# PASO 2: Esperar a que SQL Server responda
# ============================================================
log_step "PASO 2: Esperando a que SQL Server esté listo"

for entry in "${NODES[@]}"; do
  nodo="${entry%%:*}"
  log_info "Esperando a $nodo..."
  if wait_for_node "$nodo"; then
    log_info "$nodo listo"
  else
    log_error "$nodo no respondió en 180s. Logs:"
    docker logs "$nodo" 2>&1 | tail -30
    exit 1
  fi
done

# ============================================================
# PASO 3: Restaurar WideWorldImporters si no existe
# ============================================================
log_step "PASO 3: Restaurando base de datos (si no existe)"

for entry in "${NODES[@]}"; do
  nodo="${entry%%:*}"

  if db_exists "$nodo"; then
    log_info "$nodo: $DB_NAME ya existe, se omite restauración"
    continue
  fi

  log_info "$nodo: restaurando $DB_NAME (esto tarda ~30s)..."
  if ! docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -Q "
    RESTORE DATABASE [$DB_NAME]
    FROM DISK = '/backups/WideWorldImporters-Full.bak'
    WITH
      MOVE 'WWI_Primary' TO '/var/opt/mssql/data/WideWorldImporters.mdf',
      MOVE 'WWI_UserData' TO '/var/opt/mssql/data/WideWorldImporters_UserData.ndf',
      MOVE 'WWI_Log' TO '/var/opt/mssql/data/WideWorldImporters.ldf',
      MOVE 'WWI_InMemory_Data_1' TO '/var/opt/mssql/data/WideWorldImporters_InMemory_Data_1',
      REPLACE
  " > /tmp/restore_${nodo}.log 2>&1; then
    log_error "$nodo: falló la restauración. Log:"
    tail -20 /tmp/restore_${nodo}.log
    exit 1
  fi
  log_info "$nodo: restauración completada"
done

# ============================================================
# PASO 4a: Copiar scripts SQL a cada contenedor
# ============================================================
log_step "PASO 4a: Copiando scripts SQL a los contenedores"

for entry in "${NODES[@]}"; do
  nodo="${entry%%:*}"
  log_info "$nodo: copiando $SQL_DIR → /tmp/sql/"
  docker exec "$nodo" mkdir -p /tmp/sql
  docker exec "$nodo" mkdir -p /var/opt/mssql/ReplData
  if ! docker cp "$SQL_DIR/." "$nodo:/tmp/sql/" > /dev/null 2>&1; then
    log_error "$nodo: falló docker cp"
    exit 1
  fi
done
log_info "Scripts copiados a los 3 nodos"

# ============================================================
# PASO 4b: Ejecutar scripts SQL por prefijo, con detección de errores
# ============================================================
log_step "PASO 4b: Ejecutando scripts SQL"

mapfile -t script_files < <(ls -1 "$SQL_DIR"/*.sql 2>/dev/null | sort)

if [ ${#script_files[@]} -eq 0 ]; then
  log_warn "No hay scripts .sql para ejecutar"
else
  for script_path in "${script_files[@]}"; do
    script=$(basename "$script_path")

    case "$script" in
      _all_*)   nodos_destino=("nodo_sj" "nodo_limon" "nodo_corp") ;;
      _sj_*)    nodos_destino=("nodo_sj") ;;
      _limon_*) nodos_destino=("nodo_limon") ;;
      _corp_*)  nodos_destino=("nodo_corp") ;;
      *)
        log_warn "$script: prefijo desconocido (usa _all_, _sj_, _limon_ o _corp_). Se omite."
        continue
        ;;
    esac

    for nodo in "${nodos_destino[@]}"; do
      log_info "$nodo: ejecutando $script"

      output_file=$(mktemp)

      if ! docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -I \
           -d "$DB_NAME" -i "/tmp/sql/$script" > "$output_file" 2>&1; then
        log_error "$nodo: FALLÓ $script (exit code != 0)"
        echo "--- Salida (últimas 20 líneas) ---"
        tail -20 "$output_file"
        echo "---------------------------------"
        rm -f "$output_file"
        exit 1
      fi

      if grep -qE "^Msg [0-9]+, Level (1[6-9]|2[0-9])" "$output_file"; then
        log_error "$nodo: errores SQL en $script:"
        grep -E "^Msg [0-9]+, Level (1[6-9]|2[0-9])" "$output_file" | head -5
        rm -f "$output_file"
        exit 1
      fi

      mkdir -p /tmp/init_logs
      mv "$output_file" "/tmp/init_logs/${nodo}_${script}.log"
      cnt=$(docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -h -1 -d "$DB_NAME" -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM Warehouse.StockItems" 2>/dev/null | tr -d '[:space:]' || true)
      log_info "$nodo: StockItems tras $script = $cnt"
    done
  done
  log_info "Todos los scripts ejecutados sin errores"
fi

# ============================================================
# PASO 5: Verificación final
# ============================================================
log_step "PASO 5: Verificación final"

ERRORES=0

for entry in "${NODES[@]}"; do
  nodo="${entry%%:*}"
  echo ""
  echo "--- $nodo ---"

  proc_count=$(docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -h -1 -Q \
    "SET NOCOUNT ON; USE [$DB_NAME]; SELECT COUNT(*) FROM sys.procedures WHERE schema_id = SCHEMA_ID('Api')" 2>/dev/null | tr -d '[:space:]' || echo "0")
  echo "  Procedures en Api: ${proc_count:-0}"

  syn_count=$(docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -h -1 -Q \
    "SET NOCOUNT ON; USE [$DB_NAME]; SELECT COUNT(*) FROM sys.synonyms WHERE schema_id = SCHEMA_ID('Syn')" 2>/dev/null | tr -d '[:space:]' || echo "0")
  echo "  Sinónimos en Syn: ${syn_count:-0}"

  clientes=$(docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -h -1 -Q \
    "SET NOCOUNT ON; SELECT COUNT(*) FROM [$DB_NAME].Sales.Customers" 2>/dev/null | tr -d '[:space:]' || echo "0")
  echo "  Clientes en Sales.Customers: ${clientes:-0}"

  if docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C \
      -Q "EXEC [$DB_NAME].Api.usp_Clientes_Listar" > /dev/null 2>&1; then
    echo -e "  ${GREEN}usp_Clientes_Listar: OK${NC}"
  else
    echo -e "  ${RED}usp_Clientes_Listar: FALLA${NC}"
    ERRORES=$((ERRORES + 1))
  fi

  if [ "$nodo" = "nodo_corp" ]; then
    users_count=$(docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -h -1 -Q \
      "SET NOCOUNT ON; USE [$DB_NAME]; SELECT COUNT(*) FROM dbo.Users" 2>/dev/null | tr -d '[:space:]' || echo "0")
    echo "  Usuarios en dbo.Users: ${users_count:-0}"

    if [ "${users_count:-0}" -gt 0 ]; then
      login_ok=$(docker exec -i "$nodo" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -h -1 -Q \
        "SET NOCOUNT ON; USE [$DB_NAME]; EXEC dbo.usp_Users_Login 'admin_sj', 'Admin123!'" 2>/dev/null | head -1 | tr -d '[:space:]')
      if [ "$login_ok" = "1" ]; then
        echo -e "  ${GREEN}Login admin_sj: OK${NC}"
      else
        echo -e "  ${YELLOW}Login admin_sj: FALLA (revisa hash)${NC}"
      fi
    fi
  fi
done

echo ""
if [ $ERRORES -eq 0 ]; then
  log_info "======================================"
  log_info "Inicialización completada sin errores"
  log_info "======================================"
  echo ""
  echo "Conexiones disponibles:"
  echo "  SJ    → localhost,1437"
  echo "  Limón → localhost,1435"
  echo "  Corp  → localhost,1436"
else
  log_error "======================================"
  log_error "$ERRORES errores encontrados"
  log_error "======================================"
  exit 1
fi
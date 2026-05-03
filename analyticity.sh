#!/usr/bin/env bash
# analyticity.sh — central management script for the Analyticity platform
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CITIES_DIR="$ROOT/cities"
DB_COMPOSE="$ROOT/db/centralDbCreation/docker-compose.yml"
DB_ENV="$ROOT/db/centralDbCreation/.env"
DATA_COMPOSE="$ROOT/infrastructure/docker-compose.yml"
DATA_COMPOSE_DIR="$ROOT/sources/data_model/infrastructure/compose/dev"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

  City services (infrastructure + api + ui — all in one compose per city):
    list                         List all configured cities
    setup   <city>               Create a new city from template
    start   <city|--all> [profile]   Start services (optional compose profile)
    stop    <city|--all>         Stop all services (keeps volumes/data)
    restart <city|--all> [profile]   Restart services
    pull    <city|--all>         Pull latest images from registry
    update  <city|--all>         Pull + restart
    deploy  <city> <service>      Pull + recreate one app service (no infra touch)
    logs    <city> [service]     Tail logs (optionally one service)
    status  <city|--all>         Show running containers
    ports   <city>               Check for port conflicts before starting
    sync                         Advance submodules to latest tracked branch

  Profiles (for start/restart):
    (none)      core only: postgres-timescale, redpanda + app services
    tools       + pgadmin (port 5050), redpanda-console (port 8080)
    extract     + waze-feed, ndic-closures, police-accidents
    transform   + db-migrate, all transformers, event-linker
    apps        extract + transform
    mon         + otel, jaeger, prometheus, grafana
    all         everything

  Central DB (shared, runs once per server):
    db:start                     Start central DB + pgAdmin
    db:stop                      Stop central DB
    db:restart                   Restart central DB
    db:logs                      Tail central DB logs
    db:status                    Show central DB containers

Examples:
  $(basename "$0") db:start
  $(basename "$0") setup orp_liberec
  $(basename "$0") ports brno              # check for conflicts first
  $(basename "$0") start brno              # core infra + app services
  $(basename "$0") start brno all          # everything including tools/extract/transform
  $(basename "$0") update --all
  $(basename "$0") logs brno api
  $(basename "$0") logs brno waze-feed
EOF
  exit 1
}

# ── helpers ──────────────────────────────────────────────────────────────────

city_dir() { echo "$CITIES_DIR/$1"; }

require_city() {
  local city="$1"
  if [[ ! -f "$(city_dir "$city")/docker-compose.yml" ]]; then
    echo "ERROR: City '$city' not found (missing $(city_dir "$city")/docker-compose.yml)"
    exit 1
  fi
}

require_env() {
  local city="$1"
  if [[ ! -f "$(city_dir "$city")/.env" ]]; then
    echo "ERROR: $(city_dir "$city")/.env not found — copy .env.example to .env and fill in values"
    exit 1
  fi
}

# docker compose for city app services — project: analyticity-<city>
dc() {
  local city="$1"; shift
  docker compose \
    --project-name "analyticity-${city}" \
    -f "$(city_dir "$city")/docker-compose.yml" \
    "$@"
}

# docker compose for central DB — project: analyticity
dc_db() {
  docker compose \
    --project-name "analyticity" \
    -f "$DB_COMPOSE" \
    "$@"
}

require_data_model() {
  if [[ ! -f "$DATA_COMPOSE_DIR/Dockerfile.db" ]]; then
    echo "ERROR: sources/data_model/infrastructure submodule not initialised — run: git submodule update --init --recursive"
    exit 1
  fi
}

all_cities() {
  for d in "$CITIES_DIR"/*/; do
    [[ -f "$d/docker-compose.yml" ]] && basename "$d"
  done
}

each_city() {
  local cmd="$1"; shift
  for city in $(all_cities); do
    echo "──── $city ────"
    "$cmd" "$city" "$@" || true
  done
}

# ── port conflict check ───────────────────────────────────────────────────────

# Returns 0 if port is in use by a non-Docker process (or any process on Linux/macOS)
_port_in_use() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -i ":${port}" -sTCP:LISTEN -t >/dev/null 2>&1
  elif command -v ss >/dev/null 2>&1; then
    ss -tlnp 2>/dev/null | grep -qE ":${port}[[:space:]]"
  else
    return 1  # cannot check
  fi
}

_read_env_port() {
  local env_file="$1" key="$2" default="$3"
  local val
  val=$(grep -E "^${key}=" "$env_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d ' "')
  echo "${val:-$default}"
}

cmd_ports() {
  local city="${1:?city name required}"
  require_city "$city"
  local env_file
  env_file="$(city_dir "$city")/.env"

  if [[ ! -f "$env_file" ]]; then
    echo "WARNING: .env not found, using default ports for check"
  fi

  local api_port traffic_port admin_port ui_port
  local pg_port rp_schema rp_proxy rp_kafka rp_metrics
  local pgadmin_port console_port ndic_port police_port
  local acc_port jams_port alerts_port closures_port linker_port
  local otel_grpc otel_http jaeger_ui prometheus_port grafana_port
  api_port=$(_read_env_port "$env_file" API_PORT 8000)
  traffic_port=$(_read_env_port "$env_file" TRAFFIC_BACKEND_PORT 8081)
  admin_port=$(_read_env_port "$env_file" ADMIN_BACKEND_PORT 8082)
  ui_port=$(_read_env_port "$env_file" UI_PORT 80)
  pg_port=$(_read_env_port "$env_file" POSTGRES_TIMESCALE_PORT 5432)
  rp_schema=$(_read_env_port "$env_file" REDPANDA_SCHEMA_EXT_PORT 18081)
  rp_proxy=$(_read_env_port "$env_file" REDPANDA_PROXY_EXT_PORT 18082)
  rp_kafka=$(_read_env_port "$env_file" REDPANDA_KAFKA_EXT_PORT 19092)
  rp_metrics=$(_read_env_port "$env_file" REDPANDA_METRICS_EXT_PORT 19644)
  pgadmin_port=$(_read_env_port "$env_file" PGADMIN_INFRA_PORT 5050)
  console_port=$(_read_env_port "$env_file" CONSOLE_EXT_PORT 8080)
  ndic_port=$(_read_env_port "$env_file" NDIC_EXT_PORT 8888)
  police_port=$(_read_env_port "$env_file" POLICE_EXT_PORT 9999)
  acc_port=$(_read_env_port "$env_file" ACCIDENTS_TRANSFORMER_EXT_PORT 9998)
  jams_port=$(_read_env_port "$env_file" JAMS_TRANSFORMER_EXT_PORT 9997)
  alerts_port=$(_read_env_port "$env_file" ALERTS_TRANSFORMER_EXT_PORT 9996)
  closures_port=$(_read_env_port "$env_file" CLOSURES_TRANSFORMER_EXT_PORT 9995)
  linker_port=$(_read_env_port "$env_file" EVENT_LINKER_EXT_PORT 9994)
  otel_grpc=$(_read_env_port "$env_file" OTEL_GRPC_PORT 4317)
  otel_http=$(_read_env_port "$env_file" OTEL_HTTP_PORT 4318)
  jaeger_ui=$(_read_env_port "$env_file" JAEGER_UI_PORT 16686)
  prometheus_port=$(_read_env_port "$env_file" PROMETHEUS_PORT 9090)
  grafana_port=$(_read_env_port "$env_file" GRAFANA_PORT 3000)

  echo "Checking ports for city: $city"
  echo ""

  # Format: "port:service:profile"
  local entries=(
    "${ui_port}:bp-ux-ui:always"
    "${api_port}:api:always"
    "${traffic_port}:traffic-jams-backend:always"
    "${admin_port}:admin-backend:always"
    "${pg_port}:postgres-timescale:always"
    "${rp_schema}:redpanda (schema-registry ext):always"
    "${rp_proxy}:redpanda (proxy ext):always"
    "${rp_kafka}:redpanda (kafka ext):always"
    "${rp_metrics}:redpanda (metrics ext):always"
    "${pgadmin_port}:pgadmin:tools/all"
    "${console_port}:redpanda-console:tools/all"
    "${ndic_port}:ndic-closures:extract/apps/all"
    "${police_port}:police-accidents:extract/apps/all"
    "${acc_port}:accidents-transformer:transform/apps/all"
    "${jams_port}:jams-transformer:transform/apps/all"
    "${alerts_port}:alerts-transformer:transform/apps/all"
    "${closures_port}:closures-transformer:transform/apps/all"
    "${linker_port}:event-linker:transform/apps/all"
    "${grafana_port}:grafana:mon/all"
    "${prometheus_port}:prometheus:mon/all"
    "${jaeger_ui}:jaeger:mon/all"
    "${otel_grpc}:otel-collector (grpc):mon/all"
    "${otel_http}:otel-collector (http):mon/all"
  )

  local conflicts=0
  if ! command -v lsof >/dev/null 2>&1 && ! command -v ss >/dev/null 2>&1; then
    echo "  WARNING: neither lsof nor ss found — cannot check ports"
    return 0
  fi

  for entry in "${entries[@]}"; do
    local port="${entry%%:*}"
    local rest="${entry#*:}"
    local svc="${rest%%:*}"
    local profile="${rest##*:}"
    if _port_in_use "$port"; then
      local proc=""
      if command -v lsof >/dev/null 2>&1; then
        proc=$(lsof -i ":${port}" -sTCP:LISTEN -n -P 2>/dev/null | awk 'NR==2{print $1"(pid "$2")"}')
      fi
      printf "  CONFLICT  %-6s  %-35s [profile: %s]  ← used by: %s\n" \
        "$port" "$svc" "$profile" "$proc"
      conflicts=$((conflicts + 1))
    else
      printf "  ok        %-6s  %s\n" "$port" "$svc"
    fi
  done

  echo ""
  if [[ $conflicts -eq 0 ]]; then
    echo "  All ports free ✓"
  else
    echo "  $conflicts conflict(s) found — stop conflicting services before starting."
    echo "  Note: ports from other Analyticity cities must differ (set in each city's .env)"
  fi
}

# ── city app commands ─────────────────────────────────────────────────────────

cmd_list() {
  echo "Configured cities:"
  all_cities | sed 's/^/  /'
}

cmd_setup() {
  local city="${1:?city name required}"
  local dir
  dir="$(city_dir "$city")"
  if [[ -d "$dir" ]]; then
    echo "City '$city' already exists."
    exit 1
  fi
  mkdir -p "$dir"
  sed "s/__CITY__/${city}/g" "$ROOT/templates/docker-compose.yml" > "$dir/docker-compose.yml"
  cp "$ROOT/templates/.env.example" "$dir/.env.example"
  cp "$ROOT/templates/.env.example" "$dir/.env"
  echo "Created $dir"
  echo "Fill in credentials: $dir/.env  (gitignored, never committed)"
}

cmd_start() {
  local city="$1"; local profile="${2:-all}"
  require_city "$city"; require_env "$city"

  echo "==> Checking ports for $city..."
  cmd_ports "$city"
  echo ""

  dc "$city" --profile "$profile" up -d
}

cmd_stop()    { local city="$1"; require_city "$city"; dc "$city" --profile all down; }
cmd_restart() {
  local city="$1"; local profile="${2:-all}"
  require_city "$city"; require_env "$city"
  dc "$city" --profile "$profile" restart
}
cmd_pull()    { local city="$1"; require_city "$city"; require_env "$city"; dc "$city" --profile all pull; }
cmd_update()  { local city="$1"; local profile="${2:-}"; cmd_pull "$city"; cmd_restart "$city" "$profile"; }
cmd_status()  { local city="$1"; require_city "$city"; dc "$city" --profile all ps; }

cmd_logs() {
  local city="${1:?city name required}"; shift
  require_city "$city"
  dc "$city" --profile all logs -f "$@"
}

cmd_sync() {
  echo "==> Advancing submodules to latest tracked branch..."
  git -C "$ROOT" submodule update --remote --merge
  if ! git -C "$ROOT" diff --quiet HEAD -- db sources 2>/dev/null; then
    git -C "$ROOT" add db sources
    git -C "$ROOT" commit -m "chore: bump submodules to latest"
    echo "Submodule pointers updated and committed."
  else
    echo "Submodules already up to date."
  fi
}

# ── central DB commands ───────────────────────────────────────────────────────

cmd_db_start() {
  if [[ ! -f "$DB_ENV" ]]; then
    echo "ERROR: $DB_ENV not found — copy db/centralDbCreation/.env.example to .env and fill in values"
    exit 1
  fi
  dc_db up -d
}

cmd_db_stop()    { dc_db down; }
cmd_db_restart() { dc_db restart; }
cmd_db_logs()    { dc_db logs -f "$@"; }
cmd_db_status()  { dc_db ps; }

cmd_deploy() {
  local city="${1:?city name required}" svc="${2:?service name required}"
  require_city "$city"; require_env "$city"
  echo "==> Pulling $svc for $city..."
  dc "$city" pull "$svc"
  echo "==> Restarting $svc..."
  dc "$city" up -d --no-deps "$svc"
}

cmd_topics() {
  local city="${1:?city name required}"
  require_city "$city"
  docker exec "analyticity-${city}-redpanda-1" rpk topic list --brokers=redpanda:9092
}

# ── dispatch ──────────────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && usage
COMMAND="$1"; shift

case "$COMMAND" in
  list)       cmd_list ;;
  sync)       cmd_sync ;;
  setup)      cmd_setup "${1:-}" ;;
  logs)       cmd_logs "${1:-}" "${@:2}" ;;
  deploy)     cmd_deploy "${1:-}" "${2:-}" ;;
  topics)     cmd_topics "${1:-}" ;;
  ports)      cmd_ports "${1:-}" ;;
  db:start)   cmd_db_start ;;
  db:stop)    cmd_db_stop ;;
  db:restart) cmd_db_restart ;;
  db:logs)    cmd_db_logs "$@" ;;
  db:status)  cmd_db_status ;;
  start|restart|update)
    TARGET="${1:---all}"; PROFILE="${2:-}"
    if [[ "$TARGET" == "--all" ]]; then
      each_city "cmd_$COMMAND"
    else
      "cmd_$COMMAND" "$TARGET" "$PROFILE"
    fi
    ;;
  stop|pull|status)
    TARGET="${1:---all}"
    if [[ "$TARGET" == "--all" ]]; then
      each_city "cmd_$COMMAND"
    else
      "cmd_$COMMAND" "$TARGET"
    fi
    ;;
  *) echo "Unknown command: $COMMAND"; usage ;;
esac

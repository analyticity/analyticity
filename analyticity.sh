#!/usr/bin/env bash
# analyticity.sh — central management script for the Analyticity platform
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CITIES_DIR="$ROOT/cities"
DB_COMPOSE="$ROOT/db/centralDbCreation/docker-compose.yml"
DB_ENV="$ROOT/db/centralDbCreation/.env"
DATA_COMPOSE="$ROOT/sources/data_model/infrastructure/compose/dev/docker-compose.yml"
DATA_COMPOSE_DIR="$ROOT/sources/data_model/infrastructure/compose/dev"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

  City app services (api, traffic-jams-backend, admin-backend, ui):
    list                         List all configured cities
    setup   <city>               Create a new city from template
    start   [city|--all]         Start app services
    stop    [city|--all]         Stop app services
    restart [city|--all]         Restart app services
    pull    [city|--all]         Pull latest images from registry
    update  [city|--all]         Pull + restart
    logs    <city> [service]     Tail logs (optionally one service)
    status  [city|--all]         Show running containers
    sync                         Advance submodules to latest tracked branch

  Central DB (shared, runs once per server):
    db:start                     Start central DB + pgAdmin
    db:stop                      Stop central DB
    db:restart                   Restart central DB
    db:logs                      Tail central DB logs
    db:status                    Show central DB containers

  Data model / local city stack (TimescaleDB + Redpanda + extractors):
    data:up       <city> [profile]   Start data stack  (default profile: infra)
    data:down     <city>             Stop and remove volumes
    data:restart  <city> [profile]   Restart data stack
    data:status   <city>             Show data stack containers
    data:logs     <city> [service]   Tail data stack logs
    data:topics   <city>             List Kafka topics in Redpanda

  Profiles for data:up / data:restart:
    infra       postgres-timescale + redpanda  (default)
    tools       + pgadmin, redpanda-console
    extract     + waze-feed, ndic-closures, police-accidents
    transform   + db-migrate, all transformers, event-linker
    apps        extract + transform
    mon         + otel, jaeger, prometheus, grafana
    all         everything

Examples:
  $(basename "$0") db:start
  $(basename "$0") setup orp_liberec
  $(basename "$0") data:up brno infra
  $(basename "$0") data:up brno apps
  $(basename "$0") start brno
  $(basename "$0") update --all
  $(basename "$0") logs brno api
  $(basename "$0") data:logs brno waze-feed
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

# docker compose for data model stack — project: analyticity-<city>-data
# Reads env from city's .env so city-specific vars (WAZE_URL, BBOX_*, etc.) override defaults
dc_data() {
  local city="$1"; shift
  docker compose \
    --project-name "analyticity-${city}-data" \
    --env-file "$(city_dir "$city")/.env" \
    -f "$DATA_COMPOSE" \
    "$@"
}

require_data_model() {
  if [[ ! -f "$DATA_COMPOSE" ]]; then
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

cmd_start()   { local city="$1"; require_city "$city"; require_env "$city"; dc "$city" up -d; }
cmd_stop()    { local city="$1"; require_city "$city"; dc "$city" down; }
cmd_restart() { local city="$1"; require_city "$city"; require_env "$city"; dc "$city" restart; }
cmd_pull()    { local city="$1"; require_city "$city"; require_env "$city"; dc "$city" pull; }
cmd_update()  { local city="$1"; cmd_pull "$city"; cmd_restart "$city"; }
cmd_status()  { local city="$1"; require_city "$city"; dc "$city" ps; }

cmd_logs() {
  local city="${1:?city name required}"; shift
  require_city "$city"
  dc "$city" logs -f "$@"
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

# ── data model commands ───────────────────────────────────────────────────────

cmd_data_up() {
  local city="${1:?city name required}"
  local profile="${2:-infra}"
  require_city "$city"; require_env "$city"; require_data_model

  if [[ "$profile" == "infra" ]]; then
    # infra = core services only, no profile flag needed
    dc_data "$city" up -d
  else
    dc_data "$city" --profile "$profile" up -d
  fi
}

cmd_data_down() {
  local city="${1:?city name required}"
  require_data_model
  dc_data "$city" --profile all down -v
}

cmd_data_restart() {
  local city="${1:?city name required}"
  local profile="${2:-infra}"
  require_city "$city"; require_env "$city"; require_data_model

  if [[ "$profile" == "infra" ]]; then
    dc_data "$city" restart
  else
    dc_data "$city" --profile "$profile" restart
  fi
}

cmd_data_status() {
  local city="${1:?city name required}"
  require_data_model
  dc_data "$city" --profile all ps -a
}

cmd_data_logs() {
  local city="${1:?city name required}"; shift
  require_data_model
  dc_data "$city" --profile all logs -f "$@"
}

cmd_data_topics() {
  local city="${1:?city name required}"
  require_data_model
  docker exec "$(dc_data "$city" --profile all ps -q redpanda 2>/dev/null || echo redpanda)" \
    rpk topic list --brokers=redpanda:9092
}

# ── dispatch ──────────────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && usage
COMMAND="$1"; shift

case "$COMMAND" in
  list)          cmd_list ;;
  sync)          cmd_sync ;;
  setup)         cmd_setup "${1:-}" ;;
  logs)          cmd_logs "${1:-}" "${@:2}" ;;
  db:start)      cmd_db_start ;;
  db:stop)       cmd_db_stop ;;
  db:restart)    cmd_db_restart ;;
  db:logs)       cmd_db_logs "$@" ;;
  db:status)     cmd_db_status ;;
  data:up)       cmd_data_up "${1:-}" "${2:-infra}" ;;
  data:down)     cmd_data_down "${1:-}" ;;
  data:restart)  cmd_data_restart "${1:-}" "${2:-infra}" ;;
  data:status)   cmd_data_status "${1:-}" ;;
  data:logs)     cmd_data_logs "${1:-}" "${@:2}" ;;
  data:topics)   cmd_data_topics "${1:-}" ;;
  start|stop|restart|pull|update|status)
    TARGET="${1:---all}"
    if [[ "$TARGET" == "--all" ]]; then
      each_city "cmd_$COMMAND"
    else
      "cmd_$COMMAND" "$TARGET"
    fi
    ;;
  *) echo "Unknown command: $COMMAND"; usage ;;
esac

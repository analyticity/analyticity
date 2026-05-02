#!/usr/bin/env bash
# analyticity.sh — central management script for the Analyticity platform
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CITIES_DIR="$ROOT/cities"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  setup   <city>          Create a new city from template
  start   [city|--all]    Start services for a city (or all cities)
  stop    [city|--all]    Stop services for a city (or all cities)
  restart [city|--all]    Restart services for a city (or all cities)
  pull    [city|--all]    Pull latest images for a city (or all cities)
  update  [city|--all]    Sync submodules + pull images + restart
  sync                    Advance submodules to latest tracked branch + commit
  logs    <city> [svc]    Tail logs for a city (optionally one service)
  status  [city|--all]    Show running containers
  list                    List all configured cities

Examples:
  $(basename "$0") setup orp_liberec
  $(basename "$0") start brno
  $(basename "$0") pull --all
  $(basename "$0") update orp_most
  $(basename "$0") logs brno api
  $(basename "$0") status --all
EOF
  exit 1
}

# ── helpers ─────────────────────────────────────────────────────────────────

city_dir() { echo "$CITIES_DIR/$1"; }

require_city() {
  local city="$1"
  local dir
  dir="$(city_dir "$city")"
  if [[ ! -f "$dir/docker-compose.yml" ]]; then
    echo "ERROR: City '$city' not found (missing $dir/docker-compose.yml)"
    exit 1
  fi
}

require_env() {
  local city="$1"
  local dir
  dir="$(city_dir "$city")"
  if [[ ! -f "$dir/.env" ]]; then
    echo "ERROR: $dir/.env not found — copy .env.example to .env and fill in values"
    exit 1
  fi
}

dc() {
  local city="$1"; shift
  docker compose -f "$(city_dir "$city")/docker-compose.yml" "$@"
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

# ── commands ────────────────────────────────────────────────────────────────

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
  cp "$ROOT/templates/docker-compose.yml" "$dir/docker-compose.yml"
  cp "$ROOT/templates/.env.example"       "$dir/.env.example"
  cp "$ROOT/templates/.env.example"       "$dir/.env"
  echo "Created $dir"
  echo "Fill in credentials: $dir/.env  (file is gitignored, never committed)"
}

cmd_start() {
  local city="$1"
  require_city "$city"; require_env "$city"
  dc "$city" up -d
}

cmd_stop() {
  local city="$1"
  require_city "$city"
  dc "$city" down
}

cmd_restart() {
  local city="$1"
  require_city "$city"; require_env "$city"
  dc "$city" restart
}

cmd_pull() {
  local city="$1"
  require_city "$city"; require_env "$city"
  dc "$city" pull
}

cmd_sync() {
  echo "==> Advancing submodules to latest tracked branch..."
  git -C "$ROOT" submodule update --remote --merge
  # commit only if something actually changed
  if ! git -C "$ROOT" diff --quiet HEAD -- db sources 2>/dev/null; then
    git -C "$ROOT" add db sources
    git -C "$ROOT" commit -m "chore: bump submodules to latest"
    echo "Submodule pointers updated and committed."
  else
    echo "Submodules already up to date."
  fi
}

cmd_update() {
  local city="$1"
  cmd_pull "$city"
  cmd_restart "$city"
}

cmd_logs() {
  local city="${1:?city name required}"; shift
  require_city "$city"
  dc "$city" logs -f "$@"
}

cmd_status() {
  local city="$1"
  require_city "$city"
  dc "$city" ps
}

# ── dispatch ────────────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && usage
COMMAND="$1"; shift

case "$COMMAND" in
  list)    cmd_list ;;
  sync)    cmd_sync ;;
  setup)   cmd_setup "${1:-}" ;;
  logs)    cmd_logs "${1:-}" "${2:-}" ;;
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

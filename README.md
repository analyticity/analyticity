# Analyticity — Central Deployment Repository

This is the top-level operations repository for the Analyticity platform.  
It does **not** contain source code — it wires together the other repos and manages city deployments.

## Repository structure

```
analyticity/
├── analyticity.sh          # main management script
├── cities/
│   ├── brno/               # one folder per city
│   │   ├── docker-compose.yml
│   │   ├── .env.example    # template — commit this
│   │   └── .env            # real credentials — gitignored, never commit
│   └── orp_most/
│       ├── docker-compose.yml
│       ├── .env.example
│       └── .env
├── db/                     # git submodule — central DB (branch: deploy)
├── sources/                # git submodule — source code / packages repo
└── templates/              # skeleton used by `setup` command
```

### Submodules

| Path | Purpose | Tracked branch |
|------|---------|----------------|
| `db/` | Centrálna PostgreSQL+PostGIS DB — beží raz, zdieľaná všetkými mestami | `deploy` |
| `sources/` | Zdrojové kódy — CI z nich builduje ghcr.io images | TBD |

After cloning, initialise submodules:

```bash
git submodule update --init --recursive
```

## Architecture

```
                  ┌─────────────────────────────────┐
                  │        analyticity-network        │  (Docker external network)
                  │                                   │
                  │  ┌──────────────┐                 │
                  │  │  db_central  │  ← runs once    │
                  │  │  (PostGIS)   │    on the server │
                  │  └──────────────┘                 │
                  │        ▲       ▲                  │
                  │        │       │                  │
                  │  ┌─────┴──┐ ┌──┴──────┐          │
                  │  │  brno  │ │orp_most │  ...      │
                  │  │services│ │services │          │
                  │  └────────┘ └─────────┘          │
                  └─────────────────────────────────┘
```

Každé mesto beží ako samostatná sada kontajnerov na rovnakej `analyticity-network` Docker sieti.  
Centrálna DB (`db_central`) beží raz — mestá sa k nej pripájajú cez container name.

## Prerequisites

- Docker + Docker Compose v2
- Docker network `analyticity-network` (vytvor raz na serveri):
  ```bash
  docker network create analyticity-network
  ```
- Prístup ku `ghcr.io/analyticity` — prihlás sa PAT-om so scopom `read:packages`:
  ```bash
  echo "<PAT>" | docker login ghcr.io -u <github-username> --password-stdin
  ```

## Quick start — nový server

### 1. Centrálna DB (raz)

```bash
git clone --recurse-submodules git@github.com:Analyticity/analyticity.git
cd analyticity

# Nakonfiguruj centrálnu DB
cp db/centralDbCreation/.env.example db/centralDbCreation/.env
nano db/centralDbCreation/.env   # nastav heslo a názov DB

# Spusti centrálnu DB
docker compose -f db/centralDbCreation/docker-compose.yml up -d
```

### 2. Pridaj mesto

```bash
# Vyplň .env (vygenerovaný automaticky príkazom setup)
nano cities/brno/.env   # doplň POSTGRES_PASSWORD_CENTRAL a porty

# Spusti
./analyticity.sh start brno
```

## analyticity.sh — command reference

```
./analyticity.sh <command> [options]

  list                    Zobraz zoznam nakonfigurovaných miest
  setup   <city>          Vytvor nové mesto zo šablóny
  sync                    Posuň submoduly na latest commit sledovanej vetvy
  start   [city|--all]    Spusti služby
  stop    [city|--all]    Zastav služby
  restart [city|--all]    Reštartuj služby
  pull    [city|--all]    Stiahni najnovšie images z registry
  update  [city|--all]    Sync submoduly + pull images + restart
  logs    <city> [svc]    Zobraz logy (voliteľne iba jednej služby)
  status  [city|--all]    Zobraz bežiace kontajnery
```

### Common workflows

```bash
# Nasadiť novú verziu do všetkých miest
./analyticity.sh update --all

# Nasadiť iba do jedného mesta
./analyticity.sh update brno

# Pridať nové mesto
./analyticity.sh setup orp_liberec
nano cities/orp_liberec/.env      # doplň heslá a porty
./analyticity.sh start orp_liberec

# Skontrolovať čo beží všade
./analyticity.sh status --all

# Sledovať logy API pre brno
./analyticity.sh logs brno api
```

## Environment variables (.env)

Každé mesto má vlastný `.env` (gitignored — nikdy necommituj).  
Hodnoty `POSTGRES_*_CENTRAL` musia byť rovnaké ako v `db/centralDbCreation/.env`.

| Variable | Popis |
|----------|-------|
| `REGISTRY` | Image registry (default `ghcr.io/analyticity`) |
| `IMAGE_TAG` | Tag image na nasadenie (default `latest`) |
| `API_PORT` | Host port pre API |
| `TRAFFIC_BACKEND_PORT` | Host port pre traffic-jams-backend |
| `ADMIN_BACKEND_PORT` | Host port pre admin-backend |
| `UI_PORT` | Host port pre UI |
| `CENTRAL_DB_HOST` | Hostname centrálnej DB (`db_central` ak na rovnakej sieti) |
| `CENTRAL_DB_PORT` | Port centrálnej DB (default `5432`) |
| `POSTGRES_DB_CENTRAL` | Názov centrálnej DB (musí súhlasiť s `db/.env`) |
| `POSTGRES_USER_CENTRAL` | Používateľ centrálnej DB |
| `POSTGRES_PASSWORD_CENTRAL` | Heslo centrálnej DB |

## Submodule branch tracking

Submoduly sledujú konkrétnu vetvu (`db` → `deploy`).  
Parent repo ukladá SHA commitu — verzia je vždy reprodukovateľná.  
`sync` posunie SHA na aktuálny tip sledovanej vetvy a commitne zmenu.

```bash
# Posunúť submoduly na latest
./analyticity.sh sync

# Pushnúť aby ostatné nasadenia videli nový pointer
git push
```

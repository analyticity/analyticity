# Analyticity — Central Deployment Repository

Operačné repo pre platformu Analyticity. **Neobsahuje zdrojový kód** — prepája ostatné repozitáre a riadi nasadenie miest cez Docker Compose.

---

## Čo je Analyticity?

Platforma na zber, spracovanie a vizualizáciu dopravných dát (nehody, dopravné zápchy, uzávierky) pre slovenské a české mestá. Každé mesto beží ako samostatná sada Docker kontajnerov a má vlastnú databázu.

---

## Architektúra

```
                        PREHLIADAC
                    http://localhost:80
                           |
                           v
         +---------------------------------------+
         |  bp-ux-ui  (React / Vite, nginx)      |
         |  Webova mapa s dopravnymi udalostami   |
         +--------+------------------------------++
                  |                    |
              /api/v1              /api/v1
                  |                    |
      +-----------+------+  +----------+---------+  +------------------+
      |  api (FastAPI)   |  | traffic-jams-       |  | admin-backend    |
      |  port 8000       |  | backend (FastAPI+ML)|  | (FastAPI + JWT)  |
      |                  |  | port 8081           |  | port 8082        |
      +--------+---------+  +----------+----------+  +--------+---------+
               |                       |                       |
               v                       v                       v
      +-------------------------------------------------------------------+
      |           postgres-timescale  (TimescaleDB + PostGIS)             |
      |           mestska DB -- nehody, zapchy, uzavierky, OSM            |
      +-------------------------------------------------------------------+
               ^                       ^
               |         Kafka         |
      +-------------------------------------------------------------------+
      |                      redpanda  (Kafka)                            |
      +----+------------------------------+-------------------------------+
           |                              |
           v                              v
      +---------+    +----------------------------------------------+
      | waze-   |    |  transformery (Quarkus)                      |
      | feed    |    |  jams / alerts / accidents / closures        |
      +---------+    |  + event-linker                              |
           ^         +----------------------------------------------+
           |                              ^
      +-----------+           +-----------+--------+
      | police-   |           |  ndic-closures     |
      | accidents |           |  (NDIC API)        |
      +-----------+           +--------------------+

  Zdielane pre vsetky mesta (bezi raz):
      +-------------------------------------------------------------------+
      |  db_central  (PostGIS)  -- pouzivatelia, admin data               |
      +-------------------------------------------------------------------+
```

**Tok dát:**
1. `waze-feed` / `police-accidents` / `ndic-closures` sťahujú surové dáta a posielajú ich do Kafka tém
2. Transformery konzumujú Kafka témy, normalizujú dáta a zapisujú do `postgres-timescale`
3. `event-linker` prepája nehody so zápchovými udalosťami
4. `api` + `traffic-jams-backend` čítajú z DB a servujú REST endpointy
5. `bp-ux-ui` zobrazuje dáta na mape

---

## Štruktúra repozitára

```
analyticity/
├── analyticity.sh              # hlavný riadiaci skript
├── README.md
│
├── cities/                     # konfigurácia jednotlivých miest
│   ├── brno/
│   │   ├── docker-compose.yml  # compose pre Brno (include: infraštruktúra + app services)
│   │   ├── .env.example        # šablóna — čo treba vyplniť
│   │   └── .env                # ← GITIGNORED, nikdy necommituj (heslá, porty)
│   └── orp_most/
│       ├── docker-compose.yml
│       ├── .env.example
│       └── .env
│
├── templates/                  # šablóna pre nové mestá (./analyticity.sh setup <mesto>)
│   ├── docker-compose.yml
│   └── .env.example
│
├── db/                         # submodule: centrálna DB (zdieľaná)
│   └── centralDbCreation/
│       ├── docker-compose.yml
│       └── .env                # ← GITIGNORED
│
└── sources/                    # submoduly — zdrojový kód (nerob tu zmeny priamo)
    ├── backend/                # api, AdminBackend, TrafficJamsBackend
    ├── ui/                     # bp-ux-ui (React)
    └── data_model/
        ├── infrastructure/     # docker-compose pre TimescaleDB + Redpanda
        ├── db_migrate/         # Flyway migrácie + OSM import
        ├── waze/
        ├── ndic_closures/
        ├── police_accidents_extractor/
        ├── jams_transformers/
        ├── alerts_transformator/
        ├── closures-transformer/
        ├── accidents-transformer/
        └── event_linker/
```

---

## Prvé spustenie od nuly (krok za krokom)

### Čo potrebuješ nainštalovaný

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (alebo Docker Engine na Linuxe)
- Git
- Prístup do GitHub Container Registry (`ghcr.io/analyticity`) — potrebuješ Personal Access Token

### 1. Stiahni repozitár

```bash
git clone --recurse-submodules git@github.com:analyticity/analyticity.git
cd analyticity
```

> Ak si zabudol `--recurse-submodules`, dobehnúť to môžeš:
> ```bash
> git submodule update --init --recursive
> ```

### 2. Posuň submoduly na aktuálnu verziu

```bash
./analyticity.sh sync
```

### 3. Vytvor zdieľanú Docker sieť (raz na celý počítač/server)

```bash
docker network create analyticity-network
```

### 4. Prihlás sa do GitHub Container Registry

```bash
echo "<PERSONAL_ACCESS_TOKEN>" | docker login ghcr.io -u <github-username> --password-stdin
```

Token potrebuje scope `read:packages`.

### 5. Spusti centrálnu DB (raz na celý server, beží stále)

```bash
# Skopíruj a vyplň .env pre centrálnu DB
cp db/centralDbCreation/.env.example db/centralDbCreation/.env
# Uprav db/centralDbCreation/.env — nastav heslá

./analyticity.sh db:start
```

### 6. Priprav konfiguráciu pre mesto

```bash
# Pre existujúce mestá — skopíruj .env.example do .env a vyplň
cp cities/brno/.env.example cities/brno/.env
# Uprav cities/brno/.env — nastav heslá, BBOX, VITE_APP_* premenné
```

> **Pre nové mesto** použi `setup` príkaz:
> ```bash
> ./analyticity.sh setup orp_liberec
> # Potom vyplň cities/orp_liberec/.env
> ```

### 7. Skontroluj portové konflikty

```bash
./analyticity.sh ports brno
```

Ak beží viac miest na jednom počítači, každé musí mať iné porty (nastav v `.env`).

### 8. Stiahni images a spusti

```bash
./analyticity.sh pull brno
./analyticity.sh start brno
```

> **Prvé spustenie trvá 10–30 minút** — `db-migrate` importuje OpenStreetMap dáta.
> API medzitým beží a servuje ukážkové dáta. Keď je DB pripravená, automaticky prepne.

---

## Čo vyplniť v `.env` pri novom meste

Skopíruj `templates/.env.example` do `cities/<mesto>/.env` a vyplň:

| Premenná | Popis | Príklad |
|----------|-------|---------|
| `API_PORT`, `UI_PORT`, ... | Porty dostupné z prehliadača — musia byť unikátne pre každé mesto | Brno: 80/8000, Most: 8100/8101 |
| `POSTGRES_PASSWORD` | Heslo pre mestskú TimescaleDB | `brno_timescale_pass` |
| `DB_CENTRAL_PASSWORD` | Heslo pre zdieľanú centrálnu DB | rovnaká vo všetkých mestách |
| `SECRET_KEY` | JWT kľúč pre admin backend — generuj: `openssl rand -hex 64` | |
| `WAZE_URL` | URL Waze Partner Hub feeder-u pre dané mesto | |
| `POLICE_REGION` | Skratka kraja pre políciu | `JHM`, `ULK`, ... |
| `BBOX_MIN_LON/LAT`, `BBOX_MAX_LON/LAT` | Geografický bounding box mesta | |
| `VITE_APP_CENTER_LON` | Stred mapy = `(BBOX_MIN_LON + BBOX_MAX_LON) / 2` | `16.6` pre Brno |
| `VITE_APP_CENTER_LAT` | Stred mapy = `(BBOX_MIN_LAT + BBOX_MAX_LAT) / 2` | `49.2` pre Brno |
| `VITE_APP_CITY` | Názov mesta zobrazený v UI | `Brno`, `ORP Most` |

### Predpripravené hodnoty pre existujúce mestá

**Brno**
```
BBOX_MIN_LON=16.4
BBOX_MIN_LAT=49.1
BBOX_MAX_LON=16.8
BBOX_MAX_LAT=49.3
OSM_BBOX=16.4,49.1,16.8,49.3
VITE_APP_CENTER_LON=16.6
VITE_APP_CENTER_LAT=49.2
VITE_APP_CITY=Brno
```

**ORP Most**
```
BBOX_MIN_LON=13.35
BBOX_MIN_LAT=50.43
BBOX_MAX_LON=13.82
BBOX_MAX_LAT=50.68
OSM_BBOX=13.35,50.43,13.82,50.68
VITE_APP_CENTER_LON=13.585
VITE_APP_CENTER_LAT=50.555
VITE_APP_CITY=ORP Most
```

---

## Viac miest na jednom serveri

Každé mesto musí mať **unikátne porty** — nastav ich v `cities/<mesto>/.env`:

| | Brno (default) | ORP Most |
|--|--|--|
| UI | 80 | 8100 |
| API | 8000 | 8101 |
| Traffic Jams Backend | 8081 | 8102 |
| Admin Backend | 8082 | 8103 |
| postgres-timescale | 5432 | 5532 |
| Redpanda (Kafka ext) | 19092 | 19192 |

Pred spustením vždy skontroluj: `./analyticity.sh ports <mesto>`

---

## Bežné operácie

```bash
# Nasadiť novú verziu jednej služby (napr. po update UI)
./analyticity.sh deploy brno bp-ux-ui
./analyticity.sh deploy brno api

# Nasadiť všetky služby mesta
./analyticity.sh pull brno && ./analyticity.sh restart brno

# Nasadiť do všetkých miest naraz
./analyticity.sh update --all

# Logy konkrétnej služby
./analyticity.sh logs brno api
./analyticity.sh logs brno db-migrate    # sleduj OSM import (prvé spustenie)
./analyticity.sh logs brno waze-feed

# Stav kontajnerov
./analyticity.sh status brno

# Zastav mesto (dáta zostanú zachované)
./analyticity.sh stop brno

# RESET mesta — ZMAŽE VŠETKY DÁTA
docker compose --project-name analyticity-brno --profile all down -v
./analyticity.sh start brno
```

---

## analyticity.sh — všetky príkazy

```
./analyticity.sh <command> [options]

  Mestá:
    list                           Zoznam nakonfigurovaných miest
    setup   <mesto>                Vytvor nové mesto zo šablóny
    ports   <mesto>                Skontroluj portové konflikty pred štartom
    start   <mesto|--all> [profil] Spusti (kontroluje porty, default profil: all)
    stop    <mesto|--all>          Zastav (dáta zachované)
    restart <mesto|--all> [profil] Reštartuj
    pull    <mesto|--all>          Stiahni najnovšie Docker images
    update  <mesto|--all>          Pull + restart
    deploy  <mesto> <služba>       Pull + reštart jednej služby (napr. api, bp-ux-ui)
    logs    <mesto> [služba]       Logy (voliteľne iba jednej služby)
    status  <mesto|--all>          Bežiace kontajnery
    sync                           Posuň všetky submoduly na latest

  Centrálna DB:
    db:start                       Spusti centrálnu DB + pgAdmin
    db:stop                        Zastav centrálnu DB
    db:restart                     Reštartuj centrálnu DB
    db:logs                        Logy centrálnej DB
    db:status                      Stav centrálnej DB
```

### Profily (pre start/restart)

| Profil | Čo spustí |
|--------|-----------|
| `all` *(default)* | všetko |
| `tools` | + pgAdmin (5050), Redpanda Console (8080) |
| `extract` | + waze-feed, ndic-closures, police-accidents |
| `transform` | + db-migrate, transformery, event-linker |
| `apps` | extract + transform |
| `mon` | + otel-collector, jaeger, prometheus, grafana |

---

## Prístupy k službám — Brno

### Aplikácia

| Služba | URL |
|--------|-----|
| Webová aplikácia | http://localhost |
| API (Swagger) | http://localhost:8000/docs |
| Traffic Jams Backend (Swagger) | http://localhost:8081/docs |
| Admin Backend (Swagger) | http://localhost:8082/docs |

### Nástroje (profil `tools`)

| Služba | URL | Prihlásenie |
|--------|-----|-------------|
| pgAdmin (mestská DB) | http://localhost:5050 | `admin@admin.com` / `admin` |
| Redpanda Console | http://localhost:8080 | — |
| pgAdmin (centrálna DB) | http://localhost:5051 | `admin@admin.com` / `admin` |

### Priame pripojenie k DB (napr. DBeaver)

**Mestská TimescaleDB:**
| | |
|-|-|
| Host | `localhost` |
| Port | `5432` |
| Database | `traffic` |
| Username | `traffic` |
| Password | z `cities/brno/.env` → `POSTGRES_PASSWORD` |

**Centrálna DB:**
| | |
|-|-|
| Host | `localhost` |
| Port | `5431` |
| Database | `central_db` |
| Username | `db` |
| Password | z `db/centralDbCreation/.env` |

### Monitoring (profil `mon`)

| Služba | URL |
|--------|-----|
| Grafana | http://localhost:3000 (`admin`/`admin`) |
| Prometheus | http://localhost:9090 |
| Jaeger | http://localhost:16686 |

---

## Submoduly

| Cesta | Repozitár | Vetva |
|-------|-----------|-------|
| `db/` | `analyticity/central_analyticity_db` | `deploy` |
| `sources/backend/` | `analyticity/api` | `deploy` |
| `sources/ui/` | `analyticity/bp_ux_ui` | `deploy` |
| `sources/data_model/infrastructure/` | `DP-Traffic/infrastructure` | `main` |
| `sources/data_model/waze/` | `DP-Traffic/waze` | `main` |
| `sources/data_model/ndic_closures/` | `DP-Traffic/ndic_closures` | `main` |
| `sources/data_model/police_accidents_extractor/` | `DP-Traffic/police_accidents_extractor` | `main` |
| `sources/data_model/jams_transformers/` | `DP-Traffic/jams_transformers` | `main` |
| `sources/data_model/alerts_transformator/` | `DP-Traffic/alerts_transformator` | `main` |
| `sources/data_model/closures-transformer/` | `DP-Traffic/closures-transformer` | `main` |
| `sources/data_model/accidents-transformer/` | `DP-Traffic/accidents-transformer` | `main` |
| `sources/data_model/db_migrate/` | `DP-Traffic/db_migrate` | `main` |
| `sources/data_model/event_linker/` | `DP-Traffic/event_linker` | `main` |

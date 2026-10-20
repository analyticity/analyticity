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
├── local/                      # lokálne spustenie na vývoj (./analyticity.sh local:up)
│   └── docker-compose.yml
│
└── sources/                    # submoduly — zdrojový kód (nerob tu zmeny priamo)
    ├── backend/                # analyticity/api — api, AdminBackend, TrafficJamsBackend
    ├── ui/                     # analyticity/web — bp-ux-ui (React)
    └── data-pipeline/          # analyticity/data-pipeline
        ├── infrastructure/     # docker-compose pre TimescaleDB + Redpanda
        ├── db_migrate/         # Flyway migrácie + OSM import
        ├── waze/  ndic_closures/  police_accidents_extractor/
        ├── jams_transformers/  alerts_transformator/  closures-transformer/  accidents-transformer/
        └── event_linker/
```

---

## Lokálne spustenie (vývoj a testovanie)

Spustí aplikáciu na vlastnom počítači bez Kafky, TimescaleDB a extraktorov: centrálna DB, `api` nad vzorovými dátami, `traffic-jams-backend` nad CSV, `admin-backend` a web. Images sa buildia zo zdrojákov, prístup do ghcr.io netreba.

Potrebuješ Docker Desktop. Na Apple Silicon sa Python backendy buildia pre `linux/amd64` (ako v CI), prvý build preto trvá niekoľko minút.

```bash
# Zo submodulov (verzie z vetiev deploy)
git submodule update --init
./analyticity.sh local:up

# Alebo z vlastných klonov vedľa analyticity/ (../api, ../web, ../central_analyticity_db)
# — na vyskúšanie rozpracovaných zmien
./analyticity.sh local:up --workspace
```

| Služba | URL |
|--------|-----|
| Web | http://localhost:8090 |
| API (Swagger) | http://localhost:8091/docs |
| Traffic Jams Backend | http://localhost:8092/docs |
| Admin Backend | http://localhost:8093/docs |
| Centrálna DB | `localhost:5439`, `db` / `local`, databáza `central_db` |

Porty sa dajú zmeniť, napr. `LOCAL_UI_PORT=9090 ./analyticity.sh local:up`. Prihlásenie do administrácie: `VutAdmin` / `Test` (zo seed dát centrálnej DB).

```bash
./analyticity.sh local:logs web     # logy jednej služby
./analyticity.sh local:status
./analyticity.sh local:down         # zastaví (dáta centrálnej DB ostanú)
./analyticity.sh local:reset        # zmaže dáta — pri ďalšom up sa DB znova naplní zo seedu
```

Po zmene kódu stačí znova `local:up` (prebuilduje zmenené images).

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

## Vydanie novej verzie

Každé repo má vetvu `main` (vývoj) a `deploy` (čo sa nasadzuje). Push do `deploy` zbuilduje nové images v GitHub Actions.

```bash
# 1. Ukáže commity z main, ktoré ešte nie sú v deploy, a po potvrdení ich zmerguje
./analyticity.sh release web      # alebo: api, central_analyticity_db, data-pipeline, simulations

# 2. Po dobehnutí buildu (odkaz vypíše príkaz) nasaď novú verziu
./analyticity.sh deploy brno bp-ux-ui
```

| Repo | Služby (images) |
|------|-----------------|
| `api` | `api`, `admin-backend`, `traffic-jams-backend` |
| `web` | `bp-ux-ui` |
| `central_analyticity_db` | `central-analyticity-db` |

`release` potrebuje [GitHub CLI](https://cli.github.com/) prihlásené cez `gh auth login`.

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

  Lokálne (vývoj):
    local:up [--workspace]         Zbuilduj a spusti centrálnu DB, backendy a web
    local:down                     Zastav (dáta centrálnej DB ostanú)
    local:reset                    Zastav a zmaž dáta centrálnej DB
    local:logs [služba]            Logy
    local:status                   Bežiace kontajnery

  Vydania:
    release <repo>                 main → deploy na GitHube (spustí build images)
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
| `sources/ui/` | `analyticity/web` | `deploy` |
| `sources/data-pipeline/` | `analyticity/data-pipeline` | `deploy` |

Images extraktorov a transformerov (`ghcr.io/dp-traffic/*`) sa zatiaľ stále buildia v pôvodných repozitároch DP-Traffic — CI workflowy v `data-pipeline` sú v podadresároch, kde ich GitHub nespúšťa.

Na serveri po prechode z DP-Traffic submodulov: `git pull && git submodule sync && git submodule update --init`.

## License

Copyright (C) 2026 Magdaléna Ondrušková

This program is free software: you can redistribute it and/or
modify it under the terms of the
[GNU Affero General Public License](LICENSE) as published by
the Free Software Foundation, either version 3 of the License,
or (at your option) any later version.

**What this means in practice.** You are free to use, study,
modify and redistribute this software, including for research
and teaching. If you modify it and make it available to others
over a network — for example by running your own instance of
the dashboard or API — you must offer those users the complete
corresponding source code of your modified version, under the
same license.

If you use this software in academic work, please cite it — see
[CITATION.cff](CITATION.cff).

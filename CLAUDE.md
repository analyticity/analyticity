# CLAUDE.md — Analyticity repo quick reference

## Čo je toto repo

Centrálne deployment repo pre platformu Analyticity (dopravné dáta — nehody, zápchy, uzávierky).
Neobsahuje zdrojový kód — len Docker Compose konfigurácie a riadiaci skript.
Každé mesto = samostatná sada kontajnerov s vlastnou DB.

---

## Štruktúra

```
analyticity/
├── CLAUDE.md                        # tento súbor
├── analyticity.sh                   # hlavný riadiaci skript (start/stop/deploy/logs/...)
├── infrastructure/
│   └── docker-compose.yml           # Analyticity-customizovaná verzia infra stacku
│                                    # (bez container_name, porty cez env vars)
│                                    # Sem treba robiť zmeny, NIE do sources/data-pipeline/infrastructure
├── local/
│   └── docker-compose.yml           # lokálny vývojový stack (local:up) — build zo zdrojákov,
│                                    # bez Kafky/TimescaleDB, api nad vzorovými dátami
├── cities/
│   ├── brno/
│   │   ├── docker-compose.yml       # include: infrastructure/ + app services
│   │   ├── .env.example             # šablóna s brno hodnotami
│   │   └── .env                     # GITIGNORED — reálne credentials
│   └── orp_most/
│       ├── docker-compose.yml
│       ├── .env.example
│       └── .env                     # GITIGNORED
├── templates/
│   ├── docker-compose.yml           # šablóna pre nové mestá (cmd: setup)
│   └── .env.example                 # šablóna s prázdnymi hodnotami
├── db/                              # submodule: central_analyticity_db (branch: deploy)
│   └── centralDbCreation/
│       ├── docker-compose.yml       # postgis/postgis:14-3.3 + pgadmin na porte 5051
│       └── .env                     # GITIGNORED v submodule
└── sources/                         # submoduly — NIKDY tu nerob zmeny priamo
    ├── backend/                     # analyticity/api (branch: deploy)
    ├── ui/                          # analyticity/web (branch: deploy)
    └── data-pipeline/               # analyticity/data-pipeline (branch: deploy)
        └── infrastructure/          # Originálny infra compose — nerob tu zmeny,
                                     # zmeny patria do infrastructure/docker-compose.yml
```

---

## Kľúčové pravidlo: sources/ je read-only

Nikdy nerob zmeny súborov v `sources/`. Sú to git submoduly spravované používateľkou samostatne v ich vlastných repozitároch. Ak treba niečo zmeniť v `sources/`, vysvetli čo a nechaj to na ňu.

Výnimka: `infrastructure/docker-compose.yml` v MAIN repo (nie v `sources/`) je miesto kde patria zmeny infra compose.

---

## Mestá a porty

| | Brno | ORP Most |
|--|--|--|
| UI | 80 | 8100 |
| API | 8000 | 8101 |
| postgres-timescale | 5432 | 5532 |
| redpanda kafka ext | 19092 | 19192 |
| redpanda schema-registry | 18081 | 18181 |
| redpanda proxy | 18082 | 18182 |
| pgadmin (infra) | 5050 | 5150 |
| redpanda-console | 8080 | 8180 |

Centrálna DB (zdieľaná): postgres na porte **5431**, pgadmin na **5051**.

Brno používa defaulty (env vars v infra compose majú brno hodnoty ako default).
ORP Most má všetky infra porty explicitne v `.env` (+100 offset).

---

## analyticity.sh — kľúčové príkazy

```bash
./analyticity.sh start <city> [profile]    # start (default profil: all)
./analyticity.sh stop <city>
./analyticity.sh restart <city> [profile]
./analyticity.sh deploy <city> <service>   # pull + up --no-deps jednej služby
./analyticity.sh pull <city>
./analyticity.sh logs <city> [service]
./analyticity.sh status <city>
./analyticity.sh ports <city>              # skontroluj portové konflikty
./analyticity.sh setup <city>              # nové mesto zo šablóny
./analyticity.sh sync                      # submoduly na latest
./analyticity.sh db:start / db:stop / db:logs / db:status
./analyticity.sh local:up [--workspace]     # lokálny stack (8090 web, 8091 api, 5439 DB)
./analyticity.sh local:down / local:reset / local:logs / local:status
./analyticity.sh release <repo>            # main → deploy na GitHube (gh api merges) → CI zbuilduje images
```

`local:up --workspace` builduje zo susedných klonov `../api`, `../web`, `../central_analyticity_db`
(premenné `BACKEND_SRC`, `UI_SRC`, `CENTRAL_DB_SRC` v `local/docker-compose.yml`), bez prepínača zo submodulov.

Profily: `all` (default), `tools`, `extract`, `transform`, `apps`, `mon`

Interná funkcia `dc()` vždy pridáva `--project-name analyticity-<city>` — kontajnery sa
volajú `analyticity-brno-redpanda-1`, `analyticity-orp_most-postgres-timescale-1` atď.

---

## Ako funguje include infra compose

Každý city compose má:
```yaml
include:
  - path: ../../infrastructure/docker-compose.yml       # main repo — upravená verzia
    project_directory: ../../sources/data-pipeline/infrastructure/compose/dev  # kde sú Dockerfile.db, otel config atď.
```

`project_directory` musí mieriť na submodul aby relatívne cesty pre build a volume mount fungovali.

---

## .env premenné — čo kde patrí

Každé `.env` riadi **všetko** pre dané mesto: app porty, infra porty, DB credentials, BBOX, UI premenné.

Kľúčové premenné:
- `VITE_API_BASE_URL` — URL API pre UI (runtime injection cez entrypoint v kontajneri)
- `VITE_APP_CENTER_LON/LAT` — stred mapy = `(BBOX_MIN + BBOX_MAX) / 2`
- `VITE_APP_CITY` — zobrazený názov mesta v UI (`Brno`, `ORP Most`)
- `POSTGRES_HOST_BRNO` — hostname DB pre API backend (vždy `postgres-timescale`, aj pre non-Brno mestá — historický artefakt v zdrojáku)
- `POSTGRES_TIMESCALE_PORT` — host port pre postgres (default 5432)
- `API_KEYS` — povolené API kľúče (čiarkou oddelené); bez nich api odmietne každú požiadavku na dáta (503). Klient posiela kľúč v hlavičke `X-API-Key`.
- `WEB_API_KEY` — kľúč, ktorý posiela web (`VITE_API_KEY` v `config.js`); musí byť jeden z `API_KEYS`

VITE_* premenné UI sa čítajú za behu: `docker-entrypoint.sh` v `sources/ui` pri štarte kontajnera zapíše `config.js` (`window.__APP_CONFIG__`), takže jeden image slúži všetkým mestám.

---

## Submoduly — vetvy

| Submodul | Repo | Vetva |
|----------|------|-------|
| `db/` | analyticity/central_analyticity_db | **deploy** |
| `sources/backend/` | analyticity/api | **deploy** |
| `sources/ui/` | analyticity/web | **deploy** |
| `sources/data-pipeline/` | analyticity/data-pipeline | **deploy** |

Pravidlo: všetky submoduly sledujú vetvu `deploy`. Images extraktorov/transformerov sú zatiaľ
`ghcr.io/dp-traffic/*` (buildia sa v pôvodných DP-Traffic repách).

---

## Dôležité quirky

1. **`container_name` v pôvodnom infra compose** — originál v `sources/data-pipeline/infrastructure` má hardcoded `container_name: redpanda` atď. Preto používame `infrastructure/docker-compose.yml` kde sú tieto odstránené. Bez toho by dve mestá na jednom stroji kolidovali.

2. **`POSTGRES_HOST_BRNO`** — premenná sa takto volá aj pre iné mestá ako Brno — je to historický artefakt v zdrojáku `sources/backend/db/connection_to_db.py`.

3. **Centrálna DB pgadmin** — beží na porte 5051 (nie 5050). Port 5050 používa pgadmin z infra stacku (mestská TimescaleDB).

4. **`cmd_topics`** v `analyticity.sh` — robí `docker exec analyticity-{city}-redpanda-1` — funguje len keď nie je `container_name` v compose (čo je prípad nášho `infrastructure/docker-compose.yml`).

5. **OSM import** — pri prvom spustení s profilom `transform`/`apps`/`all` beží `db-migrate` ktorý importuje OpenStreetMap dáta. Trvá 10–30 minút. API medzitým slúži example dáta a po dokončení prepne automaticky.

---

## Pridanie nového mesta

```bash
./analyticity.sh setup <nazov_mesta>
# Vyplniť cities/<nazov_mesta>/.env:
# - unikátne porty (app +200 od predchádzajúceho, infra +200)
# - BBOX_MIN/MAX_LON/LAT (geografický bounding box)
# - VITE_APP_CENTER_LON = (BBOX_MIN_LON + BBOX_MAX_LON) / 2
# - VITE_APP_CENTER_LAT = (BBOX_MIN_LAT + BBOX_MAX_LAT) / 2
# - VITE_APP_CITY = "Názov Mesta"
# - DB credentials, SECRET_KEY (openssl rand -hex 64), WAZE_URL, POLICE_REGION
# - API_KEYS + WEB_API_KEY (openssl rand -hex 32; WEB_API_KEY musí byť v API_KEYS)
./analyticity.sh ports <nazov_mesta>   # skontroluj pred štartom
./analyticity.sh start <nazov_mesta>
```

---

## Deploy na dexter.fit.vutbr.cz — druhá, nezávislá deploy vrstva

URL: **https://dexter.fit.vutbr.cz/analyticity/brno/**. Súbory v koreni repa:
`docker-compose.prod.yml` (db-central, api, web, proxy), `docker-compose.build.yml` (build + push
api a web do **dexter registry** `dexter.fit.vutbr.cz/analyticity/analyticity-{api,web}`, **iba z vetvy
`deploy`** cez submoduly `sources/backend` a `sources/ui`; `main` sa najprv overí a vydá cez `release`),
`nginx.conf` (projektová proxy), `.env.example`, `configure/sync-data` (`init_db_central.sql`).
Spravuje sa cez repo [Jirka/dexter](https://github.com/Jirka/dexter) (`projects/analyticity`
submodul, `dexter.sh build/push/remote-sync/remote-sync-data/remote-start analyticity`) —
**do toho repa nič nepushovať**, je Jiřího.

Tieto dve vrstvy sa nemiešajú:
- `cities/*/docker-compose.yml` + `infrastructure/docker-compose.yml` = vlastný postgres-timescale
  + redpanda + extractory, per-mesto, na vlastnej VM, images z `ghcr.io/analyticity` (CI).
- `docker-compose.prod.yml` = **žiadna vlastná DB/Kafka** — api sa cez externú Docker sieť
  `infrastructure-network` pripája na dátový stack, ktorý na dexteri beží **mimo tento repo**
  (Compose projekt `traffic`, `/home/lazy_lemour/magda/infrastructure`).

Viac miest = ďalšia sada services v `docker-compose.prod.yml` + `location` blok v `nginx.conf` +
`PROJECT_URL_PATHS_analyticity` v dexter repe.

Postup nasadenia (čisté nasadenie, API kľúče, policajný extraktor): repo docs,
`deploy-dexter/README.md`.

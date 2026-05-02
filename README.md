# Analyticity — Central Deployment Repository

Top-level operačné repo pre platformu Analyticity.  
**Neobsahuje zdrojový kód** — prepája ostatné repozitáre a riadi nasadenie miest.

---

## Štruktúra repozitára

```
analyticity/
├── analyticity.sh              # hlavný riadiaci skript
├── cities/
│   ├── SETUP_CITY.md           # podrobný postup nasadenia mesta  ← čítaj toto
│   ├── brno/
│   │   ├── docker-compose.yml
│   │   ├── .env.example        # šablóna — commitnutá
│   │   └── .env                # reálne heslá — gitignored, nikdy necommituj
│   └── orp_most/
│       ├── docker-compose.yml
│       ├── .env.example
│       └── .env
├── db/                         # submodule: centrálna DB  (branch: deploy)
├── sources/
│   └── backend/                # submodule: zdrojáky API  (github.com/analyticity/api)
└── templates/                  # šablóna pre nové mestá (používa `setup`)
```

---

## Submoduly

| Cesta | Repo | Sledovaná vetva | Účel |
|-------|------|----------------|------|
| `db/` | `analyticity/central_analyticity_db` | `deploy` | Centrálna PostgreSQL+PostGIS DB — beží raz pre všetky mestá |
| `sources/backend/` | `analyticity/api` | `main` | Zdrojové kódy — CI z nich builduje ghcr.io images |

Po klonovaní inicializuj submoduly:

```bash
git submodule update --init --recursive
```

---

## Architektúra

```
                  ┌──────────────────────────────────────────┐
                  │           analyticity-network             │
                  │                                           │
                  │   ┌──────────────┐                        │
                  │   │  db_central  │  ← jedna inštancia     │
                  │   │  (PostGIS)   │    pre celý server      │
                  │   └──────────────┘                        │
                  │     ▲        ▲                            │
                  │     │        │  (AdminBackend z každého mesta)
                  │                                           │
                  │  ┌──────────────┐  ┌──────────────┐      │
                  │  │     brno     │  │   orp_most   │ ...  │
                  │  │  api         │  │  api         │      │
                  │  │  traffic-jams│  │  traffic-jams│      │
                  │  │  admin       │  │  admin       │      │
                  │  │  ui          │  │  ui          │      │
                  │  │  local_db ←──┼──┼──────────────┘      │
                  │  └──────────────┘  (každé mesto má vlastnú local_db)
                  └──────────────────────────────────────────┘
```

Každé mesto tvorí samostatnú skupinu kontajnerov pomenovaných  
`analyticity-<mesto>-<service>-1`.

---

## Packages v `sources/backend`

| Package | Adresár | DB | Popis |
|---------|---------|----|-------|
| **api** | `api/`, `core/`, `db/`, `modules/` | city-local | Hlavné FastAPI — mapa, grafy, kontakt |
| **AdminBackend** | `AdminBackend/` | centrálna | Správa miest, používateľov, nastavení |
| **TrafficJamsBackend** | `TrafficJamsBackend/` | city-local | Analýza nehôd, clustering, ML predikcia |

---

## Predpoklady

- Docker + Docker Compose v2
- Docker network (raz na serveri): `docker network create analyticity-network`
- Prístup ku `ghcr.io/analyticity`:
  ```bash
  echo "<PAT>" | docker login ghcr.io -u <github-username> --password-stdin
  ```

---

## Rýchly štart

### 1. Klon s submodulmi

```bash
git clone --recurse-submodules git@github.com:analyticity/analyticity.git
cd analyticity
```

### 2. Centrálna DB  _(raz pre celý server)_

```bash
cp db/centralDbCreation/.env.example db/centralDbCreation/.env
nano db/centralDbCreation/.env    # nastav heslo

./analyticity.sh db:start
```

### 3. Nové mesto

```bash
./analyticity.sh setup orp_liberec
nano cities/orp_liberec/.env      # vyplň podľa cities/SETUP_CITY.md
./analyticity.sh start orp_liberec
```

> Podrobný postup s popisom každej premennej: **[cities/SETUP_CITY.md](cities/SETUP_CITY.md)**

---

## analyticity.sh — prehľad príkazov

```
./analyticity.sh <command> [options]

  Mestá:
    list                    Zoznam nakonfigurovaných miest
    setup   <city>          Vytvor nové mesto zo šablóny
    start   [city|--all]    Spusti služby
    stop    [city|--all]    Zastav služby
    restart [city|--all]    Reštartuj služby
    pull    [city|--all]    Stiahni najnovšie images z registry
    update  [city|--all]    Pull images + restart
    logs    <city> [svc]    Zobraz logy (voliteľne iba jednej služby)
    status  [city|--all]    Zobraz bežiace kontajnery

  Centrálna DB:
    db:start                Spusti centrálnu DB
    db:stop                 Zastav centrálnu DB
    db:restart              Reštartuj centrálnu DB
    db:logs                 Logy centrálnej DB
    db:status               Stav centrálnej DB

  Submoduly:
    sync                    Posuň submoduly na latest commit sledovanej vetvy
```

### Časté operácie

```bash
# Nasadiť novú verziu do všetkých miest
./analyticity.sh update --all

# Pridať nové mesto  (detaily v cities/SETUP_CITY.md)
./analyticity.sh setup orp_liberec
nano cities/orp_liberec/.env
./analyticity.sh start orp_liberec

# Sledovať logy API pre brno
./analyticity.sh logs brno api

# Stav všetkého
./analyticity.sh status --all
./analyticity.sh db:status
```

---

## Submodule branch tracking

Submoduly sledujú konkrétnu vetvu. `sync` posunie SHA pointer na aktuálny tip vetvy.

```bash
./analyticity.sh sync   # posunie db/ a sources/backend/ na latest
git push                # ostatné servery uvidia nový pointer
```

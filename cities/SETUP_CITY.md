# Postup nasadenia nového mesta

Tento dokument popisuje kompletný postup od prázdneho servera po bežiace mesto.  
Pre každé ďalšie mesto preskočíš kroky 1–3 (jednorazová infraštruktúra) a začínáš od kroku 4.

---

## Predpoklady

| Požiadavka | Poznámka |
|------------|---------|
| Docker + Docker Compose v2 | `docker compose version` |
| Prístup k `ghcr.io/analyticity` | PAT so scopom `read:packages` |
| SSH kľúč s prístupom na GitHub | pre klonovanie submodulov |

---

## Krok 1 — Jednorazová príprava servera

```bash
# Docker network pre celú platformu (raz za život servera)
docker network create analyticity-network

# Prihlásenie do GitHub Container Registry
echo "<PAT>" | docker login ghcr.io -u <github-username> --password-stdin
```

---

## Krok 2 — Klonovanie tohto repozitára

```bash
git clone --recurse-submodules git@github.com:analyticity/analyticity.git
cd analyticity
```

> `--recurse-submodules` stiahne aj `db/` (centrálna DB) a `sources/backend/` (zdrojáky).

---

## Krok 3 — Spustenie centrálnej DB  _(raz pre všetky mestá)_

Centrálna DB beží ako jedna inštancia na serveri. Obsahuje registráciu miest,
používateľov a nastavení.

```bash
# Nakonfiguruj centrálnu DB
cp db/centralDbCreation/.env.example db/centralDbCreation/.env
nano db/centralDbCreation/.env
```

Vyplň:

| Premenná | Popis |
|----------|-------|
| `POSTGRES_DB_CENTRAL` | Názov databázy (napr. `central_db`) |
| `POSTGRES_USER_CENTRAL` | Používateľ PostgreSQL |
| `POSTGRES_PASSWORD_CENTRAL` | **Zmeň z defaultu `admin`!** |
| `PGADMIN_EMAIL` | Prihlasovací email do pgAdmin |
| `PGADMIN_PASSWORD` | Heslo pgAdmin |

```bash
./analyticity.sh db:start

# Overenie
./analyticity.sh db:status
# Malo by zobraziť: analyticity-db_central-1, analyticity-pgadmin-1
```

pgAdmin beží na `http://<server>:8080`.

---

## Krok 4 — Vytvorenie nového mesta

```bash
./analyticity.sh setup <nazov_mesta>
# Príklad:
./analyticity.sh setup orp_liberec
```

Príkaz vytvorí `cities/orp_liberec/` s `docker-compose.yml`, `.env.example` a prázdnym `.env`.

---

## Krok 5 — Konfigurácia `.env`

```bash
nano cities/<nazov_mesta>/.env
```

### 5a. Registry a porty

```env
REGISTRY=ghcr.io/analyticity
IMAGE_TAG=latest

API_PORT=8000              # zmeň ak iné mesto už tento port používa
UI_PORT=80
```

> Každé mesto na rovnakom serveri musí mať **unikátne porty**.

### 5b. CORS

```env
ORIGINS=https://dexter.fit.vutbr.cz/analyticity/brno  # verejná URL frontendu tohto mesta
```

### 5c. Centrálna DB

Hodnoty skopíruj z `db/centralDbCreation/.env`:

```env
DB_CENTRAL_HOST=db_central            # container name — nemeniť
DB_CENTRAL_PORT=5432
DB_CENTRAL_NAME=central_db            # = POSTGRES_DB_CENTRAL z centrálnej DB
DB_CENTRAL_USER=db                    # = POSTGRES_USER_CENTRAL
DB_CENTRAL_PASSWORD=<rovnaké heslo>   # = POSTGRES_PASSWORD_CENTRAL
```

> ⚠️ **Poznámka:** api číta premenné `DB_CENTRAL_*` (nie `POSTGRES_*_CENTRAL`).  
> Toto je historická nezrovnalosť v zdrojovom kóde — premenné v `.env` tu pomenované správne.

### 5d. City-local DB

Táto DB beží ako súčasť docker-compose mesta (kontajner `local_db`).

```env
POSTGRES_HOST_BRNO=local_db     # container name — nemeniť
POSTGRES_PORT_BRNO=5432
POSTGRES_DB_BRNO=analyticity
POSTGRES_USER_BRNO=postgres
POSTGRES_PASSWORD_BRNO=<zvoľ heslo>
```

> ℹ️ Premenné majú suffix `_BRNO` pre všetky mestá — je to historický artefakt  
> v zdrojovom kóde API. Hodnoty sú city-specific napriek názvom.

### 5e. Rizikové úseky (súčasť api)

Používajú tú istú mestskú DB ako zvyšok api (`POSTGRES_*_BRNO`), netreba nič navyše. Voliteľne:

```env
DBSCAN_EPS_METERS=100.0
DBSCAN_MIN_SAMPLES=3
AUTO_CLUSTER_ON_STARTUP=false
WORKERS=2
```

### 5f. Prihlásenie do administrácie — JWT secret

Vygeneruj unikátny kľúč pre každé mesto:

```bash
openssl rand -hex 64
```

```env
SECRET_KEY=<výstup z openssl>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=7
```

### 5g. Email (voliteľné)

```env
EMAIL_HOST=smtp.seznam.cz
EMAIL_PORT=465
EMAIL_USE_SSL=1
EMAIL_HOST_USER=notifikace@example.cz
EMAIL_HOST_PASSWORD=<heslo>
DEFAULT_FROM_EMAIL=notifikace@example.cz
EMAIL_RECIPIENT=spravca@example.cz
```

---

## Krok 6 — Spustenie mesta

```bash
./analyticity.sh start <nazov_mesta>

# Overenie
./analyticity.sh status <nazov_mesta>
```

Kontajnery budú pomenované `analyticity-<mesto>-<service>-1`, napr.:
```
analyticity-orp_liberec-api-1
analyticity-orp_liberec-web-1
```

### Porty

| Služba | Port (default) |
|--------|---------------|
| API | `API_PORT` (8000) |
| UI | `UI_PORT` (80) |

---

## Krok 7 — Overenie

```bash
# Logy API
./analyticity.sh logs <nazov_mesta> api

# Logy všetkých služieb
./analyticity.sh logs <nazov_mesta>

# Stav všetkých miest
./analyticity.sh status --all
```

---

## Aktualizácia na novú verziu

```bash
# Aktualizuj jedno mesto
./analyticity.sh update <nazov_mesta>

# Alebo všetky naraz
./analyticity.sh update --all
```

`update` = stiahne nové images z ghcr.io + reštartuje služby.

---

## Zhrnutie premenných

| Premenná | Používa ju | Zdroj hodnoty |
|----------|-----------|---------------|
| `REGISTRY`, `IMAGE_TAG` | docker-compose | tu |
| `*_PORT` | docker-compose | tu (unikátne per server) |
| `ORIGINS` | api | URL frontendu |
| `DB_CENTRAL_*` | api (administrácia) | kopírovať z `db/.env` |
| `POSTGRES_*_BRNO` | api | zvoliť |
| `SECRET_KEY` | api (administrácia) | `openssl rand -hex 64` |
| `API_KEYS` | api | `openssl rand -hex 32` na klienta, čiarkou oddelené |
| `WEB_API_KEY` | web | jeden z `API_KEYS` |
| `EMAIL_*` | api | SMTP prístupy |

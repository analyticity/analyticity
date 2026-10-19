-----------------------------------
-- Author: Patrik Haas (xhaasp00)
-- File: init_db_central.sql
-----------------------------------
CREATE EXTENSION IF NOT EXISTS postgis;

-- Tabuľka registrovaných databáz
CREATE TABLE IF NOT EXISTS Towns (
  ID SERIAL PRIMARY KEY,
  Name TEXT UNIQUE NOT NULL,              -- napr. 'brno'
  WazeLink TEXT NOT NULL,
	UrlLink TEXT NOT NULL,
  DBHost TEXT NOT NULL,                  -- docker host napr. 'db_brno'
  DBPortExternal INTEGER NOT NULL,  -- port dostupný zvonku (napr. 5433)
  DBPortInternal INTEGER NOT NULL DEFAULT 5432, -- port vnútri kontajnera (zvyčajne 5432)
  DBName TEXT NOT NULL,
  DBUser TEXT NOT NULL,
  DBPassword TEXT NOT NULL,
  Description TEXT,
  Active BOOLEAN DEFAULT TRUE,
  CoverageArea TEXT,            -- územie pokrytia (napr. Brno, JMK)
  CreatedAt TIMESTAMPTZ DEFAULT now(),
  UpdatedAt TIMESTAMPTZ DEFAULT now()
);

-- Tabuľka nastaveni webu pre mesta
CREATE TABLE IF NOT EXISTS Settings (
  ID SERIAL PRIMARY KEY,
	VarName TEXT NOT NULL,					-- napr. 'ForegroundColor' Mozno enum veci ktore sa budu dat menit na stranke
  SettingName TEXT NOT NULL,              -- napr. 'Farbia popredia' Mozno enum veci ktore sa budu dat menit na stranke
  Setting TEXT NOT NULL,                  -- napr #FFFFFF
	Description TEXT NOT NULL,
	GroupName TEXT NOT NULL,
	Town INTEGER
);
ALTER TABLE Settings
ADD CONSTRAINT fk_Settings_town
FOREIGN KEY (Town) REFERENCES Towns(ID);

-- Tabuľka použivateľov
CREATE TABLE IF NOT EXISTS Users (
  ID SERIAL PRIMARY KEY,
  Name TEXT UNIQUE NOT NULL,
  PasswordHash TEXT NOT NULL,
  Email TEXT UNIQUE NOT NULL,
  AdminType TEXT NOT NULL,
  Active BOOLEAN DEFAULT TRUE,
  CreatedAt TIMESTAMPTZ DEFAULT now(),
  UpdatedAt TIMESTAMPTZ DEFAULT now(),
  Town INTEGER
);

ALTER TABLE Users
ADD CONSTRAINT fk_users_town
FOREIGN KEY (Town) REFERENCES Towns(ID);

-- Tabuľka nastaveni ktore sa zobraznie pre mesta
CREATE TABLE IF NOT EXISTS Show (
  ID SERIAL PRIMARY KEY,
  Name BOOLEAN NOT NULL,
  DbName BOOLEAN NOT NULL,
	DbUser BOOLEAN NOT NULL,
	CoverageArea BOOLEAN NOT NULL,
	WazeLink BOOLEAN NOT NULL,
	UrlLink BOOLEAN NOT NULL,
	DbHost BOOLEAN NOT NULL,
	DbPortExternal BOOLEAN NOT NULL,
	DbPortInternal BOOLEAN NOT NULL,
	DbPassword BOOLEAN NOT NULL,
	Description BOOLEAN NOT NULL,
	Active BOOLEAN NOT NULL,
	CreatedAt BOOLEAN NOT NULL,
	UpdatedAt BOOLEAN NOT NULL,
	Town INTEGER NOT NULL
);

ALTER TABLE Show
ADD CONSTRAINT fk_show_town
FOREIGN KEY (Town) REFERENCES Towns(ID);

ALTER TABLE Show
ADD CONSTRAINT uq_show_town UNIQUE (Town);

INSERT INTO Towns (Name, WazeLink, UrlLink, DBHost, DBPortExternal, DBPortInternal, DBName, DBUser, DBPassword, Description, CoverageArea)
VALUES
(
  'Brno',
  'https://www.waze.com/row-partnerhub-api/partners/16198912488/waze-feeds/9c8b4163-e3c2-436f-86b7-3db2058ce7a1?format=1',
  'https://TestLink.com',
  'db_brno',
  5432,
  5432,
  'traffic',
  'traffic',
  'brno_timescale_pass',
  'Popis Brno',
  '{
    "p1": { "lng": 16.4, "lat": 49.1 },
    "p2": { "lng": 16.8, "lat": 49.3 }
  }'
),
(
  'ORP Most',
  'https://www.waze.com/row-partnerhub-api/partners/16198912488/waze-feeds/d8799a1a-7fe6-4d0f-8c57-a0302547b262?format=1',
  'https://TestLink.com',
  'db_orp_most',
  5432,
  5432,
  'traffic',
  'traffic',
  'most_timescale_pass',
  'Popis ORP Most',
  '{
    "p1": { "lng": 13.35, "lat": 50.43 },
    "p2": { "lng": 13.82, "lat": 50.68 }
  }'
)
ON CONFLICT DO NOTHING;

INSERT INTO Users (Name, PasswordHash, Email, AdminType)
VALUES
(
  'VutAdmin',
  '$2b$12$0i3Fbt3BOyStgC5xXIaKe.Rklm9OGTxo8H.9Pm.IzwuKAii1SWsLm', --Heslo v hash, heslo je Test
  'VutAdmin@gmail.com',
  'Admin'
)
ON CONFLICT DO NOTHING;

INSERT INTO Users (Name, PasswordHash, Email, AdminType, Town)
VALUES
(
  'BrnoUser',
  '$2b$12$0i3Fbt3BOyStgC5xXIaKe.Rklm9OGTxo8H.9Pm.IzwuKAii1SWsLm', --Heslo v hash, heslo je Test
  'BrnoUser@gmail.com',
  'Town',
  1
),
(
  'MostUser',
  '$2b$12$0i3Fbt3BOyStgC5xXIaKe.Rklm9OGTxo8H.9Pm.IzwuKAii1SWsLm', --Heslo v hash, heslo je Test
  'MostUser@gmail.com',
  'Town',
  2
)
ON CONFLICT DO NOTHING;

INSERT INTO Show (Name, DbName, DbUser, CoverageArea, WazeLink, UrlLink, DbHost, DbPortExternal, DbPortInternal, DbPassword, Description, Active, CreatedAt, UpdatedAt, Town)
VALUES
(
  true,
  true,
  true,
  true,
  true,
  true,
  true,
  true,
  true,
  true,
  true,
  false,
  false,
  false,
  1
),
(
  true,
  true,
  true,
  true,
  true,
  true,
  true,
  true,
  true,
  true,
  true,
  false,
  false,
  false,
  2
)
ON CONFLICT DO NOTHING;

INSERT INTO Settings (VarName, SettingName, Setting, Description, GroupName, Town)
VALUES
(
  'background',
  '{"en":"Main Background","cz":"Hlavní pozadí"}',
  '#FFFFFF',
  '{"en":"Main background color of the application or page.","cz":"Hlavní barva pozadí aplikace nebo stránky."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  NULL
),
(
  'foreground',
  '{"en":"Main Text","cz":"Hlavní text"}',
  '#1C1B1A',
  '{"en":"Primary text color shown on the main background.","cz":"Primární barva textu zobrazená na hlavním pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  NULL
),
(
  'primary',
  '{"en":"Primary Action","cz":"Hlavní akce"}',
  '#1447E6',
  '{"en":"Main brand color used for buttons, links, and important actions.","cz":"Hlavní značka používaná pro tlačítka, odkazy a důležité akce."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  NULL
),
(
  'primary-foreground',
  '{"en":"Primary Text","cz":"Text hlavní akce"}',
  '#F2F5FF',
  '{"en":"Text color shown on primary colored backgrounds.","cz":"Barva textu zobrazená na hlavním barevném pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  NULL
),
(
  'secondary',
  '{"en":"Secondary Background","cz":"Vedlejší pozadí"}',
  '#F6F6F7',
  '{"en":"Soft neutral background for secondary buttons and sections.","cz":"Jemné neutrální pozadí pro vedlejší tlačítka a sekce."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  NULL
),
(
  'secondary-foreground',
  '{"en":"Secondary Text","cz":"Vedlejší text"}',
  '#2E2D30',
  '{"en":"Text color displayed on secondary backgrounds.","cz":"Barva textu zobrazená na vedlejším pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  NULL
),
(
  'accent',
  '{"en":"Accent Color","cz":"Zvýrazňující barva"}',
  '#1447E6',
  '{"en":"Highlight color used for hover states, selections, and accents.","cz":"Zvýrazňující barva používaná pro hover stavy, výběry a akcenty."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  NULL
),
(
  'accent-foreground',
  '{"en":"Accent Text","cz":"Text zvýraznění"}',
  '#F2F5FF',
  '{"en":"Text color shown on accent backgrounds.","cz":"Barva textu zobrazená na zvýrazněném pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  NULL
),
(
  'card',
  '{"en":"Card Background","cz":"Pozadí karty"}',
  '#FFFFFF',
  '{"en":"Background color for cards, panels, and content boxes.","cz":"Barva pozadí pro karty, panely a obsahové boxy."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  NULL
),
(
  'card-foreground',
  '{"en":"Card Text","cz":"Text karty"}',
  '#1C1B1A',
  '{"en":"Text color used inside cards and panels.","cz":"Barva textu používaná uvnitř karet a panelů."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  NULL
),
(
  'popover',
  '{"en":"Popover Background","cz":"Pozadí vyskakovacího okna"}',
  '#FFFFFF',
  '{"en":"Background color for dropdowns, tooltips, and floating menus.","cz":"Barva pozadí pro rozbalovací menu, tooltipy a plovoucí nabídky."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  NULL
),
(
  'popover-foreground',
  '{"en":"Popover Text","cz":"Text vyskakovacího okna"}',
  '#1C1B1A',
  '{"en":"Text color inside popovers and dropdown menus.","cz":"Barva textu uvnitř popoverů a rozbalovacích menu."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  NULL
),
(
  'muted',
  '{"en":"Muted Background","cz":"Tlumené pozadí"}',
  '#F7F7F5',
  '{"en":"Very subtle background used for muted areas and placeholders.","cz":"Velmi jemné pozadí používané pro tlumené oblasti a zástupné prvky."}',
  '{"en":"Text and content","cz":"Text a obsah"}',
  NULL
),
(
  'muted-foreground',
  '{"en":"Muted Text","cz":"Tlumený text"}',
  '#7A746D',
  '{"en":"Soft text color for hints, placeholders, and less important content.","cz":"Jemná barva textu pro nápovědy, placeholdery a méně důležitý obsah."}',
  '{"en":"Text and content","cz":"Text a obsah"}',
  NULL
),
(
  'input',
  '{"en":"Input Border","cz":"Ohraničení vstupu"}',
  '#E7E5E4',
  '{"en":"Border or background color used for form inputs.","cz":"Barva ohraničení nebo pozadí používaná pro formulářové vstupy."}',
  '{"en":"Formulars","cz":"Formuláře"}',
  NULL
),
(
  'border',
  '{"en":"Border Color","cz":"Barva ohraničení"}',
  '#E7E5E4',
  '{"en":"Default border color for inputs, cards, and dividers.","cz":"Výchozí barva ohraničení pro inputy, karty a oddělovače."}',
  '{"en":"Formulars","cz":"Formuláře"}',
  NULL
),
(
  'ring',
  '{"en":"Focus Ring","cz":"Barva fokusu"}',
  '#B1AAA3',
  '{"en":"Outline color shown when elements receive keyboard or mouse focus.","cz":"Barva obrysu zobrazená při zaměření prvků klávesnicí nebo myší."}',
  '{"en":"Formulars","cz":"Formuláře"}',
  NULL
),
(
  'destructive',
  '{"en":"Danger Action","cz":"Nebezpečná akce"}',
  '#DC2626',
  '{"en":"Color used for delete actions, errors, and destructive buttons.","cz":"Barva používaná pro mazání, chyby a nebezpečná tlačítka."}',
  '{"en":"Notifications ","cz":"Upozornění"}',
  NULL
),
(
  'chart-1',
  '{"en":"Chart Color 1","cz":"Barva grafu 1"}',
  '#A8C0FF',
  '{"en":"First data series color used in charts and graphs.","cz":"První barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  NULL
),
(
  'chart-2',
  '{"en":"Chart Color 2","cz":"Barva grafu 2"}',
  '#4F7BFF',
  '{"en":"Second data series color used in charts and graphs.","cz":"Druhá barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  NULL
),
(
  'chart-3',
  '{"en":"Chart Color 3","cz":"Barva grafu 3"}',
  '#2E63FF',
  '{"en":"Third data series color used in charts and graphs.","cz":"Třetí barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  NULL
),
(
  'chart-4',
  '{"en":"Chart Color 4","cz":"Barva grafu 4"}',
  '#1447E6',
  '{"en":"Fourth data series color used in charts and graphs.","cz":"Čtvrtá barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  NULL
),
(
  'chart-5',
  '{"en":"Chart Color 5","cz":"Barva grafu 5"}',
  '#1038C0',
  '{"en":"Fifth data series color used in charts and graphs.","cz":"Pátá barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  NULL
),
(
  'sidebar',
  '{"en":"Sidebar Background","cz":"Pozadí bočního panelu"}',
  '#FCFCFB',
  '{"en":"Main background color of the sidebar.","cz":"Hlavní barva pozadí bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  NULL
),
(
  'sidebar-foreground',
  '{"en":"Sidebar Text","cz":"Text bočního panelu"}',
  '#1C1B1A',
  '{"en":"Default text color inside the sidebar.","cz":"Výchozí barva textu uvnitř bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  NULL
),
(
  'sidebar-primary',
  '{"en":"Sidebar Primary","cz":"Hlavní barva bočního panelu"}',
  '#2E63FF',
  '{"en":"Primary action or active item color inside the sidebar.","cz":"Hlavní akční nebo aktivní barva položek v bočním panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  NULL
),
(
  'sidebar-primary-foreground',
  '{"en":"Sidebar Primary Text","cz":"Text hlavní akce bočního panelu"}',
  '#F2F5FF',
  '{"en":"Text color shown on sidebar primary backgrounds.","cz":"Barva textu zobrazená na hlavním pozadí bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  NULL
),
(
  'sidebar-accent',
  '{"en":"Sidebar Accent","cz":"Zvýraznění bočního panelu"}',
  '#F7F7F5',
  '{"en":"Hover or selected background color inside the sidebar.","cz":"Barva hover nebo vybrané položky v bočním panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  NULL
),
(
  'sidebar-accent-foreground',
  '{"en":"Sidebar Accent Text","cz":"Text zvýraznění bočního panelu"}',
  '#302F2D',
  '{"en":"Text color shown on sidebar accent backgrounds.","cz":"Barva textu zobrazená na zvýrazněném pozadí bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  NULL
),
(
  'sidebar-border',
  '{"en":"Sidebar Border","cz":"Ohraničení bočního panelu"}',
  '#E7E5E4',
  '{"en":"Border color used inside the sidebar.","cz":"Barva ohraničení používaná uvnitř bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  NULL
),
(
  'sidebar-ring',
  '{"en":"Sidebar Focus Ring","cz":"Fokus bočního panelu"}',
  '#B1AAA3',
  '{"en":"Focus outline color for interactive elements in the sidebar.","cz":"Barva fokusu pro interaktivní prvky v bočním panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  NULL
),
(
  'background',
  '{"en":"Main Background","cz":"Hlavní pozadí"}',
  '#FFFFFF',
  '{"en":"Main background color of the application or page.","cz":"Hlavní barva pozadí aplikace nebo stránky."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  1
),
(
  'foreground',
  '{"en":"Main Text","cz":"Hlavní text"}',
  '#1C1B1A',
  '{"en":"Primary text color shown on the main background.","cz":"Primární barva textu zobrazená na hlavním pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  1
),
(
  'primary',
  '{"en":"Primary Action","cz":"Hlavní akce"}',
  '#d4041c',
  '{"en":"Main brand color used for buttons, links, and important actions.","cz":"Hlavní značka používaná pro tlačítka, odkazy a důležité akce."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  1
),
(
  'primary-foreground',
  '{"en":"Primary Text","cz":"Text hlavní akce"}',
  '#F2F5FF',
  '{"en":"Text color shown on primary colored backgrounds.","cz":"Barva textu zobrazená na hlavním barevném pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  1
),
(
  'secondary',
  '{"en":"Secondary Background","cz":"Vedlejší pozadí"}',
  '#F6F6F7',
  '{"en":"Soft neutral background for secondary buttons and sections.","cz":"Jemné neutrální pozadí pro vedlejší tlačítka a sekce."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  1
),
(
  'secondary-foreground',
  '{"en":"Secondary Text","cz":"Vedlejší text"}',
  '#2E2D30',
  '{"en":"Text color displayed on secondary backgrounds.","cz":"Barva textu zobrazená na vedlejším pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  1
),
(
  'accent',
  '{"en":"Accent Color","cz":"Zvýrazňující barva"}',
  '#d4041c',
  '{"en":"Highlight color used for hover states, selections, and accents.","cz":"Zvýrazňující barva používaná pro hover stavy, výběry a akcenty."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  1
),
(
  'accent-foreground',
  '{"en":"Accent Text","cz":"Text zvýraznění"}',
  '#F2F5FF',
  '{"en":"Text color shown on accent backgrounds.","cz":"Barva textu zobrazená na zvýrazněném pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  1
),
(
  'card',
  '{"en":"Card Background","cz":"Pozadí karty"}',
  '#FFFFFF',
  '{"en":"Background color for cards, panels, and content boxes.","cz":"Barva pozadí pro karty, panely a obsahové boxy."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  1
),
(
  'card-foreground',
  '{"en":"Card Text","cz":"Text karty"}',
  '#1C1B1A',
  '{"en":"Text color used inside cards and panels.","cz":"Barva textu používaná uvnitř karet a panelů."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  1
),
(
  'popover',
  '{"en":"Popover Background","cz":"Pozadí vyskakovacího okna"}',
  '#FFFFFF',
  '{"en":"Background color for dropdowns, tooltips, and floating menus.","cz":"Barva pozadí pro rozbalovací menu, tooltipy a plovoucí nabídky."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  1
),
(
  'popover-foreground',
  '{"en":"Popover Text","cz":"Text vyskakovacího okna"}',
  '#1C1B1A',
  '{"en":"Text color inside popovers and dropdown menus.","cz":"Barva textu uvnitř popoverů a rozbalovacích menu."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  1
),
(
  'muted',
  '{"en":"Muted Background","cz":"Tlumené pozadí"}',
  '#F7F7F5',
  '{"en":"Very subtle background used for muted areas and placeholders.","cz":"Velmi jemné pozadí používané pro tlumené oblasti a zástupné prvky."}',
  '{"en":"Text and content","cz":"Text a obsah"}',
  1
),
(
  'muted-foreground',
  '{"en":"Muted Text","cz":"Tlumený text"}',
  '#7A746D',
  '{"en":"Soft text color for hints, placeholders, and less important content.","cz":"Jemná barva textu pro nápovědy, placeholdery a méně důležitý obsah."}',
  '{"en":"Text and content","cz":"Text a obsah"}',
  1
),
(
  'input',
  '{"en":"Input Border","cz":"Ohraničení vstupu"}',
  '#E7E5E4',
  '{"en":"Border or background color used for form inputs.","cz":"Barva ohraničení nebo pozadí používaná pro formulářové vstupy."}',
  '{"en":"Formulars","cz":"Formuláře"}',
  1
),
(
  'border',
  '{"en":"Border Color","cz":"Barva ohraničení"}',
  '#E7E5E4',
  '{"en":"Default border color for inputs, cards, and dividers.","cz":"Výchozí barva ohraničení pro inputy, karty a oddělovače."}',
  '{"en":"Formulars","cz":"Formuláře"}',
  1
),
(
  'ring',
  '{"en":"Focus Ring","cz":"Barva fokusu"}',
  '#B1AAA3',
  '{"en":"Outline color shown when elements receive keyboard or mouse focus.","cz":"Barva obrysu zobrazená při zaměření prvků klávesnicí nebo myší."}',
  '{"en":"Formulars","cz":"Formuláře"}',
  1
),
(
  'destructive',
  '{"en":"Danger Action","cz":"Nebezpečná akce"}',
  '#DC2626',
  '{"en":"Color used for delete actions, errors, and destructive buttons.","cz":"Barva používaná pro mazání, chyby a nebezpečná tlačítka."}',
  '{"en":"Notifications ","cz":"Upozornění"}',
  1
),
(
  'chart-1',
  '{"en":"Chart Color 1","cz":"Barva grafu 1"}',
  '#F9802F',
  '{"en":"First data series color used in charts and graphs.","cz":"První barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  1
),
(
  'chart-2',
  '{"en":"Chart Color 2","cz":"Barva grafu 2"}',
  '#E44B26',
  '{"en":"Second data series color used in charts and graphs.","cz":"Druhá barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  1
),
(
  'chart-3',
  '{"en":"Chart Color 3","cz":"Barva grafu 3"}',
  '#C8041B',
  '{"en":"Third data series color used in charts and graphs.","cz":"Třetí barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  1
),
(
  'chart-4',
  '{"en":"Chart Color 4","cz":"Barva grafu 4"}',
  '#890413',
  '{"en":"Fourth data series color used in charts and graphs.","cz":"Čtvrtá barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  1
),
(
  'chart-5',
  '{"en":"Chart Color 5","cz":"Barva grafu 5"}',
  '#54040C',
  '{"en":"Fifth data series color used in charts and graphs.","cz":"Pátá barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  1
),
(
  'sidebar',
  '{"en":"Sidebar Background","cz":"Pozadí bočního panelu"}',
  '#FCFCFB',
  '{"en":"Main background color of the sidebar.","cz":"Hlavní barva pozadí bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  1
),
(
  'sidebar-foreground',
  '{"en":"Sidebar Text","cz":"Text bočního panelu"}',
  '#1C1B1A',
  '{"en":"Default text color inside the sidebar.","cz":"Výchozí barva textu uvnitř bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  1
),
(
  'sidebar-primary',
  '{"en":"Sidebar Primary","cz":"Hlavní barva bočního panelu"}',
  '#d4041c',
  '{"en":"Primary action or active item color inside the sidebar.","cz":"Hlavní akční nebo aktivní barva položek v bočním panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  1
),
(
  'sidebar-primary-foreground',
  '{"en":"Sidebar Primary Text","cz":"Text hlavní akce bočního panelu"}',
  '#F2F5FF',
  '{"en":"Text color shown on sidebar primary backgrounds.","cz":"Barva textu zobrazená na hlavním pozadí bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  1
),
(
  'sidebar-accent',
  '{"en":"Sidebar Accent","cz":"Zvýraznění bočního panelu"}',
  '#F7F7F5',
  '{"en":"Hover or selected background color inside the sidebar.","cz":"Barva hover nebo vybrané položky v bočním panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  1
),
(
  'sidebar-accent-foreground',
  '{"en":"Sidebar Accent Text","cz":"Text zvýraznění bočního panelu"}',
  '#302F2D',
  '{"en":"Text color shown on sidebar accent backgrounds.","cz":"Barva textu zobrazená na zvýrazněném pozadí bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  1
),
(
  'sidebar-border',
  '{"en":"Sidebar Border","cz":"Ohraničení bočního panelu"}',
  '#E7E5E4',
  '{"en":"Border color used inside the sidebar.","cz":"Barva ohraničení používaná uvnitř bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  1
),
(
  'sidebar-ring',
  '{"en":"Sidebar Focus Ring","cz":"Fokus bočního panelu"}',
  '#B1AAA3',
  '{"en":"Focus outline color for interactive elements in the sidebar.","cz":"Barva fokusu pro interaktivní prvky v bočním panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  1
),
(
  'background',
  '{"en":"Main Background","cz":"Hlavní pozadí"}',
  '#FFFFFF',
  '{"en":"Main background color of the application or page.","cz":"Hlavní barva pozadí aplikace nebo stránky."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  2
),
(
  'foreground',
  '{"en":"Main Text","cz":"Hlavní text"}',
  '#1C1B1A',
  '{"en":"Primary text color shown on the main background.","cz":"Primární barva textu zobrazená na hlavním pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  2
),
(
  'primary',
  '{"en":"Primary Action","cz":"Hlavní akce"}',
  '#1447E6',
  '{"en":"Main brand color used for buttons, links, and important actions.","cz":"Hlavní značka používaná pro tlačítka, odkazy a důležité akce."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  2
),
(
  'primary-foreground',
  '{"en":"Primary Text","cz":"Text hlavní akce"}',
  '#F2F5FF',
  '{"en":"Text color shown on primary colored backgrounds.","cz":"Barva textu zobrazená na hlavním barevném pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  2
),
(
  'secondary',
  '{"en":"Secondary Background","cz":"Vedlejší pozadí"}',
  '#F6F6F7',
  '{"en":"Soft neutral background for secondary buttons and sections.","cz":"Jemné neutrální pozadí pro vedlejší tlačítka a sekce."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  2
),
(
  'secondary-foreground',
  '{"en":"Secondary Text","cz":"Vedlejší text"}',
  '#2E2D30',
  '{"en":"Text color displayed on secondary backgrounds.","cz":"Barva textu zobrazená na vedlejším pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  2
),
(
  'accent',
  '{"en":"Accent Color","cz":"Zvýrazňující barva"}',
  '#1447E6',
  '{"en":"Highlight color used for hover states, selections, and accents.","cz":"Zvýrazňující barva používaná pro hover stavy, výběry a akcenty."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  2
),
(
  'accent-foreground',
  '{"en":"Accent Text","cz":"Text zvýraznění"}',
  '#F2F5FF',
  '{"en":"Text color shown on accent backgrounds.","cz":"Barva textu zobrazená na zvýrazněném pozadí."}',
  '{"en":"Main colors","cz":"Hlavní barvy"}',
  2
),
(
  'card',
  '{"en":"Card Background","cz":"Pozadí karty"}',
  '#FFFFFF',
  '{"en":"Background color for cards, panels, and content boxes.","cz":"Barva pozadí pro karty, panely a obsahové boxy."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  2
),
(
  'card-foreground',
  '{"en":"Card Text","cz":"Text karty"}',
  '#1C1B1A',
  '{"en":"Text color used inside cards and panels.","cz":"Barva textu používaná uvnitř karet a panelů."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  2
),
(
  'popover',
  '{"en":"Popover Background","cz":"Pozadí vyskakovacího okna"}',
  '#FFFFFF',
  '{"en":"Background color for dropdowns, tooltips, and floating menus.","cz":"Barva pozadí pro rozbalovací menu, tooltipy a plovoucí nabídky."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  2
),
(
  'popover-foreground',
  '{"en":"Popover Text","cz":"Text vyskakovacího okna"}',
  '#1C1B1A',
  '{"en":"Text color inside popovers and dropdown menus.","cz":"Barva textu uvnitř popoverů a rozbalovacích menu."}',
  '{"en":"Cards and panels","cz":"Karty a panely"}',
  2
),
(
  'muted',
  '{"en":"Muted Background","cz":"Tlumené pozadí"}',
  '#F7F7F5',
  '{"en":"Very subtle background used for muted areas and placeholders.","cz":"Velmi jemné pozadí používané pro tlumené oblasti a zástupné prvky."}',
  '{"en":"Text and content","cz":"Text a obsah"}',
  2
),
(
  'muted-foreground',
  '{"en":"Muted Text","cz":"Tlumený text"}',
  '#7A746D',
  '{"en":"Soft text color for hints, placeholders, and less important content.","cz":"Jemná barva textu pro nápovědy, placeholdery a méně důležitý obsah."}',
  '{"en":"Text and content","cz":"Text a obsah"}',
  2
),
(
  'input',
  '{"en":"Input Border","cz":"Ohraničení vstupu"}',
  '#E7E5E4',
  '{"en":"Border or background color used for form inputs.","cz":"Barva ohraničení nebo pozadí používaná pro formulářové vstupy."}',
  '{"en":"Formulars","cz":"Formuláře"}',
  2
),
(
  'border',
  '{"en":"Border Color","cz":"Barva ohraničení"}',
  '#E7E5E4',
  '{"en":"Default border color for inputs, cards, and dividers.","cz":"Výchozí barva ohraničení pro inputy, karty a oddělovače."}',
  '{"en":"Formulars","cz":"Formuláře"}',
  2
),
(
  'ring',
  '{"en":"Focus Ring","cz":"Barva fokusu"}',
  '#B1AAA3',
  '{"en":"Outline color shown when elements receive keyboard or mouse focus.","cz":"Barva obrysu zobrazená při zaměření prvků klávesnicí nebo myší."}',
  '{"en":"Formulars","cz":"Formuláře"}',
  2
),
(
  'destructive',
  '{"en":"Danger Action","cz":"Nebezpečná akce"}',
  '#DC2626',
  '{"en":"Color used for delete actions, errors, and destructive buttons.","cz":"Barva používaná pro mazání, chyby a nebezpečná tlačítka."}',
  '{"en":"Notifications ","cz":"Upozornění"}',
  2
),
(
  'chart-1',
  '{"en":"Chart Color 1","cz":"Barva grafu 1"}',
  '#A8C0FF',
  '{"en":"First data series color used in charts and graphs.","cz":"První barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  2
),
(
  'chart-2',
  '{"en":"Chart Color 2","cz":"Barva grafu 2"}',
  '#4F7BFF',
  '{"en":"Second data series color used in charts and graphs.","cz":"Druhá barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  2
),
(
  'chart-3',
  '{"en":"Chart Color 3","cz":"Barva grafu 3"}',
  '#2E63FF',
  '{"en":"Third data series color used in charts and graphs.","cz":"Třetí barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  2
),
(
  'chart-4',
  '{"en":"Chart Color 4","cz":"Barva grafu 4"}',
  '#1447E6',
  '{"en":"Fourth data series color used in charts and graphs.","cz":"Čtvrtá barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  2
),
(
  'chart-5',
  '{"en":"Chart Color 5","cz":"Barva grafu 5"}',
  '#1038C0',
  '{"en":"Fifth data series color used in charts and graphs.","cz":"Pátá barva datové série používaná v grafech."}',
  '{"en":"Grafs ","cz":"Grafy"}',
  2
),
(
  'sidebar',
  '{"en":"Sidebar Background","cz":"Pozadí bočního panelu"}',
  '#FCFCFB',
  '{"en":"Main background color of the sidebar.","cz":"Hlavní barva pozadí bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  2
),
(
  'sidebar-foreground',
  '{"en":"Sidebar Text","cz":"Text bočního panelu"}',
  '#1C1B1A',
  '{"en":"Default text color inside the sidebar.","cz":"Výchozí barva textu uvnitř bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  2
),
(
  'sidebar-primary',
  '{"en":"Sidebar Primary","cz":"Hlavní barva bočního panelu"}',
  '#2E63FF',
  '{"en":"Primary action or active item color inside the sidebar.","cz":"Hlavní akční nebo aktivní barva položek v bočním panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  2
),
(
  'sidebar-primary-foreground',
  '{"en":"Sidebar Primary Text","cz":"Text hlavní akce bočního panelu"}',
  '#F2F5FF',
  '{"en":"Text color shown on sidebar primary backgrounds.","cz":"Barva textu zobrazená na hlavním pozadí bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  2
),
(
  'sidebar-accent',
  '{"en":"Sidebar Accent","cz":"Zvýraznění bočního panelu"}',
  '#F7F7F5',
  '{"en":"Hover or selected background color inside the sidebar.","cz":"Barva hover nebo vybrané položky v bočním panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  2
),
(
  'sidebar-accent-foreground',
  '{"en":"Sidebar Accent Text","cz":"Text zvýraznění bočního panelu"}',
  '#302F2D',
  '{"en":"Text color shown on sidebar accent backgrounds.","cz":"Barva textu zobrazená na zvýrazněném pozadí bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  2
),
(
  'sidebar-border',
  '{"en":"Sidebar Border","cz":"Ohraničení bočního panelu"}',
  '#E7E5E4',
  '{"en":"Border color used inside the sidebar.","cz":"Barva ohraničení používaná uvnitř bočního panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  2
),
(
  'sidebar-ring',
  '{"en":"Sidebar Focus Ring","cz":"Fokus bočního panelu"}',
  '#B1AAA3',
  '{"en":"Focus outline color for interactive elements in the sidebar.","cz":"Barva fokusu pro interaktivní prvky v bočním panelu."}',
  '{"en":"Sidebar ","cz":"Boční panel"}',
  2
)
ON CONFLICT DO NOTHING;
# Hex Skill-Tree Crafter

Wizualne narzędzie DEV do projektowania heksagonalnego drzewa umiejętności w Robloxie
("na żywym organizmie", w Studio). Klikasz węzeł → dodajesz dzieci w 6 kierunkach, ustawiasz
nazwę / opis / koszt (monety lub kostki). Autozapis do DataStore. Zaprojektowane drzewo
przenosi się potem do gry (`SkillTreeData.luau`).

> Używane do zaprojektowania drzewa 95 węzłów w WAR RNG (`Losowość wojenna 🪖`).
> **Trzymaj to w OSOBNYM place** — nie na oryginale gry.

## Pliki

| Plik | Gdzie wrzucić w Studio |
|------|------------------------|
| `CrafterServer.server.luau` | `ServerScriptService` (jako **Script**) |
| `CrafterClient.client.luau` | `StarterPlayer > StarterPlayerScripts` (jako **LocalScript**) |

Po włożeniu wystarczy uruchomić playtest (Play). Nazwy skryptów w Studio dowolne — kod sam
tworzy remoty `CrafterSave` (RemoteEvent) i `CrafterLoad` (RemoteFunction) w `ReplicatedStorage`.

## Włącz DataStore

Bez tego draft **zapisuje się tylko w sesji** (i tak działa, ale zniknie po zamknięciu).
`Game Settings → Security → Enable Studio Access to API Services` = ON.
Klucz: DataStore `SkillCrafter`, key `tree_v1`.

## Obsługa

- **Klik węzeł** → zaznacza (żółta obwódka) + pokazuje panel edycji (prawy-dół) i zielone „+"
  w 6 wolnych kierunkach heksa.
- **„+"** → dodaje dziecko w tym kierunku.
- **Panel:** `Nazwa`, `Opis` (wieloliniowy), `koszt monety`, `koszt kostki`. Zmiany zapisują się
  po wyjściu z pola (FocusLost).
- **Cofnij** (górny pasek) → undo (historia do 80 kroków).
- **Przeciąganie tła** (LPM) → przesuwanie widoku (pan).
- **Usuń węzeł (+ dzieci)** → kasuje węzeł z całym poddrzewem. Roota nie da się usunąć.

## Model danych

Węzeł: `{ id, parentId, dir, label, desc, coin, roll }`. Root ma `id = "root"`, `parentId = nil`.
Kierunki (`dir`): `Gora`, `GoraPrawo`, `DolPrawo`, `Dol`, `DolLewo`, `GoraLewo`.
`coin = 0` i `roll = 0` → węzeł **informacyjny** (nagłówek sekcji, niekupowalny).

Zapis JSON: `{ nodes = { [id] = {...} }, nextId = N }`.

## Eksport / odczyt draftu (przez MCP / Studio)

- **Klient (w trakcie playtestu):** `_G.CrafterState` = aktualny JSON drzewa (aktualizowany na bieżąco).
- **Serwer:** `_G.CrafterDump()` = JSON prosto z DataStore.
- **Bez gry (edit mode) z API:** `DataStoreService:GetDataStore("SkillCrafter"):GetAsync("tree_v1")`.
- **Hook testowy (klient):** `_G.Crafter = { select, add, del, dump }`.

## Przeniesienie do gry

Weź `nodes` z draftu i zmapuj na `SkillTreeData.luau` (jedno źródło prawdy: layout render + koszty
budują się z tego). Ikony w grze themowane po słowie kluczowym (koniczyna/kostka/moneta),
ceny skracane do K/M. Efekty umiejętności definiuje się osobno (per węzeł) — crafter trzyma
tylko strukturę + opisy + koszty.

# WAR RNG — Architektura Frameworku (v1)

*Dokument projektowy. Zero implementacji — interfejsy, kontrakty, schematy danych i kolejność budowy. Prose PL, kod/nazwy EN. Wszystko server-authoritative. Zgodne z briefem + constraintami z researchu.*

---

## 0. Decyzje otwierające i dwa świadome odstępstwa od promptu

1. **Serwisy są singletonami ze stanem per-player/per-plot** — NIE instancjonujemy zestawu serwisów per plot. Jeden `WaveService` trzyma `state[player]` dla 6 graczy. Powód: prostszy lifecycle, jeden tick, mniej okazji do rozjazdu. „Per plot" z briefu realizujemy przez wewnętrzne mapy stanu, nie przez kopie serwisów.
2. **Odstępstwo A — dodaję 15-ty serwis: `PlotService`.** Lista z promptu nie ma miejsca, gdzie żyje przydział gracz↔plot, granice plotów, kierunek „w stronę bazy wroga" i tagi mapy. Bez tego GridService i BuildService musiałyby to dublować. PlotService jest cienki (~1 ekran kodu) i jest kontraktem mapy.
3. **Odstępstwo B — `PROFILE_TEMPLATE` dostaje pole `pity`.** Prompt wymienia pola bez pity, ale constraint (2) wymaga pity — a licznik pity MUSI być persystentny (nie może resetować się przy rejoinie, bo gracze by to exploitowali w obie strony). `lifetimeRolls` nie wystarczy, bo pity resetuje się po rzadkim dropie, a lifetime nie.
4. **Nazewnictwo capa:** wszędzie `cellBudget` (budżet zajętych kratek, domyślnie 40), nigdy „unitCap" — bo to NIE jest liczba sztuk. W StatProfile pole nazywa się `cellBudget`.

---

## 1. Struktura repo (Rojo)

```
war-rng/
├── default.project.json
├── README.md
├── OWNERSHIP.md                     -- kto jest integratorem plików współdzielonych
└── src/
    ├── ReplicatedStorage/
    │   ├── Framework/               -- GENERYCZNE, reużywalne między grami
    │   │   ├── ServiceRegistry.luau
    │   │   ├── Signal.luau          -- lekki sygnał (event) server-side
    │   │   ├── Net.luau             -- definicje + akcesory RemoteEvent/Function (jedno źródło nazw)
    │   │   ├── GridMath.luau        -- czysta matematyka siatki (cell↔world, footprint iter)
    │   │   ├── WeightedRoll.luau    -- czysty algorytm rolla (denominator-divide + fallback)
    │   │   └── TableUtil.luau
    │   ├── Content/                 -- SPECYFICZNE dla WAR RNG (tylko dane/policy)
    │   │   └── Config/
    │   │       ├── GameConfig.luau  -- agregator: require() podmodułów niżej
    │   │       ├── UnitsConfig.luau
    │   │       ├── RarityConfig.luau
    │   │       ├── MutationConfig.luau
    │   │       ├── WaveConfig.luau
    │   │       ├── GridConfig.luau
    │   │       ├── SkillConfig.luau
    │   │       ├── EconomyConfig.luau
    │   │       └── RevealConfig.luau
    │   └── Shared/
    │       ├── Types.luau           -- typy Luau (Enemy, Placement, RollResult...)
    │       └── Enums.luau           -- RunPhase, WaveEndReason, Currency, UnitKind
    ├── ServerScriptService/
    │   ├── init.server.luau         -- bootstrap: rejestruje serwisy → Init all → Start all
    │   └── Services/
    │       ├── ProfileService.luau
    │       ├── StatProfileService.luau
    │       ├── PlotService.luau
    │       ├── RollService.luau
    │       ├── InventoryService.luau
    │       ├── GridService.luau
    │       ├── BuildService.luau
    │       ├── WaveService.luau
    │       ├── CombatService.luau
    │       ├── CoreService.luau
    │       ├── EconomyService.luau
    │       ├── SkillService.luau
    │       ├── IndexService.luau
    │       └── PurchaseService.luau
    └── StarterPlayer/
        └── StarterPlayerScripts/
            ├── init.client.luau
            └── Controllers/
                ├── RollRevealController.luau   -- teatr rewealu (kaskada 2x/4x/8x, starburst)
                ├── BuildController.luau        -- ghost preview, snap, klik→FireServer
                ├── EnemyRenderController.luau  -- rendering wrogów z batchy pozycji
                ├── WaveHudController.luau      -- pasek FALA X, licznik X/pula
                ├── SummaryController.luau
                └── SkillTreeController.luau
```

Zasady:
- `default.project.json` mapuje WYŁĄCZNIE `ReplicatedStorage`, `ServerScriptService`, `StarterPlayer` (wzorzec z Brainrot Fighters — bezpieczny, nie nadpisuje Workspace/mapy robionej w Studio).
- **Framework/ nie wolno importować z Content/.** Kierunek zależności: Services → Framework + Content; Framework → nic. `WeightedRoll` dostaje tabele jako argumenty, nie robi `require(RarityConfig)`.
- Mapa (ploty, baza dyktatora, ścieżki, rdzenie) żyje w Studio i jest kontraktowana **tagami CollectionService** (sekcja 3.3), nie ścieżkami instancji.

---

## 2. ServiceRegistry + lifecycle

Wzorzec potwierdzony w Brainrot Fighters (service-locator, bez configure()):

```lua
-- Framework/ServiceRegistry.luau (interfejs)
ServiceRegistry.register(name: string, service: table) -> ()
ServiceRegistry.get(name: string) -> table   -- błąd jeśli brak; wołać dopiero w Start()
ServiceRegistry.initAll() -> ()              -- deterministyczna kolejność rejestracji
ServiceRegistry.startAll() -> ()
```

Kontrakt serwisu:

```lua
local FooService = {}
function FooService.Init()  -- ZERO get() tutaj; tylko własny stan, remote'y z Net, connecty do configu
function FooService.Start() -- tu wolno ServiceRegistry.get("Bar"); subskrypcje sygnałów innych serwisów
```

Reguły twarde:
- `Init()` nie dotyka innych serwisów. `Start()` może, bo `startAll()` rusza dopiero po `initAll()` — wszystko zainicjalizowane zanim ktokolwiek zawoła `get()`.
- Komunikacja między serwisami: **wywołania metod w dół zależności, sygnały (Signal) w górę** — np. CombatService NIE woła WaveService; emituje `EnemyDied`, a WaveService subskrybuje. To ucina cykle.
- Kolejność rejestracji w `init.server.luau` (= kolejność Init): ProfileService → StatProfileService → PlotService → EconomyService → InventoryService → IndexService → RollService → GridService → BuildService → CoreService → CombatService → WaveService → SkillService → PurchaseService.

---

## 3. Serwisy — interfejsy (kontrakty)

Notacja: `→` zwrot; `Signal<...>` = event server-side; deps = czego serwis używa przez `get()` w Start().

### 3.1 ProfileService
Odpowiedzialność: ProfileStore (session-locking), load/release, dostęp do danych profilu. Nikt inny nie dotyka ProfileStore.
```lua
.GetProfile(player) → Profile?          -- nil jeśli jeszcze nie załadowany
.IsLoaded(player) → boolean
.ProfileLoaded : Signal<player, Profile>   -- po udanym LoadProfileAsync (ForceLoad); fail → Kick
.ProfileReleasing : Signal<player, Profile> -- przed release (ostatni moment na zapis offlineTs)
```
deps: — (pierwszy w kolejności).

### 3.2 StatProfileService
Odpowiedzialność: JEDYNE źródło staty. Agreguje: bazy z GameConfig + ranki skilli + gamepassy + aktywne boosty → płaska tabela. Cache per player, recompute na zdarzenie.
```lua
.Get(player) → Stats  -- {luck, rollSpeed, mutChance, cellBudget, dmgMult, fireRateMult, rangeMult, coreHP, coinMult, offlineRate}
.Recompute(player) → Stats
.StatsChanged : Signal<player, Stats>
```
Recompute triggery: ProfileLoaded, SkillPurchased, zakup gamepassa/boosta, wygaśnięcie boosta.
deps: ProfileService, SkillService (odczyt ranków), PurchaseService (aktywne passy/boosty).
**Reguła frameworku: żaden inny serwis nie liczy staty sam. Roll bierze luck stąd, Grid bierze cellBudget stąd, Combat bierze dmgMult stąd, Core bierze coreHP stąd.**

### 3.3 PlotService
Odpowiedzialność: przydział gracz↔plot przy join (release przy leave), geometria plotu, kierunek auto-face. Czyta mapę przez tagi CollectionService — to jest kontrakt mapy dla buildera:
- `WR_Plot` (+ attribute `PlotId: number` 1..6) — root plotu
- `WR_BuildGrid` — part definiujący origin+wymiary siatki 9×12
- `WR_CoreAnchor` — punkt rdzenia gracza
- `WR_EnemyBase` — baza dyktatora (wspólna)
- `WR_PathNode` (+ attributes `PlotId`, `Order: number`) — waypointy ścieżki fali do rdzenia plotu
```lua
.GetPlot(player) → PlotInfo?  -- {plotId, gridOrigin: CFrame, gridSize: Vector2int16, coreCFrame, pathNodes: {CFrame}, faceDirection: Vector3}
.GetPlayerByPlot(plotId) → Player?
.PlotAssigned : Signal<player, PlotInfo>
.PlotReleased : Signal<player, plotId>
```
`faceDirection` = znormalizowany wektor od centrum siatki plotu do `WR_EnemyBase` — z tego BuildService liczy orientację KAŻDEGO stawianego obiektu (zero rotation w danych).
deps: —.

### 3.4 RollService
Odpowiedzialność: rolka (algorytm w sekcji 6), pity, mutacja, liczniki, payload rewealu. Cooldown z `Stats.rollSpeed` egzekwowany serwerowo.
```lua
.RequestRoll(player) → ()      -- handler Net.RollRequest; walidacja: cooldown, profil załadowany
.Rolled : Signal<player, RollResult>  -- RollResult = {unitId, rarityN, mutation: {id, mult}?, pityTriggered: boolean}
```
Efekty uboczne jednej rolki (w tej kolejności): wynik → `Inventory.Add` → `lifetimeRolls += 1`, `spendableRolls += 1` → pity update → `Index.Discover` → `Net.RollResult:FireClient`.
deps: StatProfileService, InventoryService, IndexService, ProfileService.

### 3.5 InventoryService
Odpowiedzialność: pula wyrollowanych jednostek (do postawienia). Mutacja jest własnością EGZEMPLARZA, nie typu — więc inventory trzyma stack per (unitId, mutationId).
```lua
.Add(player, unitId, mutation?) → ()
.Consume(player, unitId, mutation?) → boolean   -- false jeśli brak; woła Build przy stawianiu
.Refund(player, unitId, mutation?) → ()          -- przy usunięciu obiektu z siatki
.GetCounts(player) → { [invKey]: number }        -- invKey = unitId .. "#" .. (mutationId or "")
.Changed : Signal<player>
```
deps: ProfileService.

### 3.6 GridService
Odpowiedzialność: occupancy multi-cell + cellBudget (sekcja 7). Czysta logika zajętości — NIE stawia modeli, nie zna Workspace.
```lua
.CanPlace(player, unitId, cellX, cellZ) → (ok: boolean, reason: string?)  -- bounds + wolne kratki footprintu + budżet
.Occupy(player, placementId, unitId, cellX, cellZ) → ()
.Free(player, placementId) → ()
.GetUsedCells(player) → number        -- suma footprintów
.GetBudget(player) → number           -- Stats.cellBudget
.GetPlacements(player) → { [placementId]: {unitId, x, z} }
```
deps: StatProfileService, PlotService (wymiary siatki).

### 3.7 BuildService
Odpowiedzialność: orkiestracja stawiania/usuwania — spina Inventory + Grid + Workspace + fazę. Jedyny właściciel modeli na plocie.
```lua
-- handler Net.PlaceUnit(itemId, cellX, cellZ):
--   faza == Building? → Inventory.Consume? → Grid.CanPlace? → Grid.Occupy → spawn modelu
--   (CFrame z GridMath.cellToWorld + PlotInfo.faceDirection) → zapis do profile.placements → replikacja
-- handler Net.RemoveUnit(placementId): odwrotność + Inventory.Refund
.RestorePlot(player) → ()   -- po ProfileLoaded: odtwarza modele z profile.placements
.PlacementChanged : Signal<player>
```
deps: InventoryService, GridService, PlotService, WaveService (odczyt fazy), ProfileService.

### 3.8 WaveService
Odpowiedzialność: cykl życia fali per plot — faza, spawn puli, kill counter, warunki końca, summary. NIE symuluje ruchu (to Combat).
```lua
.GetPhase(player) → Enums.RunPhase       -- Building | WaveActive | Summary
.StartWave(player) → ()                  -- handler Net.StartWave; tylko z Building
.WaveStarted : Signal<player, waveNumber, poolSize>
.WaveEnded : Signal<player, Enums.WaveEndReason, SummaryData>
   -- WaveEndReason: Cleared (kills == pool) | CoreDestroyed (koniec runu)
   -- SummaryData: {coinsEarned, kills, waveNumber}
```
Logika: `StartWave` → skład fali z `WaveConfig(waveNumber)` → `Combat.SpawnEnemies(...)` → subskrybuje `Combat.EnemyDied` (kill counter, progres do klienta) i `Core.CoreDestroyed` (przegrana). Po `Cleared`: `Economy.AwardWave`, faza → Building, waveNumber += 1. Po `CoreDestroyed`: summary, reset fali do 1 (albo wg configu), rdzeń full HP.
deps: CombatService, CoreService, EconomyService, StatProfileService.

### 3.9 CombatService  ⚠ SERCE WYDAJNOŚCI
Odpowiedzialność: JEDYNA pętla symulacji — ruch wrogów po ścieżce, ostrzał postawionych jednostek, dmg do wrogów i do rdzenia, batch replikacji. Zero Humanoidów, zero instancji fizycznych dla wrogów — wróg to WIERSZ W TABELI.
```lua
.SpawnEnemies(player, waveNumber, spec: {enemyTypeId, count, formation}) → ()
.ClearPlot(player) → ()
.GetAliveCount(player) → number
.EnemyDied : Signal<player, enemyTypeId>
.EnemyReachedCore : Signal<player, enemyTypeId>   -- Core odejmuje HP
```
Model danych wroga (server, tabela): `{id, typeId, hp, pathT: number, speed, plotId}` — pozycja = parametr `t` na polilinii z pathNodes, NIE Vector3 (tańszy sync, brak fizyki).
Tick (jeden `Heartbeat` accumulator, `SIM_HZ = 10`):
1. ruch: `pathT += speed*dt` dla wszystkich wrogów wszystkich plotów (jedna płaska pętla),
2. wieże: per postawiona jednostka bojowa — cooldown, cel = najbliższy wróg w zasięgu (porównanie kwadratów odległości w przestrzeni ścieżki/2D), dmg × `Stats.dmgMult`,
3. wrogowie przy `pathT >= 1`: atak rdzenia w interwale (event do Core),
4. batch sync do klientów (sekcja 9).
deps: PlotService, StatProfileService, GridService (lista jednostek bojowych + pozycje).

### 3.10 CoreService
```lua
.GetHP(player) → (hp: number, maxHp: number)      -- maxHp = Stats.coreHP
.ApplyDamage(player, amount) → ()
.ResetHP(player) → ()
.CoreDamaged : Signal<player, hp, maxHp>
.CoreDestroyed : Signal<player>
```
deps: StatProfileService. Subskrybuje `Combat.EnemyReachedCore`.

### 3.11 EconomyService
Odpowiedzialność: monety (jedyny writer `profile.coins`), nagrody, offline earn.
```lua
.GetCoins(player) → number
.Award(player, amount, reason: string) → ()       -- amount × Stats.coinMult
.TrySpend(player, amount) → boolean
.AwardWave(player, waveNumber, kills) → number    -- z EconomyConfig
.ComputeOfflineEarnings(profile) → {coins, seconds}  -- clamp do EconomyConfig.offlineCapHours; woła się na ProfileLoaded
.CoinsChanged : Signal<player, newBalance>
.OfflineEarningsReady : Signal<player, {coins, seconds}>  -- klient pokazuje popup "zarobiłeś X"
```
deps: ProfileService, StatProfileService.

### 3.12 SkillService
Odpowiedzialność: drzewko LEAN (2–3 gałęzie, pasywne ranki), zakupy w DWÓCH walutach.
```lua
.GetRanks(player) → { [nodeId]: rank }
.TryPurchase(player, nodeId) → (ok, reason?)
--  walidacja: node istnieje → rank < maxRank → prereq spełnione →
--  koszt wg SkillConfig.cost(rank) w walucie node'a:
--    Currency.Coins → Economy.TrySpend
--    Currency.Rolls → profile.spendableRolls (NIGDY lifetimeRolls)
--  → zapis ranku → StatProfile.Recompute
.SkillPurchased : Signal<player, nodeId, newRank>
```
deps: ProfileService, EconomyService, StatProfileService.

### 3.13 IndexService
```lua
.Discover(player, unitId) → boolean         -- true jeśli nowy wpis
.GetCompletion(player) → (count, total, percent)
.GetLuckBonus(player) → number              -- z progów IndexConfig; StatProfile wlicza to do luck
.IndexUpdated : Signal<player, unitId, percent>
```
deps: ProfileService.

### 3.14 PurchaseService
Odpowiedzialność: rollback-safe ProcessReceipt (dev products: boosty, revive, server luck z rosnącą ceną) + ownership gamepassów. Idempotencja: log purchaseId w profilu; grant TYLKO po udanym zapisie; inaczej `NotProcessedYet`. Monetyzacja wyłącznie in-game.
```lua
.OwnsPass(player, passKey) → boolean
.GetActiveBoosts(player) → { [boostId]: expiresAt }
.BoostsChanged : Signal<player>
```
deps: ProfileService, EconomyService, StatProfileService.

### 3.15 GameConfig
Nie serwis, moduł w Content — agregator configów. Serwisy robią `require(GameConfig)` bezpośrednio (dane statyczne, bez lifecycle).

---

## 4. GameConfig — schema

```lua
-- UnitsConfig: definicje jednostek (typy, nie egzemplarze)
Units = {
  ["rifleman"] = {
    kind = Enums.UnitKind.Weapon,      -- Weapon | Block
    rarityN = 3,                        -- "1 in 3"
    footprint = {w = 1, d = 1},         -- kratki; 2x2 → {w=2,d=2}
    combat = {dmg = 5, fireRate = 1.0, range = 12},  -- Block: combat = nil, hp = 200
    modelId = "rbxassetid://...",
    displayName = "Strzelec",
  },
  -- kalibracja drabiny wg Build a Base RNG: 3, 8, 15, 21, 30, 60, 100, 150, 300, 1500
}

RarityConfig = {
  tiers = {  -- do intensywności rewealu i progu pity
    {name = "Common",    maxN = 10,    revealTier = 1},
    {name = "Uncommon",  maxN = 50,    revealTier = 2},
    {name = "Rare",      maxN = 200,   revealTier = 3},
    {name = "Epic",      maxN = 1000,  revealTier = 4},
    {name = "Legendary", maxN = math.huge, revealTier = 5},
  },
  luck = { base = 1.0 },               -- reszta luck ze skilli/indeksu/boostów przez StatProfile
  pity = { threshold = 100, guaranteeMinN = 60 },  -- po 100 rolkach bez dropu N≥60 → wymuś tier Rare+
}

MutationConfig = {
  -- OSOBNY, niezależny rzut po rolce głównej; rosnące progi
  ladder = {
    {id = "x2", mult = 2, chanceN = 25},     -- 1 in 25
    {id = "x4", mult = 4, chanceN = 100},
    {id = "x8", mult = 8, chanceN = 500},
  },
  -- algorytm: idź od najrzadszej; pierwszy trafiony rzut 1-in-chanceN wygrywa; brak → bez mutacji
}

WaveConfig = {
  waves = {
    [1] = { pool = 24, composition = {{"grunt", 24}}, formation = {cols = 6}, hpMult = 1.0, coinReward = 150 },
    -- [n] generowane wzorem: pool = base + n*perWave; hpMult = growth^n — WZÓR w configu, nie w kodzie
  },
  scaling = { poolBase = 20, poolPerWave = 4, hpGrowth = 1.12, coinGrowth = 1.15 },
  enemyTypes = { ["grunt"] = {hp = 30, speed = 0.06, coreDmg = 5, coreAttackInterval = 1.0} }, -- speed w pathT/s
  bossWave = 20,   -- layer-2, zarezerwowane
}

GridConfig = { width = 9, depth = 12, cellSize = 4, baseCellBudget = 40 }

SkillConfig = {
  nodes = {
    ["luck_1"]  = {branch="Roll",  currency=Enums.Currency.Coins, maxRank=5, cost="base*rank^1.5", base=100, effect={stat="luck", perRank=0.2}},
    ["fast_1"]  = {branch="Roll",  currency=Enums.Currency.Rolls, maxRank=3, base=15, effect={stat="rollSpeed", perRank=-0.15}},
    ["cells_1"] = {branch="Base",  currency=Enums.Currency.Coins, maxRank=4, base=500, effect={stat="cellBudget", perRank=5}},
    ["dmg_1"]   = {branch="Combat",currency=Enums.Currency.Coins, maxRank=5, base=200, effect={stat="dmgMult", perRank=0.1}},
    ["core_1"]  = {branch="Base",  currency=Enums.Currency.Coins, maxRank=3, base=300, effect={stat="coreHP", perRank=25}},
    -- LEAN: 3 gałęzie (Roll/Base/Combat), pasywne ranki; keystones po premierze
  },
}

EconomyConfig = {
  offline = { capHours = 10, ratePerHourFromStats = true },  -- rate = Stats.offlineRate
  killReward = 2,
}

RevealConfig = {  -- timingi teatru na kliencie, wg tieru rzadkości
  tiers = {
    [1] = {buildupSec = 0.4, holdSec = 0.5, cascade = false},
    [3] = {buildupSec = 1.0, holdSec = 1.2, cascade = true},
    [5] = {buildupSec = 2.0, holdSec = 2.5, cascade = true, cinematic = true},
  },
}
```

Zasada: **każda liczba, którą Olo będzie kręcił, siedzi tu.** Serwisy nie zawierają liczb balansu.

---

## 5. ProfileStore — PROFILE_TEMPLATE

```lua
local PROFILE_TEMPLATE = {
  coins = 0,
  spendableRolls = 0,      -- WALUTA (skill tree); zużywana przez SkillService
  lifetimeRolls = 0,       -- statystyki/odblokowania; NIGDY nie maleje
  pity = { sinceRare = 0 },-- licznik rolek od ostatniego dropu N >= pity.guaranteeMinN (odstępstwo B)
  inventory = {},          -- { [invKey]: count }, invKey = unitId.."#"..(mutationId or "")
  placements = {},         -- { [placementId]: {itemId, x, z, mut} }  -- BEZ rot (auto-face)
  skills = {},             -- { [nodeId]: rank }
  index = {},              -- { [unitId]: true }
  waveNumber = 1,          -- postęp fal (persystowany między sesjami)
  offlineTs = 0,           -- os.time() zapisywany w ProfileReleasing
  purchaseLog = {},        -- idempotencja ProcessReceipt (ostatnie N purchaseId)
  serverLuckBuys = 0,      -- licznik do rosnącej ceny server luck
}
```

Reguły: ProfileStore (madstudioroblox), session-locking, `LoadProfileAsync` z ForceLoad; `profile == nil` → Kick (nigdy gra bez danych). `placements` przechowuje też `mut` — mutacja egzemplarza musi przetrwać restart. Jedyny writer każdego pola = jeden serwis (coins→Economy, skills→Skill, placements→Build, itd.).

---

## 6. RollService — algorytm

```
funkcja rollOnce(player):
  stats = StatProfile.Get(player)               -- luck już zawiera: skille + indeks + boosty + passy
  rng = Random.new()                            -- serwerowy; NIGDY math.random, NIGDY klient

  -- 1) PITY CHECK (przed selekcją)
  pool = Units posortowane MALEJĄCO po rarityN (najrzadsze pierwsze)
  if profile.pity.sinceRare >= Config.pity.threshold:
      pool = tylko jednostki o rarityN >= Config.pity.guaranteeMinN
      pityTriggered = true

  -- 2) SELEKCJA — dzielenie mianowników (model Sol's; ZERO pętli "best of N")
  for unit in pool:                             -- od najrzadszej
      nEff = math.max(1, math.floor(unit.rarityN / stats.luck))
      if rng:NextInteger(1, nEff) == 1: wybierz unit; break
  if nic nie trafione: wybierz FALLBACK = najczęstszy common (najmniejsze rarityN)

  -- 3) MUTACJA — osobny, niezależny rzut (nie dotyka tabeli głównej)
  mutation = nil
  for m in MutationConfig.ladder od najrzadszej (x8 → x4 → x2):
      mN = math.max(1, math.floor(m.chanceN / stats.mutChance))
      if rng:NextInteger(1, mN) == 1: mutation = m; break

  -- 4) KSIĘGOWANIE
  profile.lifetimeRolls += 1
  profile.spendableRolls += 1
  if unit.rarityN >= Config.pity.guaranteeMinN: profile.pity.sinceRare = 0
  else: profile.pity.sinceRare += 1
  Inventory.Add(player, unit.id, mutation)
  Index.Discover(player, unit.id)

  -- 5) PAYLOAD
  return {unitId, rarityN, mutation = {id, mult}?, pityTriggered}
```

Własności: O(n) po tabeli jednostek niezależnie od wartości luck; `math.max(1, ...)` gwarantuje, że nic nie spada do zera; fallback commona chroni przed pustą rolką; wysokie luck naturalnie „wyłącza" commony (nEff→1 najpierw dla rzadkich). Cooldown: serwer odrzuca `RollRequest` szybszy niż `stats.rollSpeed` (klientowa animacja to tylko teatr).

---

## 7. GridService — occupancy multi-cell + cellBudget

Dwa NIEZALEŻNE sprawdzenia (łatwo je pomylić — nie wolno ich scalić):

```
stan per player:
  occupancy : { [x..":"..z] = placementId }   -- słownik zajętych kratek
  usedCells : number                          -- suma footprintów (cache)

CanPlace(player, unitId, cellX, cellZ):
  fp = Units[unitId].footprint
  -- A) BOUNDS + KOLIZJA: każda kratka footprintu
  for dx = 0..fp.w-1, dz = 0..fp.d-1:
      x, z = cellX+dx, cellZ+dz
      if x<1 or x>Grid.width or z<1 or z>Grid.depth → (false, "OutOfBounds")
      if occupancy[key(x,z)] ~= nil            → (false, "Occupied")
  -- B) BUDŻET KRATEK (to NIE jest liczba sztuk!)
  cost = fp.w * fp.d
  if usedCells + cost > StatProfile.Get(player).cellBudget → (false, "BudgetExceeded")
  return true

Occupy: oznacz WSZYSTKIE kratki footprintu tym samym placementId; usedCells += cost
Free:   wyczyść wszystkie kratki placementId; usedCells -= cost
```

`GridMath` (Framework, czysty): `cellToWorld(gridOrigin, cellSize, x, z, fp) → CFrame` (środek footprintu) i iterator kratek footprintu. Orientacja modelu: `CFrame.lookAlong(pos, plotInfo.faceDirection)` — liczona przy stawianiu, nie przechowywana.

---

## 8. Kontrakty serwer ↔ klient (Net.luau — jedno źródło nazw)

| Remote | Typ | Kierunek | Payload |
|---|---|---|---|
| `RollRequest` | RemoteEvent | C→S | `()` |
| `RollResult` | RemoteEvent | S→C | `{unitId, rarityN, revealTier, mutation?, pityTriggered}` |
| `PlaceUnit` | RemoteFunction | C→S | `(itemId, cellX, cellZ) → (ok, reason?)` — **bez rotation** |
| `RemoveUnit` | RemoteFunction | C→S | `(placementId) → (ok)` |
| `StartWave` | RemoteEvent | C→S | `()` |
| `WaveProgress` | RemoteEvent | S→C | `{plotId, waveNumber, killed, pool}` |
| `WaveEnded` | RemoteEvent | S→C | `{plotId, reason, summary = {coinsEarned, kills, waveNumber}}` |
| `CoreHP` | RemoteEvent | S→C | `{plotId, hp, maxHp}` |
| `EnemySync` | **Unreliable**RemoteEvent | S→C (broadcast) | batch, sekcja 9 |
| `EnemyEvents` | RemoteEvent | S→C | `{plotId, spawns = {...}, deaths = {enemyId...}}` — zdarzenia MUSZĄ być reliable |
| `StatsSync` | RemoteEvent | S→C | pełny snapshot Stats po Recompute |
| `CoinsSync` | RemoteEvent | S→C | `{balance}` |
| `SkillPurchase` | RemoteFunction | C→S | `(nodeId) → (ok, reason?)` |
| `OfflineEarnings` | RemoteEvent | S→C | `{coins, seconds}` |

Zasady: klient NIGDY nie przekazuje wyniku, obrażeń, pozycji wroga ani waluty — wyłącznie intencje (`RollRequest`, `PlaceUnit`, `StartWave`, `SkillPurchase`). Wszystkie handlery walidują pełen łańcuch po stronie serwera. Payloady S→C to fakty dokonane.

---

## 9. NPC — symulacja i replikacja (fundament wydajności)

**Serwer:** wróg = wiersz w tabeli (sekcja 3.9). Brak Instance per wróg, brak Humanoidów, brak fizyki. Jedna pętla `SIM_HZ = 10` dla wszystkich plotów.

**Sync:** co tick symulacji jeden broadcast `EnemySync` (UnreliableRemoteEvent — zgubiony pakiet nadpisze następny):
```
{ [plotId] = { {id, pathT, hpPct}, ... } }   -- pathT: number 0..1; hpPct: byte 0..100
```
Spawny i śmierci idą OSOBNO przez reliable `EnemyEvents` — utrata spawnu/śmierci to desync, utrata pozycji to nic.

**Klient (`EnemyRenderController`):**
- na `spawn` tworzy wizualny model (anchored, `CanCollide=false`, `CanQuery=false`, bez Humanoida),
- co RenderStepped interpoluje między dwoma ostatnimi snapshotami `pathT` → pozycja na polilinii pathNodes (klient ma pathNodes z tagów — mapa jest zreplikowana),
- śmierć: ragdoll/efekt lokalnie, model do poola (object pooling — zero Instance.new w trakcie fali),
- **LOD od dnia zero:** pełny render tylko dla plotu, na który patrzy kamera (+ własny). Pozostałe ploty: modele uproszczone albo wcale (sam pasek postępu). To jest wymóg briefu „gracze oglądają cudze bazy" pogodzony z wydajnością.

**Wieże:** stan bojowy (cooldowny, cele) wyłącznie na serwerze; klient odgrywa muzzle flash/pociski z lekkiego eventu albo wnioskuje z śmierci wrogów (v1: efekt przy śmierci wystarczy — mniej ruchu sieciowego).

---

## 10. Vertical slice + zadania dla CC + bramka

### Zakres slice'a (nic ponad to)
Roll (algorytm z sekcji 6, bez pity w UI — licznik działa, komunikat może poczekać) → Inventory → Grid+Build (multi-cell, cellBudget, auto-face, ghost na kliencie) → jedna fala (spawn → marsz → wieże strzelają → kill counter → Cleared/CoreDestroyed → summary) → Economy (nagroda za falę) → ProfileStore (pełny template, restore placements po rejoinie). BEZ: skilli, indeksu, offline, mutacji w UI (rzut może działać, VFX poczeka), bossa, gamepassów, POWER ROLL.

### Kolejność zadań (sekwencyjnie, jeden agent CC, single integrator)
1. **Szkielet:** repo + Rojo + ServiceRegistry + Signal + Net + init.server + puste serwisy z Init/Start. *Test: startAll() loguje kolejność.*
2. **Dane:** ProfileService (ProfileStore, template, kick-on-fail) + GameConfig (schema z sekcji 4, wartości placeholder). *Test: join→load→leave→zapis offlineTs.*
3. **StatProfile:** compute z baz configu (skille = 0). *Test: Get zwraca bazy.*
4. **PlotService:** tagi na mapie testowej + przydział. *Test: 2 graczy → 2 różne ploty, faceDirection sensowny.*
5. **Roll+Inventory:** algorytm + liczniki + pity + RollResult do klienta (reveal podpinamy do ISTNIEJĄCEJ animacji Andreasa). *Test: rozkład na 10k rolek symulowanych ≈ oczekiwany przy luck 1 i luck 10.*
6. **Grid+Build:** occupancy, budżet, PlaceUnit/RemoveUnit, ghost, restore po rejoinie. *Test: 2x2 przy 39/40 → BudgetExceeded; kolizja footprintów; rejoin odtwarza plot.*
7. **Combat+Core+Wave:** tabela wrogów, tick, EnemySync/EnemyEvents, rendering + LOD, HP rdzenia, oba zakończenia, summary, nagroda. *Test: fala 1 przechodzi end-to-end na 2 plotach równolegle.*
8. **STRESS-TEST (bramka).**

### Bramka — definicja przejścia
Syntetyczny spawn **300 wrogów naraz** (50×6 plotów) + 6×20 jednostek strzelających; pomiar WYŁĄCZNIE w playteście na urządzeniu (pomiary w trybie edycji Studio są bezwartościowe — zero streamingu/cullingu):
- klient: **≥30 FPS na średnim telefonie** (realny sprzęt albo najsłabszy dostępny),
- serwer: czas ticku symulacji **< 8 ms** przy SIM_HZ=10 (budżet z zapasem), script activity stabilne,
- sieć: EnemySync **< 15 KB/s** na klienta przy pełnym obciążeniu.

Nie przechodzi → najpierw kręcimy SIM_HZ w dół (10→7), agresywniejszy LOD, mniejsze pule fal w configu — dopiero potem rozmowa o cięciu designu. **Dopóki bramka nie jest zielona, nie powstaje ani jedna linia skilli/indeksu/offline.**

### Po bramce (kolejność rozbudowy)
Skill tree (dwie waluty) → Index (+luck bonus w StatProfile) → Offline earn → mutacje w reveal VFX → PurchaseService/gamepassy → boss fali 20.

---

## Ryzyka otwarte (świadomie poza v1)
1. Skalowanie fal w nieskończoność (wzór w configu — Olo kalibruje po playtestach).
2. Trade/gifting jednostek — NIE projektujemy; dotknie inventory, wraca po premierze.
3. POWER ROLL — istnieje w buildzie Andreasa, semantyka nieustalona; wchodzi jako wariant `RequestRoll(kind)` bez zmiany architektury.
4. Widzowie na cudzych plotach widzą tylko to, co EnemySync + placements — wystarczy; pełna replika UI cudzego HUD-u nie istnieje z założenia.

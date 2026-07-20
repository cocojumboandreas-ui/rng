# war-rng

Gra Roblox — **WAR RNG** (tower-defense / RNG hybryda, wzorzec „Build a Base RNG").
Workflow: **kod w plikach (Rojo / `src/`) + plac i assety w Studio (Studio-owned, poza repo)**.

Źródło prawdy designu: `docs/WAR_RNG_architektura.md`.

## Stan slice'a (vertical slice — architektura §10)

**Cały pionowy slice zaimplementowany i przetestowany. Zostaje tylko bramka wydajności na urządzeniu.**

| # | Zakres | Test | Status |
|---|--------|------|--------|
| 1 | Szkielet: ServiceRegistry / Signal / Net / bootstrap / 14 serwisów | kolejność startAll | ✅ |
| 2 | ProfileService (ProfileStore, session-lock) + GameConfig | join→load→leave→offlineTs (live, real DataStore) | ✅ |
| 3 | StatProfileService (agregacja staty) | `Get` zwraca bazy | ✅ |
| 4 | PlotService (tagi mapy → geometria + przydział) | 6 plotów, 2 graczy→2 ploty, faceDirection | ✅ |
| 5 | RollService (§6) + Inventory + Index(min) | rozkład 30k rolek @ luck 1/10, pity, mutacja | ✅ |
| 6 | Grid + Build (occupancy, budżet, ghost, restore) | 2×2@39/40→BudgetExceeded, kolizja, rejoin-restore (live) | ✅ |
| 7 | Combat (tick sim) + Core + Wave + Economy | fala 1 end-to-end (live: 24 grunty→cleared→198 monet→wave 2) | ✅ |
| — | Klient: EnemyRenderController (§9), spawn-fix, harness bramki | render/LOD/pool (live), spawn na własnym plocie (live) | ✅ |
| 8 | **STRESS-TEST (bramka)** — 300 NPC | **playtest na URZĄDZENIU** (FPS≥30, tick<8ms, EnemySync<15KB/s) | ⏳ oddane |

Po zielonej bramce: usuń harness + markery `print("[war-rng] … init OK")`, potem warstwa
po-bramkowa (skille → indeks → offline → mutacje w reveal → gamepassy → boss fali 20).

### Kluczowe reguły architektury (utrzymane)
- **Serwer-autorytatywny.** Klient wysyła TYLKO intencje (`RollRequest`, `PlaceUnit`,
  `StartWave`, `SkillPurchase`) — nigdy wyniku, dmg, pozycji wroga ani waluty.
- **Wróg = WIERSZ W TABELI** (nie Humanoid, nie Instance). Jedna pętla symulacji
  `SIM_HZ=10`. Pozycja = `pathT` na polilinii `WR_PathNode`.
- **EnemySync** = per-plot buffer (u16 id + u8 pathT + u8 hpPct = 4 B/wróg,
  UnreliableRemoteEvent); spawn/death osobno przez reliable `EnemyEvents`.
- **Framework/ nie importuje z Content/.** Kontrakt mapy = tagi CollectionService
  (zero ścieżek na sztywno). Serwisy: `register → initAll → startAll`, `get()` w `Start`.

## Zasada podziału własności

Repo trzyma **wyłącznie kod**. Plac (mapa `RNG_MAP`, bazy, `ReplicatedStorage.Assets`,
modele jednostek) jest **Studio-owned** i NIE jest w repo. Szczegóły: `OWNERSHIP.md`.

`default.project.json` mapuje **tylko konkretne podfoldery** (partial nodes), nigdy całych
serwisów — dzięki temu sync NIE kasuje assetów tworzonych w Studio.

## Struktura

```
rng/
├── default.project.json       # partial-node mapowanie src/ -> serwisy
├── src/
│   ├── ReplicatedStorage/
│   │   ├── Framework/          # ServiceRegistry, Signal, Net, GridMath (bez importów z Content)
│   │   ├── Content/Config/     # config gry (Units, Rarity, Grid, Wave, StatBase, Sim, ...)
│   │   └── Shared/             # Enums (server+client)
│   ├── ServerScriptService/
│   │   ├── init/               # -> SSS.init (bootstrap serwera; rejestruje 14 serwisów)
│   │   ├── Services/           # 14 serwisów (Profile/StatProfile/Plot/Economy/Inventory/
│   │   │                       #   Index/Roll/Grid/Build/Core/Combat/Wave/Skill/Purchase)
│   │   └── Server/Vendor/      # ProfileStore (madstudioroblox, MIT — vendored)
│   └── StarterPlayer/StarterPlayerScripts/
│       ├── init/               # -> SPS.init (bootstrap klienta; startuje kontrolery)
│       └── Controllers/        # EnemyRenderController (§9)
├── docs/                       # WAR_RNG_architektura.md (źródło prawdy), research
├── harness/                    # TYMCZASOWY harness bramki Task 8 (+ GATE_INSTRUCTIONS.md)
├── README.md
└── OWNERSHIP.md
```

## Sync ze Studio

`rojo build` służy do **walidacji** projektu (kompilacja + sprawdzenie mapowania). Sync do
otwartego placu robimy przez **StudioBridge** (Luau hub :9977) / **robloxstudio MCP** —
push nazwanych węzłów (create/update dziecka = non-destructive), bo ten Studio NIE ma
wtyczki Rojo. `rojo serve` + plugin Rojo → Connect działa tak samo (partial nodes = bezpieczne).

```powershell
# walidacja
/d/rojo/rojo-7.6.1-windows-x86_64/rojo build --output build.rbxm   # tylko test; build/ w .gitignore
# pełny push src/ -> Studio (z katalogu D:\RobloxProjects)
.\Invoke-Studio.ps1 -File jobs\push_full_sync.luau
```

**Spójność disk = git(origin) = plac Studio = chmura Roblox:**
1. `git add -A && git commit && git push` → GitHub (origin) == dysk.
2. `Invoke-Studio.ps1 -File jobs\push_full_sync.luau` → plac Studio (edit) == dysk.
3. W Studio: **File → Publish to Roblox (Ctrl+Alt+P)** → chmura Roblox == plac Studio.
   (Publikacja placu to akcja UI Studio — nie da się jej odpalić skryptem z wtyczki.)

> **NIGDY** nie rozszerzaj `default.project.json` do całego serwisu (`"ReplicatedStorage":
> { "$path": ... }`). To skasowałoby Studio-owned assety. Tylko nazwane podfoldery.

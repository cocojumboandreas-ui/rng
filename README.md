# war-rng

Gra Roblox — **WAR RNG** (tower-defense / RNG). Workflow: **kod w plikach (Rojo/`src/`)
+ plac i assety w Studio (Studio-owned, poza repo)**.

## Zasada podzialu wlasnosci

Repo trzyma **wylacznie kod**. Plac (mapa `RNG_MAP`, bazy, `ReplicatedStorage.Assets`,
modele jednostek) jest **Studio-owned** i NIE jest w repo. Szczegoly: `OWNERSHIP.md`.

`default.project.json` mapuje **tylko konkretne podfoldery** (partial nodes), nigdy calych
serwisow — dzieki temu sync NIE kasuje assetow tworzonych w Studio.

## Struktura

```
rng/
├── default.project.json      # partial-node mapowanie src/ -> serwisy
├── src/
│   ├── ReplicatedStorage/
│   │   ├── Framework/        # -> RS.Framework (ModuleScript: ServiceRegistry)
│   │   ├── Content/Config/   # -> RS.Content (config gry)
│   │   └── Shared/           # -> RS.Shared (moduly wspoldzielone)
│   ├── ServerScriptService/
│   │   ├── init.server.luau  # -> SSS.init (bootstrap serwera)
│   │   └── Services/         # -> SSS.Services (serwisy serwerowe)
│   └── StarterPlayer/StarterPlayerScripts/
│       ├── init.client.luau  # -> STP.SPS.init (bootstrap klienta)
│       └── Controllers/      # -> STP.SPS.Controllers (kontrolery klienta)
├── README.md
└── OWNERSHIP.md
```

## Sync ze Studio

Kanoniczny live-sync (dla czlowieka):

```powershell
rojo serve                 # start serwera; w Studio: plugin Rojo -> Connect
rojo build -o build.rbxmx  # zbuduj model tylko z kodu (test; build/ w .gitignore)
```

W tym repo sync do otwartego placu robimy przez istniejacy **robloxstudio MCP** (plugin
MCPPlugin) + StudioBridge — te same kanaly, ktore steruja Studio w tej maszynie.
`rojo serve` + plugin Rojo -> Connect dziala tak samo (partial nodes = bezpieczne).

> **NIGDY** nie rozszerzaj `default.project.json` do calego serwisu (`"ReplicatedStorage":
> { "$path": ... }`). To skasowaloby Studio-owned assety. Tylko nazwane podfoldery.

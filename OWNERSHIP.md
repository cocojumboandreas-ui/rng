# Wlasnosc: co jest w repo, a co w Studio

Twardy podzial, zeby sync nigdy nie skasowal pracy zrobionej w Studio.

## REPO-owned (kod, w `src/`, sync z Rojo)

| Node w Studio                                  | Zrodlo w repo                                              |
|------------------------------------------------|-----------------------------------------------------------|
| `ReplicatedStorage.Framework`                  | `src/ReplicatedStorage/Framework/`                        |
| `ReplicatedStorage.Content`                    | `src/ReplicatedStorage/Content/`                          |
| `ReplicatedStorage.Shared`                     | `src/ReplicatedStorage/Shared/`                           |
| `ServerScriptService.init`                     | `src/ServerScriptService/init.server.luau`                |
| `ServerScriptService.Services`                 | `src/ServerScriptService/Services/`                       |
| `StarterPlayer.StarterPlayerScripts.init`      | `src/StarterPlayer/StarterPlayerScripts/init.client.luau` |
| `StarterPlayer.StarterPlayerScripts.Controllers` | `src/StarterPlayer/StarterPlayerScripts/Controllers/`   |

Rojo zarzadza **wylacznie** tymi nodami (partial nodes). Wszystko inne w tych serwisach
zostaje nietkniete.

## STUDIO-owned (plac, NIE w repo, NIE ruszane przez sync)

- `Workspace.RNG_MAP` — mapa: Floor, Terraces, Plots (`PlayerBase_1..6`), Bases
  (`Base_1..3`), Nature.
- `Workspace."Units Comission"` — modele jednostek (roster).
- `ReplicatedStorage.Assets` (np. `Assets.Units`) — jesli/gdy powstanie w Studio.
- `Workspace.Terrain`, `Baseplate`, `SpawnLocation`, Lighting, itd.
- Istniejace skrypty poza mapowaniem (np. `ServerScriptService.PlayerData`,
  `ServerScriptService.PlotAssignment`) — dopoki nie przeniesione swiadomie do `src/`.

## Regula zlota

`default.project.json` mapuje TYLKO nazwane podfoldery. Rozszerzenie mapowania na caly
serwis (`"ServerScriptService": { "$path": ... }`) skasowaloby Studio-owned nody przy
pierwszym syncu. NIE robic tego.

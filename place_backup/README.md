# place_backup

Kopie **place-owned** zawartości, której NIE ma w Rojo/src (żyje tylko w placu Studio).
Backup na wypadek utraty pliku placu. Eksport przez SerializationService (.rbxm).

| Plik | Co zawiera | Gdzie wgrać z powrotem |
|---|---|---|
| `NodeTree.rbxm` | Pack drzewka skilli + shim `Configs.Nodes` → SkillTreeLayout | `ReplicatedStorage` |
| `Assets.rbxm` | `Assets.Units` — modele jednostek (Soldier, Tank, Jeep, Heli, Jet…) | `ReplicatedStorage` |
| `RNG_MAP.rbxm` | Mapa: Plots / Bases (3× MilitaryMap z rozsuwanymi drzwiami) / WR_Nav / Floor / Terraces / Nature | `Workspace` |

## Odtworzenie
W Studio: zaznacz docelowy kontener → PPM → **Insert from File** → wybierz `.rbxm`.
Albo przez plugin/MCP: `import_rbxm(path, parentPath)`.

UWAGA: meshe to referencje do assetów Roblox (rbxassetid), nie geometria — do odtworzenia
potrzebne jest połączenie z Roblox (assety muszą istnieć na koncie/w chmurze).

Eksport: 2026-07-22. Odśwież po większych zmianach w placu (bazy/mapa/pack).

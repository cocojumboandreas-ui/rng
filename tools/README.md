# tools/ — sync placu Studio z `src/`

Ten Studio NIE ma wtyczki Rojo, więc sync do otwartego placu robimy przez **StudioBridge**
(Luau hub :9977) — push nazwanych węzłów (create/update = non-destructive, nie rusza
Studio-owned assetów: `RNG_MAP`, `ReplicatedStorage.Assets`). `Invoke-Studio.ps1` żyje w
`D:\RobloxProjects\` (poza repo) i wymaga działającego huba (Allow HTTP Requests = ON).

## Pełny sync `src/` → plac (dysk == plac Studio)

`push_full_sync.luau` jest **generowany** (osadza każdy plik `src/`, ~156 KB) — NIE trzymamy
go w gicie, tylko generator. Regeneruj po każdej zmianie w `src/`:

```bash
python tools/gen_full_sync.py D:/RobloxProjects/jobs/push_full_sync.luau
```

```powershell
# z D:\RobloxProjects (hub StudioBridge musi działać)
.\Invoke-Studio.ps1 -File jobs\push_full_sync.luau
```

Zwraca `{ pushed = 34 }` (liczba plików). Ustawia `.Source` każdego węzła z dysku →
źródło w Studio == dysk, bajt w bajt.

## Sprzątanie orphanów (klony testowe)

Testy klonują moduły (`*_TCLONE` itp.) dla świeżego require. Jeśli test padł przed
`:Destroy()`, klon zostaje. `push_full_sync` jest non-destructive, więc ich nie usuwa —
zrób to osobno:

```powershell
.\Invoke-Studio.ps1 -File tools\clean_orphans.luau
```

Zostawia kanoniczne 14 serwisów, usuwa `*_TCLONE / *_SPCLONE / *_CLONE / *_OLD`.

## Pełna spójność: dysk = git(origin) = plac Studio = chmura Roblox

1. `git add -A && git commit && git push` — dysk == GitHub (origin).
2. `gen_full_sync.py` + `Invoke-Studio.ps1 -File …\push_full_sync.luau` — dysk == plac Studio (edit).
3. (opcjonalnie) `Invoke-Studio.ps1 -File tools\clean_orphans.luau` — usuń orphany.
4. W Studio: **File → Publish to Roblox (Ctrl+Alt+P)** — plac Studio == chmura Roblox.
   (Publikacja placu to akcja UI Studio — nie da się jej odpalić skryptem z wtyczki.)

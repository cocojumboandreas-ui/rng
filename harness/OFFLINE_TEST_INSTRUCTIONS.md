# Test popup offline earn (post-gate task 3) — instrukcja

Logika serwera (ComputeOfflineEarnings + guardy + grant + Net push) i popup
**zweryfikowane end-to-end** (2h→20 monet, popup „Zarobiles 20 monet przez 2h 0m").
Zostaje **wizualny test popupu na urządzeniu**.

> Popup auto-pokazuje się na dołączeniu gdy `offlineTs` > 0 i minęło trochę czasu.
> Żeby nie czekać godzinami — harness symuluje N godzin offline jednym przyciskiem.

## Deploy harnessu

```powershell
# z D:\RobloxProjects (hub StudioBridge on)
.\Invoke-Studio.ps1 -File jobs\push_offlinetest.luau
```

Wgrywa: `WR_OfflineTestHarness` (server) + `WR_OfflineTestHud` (przyciski
**SYMULUJ OFFLINE 2h** / **20h (cap)**). Ustawia offlineTs wstecz i odpala PRAWDZIWY
`ComputeOfflineEarnings` (grant + guardy + reset) → wypycha `OfflineEarnings`.

## Test na telefonie

1. **Publish** (File → Publish to Roblox / Ctrl+Alt+P).
2. Otwórz na telefonie.
3. Lewa strona: **SYMULUJ OFFLINE 2h** → popup u góry: „Witaj z powrotem! Zarobiles 20
   monet przez 2h 0m (offline)." (auto-znika po ~6s, bez przycisku). Saldo monet +20.
4. **SYMULUJ OFFLINE 20h (cap)** → popup „…100 monet przez 10h 0m…" (cap 10h działa).
5. Sprawdź, że popup jest czytelny, nie zasłania nic krytycznego, auto-znika.

## Po weryfikacji

```powershell
.\Invoke-Studio.ps1 -File jobs\remove_offlinetest.luau
```
(OfflineController + logika ZOSTAJĄ.)

## Uwaga

Popup v1 „prosty" (jedna ramka, bez animacji). Prawdziwa ścieżka: gracz wychodzi
(`ProfileReleasing` zapisuje `offlineTs=os.time()`) → wraca → `ProfileLoaded` liczy
offline earn i pokazuje popup. Guardy: first-login (offlineTs=0 → 0, NIE od epoki),
clock-skew (elapsed<0 → 0), cap 10h, reset offlineTs (anti double-grant przy crashu).
Offline daje TYLKO monety w v1 — offline spins to layer-2 gamepass.

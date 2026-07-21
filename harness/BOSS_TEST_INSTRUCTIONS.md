# Test bossa (fala 20) — instrukcja

Boss = specjalny wróg (isBoss) w tej samej symulacji. Logika + wiring (spawn, BossHP,
BossDefeated, x3 nagroda, render isBoss) **zweryfikowane** (edit-mode + live: boss hp 4306,
BossHP dociera, pasek HP się pokazuje). Zostaje **wygląd na urządzeniu**: render bossa
(większy/fioletowy) + pasek HP bossa u góry + flourish po pokonaniu.

## Deploy harnessu

```powershell
# z D:\RobloxProjects (hub StudioBridge on)
.\Invoke-Studio.ps1 -File jobs\push_bosstest.luau
```

Wgrywa: `WR_BossTestHarness` (server) + `WR_BossTestHud` (przycisk **FORCE BOSS WAVE**).
Przycisk: ustawia falę 20, stawia 6 tanków (pokrycie ścieżki) i startuje falę — więc
boss + 10 gruntów spawnują, wieże strzelają, pasek HP bossa maleje, po czyszczeniu leci
BossDefeated.

## Test na telefonie

1. **Publish** (Ctrl+Alt+P). Otwórz na telefonie.
2. Musisz być w fazie **Building** (świeży wjazd, przed startem normalnej fali).
3. Lewa strona: **FORCE BOSS WAVE**. Sprawdź:
   - **Boss render**: 1 wróg wyraźnie WIĘKSZY (3×) i FIOLETOWY, wolniejszy; obok ~10 zwykłych.
   - **Pasek HP bossa** u góry ekranu (prominentny, styl „ender dragon"): „BOSS  X / Y", maleje gdy wieże biją bossa.
   - Boss maszeruje do rdzenia jak inni (bez bespoke AI), tankuje i mocno bije rdzeń (gdy dojdzie).
   - Po zabiciu wszystkich (boss + grunci): **flourish „BOSS POKONANY!"**, pasek znika, większa nagroda monet.
4. (kontrola) Normalna fala (19/21) = bez bossa i bez paska.

## Po weryfikacji

```powershell
.\Invoke-Studio.ps1 -File jobs\remove_bosstest.luau
```
(BossController + logika bossa ZOSTAJĄ.)

## Uwaga

v1 LEAN: boss to +1 wiersz w tabeli (isBoss) — ta sama pętla/pathing/core-dmg, zero
bespoke AI. Render = 3× placeholder + kolor (docelowy model bossa = polish później).
Wartości (HP 500×hpMult, coreDmg 25, x3 nagroda, co 20. fala, 1 boss + 10 gruntów) =
placeholdery w WaveConfig (Olo retune). Relikty/crafting/dropy/attack patterns = deferred.

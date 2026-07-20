# Bramka wydajności (Task 8) — instrukcja dla Andreasa

**Cel (architektura §10):** przy **300 wrogach naraz (50×6 plotów) + 120 wieżach (20×6)**:
- klient: **≥ 30 FPS** na średnim telefonie (realny sprzęt albo najsłabszy dostępny),
- serwer: czas ticku symulacji **< 8 ms** (SIM_HZ = 10),
- sieć: **EnemySync < 15 KB/s** na klienta.

**To jest playtest NA URZĄDZENIU.** Pomiary w trybie edycji Studio są bezwartościowe (zero streamingu/cullingu) — musi być realny telefon albo najsłabszy dostępny.

## Deploy harnessu do Studio

Z katalogu `D:\RobloxProjects` (hub StudioBridge musi działać, Allow HTTP Requests = ON):

```
.\Invoke-Studio.ps1 -File jobs\push_harness.luau
```

To wgrywa (non-destructive):
- `ServerScriptService.WR_StressHarness` (Script) — spawner + instrumentacja (inertny do kliknięcia),
- `StarterPlayerScripts.WR_StressHud` (LocalScript) — ekran FPS/tick/KB/s + przycisk START/STOP.

## Uruchomienie na telefonie

1. **Publish** placu (File → Publish to Roblox). Harness jedzie razem z placem.
2. Otwórz plac w **aplikacji Roblox na telefonie** (średni/najsłabszy dostępny).
3. Gdy wejdziesz — stoisz na SWOIM placu. W lewym górnym rogu jest HUD + przycisk **START STRESS**.
4. Tapnij **START STRESS**. Harness syntetycznie stawia 300 wrogów + 120 wież na 6 plotach.
5. **Rozejrzyj się kamerą po innych placach** (LOD renderuje własny + oglądany plot) i **poczekaj ~30 s** aż odczyty się ustabilizują.
6. Odczytaj z HUD (i z Dev Console → Server, gdzie harness printuje tick/KB/s):
   - **FPS** (cel ≥ 30),
   - **serwer tick** ms (cel < 8),
   - **EnemySync** KB/s (cel < 15).
7. Tapnij **STOP STRESS** żeby wyczyścić.

## Interpretacja / tuning (kolejność wg §10)

Jeśli bramka **nie** przechodzi — kręcimy w tej kolejności, dopiero potem cięcie designu:
1. **SIM_HZ w dół 10→7** — `Content/Config/SimConfig.luau` `simHz`. Obniża i tick, i pasmo (~×0.7).
2. **Agresywniejszy LOD** — `EnemyRenderController` (mniej renderowanych plotów / prostszy wizual).
3. **Mniejsze pule fal** — `WaveConfig.scaling`.
- Dodatkowy knob pasma: id w EnemySync z u32 → u16 (4 B/wroga zamiast 6) w `CombatService` + dekoder w `EnemyRenderController`.

## Po ZIELONEJ bramce

- Usuń harness: `.\Invoke-Studio.ps1 -File jobs\remove_harness.luau`
- Usuń markery `print("[war-rng] ... init OK")` z `init.server` i `init.client`.
- Dopiero wtedy startuje warstwa po-bramkowa (skille → indeks → offline → mutacje w reveal → passy → boss 20).

## Uwagi techniczne

- Wrogowie w stress-teście mają zawyżone HP (STRESS_WAVE=40 → duży hpMult), żeby 300 sztuk przetrwało okno pomiaru mimo ostrzału wież. To nie wpływa na koszt symulacji/renderu (300 wierszy tyka tak samo).
- `EnemySync` = per-plot buffer (u32 id + u8 pathT + u8 hpPct = 6 B/wroga). Per-klient KB/s ≈ Σ(wrogów) × 6 × simHz / 1024. Przy 300 × 6 × 10 / 1024 ≈ **17.6 KB/s** — tuż nad celem; SIM_HZ 10→7 daje ~12.3 KB/s (albo u16 id → ~11.7 KB/s przy simHz 10).

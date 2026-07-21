# Test roll reveal + mutacje VFX (post-gate task 4) — instrukcja

Reweal to warstwa CZYSTO KLIENCKA (serwer rzuca mutacje od Task 5). Struktura faz +
pooling **zweryfikowane headless** (sekwencja odpala dla tier 1/3/5 i x2/x4/x8 bez błędów,
pula koniczyn zwalniana). Właściwy test to **WYGLĄD na urządzeniu**.

> `revealTier` NIE ma w payloadzie RollResult — klient DERYWUJE go z `rarityN` przez
> RarityConfig (identycznie jak liczyłby serwer). Zero zmian na serwerze.

## Deploy harnessu

```powershell
# z D:\RobloxProjects (hub StudioBridge on)
.\Invoke-Studio.ps1 -File jobs\push_revealtest.luau
```

Wgrywa: `WR_RevealTestHarness` (server) + `WR_RevealTestHud` (przyciski **FORCE ROLL /
FORCE x2 / x4 / x8**). FORCE ROLL = prawdziwa rolka; x2/x4/x8 = fabrykowany RollResult
z mutacją + jednostka o różnym tierze rzadkości (x2=tier1, x4=tier3, x8=tier5).

## Test na telefonie

1. **Publish** (File → Publish to Roblox / Ctrl+Alt+P).
2. Otwórz na telefonie.
3. Przyciski: **ROLL** (na dole, środek — prawdziwa rolka) + lewa strona **FORCE x2/x4/x8**.
4. Sprawdź sekwencję faz (każdy przycisk):
   - **dim** tła (przygaszenie),
   - **build-up**: deszcz koniczyn 🍀 (gęstość rośnie z tierem),
   - **kaskada mutacji** (tylko x2/x4/x8): ikony ×2 → ×4 → ×8 pop-scale sekwencyjnie,
   - **reveal**: starburst ✦ + „1 in {N}" + nazwa jednostki (kolor wg tieru: szary/zielony/niebieski/fiolet/złoto),
   - **settle**: tło wraca.
   - **FORCE x2** = szybki mały (tier1); **x4** = większy/dłuższy (tier3); **x8** = cinematic (tier5, dłuższy hold, większy burst).
   - **FORCE ROLL** = prawdziwa rolka (zwykle common bez mutacji — sam reveal bez kaskady).
5. Odczucie: ma być satysfakcjonujące, czytelne, bez lagów (pooling — zero spamu Instance.new).

## Po weryfikacji

```powershell
.\Invoke-Studio.ps1 -File jobs\remove_revealtest.luau
```
(RollRevealController + przycisk ROLL ZOSTAJĄ.)

## Uwaga

v1 LEAN — poprawna STRUKTURA faz + tier scaling + pooling, ikony emoji (🍀 ✦ ×N) bez
assetów. To NIE jest docelowa „zajebista" animacja Andreasa (target polishu później) —
ma mieć dobrą strukturę i czuć się dobrze. Przycisk ROLL jest tymczasowy (re-hook do
docelowego UI rolki). Reweal jest kolejkowany (do 6) i gra sekwencyjnie.

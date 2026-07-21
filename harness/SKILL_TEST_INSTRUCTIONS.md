# Test UI drzewka umiejętności (post-gate task 1) — instrukcja

Logika serwera i kontrakt sync (RollsSync/CoinsSync/GetSkillState/SkillPurchase) są
**zweryfikowane end-to-end**. Zostaje **wizualny test UI na urządzeniu**: czy panel się
renderuje, przyciski są klikalne, zakup aktualizuje ranki i salda.

## Deploy harnessu (grant waluty testowej)

```powershell
# z D:\RobloxProjects (hub StudioBridge on)
.\Invoke-Studio.ps1 -File jobs\push_skilltest.luau
```

Wgrywa (non-destructive, INERTNE do kliknięcia):
- `ServerScriptService.WR_SkillTestHarness` — przyznaje 5000 coins + 500 rolls na żądanie.
- `StarterPlayerScripts.WR_SkillTestHud` — przycisk **GRANT TEST $$**.

## Test na telefonie

1. **Publish** placu (File → Publish to Roblox / Ctrl+Alt+P).
2. Otwórz plac w aplikacji Roblox na telefonie.
3. Lewa strona ekranu: przycisk **GRANT TEST $$** — tapnij (dostajesz 5000 monet + 500 rolek).
4. Tapnij **SKILLE** — otwiera się panel drzewka.
5. Sprawdź:
   - 3 zakładki gałęzi: **Roll / Base / Combat** — przełączanie pokazuje właściwe węzły.
   - Każdy węzeł: `id [rank x/max]`, efekt, `koszt: N Coins|Rolls`, przycisk **Kup**.
   - Saldo u góry: **Monety** + **Rolki** — aktualne.
   - **Kup** na węźle Coins (np. `dmg_1`) → rank rośnie, monety spadają na żywo.
   - **Kup** na węźle Rolls (`fast_1`) → rank rośnie, rolki spadają na żywo.
   - Węzeł przy max → przycisk **MAX** (nieaktywny); za mało waluty → Kup na czerwono, serwer odrzuca.
   - **X** zamyka panel.
6. (opcjonalnie) Zrób kilka rolek w grze → saldo **Rolki** tyka w panelu na żywo (RollsSync).

## Po weryfikacji

```powershell
.\Invoke-Studio.ps1 -File jobs\remove_skilltest.luau   # usuń grant-harness
```
(SkillTreeController i logika ZOSTAJĄ — to jest właściwa funkcja, nie harness.)

## Uwaga

UI to v1 „proste" (Instance.new, bez motywu). Polish (ikony, layout, animacje) — później.
Serwer waliduje każdy zakup (klient wysyła tylko intencję `SkillPurchase`), więc UI nie
może oszukać ekonomii.

# Test UI kolekcji / indeksu (post-gate task 2) — instrukcja

Logika serwera + sync (GetIndexState / IndexUpdated / StatProfile luck) **zweryfikowane
end-to-end**. Zostaje **wizualny test UI na urządzeniu**: siatka typów, % ukończenia,
bonus luck na żywo, notyfikacja „nowa jednostka".

> **Wejście tymczasowe:** IndexController ma własny przycisk **INDEKS** (jak „SKILLE").
> Prawdziwej żółtej ikony książki NIE ma w placu (StarterGui pusty, zero HUD). Gdy HUD
> się pojawi — re-hook `openBtn` w `IndexController` pod istniejący przycisk (1 linia).

## Deploy harnessu (odkrywanie typów)

```powershell
# z D:\RobloxProjects (hub StudioBridge on)
.\Invoke-Studio.ps1 -File jobs\push_indextest.luau
```

Wgrywa (non-destructive): `WR_IndexTestHarness` (server) + `WR_IndexTestHud` (przyciski
**ODKRYJ +3** / **ODKRYJ WSZYSTKIE**). Używa prawdziwego `Index.Discover` → pełna ścieżka
profile.index → IndexUpdated → StatProfile.Recompute.

## Test na telefonie

1. **Publish** placu (File → Publish to Roblox / Ctrl+Alt+P).
2. Otwórz na telefonie.
3. Lewa strona: **INDEKS** (otwórz panel), **ODKRYJ +3 / ODKRYJ WSZYSTKIE** (harness).
4. Sprawdź:
   - Panel **KOLEKCJA (INDEKS)**: siatka 9 typów; nieodkryte = „?", odkryte = nazwa (zielone).
   - Nagłówek: **Ukończenie: X/9 (Y%)**; **Bonus luck z indeksu: +Z**.
   - Tapnij **ODKRYJ +3** → 3 komórki się odsłaniają, % rośnie, przy 3/9 (33%≥25%) **bonus luck = +0.50**, toast „Nowa jednostka: …".
   - Tapnij **ODKRYJ WSZYSTKIE** → 9/9, 100%, **bonus luck +2.00**.
   - (opcjonalnie) sprawdź w grze, że wyższy luck = częstsze rzadkie rolki (pętla rolki→indeks→luck).
   - **X** zamyka panel.

## Po weryfikacji

```powershell
.\Invoke-Studio.ps1 -File jobs\remove_indextest.luau   # usuń discover-harness
```
(IndexController + logika ZOSTAJĄ.)

## Uwaga

UI v1 „proste" (Instance.new, bez motywu/ikon jednostek — same nazwy). Docelowe ikony
jednostek + żółta książka jako wejście = polish później. Serwer liczy wszystko (klient
tylko `GetIndexState`/odbiera `IndexUpdated`), więc UI nie może zafałszować kolekcji.

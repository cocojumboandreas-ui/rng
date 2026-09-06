# PROMPT DLA FABLE — zbuduj plugin „AnimLab Studio"

Jesteś ekspertem od pluginów Roblox Studio. Zbuduj kompletny, produkcyjny plugin **AnimLab Studio** —
zunifikowany warsztat **animacji proceduralnej + VFX** dla gry TD/RNG (żołnierze R6/R15 z bronią).
Plugin ma dwóch odbiorców i MUSI obsłużyć obu równorzędnie:

1. **Człowiek** (twórca) — pełne GUI: gizmo, suwaki, biblioteka póz, timeline, przeglądarka VFX.
2. **Agent AI** (drugi model, steruje przez `execute_luau`/MCP) — **każda akcja GUI ma odpowiednik w skryptowalnym API** `_G.AnimLabStudio`. Zero funkcji „tylko-UI". Wszystko zwraca dane.

To jest fundament: plugin = wspólny mózg dla człowieka-artysty i agenta-inżyniera.

---

## 1. WIZJA / czym to bije Moon Animatora
- **Pozowanie NA GRANEJ animacji (overlay live):** nakładasz edytowaną pozę (np. „aim") NA rig,
  który W TYM CZASIE gra swój chód/idle — i widzisz blend na żywo. Moon pracuje na martwym rigu; my nie.
- **Podwójny eksport z jednej pozy:** (a) prawdziwa `Animation` (assetId przez Open Cloud), (b) **tabela póz w Luau**
  do systemów proceduralnych (Motor6D.Transform per staw). Nic nie ginie w ręcznym przeklejaniu.
- **VFX zsynchronizowane z animacją:** eventy VFX (muzzle flash, impact, smuga) przypięte do KLATKI + KOŚCI
  (np. flash na attachmencie lufy w klatce „fire"), z podglądem i eksportem toru eventów.
- **Sterowalny przez agenta:** agent buduje/publikuje animacje headless przez API — plugin to jego „ręce w Studio".

---

## 2. INTEGRACJA z „VFX Studio" (istniejący nasz plugin)
VFX Studio = biblioteka ~9k tekstur particle (katalog JSON na GitHubie) + 547 meshy FX.
AnimLab Studio ma z nim GADAĆ. Kontrakt komunikacji między pluginami (wybierz najprostszy działający):
- **Preferowane:** wspólna szyna `_G.VFXStudio` (VFX Studio ją publikuje), z funkcjami:
  - `VFXStudio.search(query) -> { {id, name, kind="Particle"|"Mesh", thumb} }`
  - `VFXStudio.catalog() -> lista` (pełny indeks)
  - `VFXStudio.spawn(id, cframe, params) -> Instance` (podgląd/bake: params = {scale, color, life, rate})
- **Fallback** (gdy VFX Studio niezaładowany): AnimLab czyta ten sam katalog JSON z GitHuba bezpośrednio
  (URL katalogu podam osobno; przewiduj `MCP_VFX_CATALOG_URL` w ustawieniach pluginu).
Jeśli chcesz — zaproponuj lepszy protokół (BindableFunction w znanym folderze `ServerStorage/_PluginBus`,
albo `plugin`-messaging). Ważne: AnimLab działa też SAM, gdy VFX Studio nie ma (graceful degrade).

---

## 3. UKŁAD GUI (dokowalny `DockWidgetPluginGui` + przycisk na Toolbar)
Panel z zakładkami/sekcjami:

**A. Rig** — wybór riga (z Selection albo z Workspace/ReplicatedStorage). Auto-detekcja R6 (6 Motor6D) /
R15 (15 Motor6D). Drzewko stawów (nazwy Motor6D). Klik stawu = podświetlenie części w viewporcie.

**B. Pose Editor** — dla wybranego stawu: **gizmo obrotu w 3D** (Studio handles/adornments) + pola numeryczne
(Euler XYZ oraz podgląd CFrame). Zmiana → `Motor6D.Transform` na żywo. Przycisk **Mirror L↔R**
(kopiuje pozę prawej strony na lewą z odbiciem). „Solo staw" vs „cała poza".

**C. Overlay (live preview)** — toggle: applikuj bieżącą pozę NA rig przez `BindToRenderStep` na
`RenderPriority.Character.Value + 1` (PO Animatorze → nakładka wygrywa). Suwak **weight 0..1** (blend z animacją).
Działa i w edit-mode, i w play-mode.

**D. Pose Library** — zapisz/wczytaj nazwane pozy do configu projektu (ModuleScript
`ReplicatedStorage/Content/Anim/PoseLib` — persist + wersjonowalne). Kategorie (carry/aim/reload/idle…).
Miniatury (opcjonalnie viewport-render). Import/export biblioteki.

**E. Timeline** — klatki (czas → poza), scrub, play preview, easing per-klatka. Buduje `KeyframeSequence`.
Pod spodem **tor VFX**: eventy przypięte do czasu + kości/attachmentu.

**F. VFX Track** — przeglądarka katalogu VFX Studio (search + miniatury). Wybierasz item → przypinasz jako
**event** w czasie T, zakotwiczony do kości/attachmentu (dropdown z części riga + attachmentów broni,
np. `Handle`, `ShotPart`). Ustawiasz scale/color/life. **Podgląd**: podczas scrubu timeline VFX odpala się
na kości. Eksport bake'uje listę eventów.

**G. Publish** — trzy wyjścia jednym klikiem:
1. **Animation** → `KeyframeSequence` → **upload Open Cloud** → `assetId` (zapis do configu animacji).
2. **Pose-data Luau** → wybrane pozy jako tabela Luau (do wklejenia w system proceduralny).
3. **VFX-events** → tor eventów jako tabela `{ {t, vfxId, bone, offset, scale, color, life}, ... }`.

---

## 4. SKRYPTOWALNE API `_G.AnimLabStudio` (dla agenta — RÓWNORZĘDNE z GUI)
Plugin ustawia `_G.AnimLabStudio` przy załadowaniu. KAŻDA funkcja zwraca dane (agent łańcuchuje przez MCP):
```
-- rig
setRig(instanceOrPath)            -> {rigType, joints={names}}
joints()                          -> {name}
-- pozowanie
setPose(jointName, cframe)        -> ok
setPoseEuler(jointName, x,y,z)    -> ok            -- stopnie
capture()                         -> { [joint]=CFrame }   -- zdejmij bieżącą pozę (z animacją w locie!)
applyPoseTable(poseTable)         -> ok
mirrorPose()                      -> poseTable
-- biblioteka
savePose(name, category)          -> ok
loadPose(name)                    -> poseTable
listPoses()                       -> { {name, category, rigType} }
-- overlay live
overlay(on, weight)               -> ok
-- timeline / animacja
addKeyframe(time, poseTable?)     -> index      -- brak poseTable = capture()
listKeyframes()                   -> { {t, pose} }
buildSequence(name, looped)       -> KeyframeSequence (parented ServerStorage)
publishAnimation(name, looped)    -> {assetId} | {rbxmPath}  -- Open Cloud; fallback: zapis .rbxm + info
exportPoseLuau(names)             -> string     -- gotowy kod Luau
-- VFX
vfxSearch(query)                  -> { {id,name,kind,thumb} }
vfxAttach(time, vfxId, bone, params) -> eventIndex
listVfxEvents()                   -> { {t,vfxId,bone,offset,scale,color,life} }
vfxPreviewAt(time)                -> ok
```
Zasada: agent MUSI móc zrobić przez API 100% tego co człowiek przez GUI (zbudować pozę, klatki, przypiąć VFX,
opublikować) — bez klikania.

---

## 5. KONTRAKTY DANYCH (żeby agent i plugin się rozumiały)
- **Poza:** `{ [jointName:string] = CFrame }` (wartości `Motor6D.Transform`).
- **PoseLib entry:** `{ name, category, rigType="R6"|"R15", pose }`.
- **Wejście animacji:** `{ {t=0, pose=...}, {t=0.5, pose=...}, ... }`.
- **VFX event:** `{ t=number, vfxId=string, bone=string, offset=CFrame, scale=number, color=Color3, life=number }`.
- Config projektu: ModuleScript `ReplicatedStorage/Content/Anim/PoseLib` zwraca `{ poses={...}, anims={name=assetId}, vfx={...} }`.

---

## 6. OPEN CLOUD (upload animacji)
Klucz Open Cloud (asset:write) siedzi w zmiennej środowiskowej użytkownika / ustawieniu pluginu
(`plugin:GetSetting("OpenCloudKey")`, z możliwością wpisania w małym panelu Settings).
Flow: `KeyframeSequence` → serializacja → Open Cloud Assets API (typ animation) → `assetId`.
**WAŻNY fallback:** jeśli plugin nie może uploadować bezpośrednio (uprawnienia/CORS/grupa) — zapisz
`KeyframeSequence` do `ServerStorage/_AnimLabExport/<name>` i zwróć `{rbxmPath=...}`; agent dokończy upload
przez MCP (`export_rbxm` → Open Cloud). Zaprojektuj tak, by OBIE ścieżki działały.

---

## 7. TWARDE WYMAGANIA TECHNICZNE
- Jeden self-contained plugin (Script + ewentualnie kilka ModuleScriptów w jego drzewie). Czysty, komentowany.
- **R6 i R15** — generycznie po `Motor6D` (klucz = nazwa motoru). Nie hardkoduj listy stawów.
- Live-pose przez `RunService.RenderStepped` (bind Character+1). Zawsze guard `if not rig or not rig.Parent`.
- **Undo/Redo** przez `ChangeHistoryService` (każda zmiana pozy/klatki = waypoint).
- Dokowalny widget, toolbar button z ikoną. Zapamiętuj stan (ostatni rig, otwarte panele) w `plugin:SetSetting`.
- Nie blokuj Studio (żadnych `while true` bez `wait`; ciężkie operacje w `task.spawn`).
- Odporność: brak riga / brak VFX Studio / brak klucza OC → czytelny komunikat, nie crash.
- Kod PL komentarze OK, identyfikatory EN.

---

## 8. KAMIENIE MILOWE (buduj przyrostowo, każdy działający)
1. Szkielet: toolbar + dokowalny widget + wybór riga + drzewko stawów + `_G.AnimLabStudio.setRig/joints`.
2. Pose Editor (gizmo + numerycznie) + `setPose/capture/applyPoseTable` + Undo.
3. Overlay live (bind Character+1, weight) — pozowanie na granej animacji.
4. Pose Library (zapis/wczytaj do ModuleScript) + Mirror L↔R.
5. Timeline + `buildSequence` + `exportPoseLuau`.
6. Publish animacji (Open Cloud + fallback rbxm).
7. VFX Track: bridge do VFX Studio (search/spawn) + eventy na timeline + podgląd + eksport toru.

Zbuduj to jako spójny produkt. Priorytet: **overlay-live + podwójny eksport + skryptowalne API + bridge VFX** —
to jest to, czego nie ma nigdzie indziej.

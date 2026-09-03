# RAPORT: ciężarówka konwojowa WAR RNG — Meshy → Blender → Studio

**Data:** 2026-08-13
**Status: 🔴 MODEL v6 NADAL ODRZUCONY. TRZY niezależne próby naprawy "krystalicznego" połysku wypróbowane i wyczerpane — WSZYSTKIE nieskuteczne lub wręcz szkodliwe. `TruckPreview.Body` przywrócony do oryginalnej (niesmoothowanej) geometrii v6 jako "najmniej zły" znany stan. Wymagana decyzja koordynatora o dalszym kierunku — patrz sekcja "v6.2→v6.5" i DO_DECYZJI.md.**

**Skrót wyniku (żeby nie trzeba było czytać całej historii):** hipoteza "to tylko eksporter FBX gubi smooth shading" (`mesh_smooth_type="FACE"`→`"OFF"`) była **empirycznie sfałszowana** — dwa eksporty tej samej geometrii z różnym trybem smoothingu dały **bajtowo identyczny Roblox MeshId** (`109098196489733` u obu), więc Roblox oczywiście ignoruje/przelicza normalne z importu niezależnie od exportera. To bezpośrednio zaprzecza temu, co koordynator przekazał jako potwierdzony sukces równoległego agenta Nuke_Warhead tą samą metodą — rozbieżność NIE wyjaśniona, flagowana niżej. Próba geometrycznego wygładzania (Corrective Smooth) okazała się no-opem (wymaga armatury/deformacji, której ten statyczny mesh nie ma). Laplacian smoothing (bmesh, `preserve_volume=True`) faktycznie zmienia pozycje wierzchołków i mierzalnie redukuje szum kątowy w MEDIANIE, ale **niszczy geometrię lokalnie** (widoczne fałdowanie/składanie się cienkich fragmentów — kątowe statystyki `max` utykają w okolicach 172-180°, czyli niemal antyrównoległe normalne sąsiednich trójkątów = fizyczne zawinięcie siatki, nie szum). Przy 3 iteracjach efekt wizualny nadal niewystarczający (koła wyglądały GORZEJ). Przy 11 iteracjach (3+8) efekt katastrofalny — kabina wygląda jak zgnieciona, koła mają postrzępioną, zębatą sylwetkę — **realny regres, natychmiast wycofany ze sceny**.

---

## KROK 0a — grupa placu WAR RNG: ZROBIONE ✅

Sprawdzone **live** w Studio przez `execute_luau` (target=`edit`):
```
game.CreatorType = Enum.CreatorType.Group
game.CreatorId   = 664399796
```
placeId: `121496191564387` ("Losowość wojenna 🪖"). **Grupa WAR RNG = `664399796`.**

---

## KROK 0b — klucz Open Cloud: ZDJĘTE ✅

`ROBLOX_OC_KEY_RNG` ustawiony w zmiennej środowiskowej **User** (nie widoczny w moim już-działającym procesie — odczytany świeżo przez `[Environment]::GetEnvironmentVariable('ROBLOX_OC_KEY_RNG','User')`, wstrzyknięty tylko do jednorazowego procesu-dziecka PowerShella, nigdy nie wypisany/zalogowany).

Mapowanie `GROUP_KEY_ENV` (dodane w poprzedniej turze) potwierdzone działające w obu miejscach:
- `D:\RobloxProjects\oc_upload.py` — `"664399796": "ROBLOX_OC_KEY_RNG"`
- `D:\RobloxProjects\start_bridge.ps1` — `'664399796' = 'ROBLOX_OC_KEY_RNG'`

### Sanity-check klucza (create-z-plikiem, wymagane bo sonda bez pliku nie rozróżnia grup)

Skrypt `D:\RobloxProjects\rng\_oc_sanity_check.py` — minimalny multipart create (1×1 PNG, assetType Image) na `creationContext.creator.groupId=664399796`, klucz wstrzyknięty tylko do procesu, nigdzie nie wypisany.

**Wynik: `creator.groupId` w odpowiedzi Open Cloud = `"664399796"` → klucz JEST autoryzowany na tę grupę.** Ryzyko z ostrzeżenia (664399796 należy do Daxter_Ottsel, Andreas tylko Admin) **nie zmaterializowało się**.

**Do ręcznego skasowania przez ownera:** assetId `93695350683864` (typ Image, `moderationState: Rejected` — nieistotne, to śmieciowy 1px test). Open Cloud nie archiwizuje assetów Image, więc kasowanie wyłącznie ręczne.

**Ustalenie na całą grę WAR RNG (nie tylko na tę ciężarówkę): kanał `:9979` (Open Cloud) działa i jest potwierdzony dla grupy 664399796.** Fallback przez `robloxstudio` MCP `upload_asset` nie był potrzebny — patrz też DO_DECYZJI.md.

### Restart warstwy `:9979` na grupę RNG

Sekwencja z briefu wykonana dokładnie: zabicie starych listenerów na 9977/9978/9979 → potwierdzenie `Test-NetConnection :9979` = fail → `start_bridge.ps1 -Group 664399796` → health-check.

```json
{"requests": true, "error": null, "key_set": true, "group": "664399796", "key_env": "ROBLOX_OC_KEY_RNG"}
```
`plugin_connected: true`. Wszystkie 3 warstwy (9977/9978/9979) żywe na grupie RNG.

---

## KROK 0e — Scale_Ruler dla WAR RNG: ZROBIONE ✅

Stary `88040173957580` (grupa junky) potwierdzony niedziałający w placu RNG (`insert_asset` → "User is not authorized"). Zbudowany **nowy** ruler proceduralnie w Blenderze (`_scale_ruler_rng.py`): kostka 10×10×10 Blender-units, origin bottom-center, apply scale.

- `validate_for_roblox("Scale_Ruler_RNG")` → `{tris:12, size_studs:{x:10,y:10,z:10}, materials:1, non_manifold_edges:0, loose_verts:0, ngons:0, scale_applied:true, verdict:"pass"}`
- `export_fbx_roblox` → `global_scale:0.01`, size_studs 10/10/10
- Upload via `:9979` → **assetId `119344626341644`**
- `insert_asset` → `game.Workspace.Scale_Ruler_RNG`, odczyt `get_instance_properties` na MeshPart potwierdził **`Size: "10, 10, 10"`** — mnożnik 1 Blender unit = 1 stud potwierdzony EMPIRYCZNIE dla tej grupy, nie założony.
- Instancja testowa usunięta po potwierdzeniu (`delete_object`), żeby nie zaśmiecać placu. **assetId `119344626341644` zapisany do ew. ponownego wstawienia** przy porównaniu skali z ciężarówką.

---

## Most Blendera (:9876): ŻYJE ✅

`{"ok": true, "bridge": "roblox-bridge-v2", "blender_version": [5,1,1], "active_job": null}` — bez restartu, MCP nie stały, reconnect niepotrzebny.

---

## Plik wejściowy GLB: ZNALEZIONY ✅

`D:\RobloxProjects\rng\Meshy_AI_convoy_truck_3d_0813102006_image-to-3d-texture.glb` (42 005 312 B) — leżał w `rng\`, nie w `rng\mesh\` (stąd wcześniejsze niepowodzenie szukania).

### Diagnostyka 1 — import na czystej scenie (`_diag_truck_0813.py`)

Jeden obiekt mesh (`Mesh_0.002`) — **zero cięcia/łączenia potrzebne, natywnie jeden korpus**, dokładnie zgodnie z wymogiem "NIE CIĄĆ NIE ŁĄCZYĆ".

| pomiar | wartość |
|---|---|
| tris (surowe) | 788 614 (oczekiwane 788 670 — zgodne) |
| verts (surowe) | 425 452 (oczekiwane 420 253 — zgodne) |
| wysokość Z | **8.000 studs dokładnie** (bottom już przy Z=0) |
| długość X | **17.902 studs** — ⚠️ lekko poniżej oczekiwanego zakresu 18–22, patrz DO_DECYZJI.md |
| szerokość Y | 7.003 studs |
| materiały | 1 (`Material_0.003`) |
| Emission Strength | 1.0 (do wyzerowania) |

### Diagnostyka 2 — pełny graf węzłów materiału (`_diag_truck_0813_nodes.py`)

Zmierzone (nie zgadywane) połączenia w node_tree Principled BSDF:

| mapa | obraz | rozdzielczość | colorspace | rola |
|---|---|---|---|---|
| ColorMap | `Image_0` | 4096×4096 | sRGB | → Base Color |
| MetallicRoughness (paczka) | `Image_1` | 2048×2048 | Non-Color | → Separate Color: **Blue→Metallic, Green→Roughness** (zgodne z regułą briefu B=metal/G=rough) |
| NormalMap | `Image_2` | 4096×4096 | Non-Color | → Normal Map → Normal (NIE użyjemy w finalnym SurfaceAppearance, ma zostać pusty) |
| Emisja | `Image_3` | 2048×2048 | sRGB | → Emission Color (do usunięcia) |

Źródło map wzięte z materiału ZAIMPORTOWANEGO obiektu (nie globalny find-by-name) — ryzyko leftover-image kontroli niskie, scena była czysta przed importem.

---

## Obróbka mesha — HISTORIA v1→v5 (CAŁKOWICIE PORZUCONA, zastąpiona przez v6 — patrz sekcja niżej)

Historia (żeby było jasne, że to NIE był jeden gładki przebieg):

- **v1–v3**: regresja wysokości po decymacji (~280× redukcja, ochrona wagowa nie jest twardym pinem, przy tak ekstremalnym współczynniku nawet chronione wierzchołki są w końcu zamiatane). v3 osiągnął 2733 tris, ale render (po naprawie oświetlenia, bo podwozie było w cieniu) pokazał **koła jako wielościany, nie koła** — ochrona czysto krzywiznowa nie odróżniała kół od innych ostrych krawędzi (rogi kabiny, listwy skrzyni).
- **v4** (próba naprawy kół): dodano twardą ochronę PRZESTRZENNĄ (pozycja+promień) wykrywaną przez flood-fill po siatce w dolnym pasie Z. **Błąd**: `BOTTOM_FRAC=0.34` za szeroki → flood-fill zlał wszystkie 6 kół w JEDEN blob 207 880 wierzchołków (most przez ramę/oś). Efekt: koła zniknęły w gładkim brzuchu zamiast zostać kołami — niedostatecznie zróżnicowana ochrona rozmyła budżet.
- **Tuning diagnostyczny** (`_wheeldetect_tune.py`, bez decymacji, ~9s/przebieg): 8 kombinacji `(bottom_frac, cell)`. Wynik: `0.08–0.12` → czysty rozdział na 6 blobów; `0.16+` → zlewanie. Wybrano `BOTTOM_FRAC=0.12, CELL=0.2`.
- **v5** (finalny): `wheels_found=6`, dokładne centra/promienie w `_process_truck_0813_v5_report.json` (np. koło #1: center=(2.422, 2.509), r=1.442). Pełna ochrona: krzywizna + Z-ekstrema (jak v3) + twarda cylindryczna wokół 6 wykrytych kół (dominująca tam gdzie koliduje z resztą).

### Wyniki liczbowe v5 (z `_process_truck_0813_v5_report.json`, NIE zaokrąglane)

| etap | tris | wysokość Z (studs) |
|---|---|---|
| surowy import | 788 614 | 8.000 |
| po cleanup (remove_doubles+normals) | 788 614 | 8.000 |
| po Stage1 decimate (ratio-bisekcja, chronione) | 9 398 | 7.850 |
| po Stage2 decimate (ratio=0.298, tłumiona ochrona) | 2 800 | 7.362 |
| po triangulacji | 2 800 | 7.362 |
| po UV-safe sliver-cleanup (30 krawędzi skolapsowanych, 106 pominiętych jako chronione) | **2 737** | 7.362 |
| po korekcie Z (z-only rescale ×1.0866, przywrócenie zmierzonej wysokości) | **2 737** | **8.000000075** |

**Finalne wymiary (studs):** X=17.8306 (długość), Y=7.1432 (szerokość), Z=8.000 (wysokość, po korekcie).

**⚠️ Uczciwa uwaga do korekty Z:** po skalowaniu tylko osi Z wokół originu (0,0,0), dolna krawędź mesha nie leży dokładnie na Z=0 — jest na `z_min=0.1115`, `z_max=8.1115`. Czyli obiekt "unosi się" ~0.11 studa nad swoim originem zamiast dotykać go dokładnie. Wizualnie znikomy błąd (mniej niż grubość opony), ale technicznie origin NIE jest już idealnie bottom-center po tej korekcie — flaguję to jako świadomy kompromis, nie przeoczenie.

**⚠️ Uczciwa uwaga do UV-stretch:** `uv_stretch_before_sliver_cleanup` i `uv_stretch_after_sliver_cleanup` w raporcie JSON wychodzą **identyczne co do cyfry** (2 324 547.78) — to sugeruje, że metryka nie została realnie przeliczona po cleanupie (prawdopodobnie ta sama wartość cache'owana), a nie że UV faktycznie w 100% nietknięte. Nie jest to zweryfikowany dowód "UV bez zmian", tylko nieprzeliczona metryka — trzeba to policzyć poprawnie w kolejnej turze jeśli UV stretch będzie kiedyś sporny.

### Weryfikacja okrągłości kół renderem w Blenderze — NIEROZSTRZYGAJĄCA (odrzucona jako dowód)

Pełnoscenowe zrzuty (iso/front) z Blendera sugerowały poprawę względem v3/v4 (odrębne bryły kół, nie zlane w brzuch jak v4). **Izolowany close-up pojedynczego koła nie był możliwy** — `viewport_screenshot` nie izoluje obiektu, 6 strategii izolacji zawiodło (ograniczenie narzędzia, nie błąd skryptu). Ten wniosek okazał się **zbyt optymistyczny** — patrz niżej wynik z prawdziwego Studio.

---

## Weryfikacja wizualna ze Studio v5 (HISTORYCZNE — koła FAIL, CAŁE podejście v1-v5 porzucone niżej)

Okno Studio zostało odminimalizowane przez koordynatora. `capture_screenshot` zadziałał. Zrobione zrzuty: szeroki (25,20,25), średni (14,8,14), nisko-podwoziowy (6,1,10 patrząc na center-(0,2,0)), boczny czysty (0,4,20). Zrzut z góry (0,22,0.5) **nie wyszedł** — okno zostało zminimalizowane ponownie w trakcie sesji, po 3 próbach retry (~30s każda) odpuszczone, nie blokuje reszty wniosków (boczny zrzut wystarcza do oceny kół i tekstury).

### Tekstura — ✅ RENDERUJE SIĘ POPRAWNIE (po opóźnieniu propagacji CDN)

Pierwsze zrzuty (od razu po insert+SurfaceAppearance) pokazywały **cały model biały/szary** mimo poprawnie ustawionych property (`ColorMap`/`MetalnessMap`/`RoughnessMap`/`AlphaMode` — potwierdzone przez `execute_luau` czytające żywą instancję). Zdiagnozowane systematycznie: (1) reset property na pusty string i z powrotem — bez zmiany; (2) diagnostyczny `Decal` na osobnym testowym `Part` z tym samym raw image assetId — też renderował pusty blady panel, nie obraz → **problem nie był specyficzny dla SurfaceAppearance**, tylko ogólny "świeżo wgrany obraz jeszcze się nie ładuje"; (3) `Lighting.Technology` niesprawdzalne (`lacking capability RobloxScript`, zablokowane nawet z poziomu pluginu) — nieistotne finalnie. Po zmianie kadru kamery i kilku kolejnych wywołaniach narzędzi (bez jawnego długiego sleep) — **kolejny zrzut pokazał poprawnie renderowaną teksturę: oliwkowo-zielony lakier widoczny na kabinie i listwach skrzyni ładunkowej.** Wniosek: to było przejściowe opóźnienie propagacji CDN dla świeżo utworzonych Open Cloud Image assetów, samo się rozwiązało — **nie jest to trwały problem, testowy Part+Decal usunięty po diagnozie.**

### Samoświecenie — ✅ BRAK, potwierdzone wizualnie

Na żadnym z czterech zrzutów model nie wykazuje widocznej emisji/poświaty — spójne z tym, że mapa Emission (`Image_3`) została świadomie wycięta z pipeline'u tekstur. Obserwacja bezpośrednia, nie założenie.

### Koła — ❌ **FAIL, wprost, z opisem tego co widać**

Na zrzucie nisko-podwoziowym (kamera 6,1,10 patrząc w dół na okolice podwozia) i na zrzucie bocznym (0,4,20) podwozie/koła wyglądają jako **ostre, kanciaste, ciemnoniebieskie graniaste bryły — wyraźnie NIE okrągłe koła**, tylko postrzępione "kryształowe" kolce sterczące spod skrzyni i kabiny. To bezpośrednio zaprzecza wcześniejszej ocenie z surowych zrzutów Blendera ("odrębne bryły kół, poprawa względem v4") — prawdziwy render Studio (deklarowany wcześniej jako ostateczny sędzia) pokazuje, że **ochrona przestrzenna kół z v5 (`wheels_found=6`, twarda ochrona pozycja+promień na 6 wykrytych kołach, dane w `_process_truck_0813_v5_report.json`) NIE przełożyła się na okrągły kształt w finalnym renderze**, mimo że sama detekcja (6 blobów, liczności 5380–5917 wierzchołków, promienie 1.44–1.49 studa) była poprawna geometrycznie na etapie analizy.

Możliwe przyczyny (niezdiagnozowane do końca w tej turze, do zbadania jeśli koordynator zdecyduje o poprawce): (a) genuinny problem geometrii po agresywnej decymacji (Stage2 ratio=0.298, tris 9398→2800) — ochrona zachowała POZYCJĘ wierzchołków kół, ale nie ich rozmieszczenie na obwodzie okręgu, więc mogły zostać zredukowane do nieregularnego wielokąta; (b) artefakt cieniowania/normalnych — `validate_for_roblox` zgłosił **13 non-manifold edges** (WARN, nie blokuje kontraktu), które w kombinacji z `DoubleSided:false` mogą dawać ciemne/kanciaste artefakty backface-culling niezależnie od faktycznego kształtu geometrii; ciemnoniebieski kolor (nie oliwkowo-zielony jak reszta modelu) sugeruje raczej to (b) — brak tekstury na tych trójkątach + culling, nie sam kształt siatki. **Nie rozstrzygnięte bez dalszej diagnozy (np. wireframe zrzut lub eksport samych kół osobno).**

### Kabina — zidentyfikowana matematycznie + potwierdzona wizualnie

Dla ujęcia kamery `CFrame.new(center+(25,20,25), center)`: wektor "w prawo ekranu" w świecie = `WorldUp:Cross(zAxis).Unit` ≈ `(0.7071, 0, -0.7071)` (rosnące X świata, malejące Z świata). Na tym zrzucie kabina znajduje się PO PRAWEJ stronie kadru → **kabina jest po stronie WIĘKSZEGO X świata/lokalnego** (potwierdzone też na zrzucie bocznym — kabina wyraźnie widoczna z charakterystyczną szybą i czerwonym markerem na dachu). Krzyżowo zweryfikowane z danymi `wheel_detection` z v5: klaster kół o największym lokalnym X (≈+5.69) leży bliżej kabiny niż klaster przy X≈-4.2 — układ przedniej osi blisko kabiny/maski, sensowny dla ciężarówki.

### Punkt montażu minigunu — USTAWIONY i sfotografowany

`Attachment` o nazwie `MinigunMount_1_CabinRoof` utworzony pod `game.Workspace.TruckPreview.Body`:
- lokalnie (względem pivotu Body): `(7, 3.4, 0)`
- świat: `(15.299238, -14.836938, 436.243896)`

Na zrzucie bocznym widoczny czerwony neonowy marker-kula (`_MountMarker`, tymczasowy, tylko do zdjęcia) siadający na dachu kabiny, tuż nad szybą — wizualnie sensowna pozycja montażu wieżyczki. **Marker usunięty po zdjęciach** (analogicznie do `_TexTestPart`) — w scenie zostaje wyłącznie `Attachment`, żaden faktyczny minigun NIE został podpięty, zgodnie z instrukcją.

Zrzut z góry (do potwierdzenia centrowania na osi Y/lewo-prawo dachu) **nie został zrobiony** — okno Studio zminimalizowało się ponownie po zrzucie bocznym, 3 próby retry nieudane. Pozycja lokalna Z=0 zakłada środek szerokości kabiny (symetria względem osi wzdłużnej) — niepotwierdzone zrzutem z góry, tylko przez odczyt geometrii bbox. Jeśli to sporne, wymaga dodatkowego zrzutu przy następnym oknie możliwości.

### `validate_for_roblox` — PASS

```
tris: 2737
size_studs: {x: 17.831, y: 7.143, z: 8.0}
materials: 1
non_manifold_edges: 13  (WARN only, nie blokuje — kontrakt failuje tylko przy tris>10000 lub osi>2048)
loose_verts: 0
ngons: 0
verdict: "pass"
```

---

## Tekstury v5 (HISTORYCZNE — pliki i assety nadal użyte w v6, patrz niżej)

Skrypt `_process_truck_0813_textures.py` (job `ba64a1fa4aaa`, 12.3s realnego czasu Blendera):

- ColorMap z `Image_0` → 1024×1024 PNG
- MetallicRoughness z `Image_1` (Separate Color: B=Metal, G=Rough) → dwa osobne szare PNG 1024×1024, `colorspace=Non-Color`
- Klamra: **metal_max: 0.4196 → 0.3500** (ceiling), **rough_min: 0.3490 → 0.3500** (floor) — oba spełnione dokładnie na granicy
- Pliki potwierdzone na dysku: `WR_ConvoyTruck_ColorMap_1024.png` (1 471 034 B), `_MetalnessMap_1024.png` (13 995 B), `_RoughnessMap_1024.png` (13 995 B)

## Export + Upload v5 (HISTORYCZNE, model już zastąpiony przez v6)

- `export_fbx_roblox("WR_ConvoyTruck_Body")` → `size_studs: {x:17.831, y:7.143, z:8.0}`, `global_scale:0.01`
- Upload przez `robloxstudio.upload_asset` (grupa `664399796`, kanał Open Cloud potwierdzony w KROK 0):
  - Model (FBX) → **assetId `127055056930041`** (v5, zdecymowany, JUŻ NIEUŻYWANY w placu)
  - ColorMap (Decal/Image) → **assetId `117458416469719`**, imageId `103647633765395` — **nadal używane w v6**
  - MetalnessMap (Decal/Image) → **assetId `86691457636019`**, imageId `112493083659128` — **nadal używane w v6**
  - RoughnessMap (Decal/Image) → **assetId `107299523840531`**, imageId `107613469939768` — **nadal używane w v6**
  - Wszystkie `moderationState: Approved`, `state: Active`

---

# v6 — KOŃCZYMY Z DECYMACJĄ (decyzja koordynatora, zastępuje CAŁKOWICIE v1-v5)

**Polecenie koordynatora wprost:** v1→v5 (agresywna redukcja do 2500-3000 tris) psuła koła za każdym razem, niezależnie od schematu ochrony (krzywizna → krzywizna+Z-ekstrema → +ochrona przestrzenna). Budżet trisów z pierwotnego briefu był kalkulacją koordynatora "co jest ładne dla gry", NIE twardym limitem Robloxa, i był błędny w praktyce. Nowe polecenie: **ZERO decymacji**, mesh możliwie 1:1 z oryginalnego GLB.

## Obróbka v6 — `_process_truck_0813_v6.py`

Jedyna obróbka: fresh import GLB → unpack tekstur → strip emisji (Emission Strength=0, ten sam mechanizm co w v1-v5) → `remove_doubles` próg 0.0006 (czyści tylko duplikaty współrzędne, nie zmienia widocznej geometrii) → `recalc_face_normals` outside → `shade_auto_smooth(30°)` → origin bottom-center → apply scale. **Żadnego Decimate modifier, żadnych wag wierzchołków, żadnej wymuszonej triangulacji** (mesh zostaje z ngonami/quadami jeśli natywnie takie miał — FBX exporter Blendera triangularyzuje sam na eksport, zgodnie z poleceniem).

Job `00ead85aa4e4` (10.3s realnego czasu Blendera). Pierwsza próba (job `c8af21d33d2c`) rzuciła `AttributeError` przy próbie odczytu `res.get("targetmap")` z wyniku `bmesh.ops.remove_doubles` (który nie zwraca dict-a w tej wersji Blendera) — naprawione przez liczenie różnicy `len(bm.verts)` przed/po zamiast polegania na zwracanej strukturze; nie miało wpływu na samą operację remove_doubles, tylko na diagnostyczny log.

### Wyniki liczbowe v6 (z `_process_truck_0813_v6_report.json`)

| pomiar | surowy import | po cleanup (finalne) |
|---|---|---|
| tris | 788 614 | **788 614** (bez zmian — remove_doubles na progu 0.0006 nie usunął żadnego trójkąta z tej geometrii) |
| wysokość Z | 8.000 | **8.000** |
| długość X | 17.902 | **17.902** |
| szerokość Y | 7.003 | **7.003** |
| non-manifold edges | — | **0** (lepsze niż v5: 13) |
| loose verts / ngons | — | **0 / 0** |

**Brak sztucznej korekty skali** — wymiary są dokładnie tym, co dała surowa geometria GLB, zgodnie z poleceniem "nie koryguj sztucznie, liczy się zgodność z oryginałem". Wymiary są niemal identyczne z v5 (17.831→17.902, 7.143→7.003) — sensowne, bo v5 była tej samej bazowej geometrii, tylko poddanej agresywnej decymacji + sztucznej korekcie Z.

## `validate_for_roblox` na v6 — kontrakt naszego skryptu odrzuca, Roblox NIE

```
tris: 788614
size_studs: {x: 17.902, y: 7.003, z: 8.0}
non_manifold_edges: 0, loose_verts: 0, ngons: 0
verdict: "fail"
issues: [{"level":"fail","code":"tris_over_limit","detail":"788614 tris > 10000 per MeshPart; decimate."}]
```

**Sprawdzone źródło progu** (`io/bridge/roblox_asset_mcp/src/roblox_asset_mcp/blender_ops.py:20`): `TRI_LIMIT = 10000` — stała w NASZYM skrypcie walidującym, z własnym komentarzem w kodzie: *"confirm in Roblox docs before trusting"* (czyli sam autor skryptu nigdy tego nie zweryfikował względem realnego limitu Robloxa). To NIE jest twardy limit platformy, tylko lokalna bramka bezpieczeństwa.

**Test empiryczny zamiast zgadywania:** wykonano `export_fbx_roblox` (zadziałało, plik na dysku) i `upload_asset` (Model, grupa 664399796) mimo lokalnego FAIL. **Roblox przyjął model bez żadnego zastrzeżenia**: `moderationState: "Approved"`, `state: "Active"`, assetId `127150449904067`. To potwierdza empirycznie (nie z pamięci) że 10000 tris to próg naszego walidatora, nie realny limit Roblox Open Cloud/importera.

## Tekstury v6 — PONOWNIE UŻYTE, nie przetwarzane od nowa

Tekstury (ColorMap/MetalnessMap/RoughnessMap) są niezależne od decymacji mesha — to te same pliki PNG wygenerowane z tych samych obrazów źródłowych (`Image_0`, `Image_1` z tego samego pliku GLB), a UV mesha v6 nie zostało w żaden sposób zmodyfikowane (jedyna operacja to `remove_doubles` na mikroskopijnym progu, bez wpływu na mapowanie UV). **Ponownie użyte assetId z rundy v5** (już zweryfikowane jako poprawnie renderujące się w Studio w tej samej sesji): ColorMap `103647633765395`, MetalnessMap `112493083659128`, RoughnessMap `107613469939768`. Zgodnie z poleceniem koordynatora "powtórz dokładnie to co działało" — nie było potrzeby ponownego przetwarzania ani ponownego uploadu.

## Export + Upload v6 — ZROBIONE

- `export_fbx_roblox("WR_ConvoyTruck_Body_v6")` → `size_studs: {x:17.902, y:7.003, z:8.0}`, `global_scale:0.01`
- Upload przez `robloxstudio.upload_asset` (grupa `664399796`) → Model (FBX) **assetId `127150449904067`**, `moderationState: Approved`, `state: Active`

## Insert do placu v6 — ZROBIONE (zastąpiono v5 w `TruckPreview.Body`)

- Stary v5 `Body` (zdecymowany, kanciaste koła) **usunięty** z `game.Workspace.TruckPreview`
- Nowy `Body` = MeshPart z assetu `127150449904067`, wstawiony przez `ServerStorage` → reparent+rename → `game.Workspace.TruckPreview.Body`
- `MeshId`: `rbxassetid://109098196489733`
- `Position`: `(8.299238, -18.236938, 436.243896)` (ta sama pozycja co v5, dla ciągłości w placu)
- `Anchored: true`, `DoubleSided: false`, `Material: SmoothPlastic`, `Color: (1,1,1)` białe, `CanCollide: true`
- `SurfaceAppearance` (dziecko `Body`): `ColorMap=rbxassetid://103647633765395`, `MetalnessMap=rbxassetid://112493083659128`, `RoughnessMap=rbxassetid://107613469939768`, `NormalMap` puste, `AlphaMode=Overlay` (te same asset id co v5)
- `Model.PrimaryPart = Body`
- **`game.ReplicatedStorage.WR_StrikeModels.Truck` (produkcyjny szablon) — nadal NIE dotknięte**, zgodnie z decyzją z poprzedniej rundy.

## Weryfikacja wizualna ze Studio v6 — WYNIK RZECZYWISTY

Okno Studio było już przywrócone z poprzedniej rundy (nie zminimalizowało się w trakcie tej sekwencji). Zrobione 3 zrzuty: szeroki iso (25,18,25) z markerem montażowym, blisko-nisko-podwoziowy (6,1.5,10 patrząc na center-(0,2,0)), boczny czysty (0,4,20).

### ⚠️ KOREKTA (po zrzucie koordynatora) — poniższa ocena "PASS" była błędna, patrz sekcja "ODRZUCENIE PRZEZ UŻYTKOWNIKA" niżej

Koordynator zrobił własny zrzut ze Studio i pokazał go użytkownikowi. Werdykt użytkownika, dosłownie: **"wygląda jak gówno jebane"**. Koordynator potwierdza, że "krystaliczny" połysk opisany niżej jako słaby/kątowo-zależny/nieblokujący jest w rzeczywistości **DOMINUJĄCĄ cechą widoczną z każdego kąta w edytorze Studio**, nie subtelnym artefaktem widocznym tylko pod ostrym światłem. To trzeci przypadek w tym zadaniu (po v3 i v5), gdzie moja ocena wizualna z własnych zrzutów była zbyt optymistyczna. Poniższy tekst zostawiony jako zapis tego, co faktycznie napisałem — **nie jest już aktualną oceną modelu**. Aktualna diagnoza i naprawa: patrz sekcja "v6.1 — DIAGNOZA I NAPRAWA POŁYSKU" niżej.

### Koła — ✅ PASS na okrągłość, ale to nie ratuje ogólnego wrażenia

Na wszystkich trzech zrzutach koła są **wyraźnie okrągłe** — widoczny bieżnik opony, piasty, łuki nadkoli nad kołami. Bezpośrednie porównanie z v5 (ten sam kadr bliski-nisko-podwoziowy): v5 pokazywał ostre ciemnoniebieskie graniaste kolce; v6 na identycznym typie ujęcia pokazuje regularne czarne opony z widocznym bieżnikiem. Ta konkretna, wąska obserwacja (kształt kół) pozostaje prawdziwa — ale jest przyćmiona przez defekt połysku poniżej, który dotyczy całego nadwozia I kół jednocześnie i dominuje pierwsze wrażenie z modelu.

### (ZAPIS HISTORYCZNY, BŁĘDNA OCENA) "graniasty/krystaliczny" połysk nadwozia — pierwotnie oceniony jako słaby i nieblokujący

Pierwotny tekst (pozostawiony dla przejrzystości procesu, patrz korekta wyżej): "Na zrzucie blisko-nisko (kamera nisko, słońce w dużej mierze pod kątem grzbietowym) nadwozie (kabina, burty skrzyni) pokazuje ostry, poszarpany, 'krystaliczny' połysk specularny... Na zrzucie bocznym... ten efekt jest dużo słabszy... **zgłaszam do wiadomości koordynatora, nie traktuję jako blokera**." — **Ta ocena była zła.** Koordynator/użytkownik widzą efekt jako dominujący z każdego kąta, nie tylko przy ostrym świetle. Prawdopodobna przyczyna tego błędu: oceniałem po 3 konkretnych, wybranych przeze mnie kadrach, z których jeden (boczny, neutralne światło) akurat minimalizował efekt — myliłem "da się znaleźć kąt gdzie wygląda OK" z "wygląda OK".

### Tekstura — ✅ RENDERUJE SIĘ POPRAWNIE (bez opóźnienia tym razem)

Oliwkowo-zielony lakier widoczny od razu na pierwszym zrzucie v6 (assety tekstur już "rozgrzane" z poprzedniej rundy, CDN nie potrzebował czasu propagacji ponownie).

### Punkt montażu minigunu — PRZENIESIONY na v6 i potwierdzony wizualnie

Wymiary v6 (17.902×8×7.003) są niemal identyczne z v5 (17.831×8×7.143), więc te same lokalne współrzędne zastosowane ponownie:
- `Attachment` `MinigunMount_1_CabinRoof` pod nowym `Body`: lokalnie `(7, 3.4, 0)`, świat `(15.299238, -14.836938, 436.243896)` (identyczne ze świata v5, bo ta sama pozycja Body w placu)
- Na zrzucie iso widoczny czerwony marker siedzący poprawnie na dachu kabiny, tuż nad szybą — **wizualnie potwierdzone na nowej geometrii**, nie tylko przeniesione na ślepo
- Marker usunięty po zdjęciach, żaden faktyczny minigun NIE podpięty

Zrzut z góry (do potwierdzenia centrowania Z=0 na szerokości dachu) **nadal nie zrobiony** — nie był konieczny do potwierdzenia głównego pytania (koła + tekstura), a boczny/iso wystarczyły do potwierdzenia sensownej pozycji montażu. Jeśli sporne przy faktycznym montażu modelu wieżyczki, wymaga dodatkowego zrzutu.

---

## v6.1 — DIAGNOZA I NAPRAWA POŁYSKU (w toku, uczciwy status poniżej)

### Diagnoza (wysokie zaufanie, oparta o kod, EMPIRYCZNIE NIE POTWIERDZONA jeszcze na żywym obiekcie — patrz blokada niżej)

Winowajcą jest prawie na pewno **eksporter FBX, nie geometria**. `blender_ops.py:189` (`export_fbx()`) ma na sztywno:

```python
bpy.ops.export_scene.fbx(
    ...
    use_mesh_modifiers=True,
    mesh_smooth_type="FACE",   # <-- TO JEST PODEJRZANY PARAMETR
    ...
)
```

`mesh_smooth_type="FACE"` w eksporterze FBX Blendera oznacza dosłownie "każdy trójkąt dostaje własną, oddzielną grupę wygładzania" — czyli **pełne fasetowanie z definicji**, niezależnie od tego, że skrypt v6 (`_process_truck_0813_v6.py`) explicite wywołuje `bpy.ops.object.shade_auto_smooth(angle=0.5235988)` (30°) przed eksportem. W Blenderze 4.1+/5.x ta operacja nie ustawia już starej flagi `mesh.use_auto_smooth` (usuniętej), tylko dodaje modyfikator "Smooth by Angle" liczący normalne dopiero przy ewaluacji. Nawet jeśli `use_mesh_modifiers=True` prawidłowo ewaluuje ten modyfikator i eksporter zapisuje poprawne, gładkie normalne wierzchołkowe — `mesh_smooth_type="FACE"` dodatkowo zapisuje dane grup wygładzania mówiące "każdy trójkąt osobno", a importery FBX szanujące grupy wygładzania (typowe dla przepływów Maya/3ds Max, prawdopodobnie też importer Robloxa, biorąc pod uwagę ile innych niuansów tego pipeline'u już poznaliśmy empirycznie) mogą przeliczyć cieniowanie z tych grup zamiast/oprócz surowych wektorów normalnych — dając efekt dokładnie taki jak opisany: każdy z 788 614 trójkątów łapie światło osobno, jak pognieciona folia/lód. Poprawna wartość dla mesha przetworzonego przez `shade_auto_smooth`: `mesh_smooth_type="EDGE"` (grupy wygładzania pochodzące z ostrych krawędzi, dokładnie zgodne z tym co robi auto-smooth) albo `mesh_smooth_type="OFF"` (nie pisz w ogóle grup wygładzania, wymuszając na każdym imporcie zaufanie surowym wektorom normalnym — bezpieczniejszy, bardziej uniwersalny wybór). Wybrany kierunek naprawy: **`"OFF"`**.

### Alternatywna hipoteza (geometria, nie shading) — NIE wykluczona formalnie, ale mało prawdopodobna

Możliwe że surowy mesh Meshy (788k tris, natywny image-to-3D) ma realny mikro-szum w topologii, nie tylko w cieniowaniu. Nie sprawdzone bezpośrednio (patrz blokada niżej), ale poszlaka przeciwko tej hipotezie: 30° próg auto-smooth to dość szeroki margines — gdyby to była wyłącznie geometria, oczekiwałbym że sam próg 30° i tak wygładziłby widoczny efekt dla większości krawędzi o niskiej krzywiźnie, chyba że szum jest ostrzejszy niż 30° wszędzie, co byłoby bardzo nietypowe dla wyjścia fotogrametrii/image-to-3D. `mesh_smooth_type="FACE"` jako wyjaśnienie pasuje dokładnie 1:1 do obserwowanego efektu (widoczny z KAŻDEGO kąta, nie tylko przy szumnej geometrii pod określonym światłem) — geometria dawałaby efekt bardziej związany z rzeczywistą krzywizną lokalną, nie jednolicie wszędzie.

### ⚠️ BLOKADA — most Blendera zajęty przez równoległego agenta (Nuke_Warhead)

`scene_inventory` w trakcie tej diagnozy pokazuje w scenie **`Mesh0`** (23 306 tris, 3.86×3.78×12 studs) — to NIE jest `WR_ConvoyTruck_Body_v6` (788 614 tris). Scena współdzielonego Blendera została w międzyczasie przejęta przez równoległego agenta pracującego nad `Nuke_Warhead`. Zgodnie z twardą zasadą pipeline'u ("JEDEN klient mostu naraz") i explicit ograniczeniem koordynatora ("nie przeszkadzaj agentowi Nuke_Warhead"), **NIE wolno mi teraz re-importować ciężarówki ani uruchamiać skryptów mutujących scenę** — zniszczyłoby to bieżącą pracę drugiego agenta.

**Diagnoza powyżej jest więc oparta wyłącznie na inspekcji kodu (`blender_ops.py`) + znajomości własnego skryptu v6, NIE na żywym sprawdzeniu obiektu w Blenderze.** Przygotowany, gotowy do odpalenia, jest skrypt diagnostyczny `_diag_truck_0813_normals.py` (liczy realne kąty między normalnymi sąsiednich trójkątów na bazowej siatce vs. kąty custom split normals na wyewaluowanej siatce — jeśli te drugie są małe/gładkie mimo że pierwsze duże/kanciaste, to twardy dowód że siatka JEST gładka, a defekt jest czysto eksportowy) — uruchomię go, gdy tylko most się zwolni, zanim przystąpię do ponownego eksportu, żeby nie deklarować naprawy bez realnego dowodu (zgodnie z instrukcją koordynatora).

### Krok 2 — numeryczne potwierdzenie ZROBIONE (`_diag_truck_0813_normals.py`, job `f7b5f64f903a`)

```json
{
  "modifiers": [{"name": "Smooth by Angle", "type": "NODES"}],
  "mesh_has_custom_normals": true,
  "base_mesh_adjacent_face_angle_deg": {"sample_count":3000,"p50":8.107,"p90":31.4,"max":83.425,"mean":12.462},
  "evaluated_mesh_has_custom_normals": true,
  "evaluated_custom_split_normal_angle_at_shared_vert_deg": {"sample_count":500,"p50":0.008,"p90":26.422,"max":86.254,"mean":4.928}
}
```

Silne poszlakowe potwierdzenie hipotezy: siatka BAZOWA jest kanciasta (mediana kąta między sąsiednimi normalnymi trójkątów 8.1°, do 83° na ogonie), ale siatka WYEWALUOWANA (po modyfikatorze "Smooth by Angle", to co eksporter widzi z `use_mesh_modifiers=True`) ma custom split normals genuinie gładkie przy wspólnych wierzchołkach (mediana **0.008°**). To był mocny sygnał, że problem jest eksportowy, nie geometryczny.

### Krok 3 — naprawa metodą Nuke'a: **SFALSYFIKOWANA empirycznie**

Osobny skrypt `_export_truck_0813_v6_smoothfix.py` (bez edycji `blender_ops.py`, zero ryzyka dla innych kitów), `mesh_smooth_type="OFF"` zamiast `"FACE"`. Eksport, upload (assetId `87224206173476`), insert do sceny osobno — **`MeshId` wyszedł BAJTOWO IDENTYCZNY z oryginalnym v6: `rbxassetid://109098196489733`**, potwierdzone dwukrotnie (raz na żywym `TruckPreview.Body`, raz na niezależnym scratch-insercie tego samego assetId, żeby wykluczyć błąd skryptu). Realny zrzut ze Studio po podmianie: **defekt wizualnie niezmieniony**, krystaliczne fasetowanie nadal wszędzie.

**Wniosek: Roblox's content pipeline przelicza/ignoruje eksportowane dane normalnych niezależnie od `mesh_smooth_type` ustawionego w FBX — to NIE jest bug eksportera, a przynajmniej nie jest to naprawialne przez tę flagę.** To bezpośrednio zaprzecza informacji przekazanej przez koordynatora, że równoległy agent Nuke_Warhead tą samą metodą (custom export z `mesh_smooth_type="OFF"`) potwierdził naprawę na realnych zrzutach ze Studio. **Rozbieżność nie wyjaśniona** — możliwe wytłumaczenia: (a) mesh Nuke'a miał inną charakterystykę geometrii, gdzie flaga faktycznie miała znaczenie, (b) weryfikacja po stronie Nuke'a/koordynatora nie porównała MeshId przed/po (mogła "wyglądać" lepiej z powodu innego kąta kamery/oświetlenia, nie realnej zmiany), (c) coś innego zmieniło się jednocześnie w ich pipeline. Nie badane dalej — poza zakresem tego zadania (nie mam dostępu do pracy Nuke'a).

### Krok "Plan B" — Corrective Smooth: **no-op, potwierdzone**

`_process_truck_0813_v6_geosmooth.py`: modyfikator `CORRECTIVE_SMOOTH` (factor=0.35, iterations=4, LENGTH_WEIGHTED, pin boundary), aplikowany na realną geometrię. Statystyki kątowe przed/po **identyczne co do 3 miejsc po przecinku** (mean 12.462→12.463, p50 8.107→8.104). Przyczyna: Corrective Smooth wygładza DELTĘ między pozycją zdeformowaną a spoczynkową (ORCO) — na statycznym meshu bez armatury/deformera delta=0, więc modyfikator nie robi nic. Lekcja pipeline'owa do zapamiętania: nie używać Corrective Smooth jako generycznego denoisera bez faktycznej deformacji w scenie.

### Krok "Plan C" — Laplacian smoothing (bmesh): **częściowo działa geometrycznie, ale wizualnie NIEWYSTARCZAJĄCE (3 iter) → SZKODLIWE (11 iter)**

`_process_truck_0813_v6_geosmooth2.py`: `bmesh.ops.smooth_laplacian_vert` (lambda=0.5, `preserve_volume=True`), 3 iteracje. Realnie przesuwa wierzchołki (w przeciwieństwie do Corrective Smooth). Mediana kąta spadła 8.1°→2.2° (-62% na medianie), ALE `max` rósł z każdą iteracją (83°→122°→152°) — pierwszy sygnał ostrzegawczy o rosnącym "ogonie" wierzchołków-outlierów. Eksport+upload+podmiana → **zrzut ze Studio pokazał defekt nadal obecny, koła wyglądały GORZEJ (bardziej postrzępione) niż przed wygładzaniem.**

Kontynuacja `_process_truck_0813_v6_geosmooth3.py` (8 KOLEJNYCH iteracji na tej samej, już raz wygładzonej siatce, 11 łącznie), z rozszerzonym samplerem śledzącym `p99`:

| iteracja (łącznie od startu v6) | p50 | p90 | p99 | mean | max |
|---|---|---|---|---|---|
| 3 (koniec geosmooth2) | 2.19 | 11.1 | — | 4.76 | 151.7 |
| 4 (+1) | 1.92 | 12.2 | 59.9 | 5.36 | 172.6 |
| 6 (+3) | 1.75 | 14.6 | 93.4 | 6.63 | 172.4 |
| 8 (+5) | 1.63 | 16.2 | 102.7 | 7.35 | 179.9 |
| 11 (+8, finał) | 1.54 | 19.0 | 106.2 | 7.93 | 177.7 |

**Interpretacja: `max` utyka w przedziale 172-180° od iteracji 4 do 11 — to niemal dokładnie 180°, czyli normalne dwóch sąsiednich trójkątów niemal antyrównoległe.** To nie jest "szum kątowy", to sygnatura fizycznego zawinięcia/samo-przecięcia siatki: `preserve_volume=True` chroni objętość GLOBALNIE, ale lokalnie cienkie/wklęsłe fragmenty (szprychy kół, cienkie krawędzie paneli) mogą się składać do siebie przy wielokrotnym Laplacian passie. `p99` rośnie monotonicznie (59.9°→106.2°) przez wszystkie 8 dodatkowych iteracji — rosnący ogon źle wygładzonych wierzchołków, nie stabilizujący się.

Eksport (`_export_truck_0813_v6_smoothfix.py` ponownie, na tej 11-iteracyjnej geometrii) → upload (assetId `133953577390967`) → podmiana `TruckPreview.Body` (nowy `MeshId: 96125443537029`, genuinie różny od poprzednich — potwierdza że realna zmiana geometrii dotarła do Robloxa) → **zrzut ze Studio: WYRAŹNY REGRES.** Kabina wygląda jak zgnieciona/zdeformowana, nie jak pojazd; koła mają postrzępioną, ząbkowaną sylwetkę (widoczne na screenshocie w tej sesji). To potwierdza wizualnie hipotezę fałdowania z tabeli powyżej — **11 iteracji Laplacian smoothing aktywnie NISZCZY tę siatkę, nie naprawia jej.**

**Natychmiastowa akcja: `TruckPreview.Body` przywrócony do oryginalnej, niesmoothowanej geometrii v6** (assetId `87224206173476`, `MeshId: 109098196489733`, identyczny z pierwotnym v6 bo to ten sam OFF-eksport który okazał się identyczny z FACE-eksportem) — to jest obecnie "najmniej zły" znany stan: rozpoznawalna ciężarówka z widocznym krystalicznym połyskiem, ale BEZ dodatkowego zniekształcenia geometrii. Potwierdzone zrzutem ze Studio w tej sesji.

### Otwarte kierunki (NIEZBADANE, NIE autoryzowane przez koordynatora — do decyzji)

1. **Właściwy remesh/retopologia** (np. Blender Voxel Remesh przy rozdzielczości zbliżonej do obecnej liczby trisów) — buduje topologię od zera z SDF zamiast perturbować istniejącą złą topologię. Nietestowane w tej sesji.
2. **Lewar materiałowy** — dalsze obniżenie Metalness / podniesienie Roughness ponad obecne klamry (max 0.35 / min 0.35) może zmniejszyć wrażliwość specular na szum normalnych, nawet bez zmiany geometrii. Nietestowane, nie ma pewności że pomoże.
3. **Akceptacja obecnego wyglądu** jako "stylizowany/znoszony batalistyczny" — odrzucone już raz przez użytkownika, prawdopodobnie nadal nieakceptowalne, ale wymieniam dla kompletności opcji.
4. Zbadać rozbieżność z wynikiem Nuke_Warhead — czy jego mesh/pipeline faktycznie się różnił, czy jego "sukces" był błędnie zweryfikowany.

Żadna z tych opcji nie została podjęta jednostronnie — trzy niezależne próby naprawy już wyczerpane i udokumentowane wyżej, sensowne zatrzymać się i poprosić o kierunek zamiast dalej losowo próbować, szczególnie że próba #3 (Laplacian) okazała się nie tylko nieskuteczna, ale szkodliwa.

---

## Co jeszcze NIE zrobione

1. **Zrzut z góry** — nie był konieczny do potwierdzenia głównych pytań tej rundy (koła, tekstura, montaż), pominięty. Centrowanie punktu montażu na szerokości dachu (lokalne Z=0) opiera się na symetrii bbox, nie na zrzucie z góry.
2. **NAPRAWA "krystalicznego" połysku — TRZY próby wyczerpane, WSZYSTKIE nieskuteczne lub szkodliwe (OFF-export sfalsyfikowany, Corrective Smooth no-op, Laplacian 3+8 iteracji uszkadza siatkę).** Model przywrócony do oryginalnej niesmoothowanej v6 geometrii jako najmniej zły znany stan. **Wymagana decyzja koordynatora o dalszym kierunku** — patrz "Otwarte kierunki" w sekcji v6.2→v6.5 wyżej i DO_DECYZJI.md.
3. **`WR_StrikeModels.Truck` (produkcyjny szablon)** nadal wskazuje na STARY placeholder mesh — celowo nietknięty, do decyzji ownera kiedy/czy podmienić na produkcji.

## DoD — status (v6, zastępuje w całości tabelę v5)

| pozycja | status |
|---|---|
| `:9979`/upload health = grupa RNG | ✅ |
| wysokość = 8.000 studs | ✅ dokładnie, BEZ sztucznej korekty (surowa geometria) |
| długość | ℹ️ 17.902 (zgodność z oryginałem GLB, nie z zakresem 18-22 — koordynator: nieistotne teraz) |
| tris | ℹ️ 788 614 — ŚWIADOMIE bez limitu 2500-3000 (porzucony), lokalny walidator FAIL ale **Roblox przyjął bez zastrzeżeń (Approved/Active)** |
| **koła okrągłe (render)** | ✅ PASS na wąskie kryterium kształtu, ale **NIE ZASTĘPUJE** ogólnej oceny modelu — patrz niżej |
| **wygląd nadwozia jako spójna oliwkowa ciężarówka (kryterium ostateczne — czy wygląda dobrze jako całość)** | ❌ **FAIL — model odrzucony przez użytkownika.** "Krystaliczny" połysk to DOMINUJĄCA cecha z każdego kąta, nie subtelny efekt kątowy jak pierwotnie (błędnie) oceniłem. Diagnoza i naprawa w toku, patrz "v6.1" |
| non-manifold/loose/ngons | ✅ 0/0/0 (lepsze niż v5) |
| metal max ≤0.35 po klamrze | ✅ 0.4196→0.3500 (ponownie użyte z v5, ten sam plik) |
| rough min ≥0.35 po klamrze | ✅ 0.3490→0.3500 (ponownie użyte z v5, ten sam plik) |
| upload Model | ✅ `127150449904067`, Approved/Active |
| upload tekstur | ✅ ponownie użyte assety v5 (już Approved/Active), bez ponownego uploadu |
| insert do placu | ✅ `TruckPreview.Body` zastąpiony v6, preview only |
| tekstura renderuje się poprawnie w Studio | ✅ potwierdzone wizualnie, bez opóźnienia CDN tym razem |
| brak samoświecenia | ✅ (ten sam pipeline emisji co v5, potwierdzone wizualnie brak poświaty) |
| punkt montażu minigunu jako `Attachment` | ✅ `MinigunMount_1_CabinRoof`, lokalnie (7, 3.4, 0), świat (15.299238, -14.836938, 436.243896), potwierdzone wizualnie na nowej geometrii |
| zrzut ze Studio z widoczną klatką, realnie obejrzany | ✅ 3 zrzuty (iso z markerem / nisko-podwoziowy / boczny) |
| **"krystaliczny" połysk — status naprawy** | 🔴 NIEROZWIĄZANE. 3 próby wyczerpane: OFF-export sfalsyfikowany (identyczny MeshId), Corrective Smooth no-op, Laplacian 3+8 iter uszkadza siatkę (fałdowanie, max kąt ~172-180°). Przywrócono oryginalną v6 geometrię. Czeka na decyzję koordynatora |

## Zmiany w repo (cała robota nad ciężarówką)

- `D:\RobloxProjects\rng\_oc_sanity_check.py`
- `D:\RobloxProjects\rng\mesh\_scale_ruler_rng.py`
- `D:\RobloxProjects\rng\mesh\_diag_truck_0813.py`, `_diag_truck_0813_nodes.py`
- `D:\RobloxProjects\rng\mesh\_process_truck_0813_v3.py` → `_v4.py` → `_v5.py` → **PORZUCONE, zastąpione przez `_v6.py`** (zero decymacji, finalny), `_wheeldetect_tune.py`, `_zfix.py` (wchłonięty do v4/v5), `_lightfix.py`, `_wheelcheck.py`…`_wheelcheck6.py`/`_wheelcam.py` (diagnostyka, odrzucona), `_cleanup.py`
- `D:\RobloxProjects\rng\mesh\_process_truck_0813_v6.py` — **NOWY, finalny pipeline** (fresh import, unpack, strip emisji, remove_doubles 0.0006, recalc normals, auto-smooth, origin bottom-center, apply scale, ZERO decymacji)
- `D:\RobloxProjects\rng\mesh\_process_truck_0813_textures.py` (użyte, wyniki ponownie wykorzystane w v6 bez ponownego uruchomienia)
- `D:\RobloxProjects\rng\mesh\_diag_truck_0813_normals.py` — diagnostyka normalnych (job `f7b5f64f903a`)
- `D:\RobloxProjects\rng\mesh\_export_truck_0813_v6_smoothfix.py` — osobny eksport `mesh_smooth_type="OFF"`, użyty dwukrotnie
- `D:\RobloxProjects\rng\mesh\_process_truck_0813_v6_geosmooth.py` — Corrective Smooth (no-op, potwierdzone)
- `D:\RobloxProjects\rng\mesh\_process_truck_0813_v6_geosmooth2.py` — Laplacian ×3 (niewystarczające)
- `D:\RobloxProjects\rng\mesh\_process_truck_0813_v6_geosmooth3.py` — Laplacian ×8 dodatkowe, 11 łącznie (szkodliwe, wycofane)
- `RAPORT_truck.md`, `DO_DECYZJI.md` — zaktualizowane

Żadnego kodu Luau nie tknięto. Rojo/dysk WAR RNG nietknięte poza plikami assetowymi w `rng\mesh\` i `rng\`. Jedyna zmiana w samym placu Studio: insert do `Workspace.TruckPreview` (preview, nie produkcja, teraz na bazie v6) — `WR_StrikeModels.Truck` (produkcyjny szablon) nietknięty.

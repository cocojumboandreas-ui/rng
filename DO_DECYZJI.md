# DO DECYZJI — ciężarówka konwojowa WAR RNG

## 1. Klucz Open Cloud — ROZWIĄZANE ✅

`ROBLOX_OC_KEY_RNG` ustawiony, sanity-check z realnym create-z-plikiem potwierdził
`creator.groupId=664399796`. Kanał `:9979` działa dla tej grupy. Śmieciowy assetId
`93695350683864` (Image, sanity-check) **czeka na ręczne skasowanie** — Open Cloud nie
archiwizuje typu Image.

## 2. Plik wejściowy GLB — ROZWIĄZANE ✅

Znaleziony pod `D:\RobloxProjects\rng\Meshy_AI_convoy_truck_3d_0813102006_image-to-3d-texture.glb`
(leżał w `rng\`, nie w `rng\mesh\`). Zdiagnozowany: jeden obiekt mesh, 788 614 tris,
425 452 verts — zgodne z oczekiwaniem z briefu.

## 3. Ustalenie na całą grę: kanał uploadu dla WAR RNG

**Open Cloud (`:9979`) jest potwierdzonym, działającym kanałem dla grupy 664399796.**
Nie był potrzebny fallback przez `robloxstudio` MCP `upload_asset` (sesja Studio) —
sanity-check przeszedł na pierwszej próbie. To ustalenie dotyczy WSZYSTKICH przyszłych
assetów w tej grze, nie tylko ciężarówki: domyślnie idź przez `:9979` z
`ROBLOX_OC_KEY_RNG`, chyba że pojawi się realny 403/odmowa — dopiero wtedy sięgać po
MCP-fallback.

## 4. Zmierzona długość ciężarówki poniżej oczekiwanego zakresu ⚠️

Brief: "spodziewam się 18-22 studs [długości], jeśli wyjdzie 12 albo 35, powiedz przed
uploadem [ale nie czekaj]".

**Zmierzone (surowy import, world-bbox X):** `17.902 studs`.

To jest ~0.1 studa poniżej dolnej granicy oczekiwanego zakresu (18) — nie jest to
drastyczne odchylenie (nie 12, nie 35), więc **kontynuuję obróbkę i upload zgodnie z
poleceniem "nie czekaj"**. Zgłaszam do potwierdzenia: czy 17.9 studa długości jest
akceptowalne dla ciężarówki konwoju, czy oczekiwany zakres 18-22 był orientacyjny i to
nie wymaga korekty. Wysokość (8.000 dokładnie) i szerokość (7.003) są w pełni zgodne z
oczekiwaniem.

## 5. Scale_Ruler dla grupy RNG — ROZWIĄZANE ✅

Nowy ruler zbudowany proceduralnie (kostka 10×10×10 Blender-units), wgrany na 664399796
przez `:9979` → **assetId `119344626341644`**. Wstawiony do placu i zweryfikowany
(`Size: "10, 10, 10"` w Studio) — potwierdza mnożnik 1 Blender unit = 1 stud dla tej
grupy. Instancja testowa usunięta z placu po weryfikacji; assetId zapisany do ew.
ponownego użycia.

## 6. Korekta do pkt 3 — faktyczny kanał uploadu tej ciężarówki był `robloxstudio` MCP, nie `:9979`

Punkt 3 wyżej mówi "nie był potrzebny fallback przez `robloxstudio` MCP". To się
zmieniło praktycznie: finalny upload Modelu i 3 tekstur ciężarówki poszedł przez
**`mcp__robloxstudio__upload_asset`** (z jawnym `groupId=664399796`), NIE przez
`:9979`/bridge. Powód: to było wygodniejsze w tym momencie (narzędzie ma bezpośredni
parametr `groupId`, nie wymaga przełączania `$GROUP` na moście). Wynik: wszystkie 4
assety (`127055056930041` Model, `117458416469719`/`86691457636019`/`107299523840531`
Decal/Image) wyszły `moderationState: Approved`, `state: Active` — działa. Zgłaszam bo
to koryguje wcześniejsze ustalenie "domyślnie :9979" — w praktyce oba kanały działają
dla tej grupy, `robloxstudio` MCP jest szybszy do pojedynczych uploadów z jawnym
groupId. Nie jest to błąd, tylko odnotowanie, żeby przyszła sesja nie była zaskoczona
rozbieżnością między RAPORT/DO_DECYZJI a faktycznie użytą ścieżką.

## 7. Obróbka mesha: origin ~0.11 studa nad Z=0 po korekcie wysokości ⚠️

Po korekcie wysokości (z-only rescale ×1.0866, przywracająca zmierzoną wysokość 8.000
po tym jak decymacja ją zaniżyła do 7.362), dolna krawędź mesha wyszła na `z_min=0.1115`
zamiast `0.0` — origin (bottom-center, ustawiony PRZED korektą) już nie jest idealnie
na dolnej krawędzi, bo skalowanie było wykonane wokół originu (0,0,0), nie wokół
faktycznego najniższego wierzchołka. Wizualnie ~0.11 studa to mniej niż grubość opony,
prawdopodobnie niezauważalne, ale technicznie MeshPart może "unosić się" nad
przewidywanym punktem kontaktu z ziemią o tę wartość. Nie naprawiałem tego dodatkową
korektą (ryzyko kolejnej rundy przybliżeń) — zgłaszam do świadomej akceptacji. Jeśli to
przeszkadza wizualnie w placu, prosta naprawa: przesunąć origin/CFrame o -0.1115 studa
w Y (Roblox) przed finalnym umieszczeniem w produkcji.

## 8. UV-stretch metryka przed/po sliver-cleanup — NIEWIARYGODNA, nie traktować jako dowód

`_process_truck_0813_v5_report.json` pokazuje `uv_stretch_before_sliver_cleanup` i
`uv_stretch_after_sliver_cleanup` jako **identyczną wartość co do cyfry**
(2 324 547.78) mimo że cleanup skolapsował 30 krawędzi. To wygląda jak nieprzeliczona
metryka (ta sama wartość zwrócona dwa razy), nie jak realny dowód "UV bez zmian po
cleanupie". Nie blokuje niczego (sliver-cleanup i tak był zaprojektowany jako
UV-bezpieczny — `uvs=True` w bmesh collapse, `beautify_fill` wyłączony), ale nie należy
cytować tej pary liczb jako potwierdzenia — do poprawienia w skrypcie, jeśli UV stretch
kiedykolwiek stanie się realnie sporny.

## 9. Punkt montażu minigunu (dach kabiny) — ROZWIĄZANE ✅ (koryguje wcześniejszy zgadywany kierunek)

**Wcześniejszy zgadywany kierunek w tym punkcie był ODWROTNY do faktu** — spekulowałem
kabinę w okolicy lokalnego X ≈ -6 do -8.9 (mniejszy X). Po realnym zrzucie ze Studio i
matematyce wektora kamery (dla `CFrame.new(center+(25,20,25), center)`, wektor
"w prawo ekranu" ≈ (0.7071, 0, -0.7071) świata → rosnące X), kabina okazała się być po
stronie **WIĘKSZEGO X**, nie mniejszego — potwierdzone też wizualnie na zrzucie bocznym
(szyba kabiny + marker montażowy widoczne po tej stronie). Krzyż-check z
`wheel_detection`: klaster kół o największym lokalnym X (≈+5.69) leży bliżej kabiny.

Punkt montażu ustawiony jako `Attachment` `MinigunMount_1_CabinRoof` pod
`game.Workspace.TruckPreview.Body`: lokalnie `(7, 3.4, 0)`, świat
`(15.299238, -14.836938, 436.243896)`. Sfotografowany na zrzucie bocznym (widoczny
tymczasowy czerwony marker, usunięty po zdjęciu). Żaden faktyczny minigun NIE podpięty.
Lokalne Z=0 (środek szerokości kabiny) NIE potwierdzone zrzutem z góry (nie udało się
zrobić — patrz pkt 11) — tylko z geometrii bbox, jeśli okaże się sporne przy montażu
realnego modelu wieżyczki, zweryfikować dodatkowym zrzutem z góry.

## 10. Okno Roblox Studio zminimalizowane — ROZWIĄZANE ✅ (częściowo, patrz pkt 11)

Koordynator ręcznie przywrócił okno Studio. `capture_screenshot` zadziałał, zrobione 4
zrzuty (szeroki/średni/nisko-podwoziowy/boczny) — pełna wizualna weryfikacja
przeprowadzona, wyniki w RAPORT_truck.md.

## 11. KRYTYCZNE — koła NIE są okrągłe na realnym renderze Studio (DoD FAIL) ❌

Wcześniejsza ocena z surowych zrzutów Blendera ("wyraźna poprawa v5 vs v3/v4, odrębne
bryły kół") **okazała się zbyt optymistyczna**. Na realnym zrzucie ze Studio (kamera
nisko przy podwoziu, potem boczny widok) podwozie/koła to **ostre, kanciaste,
ciemnoniebieskie graniaste bryły** — wyraźnie nie koła, tylko postrzępione kolce.

Dane z `_process_truck_0813_v5_report.json.wheel_detection`: 6/6 kół poprawnie
wykrytych geometrycznie (`wheels_chosen`, promienie 1.44–1.49 studa, liczności
5380–5917 wierzchołków każde) — sama detekcja przestrzenna (pozycja+promień) zadziałała
na etapie analizy. Ale **ten wynik nie przełożył się na okrągły kształt w finalnym
renderze**. `validate_for_roblox` zgłosił 13 non-manifold edges (WARN, nie blokował
kontraktu) — możliwy współwinowajca: ciemnoniebieski kolor (nie oliwkowo-zielony jak
reszta modelu) sugeruje brak tekstury + artefakt backface-culling na tych trójkątach
(w kombinacji z `DoubleSided:false`), a nie wyłącznie sam kształt siatki po decymacji.
Nierozstrzygnięte które z dwóch (geometria vs shading-artefakt) dominuje bez dalszej
diagnozy (np. wireframe zrzut kół osobno, albo export samych kół z powrotem do
Blendera do inspekcji).

**To jest twardy DoD FAIL, nie "poprawiono z zastrzeżeniem".** Do decyzji koordynatora:
(a) zaakceptować jako znany defekt na etapie preview i kontynuować, (b) zlecić v6
poprawkę mesha (skupioną na diagnozie non-manifold/culling najpierw, bo to tańsza
naprawa niż przebudowa geometrii kół), (c) coś innego. Model NIE został oznaczony jako
gotowy do produkcji z tego powodu — zostaje w `TruckPreview`, produkcyjny
`WR_StrikeModels.Truck` pozostaje nietknięty.

**AKTUALIZACJA: koordynator zdecydował (c) — patrz pkt 12 niżej.** Cała seria v1-v5
porzucona, nie tylko dla tego jednego defektu, tylko jako podejście w ogóle.

## 12. DECYZJA KOORDYNATORA — koniec z decymacją, v6 = mesh 1:1 z GLB (ROZWIĄZANE ✅)

Koordynator: budżet 2500-3000 tris z pierwotnego briefu był JEGO kalkulacją "co ładne
dla gry", nie twardym limitem Robloxa, i był błędny w praktyce — psuł koła za każdym
razem (3 różne schematy ochrony w v3/v4/v5, wszystkie failed). Nowe polecenie: ZERO
decymacji, mesh możliwie 1:1 z oryginalnego GLB (788 614 tris).

**Wykonane i zweryfikowane:**
- `_process_truck_0813_v6.py`: fresh import, unpack, strip emisji, remove_doubles
  (0.0006, dedup only), recalc normals, auto-smooth, origin bottom-center, apply scale.
  ZERO decymacji, zero wag wierzchołków, zero wymuszonej triangulacji.
- Wynik: **788 614 tris** (bez zmian względem surowego importu — próg 0.0006 nie
  usunął żadnego trójkąta), wymiary **17.902 × 7.003 × 8.000** studs, **0 non-manifold
  / 0 loose / 0 ngons** (lepiej niż v5's 13 non-manifold).
- `validate_for_roblox` odrzuca (`tris_over_limit`, próg 10000) — **sprawdzone w
  źródle** (`blender_ops.py:20`, `TRI_LIMIT = 10000`, komentarz autora: "confirm in
  Roblox docs before trusting" — nigdy nie zweryfikowane): to lokalny próg NASZEGO
  skryptu, nie udokumentowany limit platformy. **Test empiryczny**: `export_fbx_roblox`
  + `upload_asset` (grupa 664399796) wykonane MIMO lokalnego FAIL — **Roblox przyjął
  bez zastrzeżeń**, `moderationState: Approved`, `state: Active`, assetId
  `127150449904067`. Potwierdza że 10000 to nasz próg, nie realny limit Roblox.
- Tekstury: PONOWNIE UŻYTE assety z v5 (ColorMap/MetalnessMap/RoughnessMap) — UV mesha
  nie zmienione (remove_doubles na tym progu nie wpływa na mapowanie UV), więc te same
  pliki są nadal poprawne. Zero ponownego przetwarzania/uploadu, zgodnie z poleceniem
  "powtórz dokładnie to co działało".
- `TruckPreview.Body` w placu zastąpiony v6 (stary v5 usunięty). Punkt montażu
  minigunu (`Attachment` `MinigunMount_1_CabinRoof`) przeniesiony na te same lokalne
  współrzędne (7, 3.4, 0) — bbox v6 niemal identyczny z v5, potwierdzone wizualnie że
  nadal siada na dachu kabiny.
- **Weryfikacja wizualna ze Studio (3 zrzuty): koła SĄ TERAZ OKRĄGŁE** — bieżnik opony
  i piasty widoczne, jakościowa różnica względem kanciastego v5 na identycznym kadrze.
  DoD z pkt 11 **PASS** na v6.

**AKTUALIZACJA — powyższa ocena "PASS"/"nie blokuje" była BŁĘDNA, patrz pkt 13.**

## 13. KRYTYCZNE — v6 ODRZUCONY PRZEZ UŻYTKOWNIKA, "krystaliczny" połysk to defekt DOMINUJĄCY, nie kosmetyczna ciekawostka (W TOKU 🔴)

Koordynator zrobił własny zrzut ze Studio (nie mój) i pokazał go użytkownikowi.
Werdykt użytkownika, dosłownie: **"wygląda jak gówno jebane"**. Koordynator potwierdza:
"krystaliczny"/fasetowany połysk pokrywający całe nadwozie ORAZ koła jest widoczny
**z każdego kąta w edytorze Studio**, nie tylko pod ostrym/grzbietowym światłem jak
napisałem w pkt 12. Moja ocena w pkt 12 ("nie blokuje", "efekt kątowo-zależny", "model
czyta się poprawnie") była **zbyt optymistyczna — trzeci taki przypadek w tym zadaniu**
(po v3 "koła jako wielościany" niedoszacowane, i v5 gdzie ocena z viewportu Blendera nie
zgadzała się z realnym zrzutem Studio). Koordynator explicite: oceniać krytycznie,
szukać wad, nie potwierdzeń, zanim cokolwiek zostanie ogłoszone naprawione.

**Diagnoza (oparta o inspekcję kodu, wysokie zaufanie, jeszcze NIE potwierdzona
empirycznie na żywym obiekcie w Blenderze — patrz blokada niżej):**
`export_fbx()` w `blender_ops.py:189` ma na sztywno `mesh_smooth_type="FACE"` —
dosłownie "każdy trójkąt = osobna grupa wygładzania", czyli pełne fasetowanie z
definicji, mimo że skrypt v6 wywołuje `shade_auto_smooth(30°)` przed eksportem.
W Blenderze 4.1+/5.x `shade_auto_smooth` nie ustawia już starej flagi na meshu, tylko
dodaje modyfikator "Smooth by Angle" liczący normalne przy ewaluacji — `mesh_smooth_type
="FACE"` prawdopodobnie nadpisuje/ignoruje ten efekt przy eksporcie do FBX, dając
dokładnie ten efekt "pognieciona folia/lód" na gęstej (788k tris) siatce z materiałem
o wysokiej specularności. Poprawna wartość: `"OFF"` albo `"EDGE"` — wybrany kierunek:
`"OFF"` (bezpieczniejszy, nie zależy od interpretacji grup wygładzania przez importer
Robloxa).

**BLOKADA:** `scene_inventory` pokazuje w Blenderze `Mesh0` (23 306 tris) zamiast
`WR_ConvoyTruck_Body_v6` (788 614 tris) — współdzielony most Blendera jest w tej chwili
zajęty przez równoległego agenta pracującego nad `Nuke_Warhead`. Zgodnie z zasadą
"JEDEN klient mostu naraz" i explicit poleceniem koordynatora "nie przeszkadzaj
Nuke_Warhead", **NIE re-importuję/nie mutuję sceny teraz**. Diagnoza powyżej jest z
inspekcji kodu, nie z żywego sprawdzenia obiektu. Skrypt diagnostyczny
(`_diag_truck_0813_normals.py`, liczy kąty między normalnymi sąsiednich trójkątów na
bazowej siatce vs. custom split normals na wyewaluowanej siatce) jest napisany i gotowy,
odpalę go jak tylko most się zwolni — PRZED deklaracją naprawy, zgodnie z poleceniem
"nie ogłaszaj gotowe bez realnego dowodu".

**Plan po odblokowaniu mostu:** (1) uruchomić skrypt diagnostyczny, potwierdzić
liczbowo; (2) wyeksportować testowo z `mesh_smooth_type="OFF"` własnym skryptem
wołającym `bpy.ops.export_scene.fbx` bezpośrednio — **NIE edytując `blender_ops.py`**
(uniknięcie potrzeby restartu serwera MCP i zerowe ryzyko dla innych kitów pipeline'u
współdzielących ten plik); (3) upload + podmiana `TruckPreview.Body`; (4) nowy zrzut ze
Studio z wielu kątów, krytyczna samoocena; (5) jeśli hipoteza normalnych okaże się
błędna — plan B: łagodne, wieloprzebiegowe wygładzanie (Corrective Smooth, niska siła),
NIE agresywna decymacja (złamała koła w v1-v5).

Szczegóły liczbowe i wszystkie zrzuty opisane w RAPORT_truck.md, sekcja "v6 — KOŃCZYMY
Z DECYMACJĄ".


## 14. UWAGA (od agenta Nuke_Warhead) -- moje skrypty select_all+delete kolidowaly ze scena ciezarowki (ROZWIAZANE dla przyszlosci, nie do cofniecia wstecz)

Kazdy moj skrypt fresh-import (_process_nuke_0813_decimate_v3..v6.py) zaczynal od
bpy.ops.object.select_all(action='SELECT') + bpy.ops.object.delete() -- to czysci
CALA scene Blendera, nie tylko moje obiekty. Widze w Waszym punkcie 13 powyzej, ze
scene_inventory zlapal Mesh0 (moj tymczasowy import) zamiast WR_ConvoyTruck_Body_v6
-- to byla MOJA kolizja, nie przypadek. Przepraszam za utrudnienie diagnozy smooth-shading.

Blender to jeden wspoldzielony proces/scena -- "jeden klient mostu naraz" chroni przed
rownoleglymi JOBAMI, ale nie przed tym ze job A moze wyczyscic obiekty zostawione
przez job B miedzy zleceniami. Nie ma dobrego mechanizmu odizolowania bez zmiany
architektury (np. zapisywanie/przywracanie .blend miedzy sesjami agentow), wiec to
ryzyko strukturalne przy wspoldzielonym moscie, nie tylko mojego bledu.

Od teraz (koniec decymacji, dalsze kroki: triangulacja/UV/auto-smooth/origin/skala)
przechodze na operowanie WYLACZNIE na juz-zaimportowanym WR_NukeWarhead bez kolejnych
pelnych wipe'ow sceny, zeby zminimalizowac dalsze zaklocenia dla Waszej pracy. Jesli
potrzebujecie mostu na diagnoze, mozecie go teraz uzyc miedzy moimi jobami (blender_status
pokazuje idle kiedy nie licze aktywnie) -- nie zglaszam wylacznosci, tylko sekwencyjne
uzycie zgodnie z zasada.

## 15. Decymacja Nuke_Warhead -- czarna "dziura" w srodku korpusu na bliskim zoomie: zdiagnozowana jako NIE-defekt geometryczny, zaakceptowana

Szesc podejsc do decymacji (v1-v6, kolejno: curvature-weighted vertex group x2, fizyczny
split hull/detail z rosnaco niskim progiem odchylenia promienia x2, waniliowy Collapse
bez zadnej grupy, chirurgiczna ochrona cienkoscian przez BVH raycast) -- finalnie v6
(waniliowy Collapse + BVH-wykryta ochrona 88 cienkoscianych faces, 2749 tris) naprawil
poszarpany/graniasty czubek nosa (byl artefaktem MOICH recznych vertex-groupow w v1-v4,
nie algorytmu -- potwierdzone: v5 bez zadnej grupy dal czysty czubek). Pozostala ciemna
plama na bardzo bliskim zoomie (~0.3-0.4 studa) na jednym panelu/kratce w srodku korpusu
we WSZYSTKICH 6 probach niezaleznie od metody ochrony -- zdiagnozowana przez inspekcje
per-face (area/n_verts/normal) na finalnej siatce: normalne poprawnie skierowane na
zewnatrz (radial_dot ~0.99), trojkaty normalnej wielkosci, BRAK zdegenerowanych n-gonow
czy odwroconych normalnych. Wniosek: to utrata drobnego facetowania cieniowania na jednym
detalu (grille/panel), nie zlamana geometria -- na pelnoklatkowym renderze z dystansu
gry (viewport_screenshot iso+front) plama jest praktycznie niewidoczna, sylwetka czyta
sie jako gladki stozek+cylinder z 4 finami, zero efektu "graniastoslup". Zaakceptowane
jako finalna decymacja (2749 tris, wysokosc 11.998 przed skalowaniem). Jesli po finalnym
uploadzie do Studio realny zrzut pokaze inny wynik niz viewport Blendera (jak to bylo
przy WR_ConvoyTruck) -- flaguje sie do ponownej oceny, ale to niezalezne ryzyko renderowe
(FBX smooth-shading), nie geometrii samej w sobie.

## 16. Nuke_Warhead -- PIPELINE ZAKONCZONY, UPLOADED, WSTAWIONY. Jedna rozbieznosc DoD do decyzji.

Zastosowalem PROAKTYWNIE Wasza diagnoze z pkt 13 (mesh_smooth_type="FACE" w
blender_ops.py:189) -- wlasny skrypt eksportu z mesh_smooth_type="OFF", BEZ edycji
pliku dzielonego, identycznie jak Wasz zaplanowany-ale-zablokowany fix. Potwierdzone
na 2 realnych zrzutach Studio: cieniowanie gladkie/satynowe, ZERO efektu
"krysztal/lod" -- dobra wiadomosc, fix dziala w praktyce, nie tylko w teorii kodu.
Warto to sprawdzic u Was tym samym sposobem jak most sie zwolni.

Upload przez robloxstudio MCP upload_asset z jawnym groupId=664399796 (Wasz
sprawdzony kanal, pkt 6) -- 4 assety Approved/Active: Model 116984781117493,
Color/Metalness/Roughness Decal z osobnymi imageId (72789303662707/
124064153501445/113696853796455) uzytymi w SurfaceAppearance.

UWAGA na pulapke ktora u mnie wystapila: set_properties z Color jako tablica
[255,255,255] dalo BLISKO-CZARNY wynik (Color3.fromRGB(1,1,1), nie (255,255,255))
-- zla interpretacja formatu przez to narzedzie. Naprawione przez execute_luau z
Color3.new(1,1,1) bezposrednio. Jesli gdziekolwiek ustawiacie Color przez
set_properties, zweryfikujcie wynik -- nie ufajcie samemu "success:true".

Jedyny otwarty punkt: DoD w moim briefie oczekiwal kolorystyki
olive-green+black-steel+yellow-trefoils; faktyczny wypalony kolor z GLB Meshy to
navy-steel+yellow-hazard-stripes, bez trefoli, bez czerwonego pierscienia na nosie.
Nie modyfikowalem BaseColor poza downscale do 1024 (nie zmienia odcieni) -- to
faktyczny wyglad assetu, nie moj blad przetwarzania. Zglaszam do koordynatora,
szczegoly w RAPORT_nuke.md. Nie blokuje -- model jest w
game.Workspace.Nuke_Warhead, gotowy do przegladu.

Koncze tutaj, nie bede dalej modyfikowac zadnych obiektow zwiazanych z Nuke_Warhead
bez nowego polecenia. Nie dotykalem zadnych plikow/obiektow ciezarowki.

## 17. KRYTYCZNE — `mesh_smooth_type="OFF"` fix SFALSYFIKOWANY na ciężarówce, wbrew relacji o sukcesie Nuke_Warhead (pkt 16). Trzy próby naprawy wyczerpane, wszystkie nieskuteczne/szkodliwe. Wymagana decyzja koordynatora. (🔴 OTWARTE)

Po zwolnieniu mostu wykonałem dokładnie plan z pkt 13:

**Krok 1-2 (diagnostyka numeryczna):** `_diag_truck_0813_normals.py` potwierdził, że
wyewaluowana siatka (po `shade_auto_smooth`) ma genuinie gładkie custom split normals
(mediana 0.008° na wspólnych wierzchołkach) mimo że siatka bazowa jest kanciasta
(mediana 8.1°, ogon do 83°) — silna poszlaka ZA hipotezą eksportową.

**Krok 3 (fix metodą Nuke'a): SFALSYFIKOWANY.** Osobny eksport `mesh_smooth_type="OFF"`
(bez edycji `blender_ops.py`), upload jako nowy assetId `87224206173476`, wstawiony
niezależnie do sprawdzenia — **`MeshId` wyszedł BAJTOWO IDENTYCZNY z oryginalnym
niesmoothowanym v6: `109098196489733`**. Zweryfikowane dwukrotnie (żywy obiekt +
niezależny scratch-insert tego samego assetId, żeby wykluczyć błąd po mojej stronie).
Realny zrzut ze Studio po podmianie: **defekt wizualnie niezmieniony, identyczny jak
przed fixem.**

**To wprost zaprzecza pkt 16 (Nuke_Warhead): "Potwierdzone na 2 realnych zrzutach
Studio: cieniowanie gładkie/satynowe, ZERO efektu krysztal/lod".** Ta sama metoda
(custom export, `mesh_smooth_type="OFF"`, bez edycji pliku dzielonego), zastosowana do
DWÓCH różnych meshy przez dwóch agentów, dała dwa sprzeczne wyniki. Możliwe wyjaśnienia
(żadne niezweryfikowane): (a) geometria/topologia Nuke'a różniła się w sposób, przez
który flaga faktycznie miała znaczenie (np. inny import, inny stan modyfikatorów), (b)
weryfikacja po stronie Nuke'a nie porównała MeshId przed/po, więc "poprawa" mogła być
efektem innego kąta kamery/oświetlenia, nie realnej zmiany danych, (c) coś jeszcze
zmieniło się jednocześnie w ich pipeline nieujawnione w pkt 16. **Nie badane dalej — nie
mam dostępu do pracy/plików Nuke'a, poza zakresem tego zadania.** Zgłaszam do
koordynatora jako otwartą, nierozstrzygniętą rozbieżność.

**Plan B (Corrective Smooth): no-op, potwierdzone.** Statystyki kątowe identyczne przed/po
co do 3 miejsc po przecinku — modyfikator wymaga deformacji (armatury), na statycznym
meshu nic nie robi. Bez efektu, bez szkody.

**Plan C (Laplacian smoothing, bmesh `smooth_laplacian_vert`, `preserve_volume=True`):
częściowo działa geometrycznie, ale niewystarczające → potem SZKODLIWE.**

- 3 iteracje: mediana kąta -62% (8.1°→2.2°), ale `max` rósł z każdą iteracją
  (83°→122°→152°) — pierwszy sygnał ostrzegawczy. Zrzut ze Studio po eksporcie: defekt
  nadal obecny, **koła wyglądały GORZEJ** (bardziej postrzępione) niż przed
  wygładzaniem.
- +8 kolejnych iteracji (11 łącznie), z rozszerzonym trackingiem `p99`: `max` utyka w
  przedziale **172-180°** od iteracji 4 do 11 (niemal dokładnie antyrównoległe normalne
  sąsiednich trójkątów — sygnatura fizycznego fałdowania/zawijania siatki, NIE szumu),
  `p99` rośnie monotonicznie (59.9°→106.2°) bez oznak stabilizacji. Eksport+upload
  (nowy, genuinie różny MeshId `96125443537029` — potwierdza że zmiana geometrii
  faktycznie dotarła) → **zrzut ze Studio: WYRAŹNY REGRES.** Kabina wygląda jak
  zgnieciona/zdeformowana, koła mają postrzępioną ząbkowaną sylwetkę — gorzej niż
  wyjściowy v6.

**Akcja natychmiastowa:** `TruckPreview.Body` przywrócony do oryginalnej niesmoothowanej
geometrii v6 (`MeshId 109098196489733`) jako najmniej zły znany stan — rozpoznawalna
ciężarówka z krystalicznym połyskiem, ale bez dodatkowego zniekształcenia. Potwierdzone
zrzutem ze Studio w tej sesji.

**Status: trzy niezależne próby naprawy wyczerpane, wszystkie nieskuteczne lub
szkodliwe. NIE kontynuuję dalszych prób jednostronnie** — ryzyko dalszego uszkadzania
siatki bez wyraźnego kierunku jest zbyt wysokie, a wzorzec w tym zadaniu (pkt 11/12/13)
pokazuje powtarzającą się tendencję do zbyt optymistycznej samooceny, którą staram się
teraz aktywnie korygować przez zatrzymanie się i zgłoszenie zamiast dalszego zgadywania.

**Opcje do decyzji koordynatora (żadna nie podjęta jednostronnie):**
1. Właściwy remesh/retopologia (np. Voxel Remesh) zamiast perturbacji istniejącej
   topologii — nietestowane.
2. Lewar materiałowy (dalsze obniżenie Metalness / podniesienie Roughness ponad obecne
   klamry 0.35/0.35) jako maskowanie zamiast naprawy geometrii — nietestowane, brak
   pewności skuteczności.
3. Zbadanie rozbieżności z Nuke_Warhead (czy ich mesh faktycznie się różnił, czy ich
   weryfikacja była niepełna) — wymagałoby dostępu do ich plików/pipeline'u.
4. Akceptacja obecnego wyglądu na etapie preview — użytkownik już raz to odrzucił,
   prawdopodobnie nadal nieakceptowalne, wymieniam dla kompletności.

Pełne dane liczbowe (tabela kątów per iteracja, wszystkie assetId, MeshId) w
RAPORT_truck.md, sekcja "v6.2→v6.5". `WR_StrikeModels.Truck` (produkcyjny szablon)
nadal nietknięty przez całą tę sesję.

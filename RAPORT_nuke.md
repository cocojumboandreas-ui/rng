# RAPORT — Nuke_Warhead (WAR RNG, grupa 664399796)

Praca wykonana niezaleznie od rownoleglego agenta ciezarowki (WR_ConvoyTruck), bez
dotykania jego plikow/obiektow. Wspoldzielony DO_DECYZJI.md czytany i uzupelniany
na biezaco (sekcje 14-15 + niniejszy final).

## Wejscie

`D:\RobloxProjects\rng\Meshy_AI_Nuke_Warhead_Quad_Rem_0813120329_texture.glb`
(28 849 464 B, 23 306 tris raw, 1 material "material.001" z BaseColor +
MetallicRoughness 4096x4096, emisja obecna w materiale ale WYLACZONA/strippowana
przed dalsza obrobka).

## Trzy pytania specyficzne dla assetu — rozstrzygniete

1. **Grubosc finow.** Pomiar BVH raycast (rzut z centrum kazdego face finow wzdluz
   -normal): mediana grubosci 0.346 studa. Uznane za wystarczajace, ZERO Solidify.
2. **Dysza ogonowa: recess czy plaski korek.** Numeryczny raycast dawal falszywy
   sygnal "plaskie", ale wizualne renderowanie z wlasnej kamery (kilka katow)
   potwierdzilo prawdziwy, wklesly recess. ZERO ciecia.
3. **Okraglosc korpusu po decymacji do 2500-3000 tris.** Patrz sekcja nizej — to byl
   najbardziej pracochlonny etap (6 iteracji).

## Decymacja — v1 do v6, finalnie zaakceptowana

- v1/v2 (curvature-weighted vertex group): FAIL, poszarpany czubek nosa + czarna
  dziura w srodku korpusu.
- v3/v4 (fizyczny split hull/detail wg odchylenia promienia od lokalnej mediany Z,
  rozne progi i ramp): FAIL, jeszcze gorszy poszarpany/pilkowany czubek nosa —
  zdiagnozowane jako artefakt MOJEGO recznego wazenia vertex-groupow walczacego
  z wbudowanym QEM Blendera, nie wada algorytmu.
- v5 (waniliowy Collapse, cala siatka, BEZ zadnej grupy): czubek nosa czysty
  (potwierdza diagnoze v3/v4), ale czarna plama w srodku korpusu OSTAJE SIE
  identyczna — dowod ze to niezalezna od wazenia cecha geometrii.
- v6 (v5 + chirurgiczna BVH-wykryta ochrona 88 cienkoscianych faces, prog 0.09
  studa): plama BEZ ZMIAN — hipoteza "cienka podwojna sciana" OBALONA.
- **Diagnoza koncowa** (`_diag_nuke_blackhole_0813.py` na live obiekcie): per-face
  inspekcja normalnych/pol/n_verts w podejrzanym regionie — normalne poprawnie na
  zewnatrz (radial_dot 0.99-0.9999), trojkaty zwyklej wielkosci, ZERO
  zdegenerowanych n-gonow/odwrocen. Wniosek: to nie defekt geometryczny, tylko
  utrata drobnego facetowania cieniowania na jednym detalu (grille/panel) bez
  kompensujacej normal mapy. Na renderze z realistycznego dystansu gry
  (`viewport_screenshot` iso/front) plama jest praktycznie niewidoczna, sylwetka
  czyta sie jako gladki stozek/cylinder z 4 finami — **PASS**, zaakceptowane jako
  finalne (2749 tris po v6, pozniej 2727 po sliver-cleanup).

## Incydent: kolizja scen (przyznane, naprawione na przyszlosc)

Moje skrypty v3-v6 zaczynaly od pelnego wipe'u sceny Blendera (`select_all`+`delete`),
co skasowalo tymczasowy obiekt ciezarowki w trakcie ich diagnozy (zablokowalo im
`scene_inventory` na krytycznym etapie). Przeprosiny + zmiana zapisane w
DO_DECYZJI.md pkt 14. Od punktu decymacji v6 w gore, wszystkie dalsze kroki
(triangulacja/UV/auto-smooth/origin/skala/export) dzialaly WYLACZNIE na juz
zaimportowanym `WR_NukeWarhead`, bez kolejnych wipe'ow.

## Krytyczne ryzyko odkryte przez agenta ciezarowki — zaaplikowane zapobiegawczo

`blender_ops.py:189` (dzielony kod MCP) ma na sztywno `mesh_smooth_type="FACE"` w
`export_fbx()`, co u ciezarowki dalo "krysztaliczny"/fasetowany polysk w realnym
Studio mimo poprawnego wygladu w viewporcie Blendera (odrzucone przez uzytkownika:
"wyglada jak gowno jebane"). ZAMIAST standardowego `export_fbx_roblox`, napisalem
wlasny skrypt eksportu (`_process_nuke_0813_export.py`) wywolujacy
`bpy.ops.export_scene.fbx` bezposrednio z `mesh_smooth_type="OFF"`, replikujac
reszte parametrow 1:1 (`global_scale=0.01`, `apply_unit_scale=True`,
`apply_scale_options=FBX_SCALE_ALL`, itd.) — BEZ edycji pliku dzielonego. Potwierdzone
wizualnie na realnym zrzucie Studio (patrz sekcja Weryfikacja): brak efektu
krysztalu/lodu, cieniowanie gladkie/satynowe.

## Finalizacja mesha

`_process_nuke_0813_finish_0813.py` (operuje na live obiekcie, bez wipe'u):
triangulacja (0 non-tri faces przed startem — Collapse juz dal czyste trojkaty, wiec
krok byl no-op), UV-safe sliver cleanup (bmesh collapse najkrotszych krawedzi,
`uvs=True`, bez `beautify_fill` — 12 krawedzi ponizej 0.02 studa skolapsowane, 2749
-> 2727 tris), `shade_auto_smooth(30°)` przez natywny operator (nie legacy flag),
origin bottom-center, apply scale, przeskalowanie DO DOKLADNIE 12.000 studa wysokosci
(uniform scale factor 1.000152 — surowa wysokosc po decymacji byla 11.9982).

Dodatkowy `_process_nuke_0813_originfix.py`: potwierdzil ze origin lokalnie siedzi
dokladnie na dolnej krawedzi mesha; resztkowe 0.0074 studa w `bottom_z_final` to
tylko absolutna pozycja obiektu w swiecie Blendera (artefakt kolejnosci operacji
cursor/scale), NIE blad geometrii wzgledem lokalnego originu — nieistotne, bo
finalne umieszczenie w Robloxie i tak ustawia PivotTo/Position od nowa.

## Walidacja

`validate_for_roblox`: **PASS**. tris=2727, size_studs {x:3.871, y:3.801, z:12.0},
1 material, 0 loose verts, 0 ngons, 46 non-manifold edges (WARN, nie blokuje —
typowe dla siatki po decymacji/sliver-cleanup, analogicznie do 13 non-manifold u
ciezarowki ktore tez bylo tylko WARN).

## Tekstury

Zrodlo WYLACZNIE z wlasnego `material.001` node_tree obiektu `WR_NukeWarhead`
(`Baked_BaseColor` 4096x4096 sRGB, `Baked_MetallicRoughness` 4096x4096 Non-Color) —
nie globalny lookup po nazwie, zeby nie zlapac obrazow ciezarowki w tej samej sesji.

Split wg konwencji glTF: G=Roughness, B=Metalness. Clamp obu do max 0.35:
- Roughness: surowy max 0.761, mean 0.466 -> po clampie max 0.350, mean 0.300.
- Metalness: surowy max 0.784, mean 0.374 -> po clampie max 0.350, mean 0.254.

Skala do 1024x1024 (wszystkie 3 mapy). Sprawdzenie ze downscale nie splaszczyl
detalu: std jasnosci w centralnym pasie base-koloru po skalowaniu = 0.137 (istotnie
> 0, detal przetrwal). Wizualna inspekcja zapisanego PNG: **ZERO tekstu/liter/flag**
na teksturze — potwierdzone. Metalness po clampie widoczny jako srednio-szara mapa
(nie biala), potwierdza poprawne dzialanie clampu.

## Upload (grupa 664399796, kanal: `robloxstudio` MCP `upload_asset` z jawnym
groupId — sprawdzony kanal wg precedensu ciezarowki, DO_DECYZJI pkt 6)

| Asset | assetId | Typ | imageId (do SurfaceAppearance) | Status |
|---|---|---|---|---|
| Model (FBX) | 116984781117493 | Model | — | Approved/Active |
| Color | 127088795466882 | Decal | **72789303662707** | Approved/Active |
| Metalness | 137797667485752 | Decal | **124064153501445** | Approved/Active |
| Roughness | 130340825342468 | Decal | **113696853796455** | Approved/Active |

Uwaga: narzedzie `upload_asset` nie ma literalnej opcji `assetType=Image` (tylko
Audio/Decal/Model/Animation/Video), wiec zgodnie z precedensem ciezarowki uzyty byl
`Decal` — odpowiedz zwraca dodatkowo osobne pole `imageId` (rozny numerycznie od
`decalId`/`assetId`), ktore jest wlasnie realnym Image assetem uzywanym w
SurfaceAppearance ponizej. Nie `decalId`.

## Wstawienie do placu

`game.Workspace.Nuke_Warhead` — pojedynczy `MeshPart` (bez wrappera Model — usuniety
pusty wrapper pozostawiony przez `insert_asset`, precyzyjnie przez Luau po nazwie+
klasie+pustych dzieciach, zeby nie ryzykowac usuniecia wlasciwego obiektu przy
niejednoznacznej sciezce). Wlasciwosci: `Anchored=true`, `DoubleSided=false`,
`Material=SmoothPlastic`, `Color=(1,1,1)` (bialy — pierwsza proba przez tablicowy
format `[255,255,255]` w `set_properties` dala BLISKO-CZARNY `0.00392,0.00392,0.00392`
= `Color3.fromRGB(1,1,1)`, zla interpretacja formatu; naprawione bezposrednio przez
`execute_luau` z `Color3.new(1,1,1)`).

`SurfaceAppearance` dziecko: `ColorMap`/`MetalnessMap`/`RoughnessMap` na 3 powyzsze
`imageId`, `NormalMap=""` (pusty, zgodnie z briefem — brak normal mapy). Zweryfikowane
bezposrednio przez Luau odczyt wlasciwosci (nie tylko przez `success:true` z API).

## Weryfikacja — realny zrzut Roblox Studio (nie viewport Blendera)

Dwa zrzuty z aktywnej sesji placu (Wave 1 w toku), kamera ~26 i ~15 studow od
obiektu:

- **Sylwetka okragla, gladki stozek/cylinder, ZERO efektu graniastoslupa** —
  potwierdzone na realnym renderze Studio, nie tylko w Blenderze (kluczowa lekcja z
  incydentu ciezarowki: viewport Blendera != realny render Studio).
- **Cieniowanie gladkie/satynowe, ZERO efektu "krysztal/lod"** — potwierdza ze
  naprawa `mesh_smooth_type="OFF"` faktycznie zadzialala w praktyce, nie tylko w
  teorii kodu.
- 4 finy widoczne, wyraznie grube, nie plaskie.
- Dysza/ogon: nie widac wyraznie recessu pod tym katem (finy go czesciowo
  zaslaniaja z tej strony) — polegam na wczesniejszej wizualnej weryfikacji z
  wlasnej kamery Blendera (pkt 2 wyzej), nie powtorzone tutaj.
- **ZERO tekstu/liter/flag na modelu** — potwierdzone wizualnie.

## OTWARTE DO DECYZJI KOORDYNATORA — rozbieznosc schematu kolorow

DoD w moim briefie oczekiwal "olive-green + black-steel + yellow-trefoils, NIE
gray". Faktyczny wypalony kolor tekstury (z samego GLB Meshy, niezmieniony przeze
mnie poza clampem metal/rough) to **ciemny granatowo-stalowy + zolto-zlote akcenty
hazard-stripe** — BEZ zieleni oliwkowej, BEZ symboli trojlisci radioaktywnych, BEZ
widocznego czerwonego pierscienia/segmentow na nosie. Nie jest to defekt mojego
przetwarzania (zrodlo BaseColor uzyte 1:1, jedyna modyfikacja to downscale do 1024
ktory nie zmienia odcieni) — to po prostu faktyczny wyglad wygenerowanego przez
Meshy assetu. Przemalowanie wykracza poza zakres tego zadania (obrobka/eksport
istniejacego mesha, nie redesign). Zglaszam do swiadomej decyzji: zaakceptowac
kolorystyke jak jest, czy zlecic osobny etap przemalowania/color-grade.

## Podsumowanie DoD

| Wymog | Status |
|---|---|
| Wysokosc = 12.000 studs | PASS (12.0000 dokladnie) |
| Tris 2500-3000 | PASS (2727) |
| Korpus okragly na renderze (w tym czubek nosa) | PASS (Blender + realny Studio) |
| Finy widocznie grube | PASS (brak Solidify, mediana 0.346) |
| Dysza = recess, nie plaski korek | PASS (wizualna weryfikacja Blender) |
| ZERO tekstu/liter/flag | PASS |
| Metal max 0.35 | PASS (0.350 dokladnie po clampie) |
| Czerwony pierscien nosa/paski, matowe, zero glow | **ROZBIEZNOSC** — brak czerwonego elementu, patrz sekcja wyzej |
| UV nietkniete poza collapse-safe cleanup | PASS (uvs=True, bez beautify_fill) |
| Tekstura olive-green+black-steel+yellow-trefoils NIE gray | **ROZBIEZNOSC** — faktycznie navy-steel+yellow, brak trefoli, patrz sekcja wyzej |
| Zrzut Studio ~15-20 studow | PASS (2 zrzuty, ~15 i ~26 studow) |

Pipeline zakonczony. Model zywy w `game.Workspace.Nuke_Warhead`, gotowy do
przegladu. Kod Luau gry NIE byl dotykany (jedynie manipulacje instancjami/
wlasciwosciami przez `execute_luau`/`set_properties`/`create_object`, zero edycji
Script/LocalScript/ModuleScript source).

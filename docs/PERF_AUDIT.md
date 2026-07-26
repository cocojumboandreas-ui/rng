# WAR RNG — Audyt wydajności

**Zakres:** całe `D:\RobloxProjects\rng\src` (68 plików `.luau`) zmapowane pod oficjalną checklistę
Roblox (create.roblox.com/docs/performance-optimization). **Tryb: TYLKO ODCZYT — zero zmian w kodzie.**
Data: 2026-07-26.

**Metoda:** 5 równoległych przejść (per-frame / wycieki / sieć / rendering+fizyka / streaming) + ręczna
weryfikacja serca systemu (`CombatService.step`). Każdy punkt cytuje `plik:linia`.

**Kontekst:** base-defense RNG, do 6 równoległych placów PvE, cel ~300 wrogów naraz. Wrogowie BEZ
Humanoidów (wróg = wiersz tabeli, pozycja = `pathT` na polilinii). Jeden tick `SIM_HZ=10` na serwerze.
EnemySync = buffer per-plot (u16 id + u8 pathT + u8 hpPct = 4 B/wróg, UnreliableRemote). Framework/Content
split, ServiceRegistry Init→Start, ProfileStore.

**Legenda:** OK · RYZYKO · BUG · RECON (wymaga sprawdzenia w Studio — mapa `RNG_MAP` i `Assets.Units`
nie są w gicie).

---

## A) TOP 5 PROBLEMÓW (sortowane: koszt × pewność)

### 1. Pętla wież przelicza pozycję wroga od zera dla KAŻDEJ pary wieża×wróg — `CombatService.luau:257-260`
```lua
for _, e in pairs(enemies) do
    local epos = enemyWorldPos(plot, e.pathT)   -- Vector3 alloc W KAŻDEJ iteracji wewnętrznej
    local dx, dz = epos.X - tpos.X, epos.Z - tpos.Z
```
**Na czym polega:** `enemyWorldPos` (robi `:Lerp` → alokuje Vector3) jest liczony ponownie dla każdego
wroga **wewnątrz każdej strzelającej wieży**. Nie ma cache'a z sekcji ruchu (1), gdzie ta sama pozycja
już była policzona. Worst case 40 wież × 300 wrogów = **12 000 wywołań `enemyWorldPos`/plac/tick**, każde
alokuje Vector3. Przy 6 placach × 10 Hz to do **~720 000 alokacji Vector3/s** tylko tutaj. Brak też
partycjonowania przestrzennego — każda wieża robi pełny liniowy skan najbliższego wroga (O(P×E)).
To jest #1 koszt serwera przy docelowym obciążeniu.
**Fix:** raz na tick policz pozycję każdego wroga do pola `e._pos` (w sekcji 1 ruchu) i re-używaj w
sekcjach 2/2b/3. Opcjonalnie kubełkowanie wrogów po `pathT` (celowanie tylko w sąsiednie kubełki).
**Robota:** **M** (cache `e._pos` = S; spatial buckets = M). **Co może pęknąć:** cache musi być
inwalidowany po ruchu — policz `e._pos` PO `pathT += speed*dt`, nie przed. Boss/stagger bez zmian.

### 2. EnemySync leci `FireAllClients` zamiast do właściciela placu — `CombatService.luau:375`
```lua
_enemySync:FireAllClients(plot.plotId, buf)   -- broadcast per plac, per tick (10 Hz)
```
**Na czym polega:** bufor każdego placu jest rozsyłany do WSZYSTKICH graczy, choć klient renderuje tylko
swój plac + jeden „focused" (`EnemyRenderController` render-gate `own or plotId==_focused`). Przy 6 graczach
prawdziwy egress serwera to ~**72 KB/s** (6 placów × 200 B × 6 graczy × 10 Hz), a każdy klient ściąga 6×
więcej niż renderuje. Dodatkowo metryka bramki `_syncBytes` (`:376`) liczy bufor RAZ, a `FireAllClients`
wysyła go P razy → **bramka zaniża realny egress ~P-krotnie** (raportowane ~12.9 KB/s to bajty
*wygenerowane*, nie *wysłane*).
**Fix:** `_enemySync:FireClient(plotOwner, plotId, buf)` (+ ewentualni obserwatorzy, jeśli `showOthers`).
Popraw też licznik bramki, by mnożył przez liczbę odbiorców.
**Robota:** **S**. **Co może pęknąć:** tryb „podglądaj sąsiada" (`sShowOthers`) — trzeba wysyłać też do
obserwujących dany plac; jeśli to rzadkie, wystarczy właściciel + lista podglądających.

### 3. Bufor EnemySync bez limitu/chunkowania → cichy drop pakietu > 900 B (high-wave solo) — `CombatService.luau:362-377`
```lua
local buf = buffer.create(cnt * 4)
...
_enemySync:FireAllClients(plot.plotId, buf)
```
**Na czym polega:** 4 B/wróg potwierdzone. **900 B / 4 = 225 wrogów** na JEDNYM placu → pakiet
UnreliableRemote przekroczony i **po cichu DROPowany** (klient zamraża/teleportuje wrogów). Założenie
„50/plac" trzyma się tylko przy równym rozłożeniu na 6 placów — ale `_enemies` jest per-gracz, więc w
**grze solo jeden plac niesie całą pulę**. Pula rośnie bez sufitu: `pool≈(20+4n)/2 = 10+2n` (proto
countDiv=2). Fala ~110 → ~230 żywych → **920 B > 900 B → drop**. Brak jakiegokolwiek dzielenia na chunki.
**Fix:** jeśli `cnt > ~200`, wysyłaj w kilku bufrach (chunk po ≤200) albo twardo ogranicz liczbę
synchronizowanych wrogów na pakiet. Docelowo (2) i tak zmniejsza fan-out.
**Robota:** **S/M**. **Co może pęknąć:** klient musi umieć złożyć wielochunkowy sync (dziś zakłada jeden
bufor = pełny stan placu — przy chunkach nie może traktować „brak id w bufrze" jako śmierci).

### 4. Bootstrap klienta bez `pcall` + 60 synchronicznych klonów przy starcie — `init.client.luau:9-76`, `EnemyRenderController.luau:744-773`
```lua
local EnemyRenderController = require(Controllers:WaitForChild("EnemyRenderController"))
EnemyRenderController.start()      -- 1. kontroler = najcięższa praca synchronicznie
... -- 22 kontrolery w gołej sekwencji, ZERO pcall
```
**Na czym polega:** dwa problemy. (a) 22 kontrolery startują bez izolacji — jeden rzucony błąd w
`.start()` zabija wszystkie kolejne (znany „init cascade": martwe HUD/przyciski = crash wyżej w łańcuchu).
(b) Pierwszy kontroler prewarmuje **60 modeli grunta synchronicznie** (`PREWARM=60`, `:24`), każdy =
`Clone()` + kilka pętli `GetDescendants()` + BillboardGui z 3 dziećmi. Reszta tierów jest już rozłożona
na klatki (OK), ale te 60 to hitch na starcie. Dodatkowo `buildEnemyModel` używa `FindFirstChild("Assets")`
(nie `WaitForChild`, `:177`) — jeśli `Assets` jeszcze się nie zreplikował, wszystkie 60 klonów zwracają
`nil` i prewarm po cichu nie robi nic.
**Fix:** owiń każdy `start()` w `pcall` z `warn`. Prewarm rozłóż na klatki jak resztę (`task.wait` co N).
Zmień `FindFirstChild("Assets")` → `WaitForChild("Assets", 10)`.
**Robota:** **S**. **Co może pęknąć:** kolejność startu kontrolerów (część czyta stan innego przy starcie
— przy pcall trzeba zalogować, który padł, ale nie przerywać).

### 5. Mapa: 648 kafli z CastShadow+CanTouch ON oraz Streaming ON z placami nie-Persistent — POTWIERDZONE reconem
**Na czym polega (dwa pewne ustalenia mapowe, oba naprawiane w Properties, nie w kodzie):**

(a) **648 kafli `Tile`** ma **wszystko włączone**: `CanCollide=648, CanTouch=648, CanQuery=648,
CastShadow=648` (recon D5). 648 płaskich podłogowych kafli rzucających cień = czyste marnotrawstwo GPU;
648× `CanTouch` = narzut event-owy bez odbiorcy. `CanQuery` prawdopodobnie potrzebne (raycast placementu w
`PlotService`), ale `CastShadow` i `CanTouch` — nie.
**Fix:** na kaflach ustaw `CastShadow=false` i `CanTouch=false` (zostaw `CanQuery`, jeśli placement raycastuje
w kafle). Jednorazowy skrypt po mapie albo w prep. **Robota: S.**

(b) **`StreamingEnabled=true`**, a wszystkie **6 placów `WR_Plot` ma `ModelStreamingMode=Default`, NIE
`Persistent`** (recon D6). Kod zależy od istnienia otagowanych instancji placu (`PlotService.deriveGrid`,
`EnemyRenderController.buildNodes` czytają `Tile`/`WR_PathNode`/`WR_CoreAnchor`). Z włączonym streamingiem
odległy plac (i jego węzły ścieżki/rdzeń) może **wystreamować się** u klienta → podgląd sąsiada i lookup
węzłów po cichu zawodzą; a jeśli gracz odejdzie od własnego placu, mogą zniknąć jego węzły ścieżki.
**Fix:** oznacz modele placów `ModelStreamingMode=Persistent` (albo wyłącz streaming, jeśli mapa jest mała).
**Robota: S.** **Co może pęknąć:** Persistent trzyma plac w pamięci u wszystkich — przy 6 małych placach to
akceptowalne; przy dużej mapie rozważ `Atomic`/tuning promieni.

**Poboczne, pewne (kod):** player-unity w `BuildService.luau:269-275` ustawiają `Anchored/CanCollide/CanQuery`,
ale **nigdy `CastShadow=false`** → każda postawiona jednostka rzuca cień (wrogowie mają `CastShadow=false`,
`EnemyRenderController.luau:207`). Fix: `d.CastShadow=false` w pętli kotwiczenia. Robota S.

> **RECON ROZSTRZYGNĄŁ obawę o Humanoidy (D3): OBALONA.** Wszystkie 12 modeli `Assets.Units` mają
> `Humanoid=false, Animatory=0`. Zero maszyn stanów przy 300 wrogach — to NIE jest problem. Dlatego ten punkt
> zszedł z „potencjalnego #1" do mapowych drobiazgów powyżej.

---

## B) PEŁNA TABELA — wszystkie 6 sekcji

### Sekcja 1 — Skrypty / per-frame

| Miejsce | Co robi | Werdykt |
|---|---|---|
| `CombatService.luau:440` Heartbeat | akumulator 10 Hz, `step()` odpala tylko gdy `_acc>=dtStep` | **OK** (poprawne rozprzężenie; koszt w `step`) |
| `CombatService.luau:442` `while _acc>=dtStep` | drenaż akumulatora, **brak klamry max-iteracji** | **RYZYKO** — spirala śmierci jeśli `step` > 100 ms |
| `CombatService.luau:257-260` pętla wież | O(P×E), `enemyWorldPos` liczony od nowa per para | **RYZYKO** (TOP 1) |
| `CombatService.luau:215-243` ruch | O(E×P) blok-detekcja, 2 Vec3/wróg | **RYZYKO** (mniejszy; `break` łagodzi) |
| `CombatService.luau:285-342` wróg→jednostka | O(E×U), budowa `unitList` co tick | **RYZYKO** (bramkowane `unitTimer`) |
| `CombatService.luau:363` licznik przed bufrem | drugi pełny `pairs` tylko po policzenie | RYZYKO (low) — nieść running count |
| `CombatService.luau:381-386` skan bossów | pełny skan E po flagę `isBoss` (≤1 boss) | RYZYKO (low) |
| `EnemyRenderController.luau:784` RenderStepped | dominujący koszt klienta w fali; LOD + PerfSettings łagodzą | **RYZYKO** |
| `UnitCombatAnimator.luau:387` Heartbeat | own-unity (≤~40), `nearestEnemy` skan/strzał | RYZYKO (low) |
| `ProfileStore:2115` Heartbeat | vendor auto-save, throttled | OK |
| `BuildController:857`, `UnitTooltip:228`, `Wobble:33`, `Boss:79` | bramkowane / trywialne | OK |
| FX-korutyny (`EnemyRender` 293/317/395/422, `UnitAnim` 89/109, `UnitHealth` 76) | 1 korutyna/efekt, `Heartbeat:Wait`, samo-kończące | RYZYKO (low) — skala z liczbą pocisków |
| `Signal.luau:36` `table.clone` per `:Fire()` | klonuje listę handlerów przy każdym Fire (częst. combat) | RYZYKO (low) |
| `PreRender/PreSimulation/PostSimulation/BindToRenderStep/Stepped` | — | **nie znalezione** (żaden nie istnieje) |
| `--!native` gdziekolwiek | — | **nie znalezione** — CombatService + GridMath to darmowe wygrane |

### Sekcja 2 — Wycieki pamięci

| Miejsce | Co robi | Werdykt |
|---|---|---|
| Całe wiring serwera w `.Start()` (18 usług) | boot-once, server-lifetime, nigdy nie rozłączane | **OK** (poprawne) |
| Wiring klienta (22 kontrolery, one-shot) | jeden raz na sesję | **OK** |
| `WaveService.luau:27` `_runGen[player]` | **nie zerowany** w PlayerRemoving (`:342-346` zeruje 3 inne, nie ten) | **BUG** (wyciek, mikroskopijny) |
| `CombatService.luau:29` `_unitHpSend[pid]` | nieczyszczony w `ClearPlot` (`:144-162`); orphany przy porzuconym runie | **RYZYKO** (wyciek, mikro) |
| `PlotService.luau:311` `CharacterAdded:Connect` | jeden connect/gracza, nigdy nie rozłączany | RYZYKO (low) |
| 9 tabel per-gracz (`_profiles`, `_state`, `_hp`, `_enemies`, `_towerCd`, `_deaths`, `_unitHp`, `_runDamage`, plot/stat...) | czyszczone w PlayerRemoving | **OK** |
| Tabela wrogów `_enemies[player][id]` | twarde usuwanie (`enemies[id]=nil` `:271,413`), brak flagowania `dead` | **OK** |
| Pula klienta `_freeByModel` | acquire/release, re-używa, prewarm, FX-pule z twardym capem | **OK** |
| `Workspace.PlayerCharacterDestroyBehavior` | nie ustawione (engine default) | OK (założenia auto-disconnect trzymają) |
| Ręczne `:Destroy()` Player/Character | — | **nie znalezione** (poprawnie) |

### Sekcja 3 — Sieć / replikacja

| Miejsce | Co robi | Werdykt |
|---|---|---|
| `Net.luau:13-50` rejestr 40 remote'ów | większość S→C event-driven | **OK** |
| `CombatService.luau:375` EnemySync `FireAllClients` | broadcast per plac (6× waste, bramka zaniża egress ~P×) | **RYZYKO** (TOP 2) |
| `CombatService.luau:362-377` bufor bez capu/chunku | >900 B przy ~220 wrogach/plac → drop (high-wave solo) | **BUG/RYZYKO** (TOP 3) |
| 4 B/wróg (u16+u8+u8) | potwierdzone; klient symetryczny `:579-584` | **CONFIRMED** |
| `CombatService.luau:383` BossHP `FireClient` per tick | reliable, 10 Hz, **bez throttle** (UnitHp obok ma 0.2 s) | **RYZYKO** — dodać throttle |
| `CombatService.luau:334` UnitHp | throttle ≥0.2 s (`:332`) | **OK** |
| `CombatService.luau:128/395/154` EnemyEvents | batch spawnów/śmierci, deaths tylko gdy niepuste | **OK** |
| `BaseDoorService.luau:160` `TweenService` na SERWERZE | tween `Position` bramy → replikacja właściwości/klatkę | **RYZYKO** (anti-pattern, ale event-gated, niski koszt) |
| VFX (muzzle/tracer/śmierć/reveal/monety) | tworzone lokalnie na kliencie | **OK** (brak serwerowych ParticleEmitterów) |
| `RollService.luau:141-146` cooldown rolki | server-side, per-gracz | **OK** |
| `BuildService` / `LevelService` / `PlayerHitEnemy` | brak throttle rate (tylko ekonomiczne bramki) | RYZYKO (low) — dodać min-interval jak RollService |

### Sekcja 4 — Rendering (klient)

| Miejsce | Co robi | Werdykt |
|---|---|---|
| `EnemyRenderController.luau:246-264` pula | acquire pop / release push, re-używa, boss≠grunt | **OK** |
| `:213-232` HP-bar w modelu | 4 instancje GUI (Billboard+2 Frame+Label) na model, rezydentne | **RYZYKO** — ~300 rezydentnych Billboardów przy szczycie |
| `:604-635` LOD | binarny: own OR focused-plac; reszta parkowana na y=-500 | **RYZYKO** — brak cull/remove/`Enabled=false`, modele rezydentne |
| `Assets.Units` MeshId/SurfaceAppearance | recon: meshy współdzielone wewnątrz modeli, SA=0; 12 typów = różne meshy (oczek.) | **OK** (recon D4) |
| RenderFidelity rigów (Precise) | recon: tylko 3 Precise (Sniper/SWAT/Rocket, po 1 MeshParcie) | **OK** (recon D4; drobiazg — może `Performance`) |
| 648 kafli `Tile` CanTouch/CanQuery/CastShadow | recon: **648/648/648 wszystko ON** (Box n/d — to Party, nie MeshParty) | **RYZYKO** (recon D5; część TOP 5) |
| `:207` CastShadow wrogów | `CastShadow=false` na każdej części | **OK** |
| `BuildService:269-275` CastShadow jednostek | **nigdy nie ustawiane** → default true | **RYZYKO** (część TOP 5) |
| ParticleEmittery w reveal VFX | reveal to czyste UI, zero emitterów | **OK** (nie znalezione) |
| `EnemyRender flameBurst:331`, `UnitAnim:279/335` emittery | capowane (HEAVY_CAP=10) / per-unit persistent | OK |

### Sekcja 5 — Fizyka

| Miejsce | Co robi | Werdykt |
|---|---|---|
| `Anchored=false` gdziekolwiek | wszystko zakotwiczone (`EnemyRender:207`, `BuildService:271`, `UnitModelFactory:45`) | **OK** (nie znalezione niezakotwiczone) |
| `Instance.new("Humanoid")` / AnimationController w kodzie | — | **OK** (nie znalezione) |
| Humanoidy/stany na szablonach `Assets.Units` | recon: **wszystkie 12 modeli Humanoid=false, Animatory=0** | **OK** (recon D3 — obalone) |

### Sekcja 6 — Streaming / pamięć assetów

| Miejsce | Co robi | Werdykt |
|---|---|---|
| RS: `Framework`/`Content`/`Shared` (kod + 15 configów, ~579 linii) | małe, muszą być współdzielone | **OK** (pamięciowo) |
| Server-only configy (Economy, Wave.scaling, Sim combat) w RS | klient ściąga balans/exploit-surface | **RYZYKO** (bajtowo tanie; wyciek tuningu) |
| `Assets.Units` (realne modele, place-owned) | recon: 12 modeli, 246 partów łącznie; Assets folder desc=534; RS desc=685 (małe) | **OK** (recon D6/D7) |
| StreamingEnabled / ModelStreamingMode | recon: **StreamingEnabled=true**, 6 placów **ModelStreamingMode=Default (nie Persistent)** | **RYZYKO** (recon D6; część TOP 5) |
| PreloadAsync / ContentProvider | — | **nie znalezione** — brak anty-patternu preload-wszystko (dobrze); możliwy pop-in |
| Bootstrap serwera `init.server.luau:36-42` | brak klonowania placów/kafli; mapa autorska, kod czyta tagi | **OK** |
| Bootstrap klienta bez pcall + 60 synchr. klonów | znany init-cascade + hitch startowy | **BUG + RYZYKO** (TOP 4) |
| `EnemyRenderController:177` `FindFirstChild("Assets")` (nie WaitForChild) | prewarm po cichu no-op jeśli Assets niezreplikowany | RYZYKO/możliwy BUG |

---

## C) CZYSTE — co kod już robi dobrze (NIE ruszać)

- **Architektura symulacji:** wrogowie jako wiersze tabeli po `pathT`, zero Humanoidów po stronie kodu,
  zero fizyki — dokładnie to, co checklist zaleca dla masy jednostek. Wszystko zakotwiczone.
- **Serializacja sieci:** ręczne pakowanie do `buffer` (4 B/wróg) zamiast tabel — wzorcowe niskoalokacyjne
  podejście. Śmierci/spawny osobno (reliable), stan (unreliable).
- **Twarde usuwanie martwych wrogów** — brak flagowania `dead=true` i rosnących tablic; `_nextEnemyId`
  monotoniczny z obsługą wrap u16.
- **Pooling klienta:** modele wrogów i FX re-używane, capy (FX_POOL/DMG_POOL/HEAVY_CAP/COIN_CAP), słabe
  klucze (`__mode="k"`) na cache'ach per-model. Prewarm zamiast lazy-spawn w fali.
- **Sprzątanie per-gracz:** 9/11 tabel czyszczonych w `PlayerRemoving`; `ClearPlot` broadcastuje śmierci,
  by klient zwolnił pulę. Brak ręcznego `:Destroy()` Playera (poprawnie).
- **VFX w całości po stronie klienta** — zero serwerowych ParticleEmitterów/replikacji efektów.
- **Rate-limit rolki** (RollService) — poprawny per-gracz cooldown.
- **LOD renderuje tylko own + 1 focused plac** — dobry throttle CPU (max 2 place animowane/klatkę), mimo
  że modele niewidoczne pozostają rezydentne (patrz RYZYKO w B/Sekcja 4).
- **CastShadow=false na wszystkich wrogach i FX** (jednostki to osobna sprawa, TOP 5).
- **UnitHp throttlowany 0.2 s** — wzorzec, którego brakuje BossHP.
- **Brak preload-wszystko** — żaden `PreloadAsync(workspace)`/`Assets.Units` (klasyczny hitch nie występuje).
- **Bootstrap serwera nie buduje mapy** — 648 kafli jest autorskich w place, nie klonowanych w runtime.

---

## D) NIEROZSTRZYGNIĘTE — wymaga pomiaru na urządzeniu / reconu w Studio

> **WYNIKI RECON (odpalone przez MCP, 2026-07-26, tryb edit):**
> - **D3 Humanoidy — OBALONE.** Wszystkie 12 modeli `Assets.Units`: `Humanoid=false, Animatory=0`. Zero
>   maszyn stanów. Nie jest problemem.
> - **D4 instancing/fidelity — OK.** Meshy współdzielone wewnątrz modeli, `SurfaceAppearance=0`, `Precise`
>   tylko 3 (Sniper/SWAT/Rocket po 1). Nic do naprawy poza opcjonalnym zejściem tych 3 na `Performance`.
> - **D5 kafle — RYZYKO (patrz TOP 5a).** `Tiles=648`, `CanCollide=648, CanTouch=648, CanQuery=648,
>   CastShadow=648` — wszystko ON.
> - **D6 streaming — RYZYKO (patrz TOP 5b).** `StreamingEnabled=true`, 6 placów `ModelStreamingMode=Default`
>   (nie Persistent). RS desc=685 (małe), Assets desc=534.
> - **D7 rig wroga — mniejszy hitch niż zakładano.** Prewarmowany „Noob Soldier" = 11 partów / 4 MeshParty
>   (nie 15+). 60 klonów ≈ 660 partów synchronicznie — realny, ale umiarkowany hitch. Najcięższe rigi:
>   SWAT/Tank Soldier 35, Sniper 34 (te NIE są prewarmowane synchronicznie — spawnują się później).
>
> **Nadal do zmierzenia na urządzeniu (nie da się z edit):** D1 (MicroProfiler serwera pod obciążeniem) i
> D2 (realny egress sieci przy 2+ graczach). Skrypty recon D3-D7 poniżej zostawione dla powtarzalności.

Skrypty pod `execute_luau target=edit` (użyte) lub `eval_*_runtime` w playteście.
**Newline = `string.char(10)`, NIE `"\n"`** (znany gotcha MCP).

### D1. MicroProfiler serwera — potwierdź który sub-loop dominuje
Odpal solo playtest, wywołaj falę ~15–20, w Studio **Ctrl+Alt+F6** (MicroProfiler) → pauza → obejrzyj
klatkę serwera. Szukaj scope `Heartbeat`/`step`. Propozycja instrumentacji (NIE wstawiona):
`debug.profilebegin("Combat/Towers")` wokół `CombatService.luau:248-279`, analogicznie Movement (215-243),
UnitDamage (285-342), Sync (362-377). **Hipoteza do obalenia:** „Combat/Towers" (uncached `enemyWorldPos`)
zjada >50% czasu `step`. Sprawdź też `_lastStepMs` (`GetLastStepMs`) — jeśli zbliża się do 100 ms przy
300 wrogach, klamra spirali śmierci (`:442`) staje się pilna.

### D2. Statystyki sieci — realny egress vs metryka bramki
F9 → **Network** (albo `Stats.DataSendKbps`) podczas fali przy 2+ graczach. Porównaj z
`GetSyncBytesAndReset`. Oczekiwanie: realny egress ~P× wyższy niż raportuje bramka (patrz TOP 2).

### D3. Recon `Assets.Units` — Humanoidy + stany (rozstrzyga TOP 5)
```lua
local units = game:GetService("ReplicatedStorage").Assets.Units
for _, model in ipairs(units:GetChildren()) do
    local hum = model:FindFirstChildOfClass("Humanoid")
    local mesh, anim = 0, 0
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("MeshPart") then mesh += 1 end
        if d:IsA("Animator") or d:IsA("AnimationController") then anim += 1 end
    end
    print(string.format("=== %s  Humanoid=%s  MeshParts=%d  Animators=%d", model.Name, tostring(hum~=nil), mesh, anim))
    if hum then
        for _, s in ipairs({"Running","Climbing","Swimming","Jumping","Freefall","GettingUp","FallingDown","Ragdoll","Physics","Seated","Dead","PlatformStanding"}) do
            local st = Enum.HumanoidStateType[s]
            local ok, en = pcall(function() return hum:GetStateEnabled(st) end)
            if ok then print("   "..s.." = "..tostring(en)) end
        end
    end
end
```
Jeśli `Humanoid=true` na rigach wrogów → koszt 300 maszyn stanów; wtedy TOP 5 skacze na #1.

### D4. Recon współdzielenia meshy (draw calls / instancing)
```lua
local units = game:GetService("ReplicatedStorage").Assets.Units
local byMesh, byName = {}, {}
for _, model in ipairs(units:GetChildren()) do
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("MeshPart") then
            byMesh[d.MeshId] = (byMesh[d.MeshId] or 0) + 1
            byName[d.Name] = byName[d.Name] or {}
            byName[d.Name][d.MeshId] = true
            if d.RenderFidelity == Enum.RenderFidelity.Precise then print("Precise: "..model.Name.."/"..d.Name) end
            if d:FindFirstChildOfClass("SurfaceAppearance") then print("SA: "..model.Name.."/"..d.Name) end
        end
    end
end
print("--- ten sam mesh w >1 części (instancing) ---")
for id, n in pairs(byMesh) do if n > 1 then print(n.."x  "..id) end end
print("--- ta sama nazwa, RÓŻNE MeshId (dubel mesha, psuje instancing) ---")
for name, set in pairs(byName) do local c=0 for _ in pairs(set) do c+=1 end if c>1 then print(name.." = "..c.." różnych MeshId") end end
```

### D5. Recon 648 kafli — CollisionFidelity / CanTouch / CanQuery / CastShadow
```lua
local n,box,nb,coll,touch,query,shadow = 0,0,0,0,0,0,0
for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA("BasePart") and d.Name == "Tile" then
        n += 1
        if d:IsA("MeshPart") then if d.CollisionFidelity == Enum.CollisionFidelity.Box then box+=1 else nb+=1 end end
        if d.CanCollide then coll+=1 end
        if d.CanTouch then touch+=1 end
        if d.CanQuery then query+=1 end
        if d.CastShadow then shadow+=1 end
    end
end
print(string.format("Tiles=%d Box=%d nonBox=%d CanCollide=%d CanTouch=%d CanQuery=%d CastShadow=%d", n,box,nb,coll,touch,query,shadow))
```
Oczekiwanie n=648. Flaguj nonBox>0 oraz CanTouch/CanQuery/CastShadow bliskie 648 (każde = koszt ×648).

### D6. Recon streaming + waga RS
```lua
print("StreamingEnabled = "..tostring(workspace.StreamingEnabled))
local RS = game:GetService("ReplicatedStorage")
print("RS descendants = "..#RS:GetDescendants())
local uf = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("Units")
if uf then for _, m in ipairs(uf:GetChildren()) do
    local parts=0 for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then parts+=1 end end
    print(string.format("  %-22s parts=%d desc=%d", m.Name, parts, #m:GetDescendants()))
end end
```
**Ręcznie w Studio → Workspace Properties → Streaming** (NotScriptable): `StreamingTargetRadius`,
`StreamingIntegrityMode`, `ModelStreamingBehavior`. Jeśli StreamingEnabled=ON — sprawdź, czy modele placów
są `Persistent` (inaczej podgląd sąsiada i lookup węzłów mogą po cichu zawodzić).

### D7. Rozmiar rigu wroga (waży TOP 4 — koszt 60 synchr. klonów)
Z D4/D6 odczytaj `parts`/`desc` dla „Noob Soldier". Jeśli rig ma ~15+ MeshPartów → 60 klonów × 15 =
900 części budowanych synchronicznie przy starcie klienta = realny hitch → priorytet fixa (b) z TOP 4.

---

## Kolejność rekomendowana (po recon D3-D7)
1. Cache `e._pos` per tick (TOP 1) — największy koszt serwera, fix S/M, niskie ryzyko.
2. EnemySync `FireClient` zamiast broadcast (TOP 2) — S, ~6× mniej egress.
3. Chunk/cap bufora EnemySync (TOP 3) — naprawia cichy drop w high-wave solo.
4. **Mapa (TOP 5, S, pewne z reconu):** placom `WR_Plot` → `ModelStreamingMode=Persistent`; kaflom `Tile`
   → `CastShadow=false` + `CanTouch=false`. Największy stosunek zysk/robota, zero ryzyka logiki.
5. `pcall` wokół startu kontrolerów + rozłożony prewarm + `WaitForChild("Assets")` (TOP 4) — S.
6. `CastShadow=false` na player-unitach (`BuildService`) — S.
7. Drobne: throttle BossHP; zerowanie `_runGen`/`_unitHpSend`; klamra max-iteracji w akumulatorze;
   `--!native` na CombatService + GridMath.

> **Obalone reconem — NIE robić:** strip Humanoidów (ich nie ma), normalizacja MeshId/RenderFidelity
> (instancing OK, Precise=3), migracja `Assets.Units` do ServerStorage z powodu wagi (RS jest małe, 685 desc).

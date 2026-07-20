# WAR RNG — Raport badawczy: analiza gatunku, matematyka RNG, retencja/monetyzacja i architektura techniczna

## TL;DR
- **Build a Base RNG (Slungpy Games) to bezpośredni, rynkowo zweryfikowany wzorzec dla WAR RNG**: utworzona 31 maja 2026, według Bloxodes osiąga ~15,3 tys. graczy jednocześnie (24h peak 16,5 tys.), 4,4 mln wizyt, 74 tys. ulubionych i ~97,6–98,2% pozytywnych ocen (globalny rank #108, best #59). Pętla „Roll → Build → Defend → Upgrade → offline" działa, a Twój plan (siatka, cap jednostek, dwie waluty, skill tree, offline, indeks) jest zgodny z meta gatunku.
- **Największe ryzyko techniczne to NPC**: 6 plotów × 20–50 jednostek + fale wrogów = 150–300+ bytów na serwer. Musisz PORZUCIĆ Humanoidy, symulować pozycje serwerowo w JEDNYM skrypcie-menedżerze i renderować wizualnie na kliencie — inaczej serwer padnie. Potwierdzają to wątki DevForum.
- **Matematyka luck jest zdradliwa**: naiwne „przeroluj N razy, weź najlepsze" zabija wydajność przy wysokim luck (potwierdza to sam autor open-source'owego modułu). Użyj modelu Sol's RNG (dziel mianowniki „1 in N" przez skumulowany współczynnik luck, `floor`, z fallbackiem na common) lub analitycznego `roll^(1/luck)`. Mutacje i pity rób jako NIEZALEŻNE dorzucane rolki po rolce głównej.

---

## Key Findings

1. **Wzorzec gatunkowy jest zweryfikowany rynkowo.** Build a Base RNG w niecałe 2 miesiące osiągnął top-108 globalnie na Roblox przy ~98% pozytywnych ocen. Pętla jest niemal identyczna z planem WAR RNG. Slime RNG, Roll to Defend, Invade the World i Anime RNG Defense potwierdzają, że hybryda „RNG rolling + base/tower defense" to obecnie jeden z najgorętszych segmentów. Dla porównania siła startu gatunku: Pets GO! od BIG Games (utworzona 11 sierpnia 2024) według Roblox Fandom „reached almost 9 million visitors in the first 24 hours" i ma dziś ponad 905 mln wizyt.
2. **Konkretne liczby z Build a Base RNG** (rdzeń = 100 HP w szklanej kostce, boss na fali 20, Luck I = 100 coins, Auto Roll = 250 coins, Luck II = 800 coins, revive = 29 Robux, drabina rzadkości 1 in 3 → 1 in 1500) dają gotowy punkt kalibracji balansu.
3. **Dwuwalutowy skill tree (coins + liczba rolek/dice) jest zgodny z gatunkiem** — Build a Base RNG używa dokładnie tego (Fast Rolls I kosztuje 15 dice/rolek, nie coins).
4. **Server-authoritative ProfileStore to właściwy wybór** (następca ProfileService od loleris) — session-locking chroni przed dupe i utratą danych.
5. **Monetyzacja gatunku opiera się na**: auto-roll pass, 2x luck pass, 2x coins pass, luck potions (dev products), server luck z rosnącą ceną, oraz slotach/„Place More Items". Ceny w skali 25–1700 Robux.

---

## Obszar 1 — GŁĘBOKA ANALIZA GATUNKU

### Build a Base RNG (Slungpy Games) — pełna mechanika

**Dane rynkowe (wg Bloxodes/Rolimon's, stan lipiec 2026):** utworzona 31 maja 2026; wg Bloxodes „Total visits 4.4M, Favorites 74K, Global rank Current #108, Best #59 (Jul 18, 5 PM)", ~15,3 tys. grających teraz, 24h peak 16,5 tys. Ocena podawana jako 97,6% (build-a-base-rng.wiki) do 98,2% (Bloxodes) — zweryfikuj bieżąco. To bardzo szybki wzrost jak na 7-tygodniowy tytuł.

**Pętla rdzenia:** Roll (kość) → Build Mode (siatka) → Start fali → przetrwaj → wydaj coins w skill tree → roluj dalej. Baza walczy offline.

**Rdzeń bazy (core):** „base heart" wewnątrz szklanej kostki, start 100/100 HP. Gdy spadnie do 0, runda się kończy, a gracz ZACHOWUJE zdobyte coins. To dokładnie Twój model (core/battery, summary screen, coins kept). ✅ Zgodne z planem.

**Rolowanie i drabina rzadkości** (zweryfikowana tabela z rozgrywki, źródło allthings.how):
- Wood Block — 1 in 3
- Wooden Trap — 1 in 8
- Cross Bow — 1 in 15
- Stone Mortar — 1 in 21
- Wooden Mortar — 1 in 23
- Basic Cannon — 1 in 30
- Stone Block — 1 in 60
- Wooden Spikes — 1 in 60
- Catapult — 1 in 100
- Rusty Block — 1 in 150
- Wooden Tesla — 1 in 1,500 (najrzadszy zaobserwowany, przychodzi przez animację „narastającego" mnożnika luck)

**Build Mode** dzieli się na dwie zakładki: **Blocks** (ściany, pułapki) i **Weapons** (wieżyczki: Basic Cannon, Cross Bow, mortary). Postawione bronie strzelają automatycznie po starcie fali; gracz może dodatkowo klikać, by zadawać obrażenia mieczem (aktywna walka + auto-combat równolegle).

**Skill tree (dwie waluty: coins + dice/rolki):**
- Luck I — 100 coins
- Auto Roll — 250 coins
- Clover Chance I — 25 coins (+10% clovers)
- Fast Rolls II — 45 coins (+20% szybkości rolki)
- Luck II — 800 coins
- Friend Luck I — 1,2 tys. coins (bonus luck od grania ze znajomymi)
- Fast Rolls I — **15 dice** (cena w rolkach, nie w coins!)
- Gold Rolls I — 3,3 tys. coins (złota rolka co 11 rolek)
- „Place More Items" — podnosi cap jednostek/wielkość bazy (kluczowe dla late-game)

**Stacking luck (wiele źródeł, mnożą się):** Luck ze skill tree + ukończenie indeksu (permanentny Luck Multiplier za % kolekcji) + bonus za granie ze znajomymi (multiplayer) + join grupy Roblox + polubienie gry (+2 Luck) + Clover Chance + Gold/Blessed Rolls + Shop boosty. To dokładnie zaplanowany przez Ciebie system.

**Indeks/kolekcja:** każdy nowy przedmiot wypełnia slot; wzrost % ukończenia odblokowuje PERMANENTNE nagrody Luck Multiplier. Dodatkowo lewelowanie przedmiotów przez indeks (np. Wood Block do Lv.1 daje 90 coins + wzrost mnożnika luck). Bronie ulepsza się przez menu indeksu za coins.

**Fale/zombie:** zombie spawnują z jaskini i idą ścieżką do rdzenia. Meta layoutu = warstwowa obrona (pułapki z przodu → bronie zasięgowe → ściany kształtujące ścieżkę), z prostą centralną ścieżką do rdzenia.

**Boss (fala 20):** gigantyczny zombie-boss potrafi zbić rdzeń do 0. Ukończenie fali 20 odblokowuje nowy przepis craftingu. „Bosses Update" (lipiec 2026) zbudował grę wokół tej walki: bossowie mają własne wzorce ataków, dropią relikty i otwierają ścieżki craftingu. (Część źródeł podaje, że bossowie zaczynają pojawiać się po fali ~15.)

**Crafting/relikty:** Crafting Machine odblokowuje się po uzbieraniu 150,000 coins. Bossowie dropią relic shards/materiały; z reliktów craftuje się mocniejsze obiekty (np. Fortune Relic zwiększa drop coins).

**Offline:** baza walczy i zarabia offline (Offline Roll to osobny upgrade). To główny hak retencji.

**Revive/monetyzacja:** po przegranej na bossie — Revive za **29 Robux** albo Continue (wrócić do bazy, zachować coins). Coin Boost w Shopie = x2 coins na 3 minuty. Coin potions z tutoriala. (Cena 29 R$ jest typowa dla gatunku — np. w pokrewnej „build ur base" gamepass „Paint Tool" = 29 R$.)

**Ekonomia:** pełny bieg może dać kilka tys. coins naraz (zaobserwowano bieg do fali 20 = 6,1 tys. coins; inny do fali 17 = 7,2 tys.). Późniejsze fale płacą więcej.

### Gry pokrewne/konkurencyjne

- **Slime RNG:** RNG-roll + auto-battle + strefy + Rebirth (prestige dający permanentny mnożnik Luck). Kategorie slime'ów (Base/Big/Huge/Shiny/Inverted) odblokowywane przez upgrade'y; najrzadsze mają szanse „w bilionach". Ma Golden Rolls i Diamond Rolls jako systemy PITY (gwarantują wyższy tier po ustalonej liczbie rolek). Auto-Roll to najważniejszy wczesny upgrade. Crafting od strefy 7 (Heaven). 20 światów, każdy nowy daje +1 Luck.
- **Invade the World:** militarne, formacja armii; jednostki generują cash i walczą; wrogowie skupiają ogień na jednostce w ŚRODKU (dlatego tank w centrum). Fale wrogów podczas inwazji; dystans do podbicia pokazany u góry. Armia najeżdża i łupi OFFLINE. Bardzo bliskie tematycznie WAR RNG (dyktator, marsz jednostek).
- **Roll to Defend (D:/Drive):** RNG + tower defense; jednostki z rarity 1/N (od 1/10K do 1/10B), stawiane na ścieżce fali; strefy; offline income; luck od znajomych i grupy. Wymaga ukończenia tutoriala przed odblokowaniem kodów.
- **Tower Defense RNG / Open World: Tower Defense RNG:** roll wież/traps; +1 Luck za grupę, +0,25 Luck dla Premium; odwiedzanie baz innych graczy.
- **Anime RNG Defense:** roll jednostek anime, Blessed Roll z mnożnikiem luck (x250 na pojedynczą rolkę), auto-delete threshold dla duplikatów.

**Co decyduje o sukcesie/porażce:** silny pierwszy hak (roll + natychmiastowa satysfakcja), przejrzysta warstwowa obrona, permanentna meta-progresja (luck stacking + indeks), offline income, częste update'y (Build a Base RNG dostał duży Bosses Update ~6 tygodni po starcie). Porażki wynikają z braku pity (frustracja pechem), słabego FTUE i zbyt drogiej/pay-to-win monetyzacji.

---

## Obszar 2 — MATEMATYKA RNG / LUCK

### Formuła Sol's RNG (wzorzec referencyjny)
Sol's RNG używa algorytmu przeszukiwania listy. Współczynnik luck (wg Sol's RNG Wiki, sekcja Luck Formula):

`Luck = (((1 + Basic Luck) * Bonus Roll Multiplier) + Special Luck) * VIP Multiplier`

Kolejność działań (kluczowa dla mnożenia się źródeł), verbatim z wiki: „Luck sources are mostly additive before multipliers. Bonus-roll multipliers apply to the basic-luck part. One-roll 'special' potions are added after bonus-roll multiplication. VIP multiplies the final total.":
- **Basic Luck** — addytywne (skill tree, potiony typu Fortune; +100% = +1.0).
- **Bonus Roll Multiplier** — mnoży TYLKO część basic (np. co 10. rolka = x2 „Double Luck"; Gravitational Device = x6).
- **Special Luck** — flat, dodawane PO mnożeniu bonus (jednorazowe potiony).
- **VIP Multiplier** — końcowe mnożenie (x1.2).

**Jak wyłania się aurę:** dla każdej aury `List Value = floor(Base Value / Luck)`; usuwa się aury o `List Value == 1`; system idzie od najrzadszej, losuje `random(1, ListValue)` — jeśli 1, aura wpada; jeśli nic nie trafi, bierze najrzadszą aurę o List Value = 1 (fallback). To utrzymuje common-tiery dostępne: common znika z puli dopiero gdy `Luck ≥ jego N`, a `floor` zapobiega przewadze ułamków typu 1.005 (verbatim wiki: „Divide all values in the list by this value and take the floor to avoid values such as 1.005 weighing the list too heavily in one aura's favour"). Efekt: luck potrafi zamienić 1/1,000,000 na ~1/35,000.

### Pułapka: naiwne „przeroluj N razy, weź najlepsze"
Open-source'owy moduł lambariniego (DevForum, „Weighted Chance System (WITH LUCK!)", thread 3056901) implementuje luck jako pętlę: wykonaj pełną rolkę `Luck` razy i zachowaj najrzadszy wynik (`for i = 1, Luck - 1 do ... if Best.Rarity < New.Rarity then Best = New`). Autor i komentujący POTWIERDZAJĄ wady: (1) wydajność skaluje się LINIOWO z luck — przy luck rzędu tysięcy/milionów (typowe dla RNG) to nie do utrzymania; divine_limerence: „the only downside with this is luck being based off of iterations", lambarini: „Yea, thats the downside, a lot of luck would cause performance issues"; (2) rozkład to `1-(1-p)^N`, trudny do precyzyjnego strojenia, luck musi być liczbą całkowitą.

### Zalecane podejścia (server-authoritative)
1. **Cumulative weight table (jeden `Random.new()` draw)** — sumuj wagi, jeden los przeciw sumie, iteruj raz. O(n) na rolkę niezależnie od wielkości luck. To kanoniczny wzorzec z DevForum (Trulineo „Weighted Chance System" thread 1373953, wariant B_rnz). Zawsze `Random.new()` na serwerze, nigdy `math.random()` do ważnych rolek, nigdy na kliencie.
2. **Dzielenie mianowników „1 in N"** (model Sol's / dyskusja „So how does luck/RNG actually work?", thread 4715260): `N_eff = floor(N / Luck)`, ale z ostrożnością — nie pozwól, by boost przekroczył bazę puli. Kluczowa uwaga OP: „you can't just multiply the weights by the boost because then everything is proportionally the same" — trzeba działać na mianownikach, nie proporcjonalnie na wszystkich wagach. lamcellari: „if your rng is 1 in 30, and you use 200% booster (2x luck) then its 2 in 30, simplifying it into 1 in 15".
3. **Skalowanie boostu per-tier** (SirTobiii) — boostuj rzadsze tiery mocniej niż common (np. dla boostu 200%: Common +25% (200/8), Rare +50% (200/4), Epic +100% (200/2), Legendary +200% (200/1)), by nie spłaszczyć rozkładu.
4. **Model interwałowy [0,1]** (au_tk, mathematically clean): `RN = math.random(); RN = RN / Multiplier` (kurczenie przestrzeni wejścia = zwiększanie luck) — równoważne mnożeniu progów rarity.
5. **Analityczny power-law (O(1), zastępuje pętlę)** (happya_x): `rollAfterLuck = math.pow(roll, 1/luck)` — matematycznie równoważne „best of N rolls", ale w jednym wywołaniu i wspiera ułamkowe/mnożone luck. Wtedy `1 in x` staje się `1 / (1 - (1 - 1/x)^luck)`. To najczystsza analityczna alternatywa dla wolnej pętli lambariniego.

### Ochrona common-tierów przy wysokim luck (pitfall b)
Wzorzec z DevForum „Basic RNG + Luck system" (thread 4683162): `effectiveChance = math.max(1, math.floor(chance / math.sqrt(luck)))`. Trzy techniki: (1) `math.sqrt(luck)` = tłumienie sub-liniowe; (2) `math.max(1, ...)` = clamp, żaden item nie spadnie do 0/ujemnej szansy; (3) hardcoded fallback „Common", gdy nic nie trafi (jak catch-all w Sol's). UWAGA: naiwne `round(Rarity/Luck)` BEZ clampu (thread 2843097) powoduje, że gdy `Luck ≥ Rarity`, tier staje się WYMUSZONY — to właśnie awaria, którą clamp/floor+fallback naprawiają.

### Mutacje jako niezależna druga rolka
Sol's implementuje mutacje jako OSOBNY, niezależny mnożnik PO wyłonieniu bazowej aury: „BaseAura (1 in N) x Mutation Chance (xM)" — mutacja to własna rolka „1 in M". Przykłady z wiki: Overture → OVERTURE I HISTORY (1 in 150,000,000) x2; Celestial → CELESTIAL DIVINE (1 in 350,000) x20; Arcane → ARCANE: DARK (1 in 1,000,000) x30; Rage → Heated x100. Wzorzec x2/x4/x8 przy 1/25, 1/33, 1/333 (jak w Kick a Lucky Block: Diamond x2 @1/25, Plasma x4 @1/33, Radioactive x8 @1/333) to ta sama architektura: druga niezależna rolka `Random.new()` PO rozstrzygnięciu głównej, nie dotykająca tabeli bazowej. To zapobiega zniekształceniu rozkładu głównego.

### Pity
Śledź na serwerze licznik rolek od ostatniego rzadkiego dropu. **Hard pity**: gwarancja rzadkiego po progu (np. 100 rolek). **Soft pity**: rosnący mnożnik prawdopodobieństwa. Slime RNG (Golden/Diamond Rolls) używa dokładnie tego. Pity jest praktycznie obowiązkowe dla retencji (KitsBlox: „Pity mechanics are not optional for a successful RNG game").

---

## Obszar 3 — RETENCJA I MONETYZACJA

### Onboarding / pierwsza sesja (FTUE)
Roblox Creator Hub: sukces FTUE = Day-1 retention. Benchmarki D1 (dane 2025–26 wg RoLearn): <20% krytyczne, 20–30% poniżej średniej, 30–40% dobre, 40–50% świetne, 50%+ wyjątkowe (top 5%). Pierwsze 5 minut decyduje. W RNG: gracz musi rolować w kilka sekund. Best practice gatunku: skryptowane wczesne dobre dropy w tutorialu (gwarantowany early rare + scryptowane mutacje x2/x4/x6), „moment radości" na koniec onboardingu, reguła 3× (pokaż → użyj → nagrodź trzykrotnie). Wg RoLearn: „over 80% of lifetime revenue comes from players who survive the first week".

### Offline earnings
Wzorzec: zapisz timestamp wyjścia; przy powrocie policz `czas_offline × rate`, z CAPEM (typowo, by wymusić codzienne logowanie). Multipliers stackują multiplikatywnie (2x pass × 1.5x buff = 3x). Build a Base RNG: baza walczy i zarabia offline; Offline Roll jako osobny skill. Rekomendacja: cap offline na np. 8–12h earnings, offline roll/spin jako gamepass.

### Server luck z rosnącą ceną (wzorzec Pets GO / BIG Games)
Pets GO! (obecnie „Pets RNG!") od BIG Games Pets, utworzona 11 sierpnia 2024, ponad 905 mln wizyt (Rolimon's), rating 90,029%, 665 918 ulubionych — używa gamepassa „Double Your Luck", który **zaczyna od 50 Robux i rośnie z każdym podwojeniem** (temporary boost na 12h). To eskalujący model cenowy. Stałe passy luck w Pets GO (potwierdzone Rolimon's): Lucky (275 R$), VIP (400 R$), Double Dice (525 R$), Ultra Lucky (800 R$, stackuje się z Lucky), Hyper Dice/Celestial/Rainbow (1200 R$), Skill Master (1700 R$).

### Typowe ceny gamepassów (Robux) w udanych RNG
- Małe perki/cosmetics: 25–99 R$
- Znaczące ulepszenia (2x cash, 2x luck, auto): ~49–199 R$ (masowa adopcja)
- „Game-changing": 500–1500 R$
- Premium/endgame: 1500+ R$
- Build a Base RNG: Revive = 29 R$ (dev product).

Roblox pobiera 30% (marketplace fee). DevEx wg oficjalnej strony Roblox: „$0.0038 per Robux (which comes out to $114 USD for 30,000 Earned Robux)", obowiązuje od 5 września 2025; UWAGA: od 8 czerwca 2026 istnieje osobna, wyższa stawka „US 18+ DevEx Rate. $0.0054 per Robux" dla zweryfikowanych graczy 18+ z USA. Priorytet: cena maksymalizująca cena×konwersja, nie najwyższa cena.

### Boost consumables (dev products)
2x luck / 2x coins / roll speed na N minut — powtarzalne dev products, tiered bundles (najlepsza wartość w środku-górze). Coin Boost w Build a Base RNG = x2 na 3 min.

### Indeks/kolekcja jako retencja
„Collection log 42/50" motywuje bardziej niż cokolwiek — gracze grindują ostatnie sloty. Permanentne nagrody Luck za % ukończenia (jak w Build a Base RNG) tworzą pętlę: więcej rolek → więcej indeksu → więcej luck → lepsze rolki.

### Błędy monetyzacji, które zabijają gry
Pay-to-win psujące free-graczy; zbyt drogie ceny zbyt wcześnie (gra pełna graczy kupuje nic); brak pity (frustracja → negatywne oceny → śmierć w algorytmie); rozstrzyganie rolek na kliencie (exploity); brak publikacji drop rates (utrata zaufania).

**Uwaga wdrożeniowa:** od 29–30 maja 2026 Roblox wyłącza cross-game sales developer products/passów (oficjalne ogłoszenie DevForum: „on May 29, we are discontinuing the ability to sell developer products and passes"); wprowadzany jest zastępczy Transfers API. Zaprojektuj monetyzację jako in-game (nie cross-game).

---

## Obszar 4 — ARCHITEKTURA TECHNICZNA

### Optymalizacja NPC (NAJWIĘKSZE RYZYKO)
Wątki DevForum („How to optimize a lot of npcs?", „How handle a lot of NPC?", tower-defense threads) są zgodne:
- **PORZUĆ Humanoidy** — są bardzo kosztowne. Używaj prostych części (hitbox cube) + własnego „mover" systemu.
- **JEDEN centralny skrypt-menedżer** zarządzający wszystkimi NPC (nie skrypt-per-NPC, nie while-loop-per-tower). Iteruj po tabeli bytów w jednej pętli (Heartbeat/Stepped). Cytat z DevForum: „have 1 AI script managing all npcs and handle VFX and Animations on the client".
- **Symulacja pozycji na SERWERZE (autorytatywnie), rendering na KLIENCIE.** Przechowuj CFrame/pozycję/dystans na serwerze; klient renderuje modele i VFX.
- **Ruch przez lerp/tween lub `GetServerTimeNow()` do liczenia dystansu na ścieżce** (network cost bardzo niski) zamiast fizyki/PathfindingService per-NPC.
- **UnreliableRemoteEvent do pozycji**, batchowanie updateów (jeden event ze stanem wszystkich enemies co N heartbeatów, np. 10 Hz), nie osobny event per-enemy per-frame.
- Deweloperzy raportują 300 NPC @ ~150 FPS i 1000 NPC @ 40–50 FPS przy R6 bez Humanoida + TweenService (`PhysicsSteppingMethod` = adaptive); jeden dev osiągnął 1000–1500 NPC „mostly without lag" przy script activity <4%.
- Wyłącz Touched eventy; używaj ręcznej detekcji zasięgu (kwadrat odległości) w menedżerze.

Dla WAR RNG (6 plotów × jednostki + fale): plotuj tak, by każdy plot był niezależną „strefą symulacji"; rozważ ograniczenie renderowania cudzych baz (LOD / renderuj tylko plot, na który patrzysz).

### System walki (damage tick)
Zamiast while-loop per wieżyczka: centralny menedżer z jednym tickiem (np. 10 Hz), który dla każdej jednostki sprawdza cooldown i cele w zasięgu (kwadrat odległości), zadaje obrażenia w tabeli HP na serwerze, wysyła zbiorczy update do klienta do renderu (animacje/VFX/pociski na kliencie). Wątki DevForum o tower defense potwierdzają: przechowuj HP w tabeli na serwerze, zadawaj obrażenia serwerowo, replikuj wynik.

### Grid occupancy dla footprintów 2x2
Wzorce z DevForum (Sandbox Tycoon Grid Placement, moduł Tunicus/glitchifyed): siatka jako 2D tablica `grid[x][y]` z referencją do zajmującego obiektu (lub `false`). Dla footprintu 2x2: przy walidacji placementu sprawdź wszystkie 4 komórki `(x,y),(x+1,y),(x,y+1),(x+1,y+1)` — wszystkie muszą być wolne i w granicach; przy postawieniu oznacz wszystkie 4 tym samym ID obiektu; przy usunięciu wyczyść wszystkie 4. Serializacja: zapisuj listę `{itemId, anchorX, anchorY, rotation}` — odtwarzaj zajętość przy ładowaniu. Snapowanie do siatki przez zaokrąglanie pozycji myszy do rozmiaru komórki.

### ProfileStore (dane)
**Używaj ProfileStore (loleris), nie ProfileService** — autor jawnie deklaruje na DevForum: „ProfileService IS STABLE, BUT NO LONGER SUPPORTED - USE 'ProfileStore' FOR NEW PROJECTS". Zalety: session-locking (chroni przed dupe i utratą danych przy wielu serwerach), auto-save — verbatim ze strony ProfileStore: „Default auto-save period increased from 30 to 300 seconds - Nearly x10 fewer DataStore calls consume less server resources which means more scalability!", MessagingService do szybkiego rozwiązywania konfliktów sesji, GlobalUpdates do prezentów/adminowania. Wzorzec: `LoadProfileAsync` z „ForceLoad"; jeśli `profile == nil` → kick gracza (nigdy nie pozwól grać bez danych).

Schemat profilu WAR RNG (PROFILE_TEMPLATE): `coins`, `rollCount`, `inventory` (tabela jednostek z rarity+mutacją), `placements` (lista {itemId, anchorX, anchorY, rot}), `skills` (kupione węzły), `index` (odkryte + poziomy), `boosts`/timestampy, `lastLogout` (do offline), `settings`. Serializuj placements/inventory jako lekkie tabele (ID, nie instancje).

### Replikacja (6 graczy oglądających swoje bazy)
Serwer autorytatywny dla stanu (pozycje NPC, HP, wynik fali). Rozważ ReplicaService (loleris) do replikacji stanu, lub własny system z batchowanymi UnreliableRemoteEvents. Klient renderuje. Dla wydajności: renderuj pełne szczegóły tylko dla plotu obserwowanego przez danego gracza; sąsiednie ploty na uproszczonym LOD lub na żądanie.

### ServiceRegistry / config-driven
Wzorzec ServiceRegistry (single-script-architecture / Knit-like) jest zdrowy: serwisy rejestrowane centralnie, dostęp przez registry, balans (rarity, koszty, HP, obrażenia, ceny) w ModuleScript-configach (nie hardcoded), by tuningować bez zmian w logice.

---

## Recommendations — architektura i zakres v1 WAR RNG

### Zakres v1 (MVP, kalibrowany na Build a Base RNG)
1. **Rdzeń:** core/battery 100 HP w kostce; przegrana = summary screen + zachowanie coins. ✅ (zgodne z planem — trzymaj się).
2. **Roll:** server-authoritative, cumulative weight table + `Random.new()`. Drabina 1 in N w zakresie 1/3 → ~1/1500 na start (jak Build a Base RNG), z zapasem na wyższe tiery w update'ach.
3. **Luck:** JEDEN skumulowany współczynnik (formuła w stylu Sol's: `(((1+Basic)*Bonus)+Special)*VIP`), aplikowany przez dzielenie mianowników z `math.max(1, floor(N/luck))` + fallback common. NIE używaj pętli „best of N".
4. **Mutacje:** niezależna druga rolka po głównej (x2/x4/x8), własne 1/M. Scryptowane mutacje w tutorialu (gwarantowany early x2/x4).
5. **Pity:** licznik serwerowy; hard pity po np. 100 rolkach bez rzadkiego.
6. **Siatka:** 9×12, cap jednostek + footprinty 1x1 i 2x2 przez `grid[x][y]` occupancy. ✅ (patrz flaga #2).
7. **Dwie waluty:** coins + rollCount w skill tree (luck / roll-speed / mutation / „Place More Units"). ✅
8. **Fale:** wrogowie marszują z bazy dyktatora do core; licznik killed/pool. ✅
9. **Offline:** timestamp + rate z capem (proponuję 8–12h); Offline Roll jako skill/gamepass.
10. **Indeks:** kolekcja z permanentnymi nagrodami Luck za % ukończenia. ✅
11. **NPC od dnia zero:** bez Humanoidów, centralny menedżer, serwer symuluje / klient renderuje, batchowane Unreliable events. To NIE jest optymalizacja „na później" — to fundament architektury.
12. **Dane:** ProfileStore z session-locking.

### Etapy
- **Etap 1 (rdzeń grywalny):** roll + siatka + jedna fala + core HP + coins + ProfileStore. Zwaliduj NPC performance stress-testem (150–300 NPC) ZANIM dodasz resztę.
- **Etap 2 (progresja):** skill tree (2 waluty), luck stacking, indeks, offline, boss na fali ~20.
- **Etap 3 (retencja/monetyzacja):** mutacje, crafting/relikty z bossów, gamepassy (auto-roll, 2x luck, 2x coins), server luck z rosnącą ceną, luck potions.
- **Etap 4 (skala):** LOD dla cudzych baz, więcej stref/światów, prestige/rebirth (jak Slime RNG) jeśli retencja tego wymaga.

### Progi/benchmarki zmieniające decyzje
- Jeśli stress-test 300 NPC < 30 FPS na średnim urządzeniu (mobile!) → zredukuj cap jednostek lub agresywniejszy LOD/culling zanim pójdziesz dalej.
- Jeśli D1 retention < 30% → przeprojektuj FTUE (scryptowane dropy, szybszy pierwszy roll).
- Jeśli konwersja gamepassów niska → obniż ceny do 49–199 R$ dla masowej adopcji, testuj A/B (Experiments/Configs w Roblox).
- Jeśli gracze skarżą się na pech → wzmocnij pity / obniż próg.

### Sprzeczności z obecnym planem — flagi
1. **6 graczy oglądających swoje bazy = realne ryzyko wydajności.** Plan zakłada, że gracze widzą nawzajem bazy. Przy 150–300 NPC to wymaga LOD/culling od początku — nie zakładaj pełnego renderu wszystkich 6 plotów u każdego gracza. **Rozważ**: renderuj w pełni tylko własny plot + plot aktualnie obserwowany.
2. **Cap 40 jednostek × footprinty 2x2 vs siatka 9×12 (108 komórek).** 40 jednostek 2x2 = 160 komórek > 108 — czyli cap 40 przy dużym udziale 2x2 jest fizycznie niemożliwy do wypełnienia. Upewnij się, że cap jednostek i pojemność siatki są spójne (albo większość jednostek 1x1, albo mniejszy cap / większa siatka, albo cap liczony w „zajętych komórkach", nie w sztukach).
3. **Dwuwalutowy skill tree (coins + total roll count):** działa (Build a Base RNG używa dice/rolek), ale uważaj, by „total roll count" jako waluta wydawana nie kolidował z rollCount używanym do progresji/pity — trzymaj OSOBNY licznik „spendable rolls" vs „lifetime rolls".
4. **Brak PvP + parallel co-op:** dobre dla wydajności i moderacji, ale rozważ lekki element społeczny (odwiedzanie baz, leaderboard fal), bo gatunek na tym korzysta (Tower Defense RNG i Anime RNG Defense mają „visit other players' bases").

## Caveats
- Wiele danych o Build a Base RNG pochodzi z community wiki i portali poradnikowych (buildabaserng.wiki, allthings.how, nerdschalk, roonby), nie z oficjalnej dokumentacji dewelopera — konkretne koszty/HP/rarity mogą się różnić między wersjami i były aktualizowane („Bosses Update"). Traktuj liczby jako kalibrację, nie jako pewnik. Ocena gry podawana jest rozbieżnie (97,6% vs 98,2%) — zweryfikuj bieżąco.
- Formuła luck Sol's RNG jest modelem odtworzonym przez community (wiki CC-BY-SA), które samo ostrzega, że rzeczywiste szanse „may not reflect the value assigned to said aura" — to nie oficjalna specyfikacja dewelopera.
- Część wskazówek DevForum to opinie praktyków-hobbystów (np. tłumienie `math.sqrt(luck)` to wybór jednego dewa, nie standard; `roll^(1/luck)` i model interwałowy [0,1] są najbardziej rygorystyczne matematycznie). Kod traktuj jako punkt wyjścia, nie gotowe rozwiązanie produkcyjne.
- Benchmarki wydajności NPC (300 @ 150 FPS itd.) pochodzą z pojedynczych zgłoszeń DevForum na nieznanym sprzęcie — MUSISZ zrobić własny stress-test na docelowych urządzeniach (szczególnie mobile).
- Ceny gamepassów i stawki DevEx są aktualne na 2026, ale Roblox zmienia politykę (wyłączenie cross-game pass sales od 29–30 maja 2026; nowa stawka US 18+ DevEx od 8 czerwca 2026) — weryfikuj przed wdrożeniem.
- KitsBlox i część portali monetyzacyjnych to blogi marketingowe/afiliacyjne (sprzedają assety/moduły) — traktuj jako best-practice, nie źródło pierwotne.
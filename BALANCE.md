# BALANCE — mapa pokręteł (dla Olo)

Wszystkie liczby balansu siedzą w **plikach configu** (`src/ReplicatedStorage/Content/Config/`).
Serwis/kontroler **nigdy nie hardkoduje** balansu — czyta z configu. Zmieniasz liczbę → Rojo synchronizuje do Studio → działa.
**Nie ruszaj** plików w `Services/` ani `Controllers/` dla balansu — tylko te configi niżej.

> Po edycji: zapis pliku wystarczy (Rojo live-sync). Nic nie kompilujesz ręcznie.

---

## 1. Wrogowie — HP, DMG, zasięg, prędkość (per tier + boss)

**Plik:** `Config/WaveConfig.luau` → tabela `enemyTypes`

Każdy typ wroga ma:

| pole | co robi |
|---|---|
| `hp` | **HP wroga** (ile wytrzyma) |
| `speed` | prędkość marszu (pathT/s; 0..1 = start→rdzeń). Większe = szybszy |
| `atkDmg` | **DMG do NASZYCH jednostek** (mitygowane przez `def` jednostki/bloku) |
| `atkRange` | **zasięg broni** — do jednostek **oraz** do rdzenia (w tym dystansie staje i strzela) |
| `atkRate` | strzały/s do jednostek (większe = szybciej) |
| `coreDmg` | **DMG do rdzenia** za jeden strzał |
| `coreAttackInterval` | co ile sekund strzela w rdzeń |
| `model` | model wizualny z `Assets.Units` (NIE balans) |

**Tiery** (klucze w `enemyTypes`):
- Tier 1: `grunt`
- Tier 2: `t2_soldier`, `t2_swat`, `t2_sniper`
- Tier 3: `t3_flame`, `t3_rocket`
- Tier 4: `t4_heavy`, `t4_jeep`
- Tier 5: `t5_tank`, `t5_heli`
- Tier 6: `t6_jet`

**Bossy** (osobne wpisy, `isBoss = true`): `boss` (tier4, fala 20), `boss5` (tier5, fala 40), `boss6` (tier6, fala 60).
Boss = te same pola (hp/atkDmg/coreDmg/...), tylko większe. Model bossa jest wizualnie ~2.5× większy (patrz §6).

---

## 2. Skalowanie fal w nieskończoność

**Plik:** `Config/WaveConfig.luau` → tabela `scaling`

| pole | co robi | teraz |
|---|---|---|
| `poolBase` | bazowa **ilość wrogów** w fali | 20 |
| `poolPerWave` | +ile wrogów **za każdą falę** | 4 |
| `hpGrowth` | mnożnik **HP wrogów** za falę (`hp × hpGrowth^(n-1)`) | 1.12 |
| `dmgGrowth` | mnożnik **atkDmg wrogów** za falę | 1.07 |
| `coinGrowth` | mnożnik nagrody monet za falę | 1.15 |

Wzór na falę `n` (gdy brak jawnej definicji):
- ilość wrogów `pool = poolBase + n * poolPerWave`
- HP wroga = `hp × hpGrowth^(n-1)`  •  atkDmg wroga = `atkDmg × dmgGrowth^(n-1)`

> `hpGrowth=1.12` rośnie szybko (×~9.6 HP po 20 falach). Jak za mocno — zjedź do 1.06–1.09.

---

## 3. Bossy i odblokowywanie tierów

**Plik:** `Config/WaveConfig.luau` (pola najniżej)

| pole | co robi | teraz |
|---|---|---|
| `bossWave` | **co ile fal boss** (20 = fala 20,40,60...) | 20 |
| `tierBase` | najwyższy tier na falach 1..bossWave-1 | 3 |
| `tierWindow` | ile ostatnich tierów aktywnych w mixie (np. 4 → fala 21 = tier 1-4) | 4 |
| `bossTiers` | który boss na której fali bossa (`{boss, boss5, boss6}`) | ↓ |
| `bossGrunts` | ilu zwykłych wrogów towarzyszy bossowi | 10 |
| `bossRewardMult` | ile× nagroda monet za falę bossa | 3 |

**Reguła tierów:** `maxTier = tierBase + floor(fala / bossWave)` (do 6). Czyli:
fale 1-19 → tier 3 · fala 20 boss tier4 · fale 21-39 → tier 4 · fala 40 boss tier5 · itd.

Fala 1 ma jawny skład: `waves[1]` (teraz `grunt ×24`).

---

## 4. Nasze jednostki i przedmioty — HP, obrona, DMG

**Plik:** `Config/UnitsConfig.luau`

Każda jednostka (np. `soldier`, `tank`, `helicopter`, `jeep`, `sniper`, `swat`, `tank_soldier`, `rocket_soldier`, `flamethrower`, `noob_soldier`, `jet`):

| pole | co robi |
|---|---|
| `hp` | **HP jednostki** (ile wytrzyma ostrzał wrogów) |
| `def` | **OBRONA** — obrażenia wroga = `max(0, atkDmg - def)`. Gdy def ≥ dmg wroga → **0** (nie traci HP) |
| `combat.dmg` | **DMG jednostki** na strzał |
| `combat.fireRate` | strzały/s jednostki |
| `combat.range` | zasięg jednostki |
| `rarityN` | rzadkość dropu (1inN) — nie bojowe |

**Bloki (ściany):** wpisy `test_block_wood/stone/iron/rusty`:
- `hp` — wytrzymałość bloku
- `def` — **niewidoczny pancerz**: obrażenia wroga = `max(0, atkDmg - def)` (def ≥ dmg → 0, blok nie traci HP)

---

## 5. Rdzeń (serduszko bazy)

- **Bazowe HP rdzenia:** `Config/StatBaseConfig.luau` → `coreHP` (teraz **100**).
- **Ulepszenie HP rdzenia w drzewku:** `Config/SkillConfig.luau` → `core_1` (`perRank`, teraz +25/rank, maxRank 3).
- **Zasięg ostrzału rdzenia przez wrogów** = `atkRange` danego wroga (§1). Wróg staje w tym dystansie i strzela w rdzeń (nie wchodzi w niego). `coreDmg` + `coreAttackInterval` = jego obrażenia/tempo na rdzeń.

---

## 6. Blokowanie ruchu (wrogowie nie przenikają przez bloki/jednostki)

Wrogowie **stają przed** każdym postawionym blokiem/jednostką na ścieżce i muszą go zniszczyć, żeby iść dalej.
Bloki są **pasywne** (mają HP + `def`, blokują, ale NIE zadają dmg — obrażenia zadają dopiero pułapki).

**Plik:** `Config/SimConfig.luau`
- `blockAhead` — jak daleko przed wrogiem sprawdzana jest przeszkoda (teraz 2.5 studa)
- `blockRadius` — promień zajętości jednostki/bloku (teraz 4.0; ~pół kafla 6/2 + margines)

> HP/def bloków = §4 (`UnitsConfig.test_block_*`). Ile wróg zdejmuje blokowi = `max(0, atkDmg - def)` — gdy def ≥ dmg wroga, blok NIE traci HP (obrona w pełni chroni).

---

## 7. Wizual (NIE balans, ale gdyby trzeba)

**Plik:** `Controllers/EnemyRenderController.luau` (góra):
- `BOSS_FOOT = 10` / `GRUNT_FOOT = 4` — rozmiar modelu bossa vs zwykłego (study).
- Rozstaw/chmara, animacje — stałe `WALK_FREQ`, `LEG_AMP` itd.

---

### Ściąga „chcę zmienić X":
- **HP wroga / tiera** → `WaveConfig.enemyTypes[typ].hp`
- **HP bossa** → `WaveConfig.enemyTypes.boss/boss5/boss6.hp`
- **DMG wroga do jednostek** → `atkDmg` · **do rdzenia** → `coreDmg`
- **HP naszych** → `UnitsConfig[jednostka].hp` · **obrona** → `def` · **DMG** → `combat.dmg`
- **Ilość wrogów w fali** → `WaveConfig.scaling.poolBase` + `poolPerWave`
- **Jak szybko rośnie trudność** → `scaling.hpGrowth` / `dmgGrowth`
- **HP rdzenia** → `StatBaseConfig.coreHP`
- **Co ile boss / jaki boss** → `WaveConfig.bossWave` / `bossTiers`

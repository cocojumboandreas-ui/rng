--!strict
-- ⚙ BALANS: pelna mapa pokretel w /BALANCE.md (dla Olo). Tu: HP/DMG/zasieg/ilosc wrogow + bossy + skala.
-- Content/Config/WaveConfig.luau — sklad fal. Wave [1] jawny; [n] z formuly `scaling`
-- (WZOR w configu, nie w kodzie). enemyTypes: speed w pathT/s (0..1 na polilinii).
--
-- TIERY (§fala): 6 tierow wrogow (jak platy na bazie: tier1 szary -> tier6 czerwony).
--   maxTier fali = 1 + floor((n-1)/tierEvery); w mixie aktywne ostatnie `tierWindow` tierow.
--   Bossy co `bossWave` fal (20,40,60...); k-ty boss = bossTiers[k] (coraz wiekszy: Tank->Heli->Jet).
--   Wszystko ma hp+dmg; skalowanie w nieskonczonosc przez hpMult (hpGrowth^n) + rosnaca pula.
--   coreDmg = obrazenia serduszka bazy; atk* = walka z jednostkami gracza (DEF bloku mityguje w CombatService).
local WaveConfig = {
	waves = {
		[1] = { pool = 24, composition = { { "grunt", 24 } }, formation = { cols = 6 }, hpMult = 1.0, coinReward = 150 },
	},
	-- Formula dla wave n (WaveService/CombatService licza gdy brak jawnego [n]):
	--   pool       = poolBase + n * poolPerWave
	--   hpMult     = hpGrowth ^ (n-1)     (skaluje hp wroga)
	--   atkMult    = dmgGrowth ^ (n-1)    (skaluje atkDmg wroga -> DEF bloku spowalnia, nie zatrzymuje na zawsze)
	--   coinReward = round(waves[1].coinReward * coinGrowth ^ (n-1))
	scaling = { poolBase = 20, poolPerWave = 4, hpGrowth = 1.12, dmgGrowth = 1.07, coinGrowth = 1.15 },
	enemyTypes = {
		-- model = wizual wroga (klient renderuje prawdziwy model z Assets.Units, strzela z broni + animacje).
		-- TIER 1 (szary) — Noob Soldier, pistolet. 'grunt' = alias tier1 (harness + wave 1).
		grunt = { tier = 1, hp = 30, speed = 0.065, coreDmg = 4, coreAttackInterval = 1.0, model = "Noob Soldier", atkRange = 16, atkRate = 1.0, atkDmg = 6 },
		-- TIER 2 (zielony) — karabiny / snajperka
		t2_soldier = { tier = 2, hp = 55, speed = 0.060, coreDmg = 6, coreAttackInterval = 1.0, model = "Soldier", atkRange = 18, atkRate = 1.1, atkDmg = 9 },
		t2_swat = { tier = 2, hp = 110, speed = 0.052, coreDmg = 7, coreAttackInterval = 1.1, model = "SWAT", atkRange = 16, atkRate = 1.3, atkDmg = 8 },
		t2_sniper = { tier = 2, hp = 45, speed = 0.058, coreDmg = 8, coreAttackInterval = 1.0, model = "Sniper", atkRange = 30, atkRate = 0.5, atkDmg = 18 },
		-- TIER 3 (cyan) — miotacz ognia / RPG
		t3_flame = { tier = 3, hp = 130, speed = 0.055, coreDmg = 9, coreAttackInterval = 1.1, model = "Flamethrower", atkRange = 10, atkRate = 3.0, atkDmg = 6 },
		t3_rocket = { tier = 3, hp = 95, speed = 0.048, coreDmg = 12, coreAttackInterval = 1.2, model = "Rocket Soldier", atkRange = 26, atkRate = 0.6, atkDmg = 22 },
		-- TIER 4 (fiolet) — ciezki piechur (minigun+tarcza) / jeep
		t4_heavy = { tier = 4, hp = 260, speed = 0.045, coreDmg = 13, coreAttackInterval = 1.2, model = "Tank Soldier", atkRange = 18, atkRate = 1.5, atkDmg = 12 },
		t4_jeep = { tier = 4, hp = 340, speed = 0.050, coreDmg = 15, coreAttackInterval = 1.3, model = "Jeep", atkRange = 16, atkRate = 1.2, atkDmg = 14 },
		-- TIER 5 (zolty) — czolg / helikopter
		t5_tank = { tier = 5, hp = 650, speed = 0.036, coreDmg = 20, coreAttackInterval = 1.4, model = "Tank", atkRange = 24, atkRate = 0.7, atkDmg = 40 },
		t5_heli = { tier = 5, hp = 430, speed = 0.044, coreDmg = 18, coreAttackInterval = 1.3, model = "Helicopter", atkRange = 28, atkRate = 1.8, atkDmg = 16 },
		-- TIER 6 (czerwony) — jet
		t6_jet = { tier = 6, hp = 520, speed = 0.050, coreDmg = 24, coreAttackInterval = 1.4, model = "Jet", atkRange = 32, atkRate = 1.2, atkDmg = 30 },
		-- BOSSY = wieksi warianci (isBoss -> wieksza skala na kliencie + pasek HP). 'boss' = boss fali 20 (tier 4).
		boss = { tier = 4, isBoss = true, hp = 900, speed = 0.028, coreDmg = 30, coreAttackInterval = 1.5, model = "Tank", atkRange = 24, atkRate = 0.6, atkDmg = 45 },
		boss5 = { tier = 5, isBoss = true, hp = 1800, speed = 0.026, coreDmg = 42, coreAttackInterval = 1.5, model = "Helicopter", atkRange = 28, atkRate = 0.9, atkDmg = 55 },
		boss6 = { tier = 6, isBoss = true, hp = 3200, speed = 0.024, coreDmg = 58, coreAttackInterval = 1.6, model = "Jet", atkRange = 34, atkRate = 1.1, atkDmg = 72 },
	},
	-- typy wroga per tier (WaveService losuje deterministycznie po numerze fali -> stabilne + zroznicowane)
	tierTypes = {
		[1] = { "grunt" },
		[2] = { "t2_soldier", "t2_swat", "t2_sniper" },
		[3] = { "t3_flame", "t3_rocket" },
		[4] = { "t4_heavy", "t4_jeep" },
		[5] = { "t5_tank", "t5_heli" },
		[6] = { "t6_jet" },
	},
	tierBase = 3, -- tier startowy (fale 1-19 mają maxTier=3); +1 po każdej fali bossa (patrz maxTierFor)
	tierEvery = 6, -- (DEPRECATED — maxTier przewiązane teraz do bossWave, nie tierEvery)
	tierWindow = 4, -- ile ostatnich (najwyzszych) tierow jest aktywnych w mixie fali (4 -> np. fala 21 = tier 1-4)
	bossTiers = { "boss", "boss5", "boss6" }, -- k-ta boss-fala (20,40,60...) -> ten boss (k>#-> ostatni)
	bossWave = 20, -- INTERWAL: co 20. fala = boss (20, 40, 60...)
	bossRewardMult = 3, -- boss-fala daje x nagrody normalnej fali n
	bossGrunts = 10, -- kompozycja boss-fali = 1 boss + tylu wrogow podkladu (tier maxTier-1)
}

return WaveConfig

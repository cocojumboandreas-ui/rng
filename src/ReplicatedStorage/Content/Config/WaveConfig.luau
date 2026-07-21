--!strict
-- Content/Config/WaveConfig.luau — sklad fal. Wave [1] jawny; [n] z formuly `scaling`
-- (WZOR w configu, nie w kodzie). enemyTypes: speed w pathT/s (0..1 na polilinii).
local WaveConfig = {
	waves = {
		[1] = { pool = 24, composition = { { "grunt", 24 } }, formation = { cols = 6 }, hpMult = 1.0, coinReward = 150 },
	},
	-- Formula dla wave n (WaveService liczy gdy brak jawnego [n]):
	--   pool       = poolBase + n * poolPerWave
	--   hpMult     = hpGrowth ^ n
	--   coinReward = round(waves[1].coinReward * coinGrowth ^ (n-1))
	scaling = { poolBase = 20, poolPerWave = 4, hpGrowth = 1.12, coinGrowth = 1.15 },
	enemyTypes = {
		-- model = wizual wroga (klient renderuje prawdziwy model z Assets.Units). atkRange/atkRate = wizual
		-- strzelania do naszych jednostek (faza 4); realne obrazenia jednostek dojda w fazie 5.
		grunt = { hp = 30, speed = 0.06, coreDmg = 5, coreAttackInterval = 1.0, model = "Noob Soldier", atkRange = 16, atkRate = 1.0 },
		-- BOSS = specjalny wrog w tej samej symulacji (isBoss). Wysokie HP (x hpMult fali),
		-- wolny, mocny cios w rdzen. Zero bespoke AI — maszeruje do rdzenia jak inni.
		boss = { hp = 500, speed = 0.03, coreDmg = 25, coreAttackInterval = 1.5, isBoss = true, model = "Tank", atkRange = 24, atkRate = 0.6 },
	},
	bossWave = 20, -- INTERWAL: co 20. fala = boss (20, 40, 60...)
	bossRewardMult = 3, -- boss-fala daje x nagrody normalnej fali n
	bossGrunts = 10, -- kompozycja boss-fali = 1 boss + tylu zredukowanych gruntow
}

return WaveConfig

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
		grunt = { hp = 30, speed = 0.06, coreDmg = 5, coreAttackInterval = 1.0 },
	},
	bossWave = 20, -- layer-2, zarezerwowane (poza v1)
}

return WaveConfig

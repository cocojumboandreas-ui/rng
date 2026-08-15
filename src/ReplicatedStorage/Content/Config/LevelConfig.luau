--!strict
-- Content/Config/LevelConfig.luau — LEWELOWANIE TYPU jednostki (Etap 3 indeksu: anty-sciana + coin sink).
-- Level per unitId (wariant-niezalezny: regular/shiny/galaxy dziela poziom TYPU). Poziom buffuje WSZYSTKIE
-- postawione kopie typu. Efekt MULTIPLIKATYWNY: stat = base * growthPerLevel^level (weapon->dmg, block->hp).
-- Koszt kolejnego poziomu: baseCost(unitId) * costGrowth^level, gdzie baseCost = floor(rarityN * baseCostK)
-- (rzadsze jednostki drozej lewelowac). WSZYSTKIE LICZBY = PLACEHOLDER (Olo dostroi w BALANCE).
-- ZASADA: zero liczb w logice serwisu — LevelService czyta tylko stad.
local LevelConfig = {
	growthPerLevel = 1.10, -- ATTACK(Weapon) dmg — glowna krzywa (niezmieniona). DEFENSE(Block) hp — reuse tej samej krzywej.
	attackHpGrowthPerLevel = 1.03, -- ATTACK(Weapon) hp — MALA sekundarna krzywa (dmg jest glownym skalowaniem typu attack).
	-- Rezerwa (NIEUZYWANA): gdyby po playtestach defense (Block, hp=growthPerLevel powyzej) nie wyprzedzal
	-- attacka (hp=attackHpGrowthPerLevel) wystarczajaco wyraznie, mozna dodac wlasna wieksza krzywe np.
	-- defenseHpGrowthPerLevel = 1.12 i podpiac w LevelService.GetHpLevelMult zamiast reuse growthPerLevel.
	costGrowth = 1.5, -- geometryczny wzrost kosztu kolejnego poziomu (koszt = baseCost * costGrowth^level)
	baseCostK = 5, -- baseCost(unitId) = floor(rarityN * baseCostK) — K do strojenia; rzadsze = drozsze
	maxLevel = 100, -- twardy sufit poziomu typu
}

return LevelConfig

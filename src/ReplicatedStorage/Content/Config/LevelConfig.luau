--!strict
-- Content/Config/LevelConfig.luau — LEWELOWANIE TYPU jednostki (Etap 3 indeksu: anty-sciana + coin sink).
-- Level per unitId (wariant-niezalezny: regular/shiny/galaxy dziela poziom TYPU). Poziom buffuje WSZYSTKIE
-- postawione kopie typu. Efekt MULTIPLIKATYWNY: stat = base * growthPerLevel^level (weapon->dmg, block->hp).
-- Koszt kolejnego poziomu: baseCost(unitId) * costGrowth^level, gdzie baseCost = floor(rarityN * baseCostK)
-- (rzadsze jednostki drozej lewelowac). WSZYSTKIE LICZBY = PLACEHOLDER (Olo dostroi w BALANCE).
-- ZASADA: zero liczb w logice serwisu — LevelService czyta tylko stad.
local LevelConfig = {
	growthPerLevel = 1.10, -- mnoznik efektu na poziom (1.10 = +10%/lvl, kumulatywnie, multiplikatywnie)
	costGrowth = 1.5, -- geometryczny wzrost kosztu kolejnego poziomu (koszt = baseCost * costGrowth^level)
	baseCostK = 5, -- baseCost(unitId) = floor(rarityN * baseCostK) — K do strojenia; rzadsze = drozsze
	maxLevel = 100, -- twardy sufit poziomu typu
}

return LevelConfig

--!strict
-- Content/Config/StatBaseConfig.luau — BAZY plaskiej tabeli Stats (§3.2).
-- StatProfileService startuje od tych baz i doklada delty skilli/passow/boostow.
-- luck i cellBudget maja kanoniczne domy (Rarity/Grid) — referujemy, zeby nie dublowac liczby.
-- Multiplikatory (mut/dmg/fireRate/range/coin): baza 1.0 (neutralna; skille dokladaja delty).
-- rollSpeed / coreHP / offlineRate: placeholdery do kalibracji (Olo).
local Config = script.Parent
local RarityConfig = require(Config:WaitForChild("RarityConfig"))
local GridConfig = require(Config:WaitForChild("GridConfig"))

local StatBaseConfig = {
	luck = RarityConfig.luck.base, -- 1.0 (dom: RarityConfig)
	rollSpeed = 4.0, -- cooldown rolki [s] START; Fast Rolls schodzi do floor 3.0 (klamp w StatProfile)
	mutChance = 1.0, -- mnoznik szansy mutacji (chanceN / mutChance)
	cellBudget = GridConfig.baseCellBudget, -- 40 (dom: GridConfig)
	dmgMult = 1.0, -- mnoznik dmg wiez
	fireRateMult = 1.0, -- mnoznik szybkostrzelnosci
	rangeMult = 1.0, -- mnoznik zasiegu
	coreHP = 200, -- STALE HP rdzenia (design: nieskonczone przetrwanie, gracz w koncu zawsze przegrywa; core_1 +25/rank na wierzchu)
	coinMult = 1.0, -- mnoznik monet (killReward x coinMult)
	offlineRate = 10, -- monety/h offline (POST-BRAMKA; placeholder)
	variantLuck = 1, -- mnoznik szansy wariantu (chanceN / variantLuck); hook pod gamepassy shiny/galaxy
}

return StatBaseConfig

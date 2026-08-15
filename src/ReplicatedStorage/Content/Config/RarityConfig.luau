--!strict
-- Content/Config/RarityConfig.luau — progi tierow (intensywnosc rewealu) + luck baza + pity.
-- rarityN jednostki -> tier po pierwszym progu maxN, ktory obejmuje N.
local RarityConfig = {
	tiers = {
		{ name = "Common", maxN = 10, revealTier = 1 },
		{ name = "Rare", maxN = 40, revealTier = 2 },
		{ name = "Super Rare", maxN = 150, revealTier = 3 },
		{ name = "Mystic", maxN = 600, revealTier = 4 },
		{ name = "Legend", maxN = 1500, revealTier = 5 },
		{ name = "Mysterious", maxN = math.huge, revealTier = 6 },
	},
	luck = { base = 1.0 }, -- reszta luck ze skilli/indeksu/boostow przez StatProfile
	pity = { threshold = 100, guaranteeMinN = 60 }, -- 100 rolek bez N>=60 -> wymus tier Rare+
}

return RarityConfig

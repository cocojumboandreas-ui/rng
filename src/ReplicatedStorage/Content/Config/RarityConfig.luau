--!strict
-- Content/Config/RarityConfig.luau — progi tierow (intensywnosc rewealu) + luck baza + pity.
-- rarityN jednostki -> tier po pierwszym progu maxN, ktory obejmuje N.
local RarityConfig = {
	tiers = {
		{ name = "Common", maxN = 10, revealTier = 1 },
		{ name = "Uncommon", maxN = 50, revealTier = 2 },
		{ name = "Rare", maxN = 200, revealTier = 3 },
		{ name = "Epic", maxN = 1000, revealTier = 4 },
		{ name = "Legendary", maxN = math.huge, revealTier = 5 },
	},
	luck = { base = 1.0 }, -- reszta luck ze skilli/indeksu/boostow przez StatProfile
	pity = { threshold = 100, guaranteeMinN = 60 }, -- 100 rolek bez N>=60 -> wymus tier Rare+
}

return RarityConfig

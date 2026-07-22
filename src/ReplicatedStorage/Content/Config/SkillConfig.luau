--!strict
-- Content/Config/SkillConfig.luau — drzewko umiejetnosci (rankowane, pasywne), 2 waluty.
-- SCHEMA authored wg §4. UWAGA: SkillService jest POST-BRAMKA — tu tylko dane, brak logiki.
-- StatProfileService agreguje GENERYCZNIE po effect.{stat,perRank} -> nowy wezel = zero kodu serwera,
-- wystarczy zeby effect.stat byl jednym z pol Stats (StatBaseConfig).
-- `label` = krotka nazwa do UI drzewka (NodeTree). `branch` = grupowanie/layout.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enums = require(Shared:WaitForChild("Enums"))

local C = Enums.Currency

local SkillConfig = {
	costExp = 1.5, -- cost(rank) = round(base * rank ^ costExp)  (liczone w SkillService)
	nodes = {
		-- ── ROLL (RNG) ──────────────────────────────────────────────────────
		luck_1 = { branch = "Roll", label = "Szczescie", currency = C.Coins, maxRank = 5, base = 100, effect = { stat = "luck", perRank = 0.2 } },
		fast_1 = { branch = "Roll", label = "Tempo rolki", currency = C.Rolls, maxRank = 3, base = 15, effect = { stat = "rollSpeed", perRank = -0.15 } },
		mut_1 = { branch = "Roll", label = "Mutacja", currency = C.Rolls, maxRank = 3, base = 20, effect = { stat = "mutChance", perRank = 0.15 } },
		variant_1 = { branch = "Roll", label = "Wariant", currency = C.Rolls, maxRank = 3, base = 30, effect = { stat = "variantLuck", perRank = 0.25 } },

		-- ── BASE (ekonomia/obrona) ─────────────────────────────────────────
		cells_1 = { branch = "Base", label = "Budzet cel", currency = C.Coins, maxRank = 4, base = 500, effect = { stat = "cellBudget", perRank = 5 } },
		core_1 = { branch = "Base", label = "HP rdzenia", currency = C.Coins, maxRank = 3, base = 300, effect = { stat = "coreHP", perRank = 25 } },
		coin_1 = { branch = "Base", label = "Monety", currency = C.Coins, maxRank = 5, base = 150, effect = { stat = "coinMult", perRank = 0.1 } },
		offline_1 = { branch = "Base", label = "Offline", currency = C.Coins, maxRank = 4, base = 400, effect = { stat = "offlineRate", perRank = 5 } },

		-- ── COMBAT (wieze) ─────────────────────────────────────────────────
		dmg_1 = { branch = "Combat", label = "Obrazenia", currency = C.Coins, maxRank = 5, base = 200, effect = { stat = "dmgMult", perRank = 0.1 } },
		fire_1 = { branch = "Combat", label = "Szybkostrz.", currency = C.Coins, maxRank = 5, base = 250, effect = { stat = "fireRateMult", perRank = 0.1 } },
		range_1 = { branch = "Combat", label = "Zasieg", currency = C.Coins, maxRank = 4, base = 300, effect = { stat = "rangeMult", perRank = 0.08 } },
	},
}

return SkillConfig

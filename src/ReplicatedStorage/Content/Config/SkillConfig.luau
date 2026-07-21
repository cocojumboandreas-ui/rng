--!strict
-- Content/Config/SkillConfig.luau — drzewko LEAN (3 galezie, pasywne ranki), 2 waluty.
-- SCHEMA authored wg §4. UWAGA: SkillService jest POST-BRAMKA — tu tylko dane, brak logiki.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enums = require(Shared:WaitForChild("Enums"))

local SkillConfig = {
	costExp = 1.5, -- cost(rank) = round(base * rank ^ costExp)  (liczone w SkillService)
	nodes = {
		luck_1 = { branch = "Roll", currency = Enums.Currency.Coins, maxRank = 5, base = 100, effect = { stat = "luck", perRank = 0.2 } },
		fast_1 = { branch = "Roll", currency = Enums.Currency.Rolls, maxRank = 3, base = 15, effect = { stat = "rollSpeed", perRank = -0.15 } },
		cells_1 = { branch = "Base", currency = Enums.Currency.Coins, maxRank = 4, base = 500, effect = { stat = "cellBudget", perRank = 5 } },
		dmg_1 = { branch = "Combat", currency = Enums.Currency.Coins, maxRank = 5, base = 200, effect = { stat = "dmgMult", perRank = 0.1 } },
		core_1 = { branch = "Base", currency = Enums.Currency.Coins, maxRank = 3, base = 300, effect = { stat = "coreHP", perRank = 25 } },
	},
}

return SkillConfig

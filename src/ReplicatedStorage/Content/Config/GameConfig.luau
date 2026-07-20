--!strict
-- Content/Config/GameConfig.luau — agregator configow (§4 architektury).
-- Serwisy robia require(GameConfig) i czytaja GameConfig.Units / .Rarity / .Grid ...
-- ZASADA: kazda liczba balansu siedzi w podmodulach; serwisy nie zawieraja liczb.
local Config = script.Parent

local GameConfig = {
	Units = require(Config:WaitForChild("UnitsConfig")),
	Rarity = require(Config:WaitForChild("RarityConfig")),
	Mutation = require(Config:WaitForChild("MutationConfig")),
	Wave = require(Config:WaitForChild("WaveConfig")),
	Grid = require(Config:WaitForChild("GridConfig")),
	Skill = require(Config:WaitForChild("SkillConfig")),
	Economy = require(Config:WaitForChild("EconomyConfig")),
	Reveal = require(Config:WaitForChild("RevealConfig")),
}

return GameConfig

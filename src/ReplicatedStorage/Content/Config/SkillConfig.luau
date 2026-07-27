--!nonstrict
-- Content/Config/SkillConfig.luau — koszty/kupno drzewa umiejetnosci (dane z SkillTreeData).
-- FAZA: BEZ efektow (node bez `effect` -> StatProfile go pomija, zero zmiany Stats). Efekty dorobimy pozniej.
-- maxRank=1 -> cost = base * 1^costExp = base (koszt = wprost z crafteru). currency: coin>0 -> Coins, roll>0 -> Rolls.
-- Wezly 0/0 (informacyjne) NIE trafiaja tu -> niekupowalne (SkillService: NoSuchNode).
local Config = script.Parent
local SkillTreeData = require(Config:WaitForChild("SkillTreeData"))
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enums = require(Shared:WaitForChild("Enums"))
local C = Enums.Currency

local nodes = {}
for _, n in ipairs(SkillTreeData) do
	local coin, roll = n.coin or 0, n.roll or 0
	if n.id ~= "root" and (coin > 0 or roll > 0) then
		nodes[n.id] = {
			label = n.label,
			currency = (coin > 0) and C.Coins or C.Rolls,
			maxRank = 1,
			base = (coin > 0) and coin or roll,
			-- kupno tylko gdy RODZIC kupiony (progresja od podstaw; blokuje kupno "?" poza kolejnoscia)
			prereqs = (n.parent ~= "root") and { [n.parent] = 1 } or nil,
			-- BEZ `effect`: na razie zero mechaniki (StatProfile pomija). Efekty dorobimy per-wezel pozniej.
		}
	end
end

return {
	costExp = 1.0, -- maxRank=1, wiec cost = base (koszt wprost z projektu)
	nodes = nodes,
}

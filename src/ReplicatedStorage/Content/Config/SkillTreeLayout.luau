--!nonstrict
-- Content/Config/SkillTreeLayout.luau
-- Generuje liste wezlow dla packa NodeTree z naszego SkillConfig.
-- Kazdy rankowany skill -> LANCUCH wezlow (rank1 -> rank2 -> ...), kupowany po kolei.
-- NodeTree.Configs.Nodes jest shimem: `return require(...SkillTreeLayout)`.
-- Kontrakt wezla (NodeTree.Configs.Types): parentNodeId, direction, icon, text,
--   price{quantity,currencyIcon}, headerText, inheritVisibility.
-- Id wezla ranku = "<skillId>#<rank>" (klient parsuje -> skillId do SkillPurchase).
local Config = script.Parent
local SkillConfig = require(Config:WaitForChild("SkillConfig"))
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enums = require(Shared:WaitForChild("Enums"))

-- ikony walut (textureId decali z Creator Store): moneta / kostka
local CURRENCY_ICON = {
	[Enums.Currency.Coins] = "rbxassetid://5684864491",
	[Enums.Currency.Rolls] = "rbxassetid://92190657341460",
}

-- kierunki hex (jak w packu: X * sqrt(3)*halfW, Y * halfH)
local Side = {
	bottom = Vector2.new(0, 2),
	top = Vector2.new(0, -2),
	bottomLeft = Vector2.new(-1, 1),
	bottomRight = Vector2.new(1, 1),
	topLeft = Vector2.new(-1, -1),
	topRight = Vector2.new(1, -1),
}

-- 4 galezie w rogach root; kazdy skill startuje z innego kierunku, lancuch idzie wspolnym `chain`.
local LAYOUT = {
	{
		id = "RNG",
		label = "RNG",
		dir = Side.topLeft,
		chain = Side.topLeft,
		skills = {
			{ skill = "luck_1", start = Side.top },
			{ skill = "mut_1", start = Side.topLeft },
			{ skill = "variant_1", start = Side.bottomLeft },
		},
	},
	{
		id = "Eco",
		label = "Ekonomia",
		dir = Side.topRight,
		chain = Side.topRight,
		skills = {
			{ skill = "fast_1", start = Side.top },
			{ skill = "coin_1", start = Side.topRight },
			{ skill = "offline_1", start = Side.bottomRight },
		},
	},
	{
		id = "Combat",
		label = "Combat",
		dir = Side.bottomRight,
		chain = Side.bottomRight,
		skills = {
			{ skill = "dmg_1", start = Side.bottom },
			{ skill = "fire_1", start = Side.bottomRight },
			{ skill = "range_1", start = Side.topRight },
		},
	},
	{
		id = "Base",
		label = "Baza",
		dir = Side.bottomLeft,
		chain = Side.bottomLeft,
		skills = {
			{ skill = "cells_1", start = Side.bottom },
			{ skill = "core_1", start = Side.bottomLeft },
		},
	},
}

local function costFor(node, rank)
	return math.round(node.base * rank ^ SkillConfig.costExp)
end

local Nodes = {}

-- root wymagany przez pack
Nodes["root"] = { icon = "", text = "SKILLE" }

for _, branch in ipairs(LAYOUT) do
	local branchNodeId = "b:" .. branch.id
	Nodes[branchNodeId] = {
		parentNodeId = "root",
		direction = branch.dir,
		icon = "",
		text = branch.label,
		inheritVisibility = true, -- pokaz zawsze gdy root widoczny
	}

	for _, entry in ipairs(branch.skills) do
		local skillId = entry.skill
		local node = SkillConfig.nodes[skillId]
		if node then
			local currencyIcon = CURRENCY_ICON[node.currency] or ""
			for rank = 1, node.maxRank do
				local nodeId = skillId .. "#" .. rank
				Nodes[nodeId] = {
					parentNodeId = (rank == 1) and branchNodeId or (skillId .. "#" .. (rank - 1)),
					direction = (rank == 1) and entry.start or branch.chain,
					icon = "",
					text = tostring(rank),
					headerText = (rank == 1) and node.label or nil,
					price = { quantity = costFor(node, rank), currencyIcon = currencyIcon },
					inheritVisibility = false, -- odkrywaj rank po ranku (po zakupie poprzedniego)
				}
			end
		end
	end
end

return Nodes

--!nonstrict
-- Content/Config/SkillTreeLayout.luau — buduje liste wezlow dla packa NodeTree z SkillTreeData (95 wezlow).
-- Id wezla = "<origId>#1" (poza rootem) -> SkillTreeController podpina kupno (parseNodeId wymaga "#");
--   klik -> SkillPurchase(origId) -> SkillService (koszt+zapis). Kupno = markOwned -> pack odslania dzieci.
-- Widocznosc: root -> 3 bezposrednie dzieci widoczne od startu (inheritVisibility=true); reszta odslania sie
--   gdy rodzic "owned" (kupiony). 0/0 = wezel informacyjny (bez ceny, niekupowalny -> SkillService NoSuchNode).
-- Ceny pack sam skraca do K/M. Nie ruszamy wygladu packa.
local Config = script.Parent
local SkillTreeData = require(Config:WaitForChild("SkillTreeData"))

local COIN = "rbxassetid://5684864491"
local DICE = "rbxassetid://92190657341460"
local CLOVER = "rbxassetid://123550318368193"

local DIR = {
	Gora = Vector2.new(0, -2),
	Dol = Vector2.new(0, 2),
	GoraLewo = Vector2.new(-1, -1),
	GoraPrawo = Vector2.new(1, -1),
	DolLewo = Vector2.new(-1, 1),
	DolPrawo = Vector2.new(1, 1),
}

local function nid(id: string): string
	return (id == "root") and "root" or (id .. "#1")
end

-- ikona wg tematu (koniczyna dla luck/szczescia/koniczyn, kostka dla rolek, inaczej moneta)
local function iconFor(n)
	local l = string.lower(n.label or "")
	if string.find(l, "konicz") or string.find(l, "szczesc") then
		return CLOVER
	end
	if string.find(l, "rol") or (n.roll or 0) > 0 then
		return DICE
	end
	return COIN
end

local Nodes = {}
for _, n in ipairs(SkillTreeData) do
	if n.id == "root" then
		Nodes.root = { icon = "", text = "DRZEWO UMIEJETNOSCI" }
	else
		local price = nil
		if (n.coin or 0) > 0 then
			price = { quantity = n.coin, currencyIcon = COIN }
		elseif (n.roll or 0) > 0 then
			price = { quantity = n.roll, currencyIcon = DICE }
		end
		Nodes[nid(n.id)] = {
			parentNodeId = nid(n.parent or "root"),
			direction = DIR[n.dir] or DIR.Dol,
			icon = iconFor(n),
			text = "",
			headerText = n.label,
			price = price, -- nil dla 0/0 (informacyjne)
			-- widocznosc liczy zmodyfikowany canShowNode packa: root(owned) -> 3 dzieci REALNE, ich dzieci jako "?"
			inheritVisibility = false, -- tylko dzieci roota widoczne od startu
		}
	end
end

return Nodes

--!nonstrict
-- Content/Config/SkillTreeLayout.luau — buduje liste wezlow dla packa NodeTree z SkillTreeData (95 wezlow).
-- Id wezla = "<origId>#1" (poza rootem) -> SkillTreeController podpina kupno (parseNodeId wymaga "#");
--   klik -> SkillPurchase(origId) -> SkillService (koszt+zapis). Kupno = markOwned -> pack odslania dzieci.
-- Widocznosc: root -> 3 bezposrednie dzieci widoczne od startu (inheritVisibility=true); reszta odslania sie
--   gdy rodzic "owned" (kupiony). 0/0 = wezel informacyjny (bez ceny, niekupowalny -> SkillService NoSuchNode).
-- Ceny pack sam skraca do K/M. Nie ruszamy wygladu packa.
local Config = script.Parent
local SkillTreeData = require(Config:WaitForChild("SkillTreeData"))
local SkillCosts = require(Config:WaitForChild("SkillCosts")) -- nadpisania cen (plik dla Olo) — spojne z SkillConfig

local COIN = "rbxassetid://5684864491"
local DICE = "rbxassetid://92190657341460"
local CLOVER = "rbxassetid://123550318368193"
-- grafiki hexow ze wzorca Upgrade_Skill_Tree.rbxl (backgroundIcon packa):
local HEX_SECTION = "rbxassetid://128421674643187" -- wejscie do sekcji / "Back" (mechanika showRootId)
local HEX_PURPLE = "rbxassetid://84116313048597" -- fioletowy: finaly galezi / specjalne
local FLAG_ICON = "rbxassetid://11224275984" -- szachownica-meta na finalach galezi (Texture z decala 11224275993, jak we wzorcu)

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

-- ikona wg tematu (koniczyna dla clover/luck, kostka dla rolek, inaczej moneta)
local function iconFor(n)
	local l = string.lower(n.label or "")
	if string.find(l, "clover") or string.find(l, "luck") then
		return CLOVER
	end
	if string.find(l, "roll") or (n.roll or 0) > 0 then
		return DICE
	end
	return COIN
end

local Nodes = {}
for _, n in ipairs(SkillTreeData) do
	if n.id == "root" then
		Nodes.root = { icon = "", text = "SKILL" .. string.char(10) .. "TREE" }
	elseif n.parent == nil then
		-- ROOT SEKCJI (parent=nil, id~=root): hex "Back" — widoczny tylko gdy sekcja aktywna
		-- (canShowNode packa: parentless widoczny wylacznie jako currentRootNodeId). Klik = showRootId wraca.
		Nodes[n.id] = {
			icon = "",
			text = n.label or "Back",
			showRootId = n.showRoot or "root",
			backgroundIcon = HEX_SECTION,
			desc = n.desc,
		}
	else
		-- cena: SkillCosts (Olo) nadpisuje SkillTreeData — TA SAMA logika co SkillConfig (spojnosc kupno<->wyswietlanie).
		local override = SkillCosts[n.id]
		local coin = (override and override.coin) or n.coin or 0
		local roll = (override and override.roll) or n.roll or 0
		local price = nil
		if coin > 0 then
			price = { quantity = coin, currencyIcon = COIN }
		elseif roll > 0 then
			price = { quantity = roll, currencyIcon = DICE }
		end
		-- rodzic: root sekcji laczymy po SUROWYM id (proRoot/baseRoot nie maja "#1")
		local parentRaw = n.parent or "root"
		local parentIsSectionRoot = false
		for _, row in ipairs(SkillTreeData) do
			if row.id == parentRaw then parentIsSectionRoot = (row.parent == nil and row.id ~= "root") break end
		end
		local isEntry = n.showRoot ~= nil -- hex-wejscie do sekcji
		Nodes[nid(n.id)] = {
			parentNodeId = parentIsSectionRoot and parentRaw or nid(parentRaw),
			direction = DIR[n.dir] or DIR.Dol,
			-- ikona: wejscie sekcji = brak (sam zloty/fiolet hex + "Open"); final = szachownica; reszta = temat
			icon = (isEntry and "") or (n.bg == "purple" and FLAG_ICON) or iconFor(n),
			text = isEntry and "Open" or "", -- wejscie: duzy napis "Open" jak we wzorcu
			headerText = isEntry and "NEW!" or n.label, -- wejscie: banner "NEW!"; zwykly: nazwa skilla (tooltip title)
			desc = n.desc, -- opis do podgladu (tooltip) — czyta go zmodyfikowany pack
			price = price, -- nil dla 0/0 (informacyjne)
			-- MECHANIKA SEKCJI (wzorzec): showRoot => klik przelacza widok na inne drzewo (pack showRootId)
			showRootId = n.showRoot,
			-- KOLORY hexow (wzorzec): wejscie sekcji = grafika sekcyjna; bg="purple" = fioletowy final
			backgroundIcon = (n.showRoot and HEX_SECTION) or (n.bg == "purple" and HEX_PURPLE) or nil,
			-- czyste odkrywanie packa: dziecko widoczne dopiero gdy rodzic KUPIONY (bez "?")
			inheritVisibility = false,
		}
	end
end

return Nodes

--!nonstrict
-- ReplicatedStorage/Content/Config/SoldierAnimConfig.luau
-- Animacje R6 zolnierzy PER BRON (Olo, 2026-09). Kazda bron ma wlasny Idle/Walk/Shot (trzymanie w rekach).
-- Zrodlo prawdy dla OBU stron: wrogowie fal (EnemyRenderController) i jednostki gracza (UnitCombatAnimator).
-- Kluczem jest NAZWA MODELU (Assets.Units): wrog zna ja wprost, jednostka gracza przez GameConfig.Units[unitId].model.
-- Model bez mapowania (pojazdy/wieze/nowe) -> default (stary generyczny zestaw). .For(modelName) nigdy nie zwraca nil.
local A = "rbxassetid://"

local weapons = {
	Pistol       = { idle = A .. "78367236188108",  walk = A .. "118863051254383", shot = A .. "133144170323832" },
	Rifle        = { idle = A .. "82709567755322",  walk = A .. "115913509736872", shot = A .. "104599768362446" },
	Sniper       = { idle = A .. "122600974152046", walk = A .. "104524013157520", shot = A .. "79088660275389" },
	RPG          = { idle = A .. "123394185965726", walk = A .. "122469232138279", shot = A .. "122238986776393" },
	Minigun      = { idle = A .. "100918836896042", walk = A .. "80962643282612",  shot = A .. "71130048222736" },
	Flamethrower = { idle = A .. "127628538938523", walk = A .. "72950520232549",  shot = A .. "103412499516948" },
}

-- zolnierz (nazwa modelu w Assets.Units) -> bron
local byModel = {
	["Noob Soldier"] = "Pistol",
	Soldier = "Rifle",
	SWAT = "Rifle",
	Sniper = "Sniper",
	["Rocket Soldier"] = "RPG",
	["Tank Soldier"] = "Minigun",
	Flamethrower = "Flamethrower",
	FlameThrower = "Flamethrower",
}

-- fallback (stare generyczne R6 idle/walk/shot) dla modeli bez mapowania
local default = { idle = A .. "114633582166730", walk = A .. "123805470740320", shot = A .. "109739383922402" }

local M = { weapons = weapons, byModel = byModel, default = default }

-- For(modelName) -> {idle, walk, shot}. Nigdy nil.
function M.For(modelName)
	return (modelName and weapons[byModel[modelName]]) or default
end

return M

--!strict
-- Content/Config/UnitIcons.luau — mapa nazwa-modelu (dziecko Assets.Units) -> Model assetId.
-- Ikony kart Indeksu: karta uzywa rbxthumb://type=Asset&id=<id> = OFICJALNY render miniatury modelu
-- (przezroczyste tlo, ladne swiatlo, statyczny kadr 3/4 — zamiast zywego ViewportFrame = lzej na perf).
-- Zrodla wgrane jako assety typu Model do grupy WAR RNG 664399796 (Open Cloud, klucz ROBLOX_OC_KEY_RNG),
-- moderacja Approved 2026-09-09. Miniatury generuje Roblox (rbxthumb sam czeka na render).
-- Regeneracja: eksport modelu -> upload_asset Model (groupId 664399796) -> podmien id ponizej.
return {
	["Tank"] = 76915831973841,
	["Noob Soldier"] = 107861553079699,
	["Soldier"] = 85012757575183,
	["Sniper"] = 83259322457190,
	["SWAT"] = 88011016463635,
	["Rocket Soldier"] = 73750364322533,
	["Flamethrower"] = 70935935933288,
	["Tank Soldier"] = 100050318644573,
	["Jeep"] = 137040729853123,
	["Helicopter"] = 117671265869386,
	["Jet"] = 124718155712979,
	["MG Nest A"] = 123483892624846,
	["MG Nest B"] = 101363860706515,
	["Minigun Turret"] = 116649569783016,
	["Rocket Launcher x2"] = 102954362760566,
	["Rocket Launcher x4"] = 133017778448681,
	["Rocket Launcher x6"] = 131930991588113,
	["Dual Minigun"] = 119875491119866,
	["Drone Base"] = 125577284512533,
}

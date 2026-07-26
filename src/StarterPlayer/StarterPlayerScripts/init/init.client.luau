--!nonstrict
-- Client bootstrap. Startuje kontrolery klienta. Kolejne (RollReveal/Build/WaveHud)
-- dochodza w warstwie po bramce; teraz EnemyRenderController (§9).
local Players = game:GetService("Players")

local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local Controllers = playerScripts:WaitForChild("Controllers")

-- FIX P0: KAZDY kontroler startuje w osobnym pcall. Kiedys jeden rzucony blad zabijal wszystkie kolejne
-- (init-cascade -> martwe HUD/przyciski). Teraz porazka = warn z nazwa+trescia, LECIMY DALEJ; na koncu
-- zbiorczy warn z lista. Kolejnosc ZACHOWANA (czesc kontrolerow zaklada, ze wczesniejsze wystartowaly).
-- Uwagi z historii pliku (zachowane): stary HudController wylaczony (duplikat guzikow -> HudBindController);
-- LevelPanelController wycofany (lewelowanie w INDEKSie); SettingsPanel = przelaczniki wydajnosci (⚙).
local ORDER = {
	"EnemyRenderController",
	"SkillTreeController",
	"IndexController",
	"OfflineController",
	"RollRevealController",
	"BossController",
	"UnitCombatAnimator",
	"UnitHealthController",
	"CoreHealthController",
	"WeaponCameraGate",
	"BuildController",
	"UnitTooltipController", -- dymek podgladu jednostki (ikona + DMG/s + HP)
	"HudBindController", -- HUD ziomka (StarterGui.SideButtons)
	"DevController",
	"SettingsPanelController",
	"WaveFxController", -- konfetti + baner po wyczyszczeniu fali
	"StoreController",
	"UIHoverBinder", -- sprezyste hover/press na przyciskach
	"AttentionBob", -- kolysanie Roll + Sklep
}

local failed = {}
for _, name in ipairs(ORDER) do
	local ok, err = pcall(function()
		local ctrl = require(Controllers:WaitForChild(name))
		ctrl.start()
	end)
	if not ok then
		failed[#failed + 1] = name
		warn(("[init.client] kontroler %s padl przy starcie: %s"):format(name, tostring(err)))
	end
end
if #failed > 0 then
	warn(("[init.client] %d/%d kontrolerow NIE wystartowalo: %s"):format(#failed, #ORDER, table.concat(failed, ", ")))
end

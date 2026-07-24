--!nonstrict
-- Client bootstrap. Startuje kontrolery klienta. Kolejne (RollReveal/Build/WaveHud)
-- dochodza w warstwie po bramce; teraz EnemyRenderController (§9).
local Players = game:GetService("Players")

local playerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
local Controllers = playerScripts:WaitForChild("Controllers")

local EnemyRenderController = require(Controllers:WaitForChild("EnemyRenderController"))
EnemyRenderController.start()

local SkillTreeController = require(Controllers:WaitForChild("SkillTreeController"))
SkillTreeController.start()

local IndexController = require(Controllers:WaitForChild("IndexController"))
IndexController.start()

local OfflineController = require(Controllers:WaitForChild("OfflineController"))
OfflineController.start()

local RollRevealController = require(Controllers:WaitForChild("RollRevealController"))
RollRevealController.start()

local BossController = require(Controllers:WaitForChild("BossController"))
BossController.start()

local UnitCombatAnimator = require(Controllers:WaitForChild("UnitCombatAnimator"))
UnitCombatAnimator.start()

local UnitHealthController = require(Controllers:WaitForChild("UnitHealthController"))
UnitHealthController.start()

local CoreHealthController = require(Controllers:WaitForChild("CoreHealthController"))
CoreHealthController.start()

local WeaponCameraGate = require(Controllers:WaitForChild("WeaponCameraGate"))
WeaponCameraGate.start()

local BuildController = require(Controllers:WaitForChild("BuildController"))
BuildController.start()

-- Dymek podgladu jednostki (ikona + DMG/s + HP) przy najechaniu na karte panelu lub na postawiona jednostke
local UnitTooltipController = require(Controllers:WaitForChild("UnitTooltipController"))
UnitTooltipController.start()

-- HUD ziomka (StarterGui.SideButtons) wpięty przez HudBindController; stary HudController wyłączony
-- (tworzył własne guziki/pille = duplikat). Plik HudController.luau zostaje na dysku (revert).
local HudBindController = require(Controllers:WaitForChild("HudBindController"))
HudBindController.start()

local DevController = require(Controllers:WaitForChild("DevController"))
DevController.start()

-- Panel ustawien wydajnosci (przycisk ⚙): przelaczniki animacji/FX/HP-barek/cudzych plotow
local SettingsPanelController = require(Controllers:WaitForChild("SettingsPanelController"))
SettingsPanelController.start()

-- Konfetti + baner po wyczyszczeniu fali
local WaveFxController = require(Controllers:WaitForChild("WaveFxController"))
WaveFxController.start()

-- Sklep (chowa HUD, tresc doda ziomek)
local StoreController = require(Controllers:WaitForChild("StoreController"))
StoreController.start()

-- Sprezyste hover/press na wszystkich przyciskach (port z obby)
local UIHoverBinder = require(Controllers:WaitForChild("UIHoverBinder"))
UIHoverBinder.start()

-- Kolysanie Roll + Sklep (przyciaga uwage)
local AttentionBob = require(Controllers:WaitForChild("AttentionBob"))
AttentionBob.start()

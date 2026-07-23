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

local BuildController = require(Controllers:WaitForChild("BuildController"))
BuildController.start()

-- HUD ziomka (StarterGui.SideButtons) wpięty przez HudBindController; stary HudController wyłączony
-- (tworzył własne guziki/pille = duplikat). Plik HudController.luau zostaje na dysku (revert).
local HudBindController = require(Controllers:WaitForChild("HudBindController"))
HudBindController.start()

local DevController = require(Controllers:WaitForChild("DevController"))
DevController.start()

--!nonstrict
-- ServerScriptService/Services/CoreService.luau  (§3.10)
-- HP rdzenia per gracz. maxHp = Stats.coreHP. Subskrybuje Combat.EnemyReachedCore -> ApplyDamage.
-- deps: StatProfileService (coreHP), + PlotService (plotId do Net.CoreHP), CombatService (subskrypcja).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Signal = require(Framework:WaitForChild("Signal"))
local ServiceRegistry = require(Framework:WaitForChild("ServiceRegistry"))
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local CoreService = {}

local _stat, _plot = nil, nil
local _coreHP = nil -- remote (guard nil w tescie)
local _hp: { [any]: number } = {} -- player -> aktualne hp

local function maxHpOf(player): number
	return (_stat and _stat.Get(player).coreHP) or GameConfig.StatBase.coreHP
end

function CoreService.GetHP(player)
	local maxHp = maxHpOf(player)
	local hp = _hp[player]
	if hp == nil then
		hp = maxHp
		_hp[player] = hp
	end
	return hp, maxHp
end

local function pushHP(player, hp, maxHp)
	if _coreHP then
		local plotId = _plot and _plot.GetPlot(player) and _plot.GetPlot(player).plotId or 0
		_coreHP:FireClient(player, { plotId = plotId, hp = hp, maxHp = maxHp })
	end
end

function CoreService.ApplyDamage(player, amount: number)
	local hp, maxHp = CoreService.GetHP(player)
	hp = math.max(0, hp - amount)
	_hp[player] = hp
	pushHP(player, hp, maxHp)
	CoreService.CoreDamaged:Fire(player, hp, maxHp)
	if hp <= 0 then
		CoreService.CoreDestroyed:Fire(player)
	end
end

function CoreService.ResetHP(player)
	local maxHp = maxHpOf(player)
	_hp[player] = maxHp
	pushHP(player, maxHp, maxHp)
	CoreService.CoreDamaged:Fire(player, maxHp, maxHp)
end

function CoreService.Init()
	CoreService.CoreDamaged = Signal.new() -- (player, hp, maxHp)
	CoreService.CoreDestroyed = Signal.new() -- (player)
end

function CoreService.Start()
	_stat = ServiceRegistry.get("StatProfileService")
	_plot = ServiceRegistry.get("PlotService")
	_coreHP = Net.get("CoreHP")

	-- wrog przy rdzeniu -> obrazenia wg coreDmg typu (WaveConfig)
	local combat = ServiceRegistry.get("CombatService")
	combat.EnemyReachedCore:Connect(function(player, enemyTypeId)
		local et = GameConfig.Wave.enemyTypes[enemyTypeId]
		local dmg = et and et.coreDmg or 0
		CoreService.ApplyDamage(player, dmg)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_hp[player] = nil
	end)
end

-- Hooki TYLKO do testow.
function CoreService._InjectForTest(deps)
	_stat, _plot = deps.stat, deps.plot
end
function CoreService._ResetForTest(player)
	_hp[player] = nil
end

return CoreService

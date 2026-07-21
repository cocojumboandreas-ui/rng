--!nonstrict
-- StarterPlayerScripts/Controllers/UnitHealthController.luau  (KLIENT — faza 5)
-- Pasek HP nad jednostka gdy oberwie (Net.UnitHp, throttled przez serwer) + poof przy smierci
-- (Net.UnitKilled). Serwer jest autorytatywny: liczy HP i decyduje o smierci; tu tylko feedback.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local UnitHealthController = {}

local RED = Color3.fromRGB(220, 60, 60)
local GREEN = Color3.fromRGB(80, 220, 90)
local _bars = {} -- placementId -> { gui, fill }

local function findModel(pid)
	local units = Workspace:FindFirstChild("WR_Units")
	if not units then return nil end
	for _, m in ipairs(units:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("PlacementId") == pid then
			return m
		end
	end
	return nil
end

local function ensureBar(pid)
	local rec = _bars[pid]
	if rec and rec.gui.Parent then return rec end
	local model = findModel(pid)
	if not model or not model.PrimaryPart then return nil end
	local gui = Instance.new("BillboardGui")
	gui.Name = "WR_HpBar"
	gui.Size = UDim2.fromOffset(64, 9)
	gui.StudsOffsetWorldSpace = Vector3.new(0, model:GetExtentsSize().Y * 0.5 + 1.4, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = model.PrimaryPart
	gui.Parent = model
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1); back.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	back.BorderSizePixel = 0; back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1); fill.BackgroundColor3 = GREEN; fill.BorderSizePixel = 0; fill.Parent = back
	rec = { gui = gui, fill = fill }
	_bars[pid] = rec
	return rec
end

local function poof(pos)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball; p.Size = Vector3.new(2, 2, 2); p.Position = pos
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon; p.Color = Color3.fromRGB(120, 120, 130); p.Transparency = 0.2
	p.Parent = Workspace
	Debris:AddItem(p, 0.5)
	task.spawn(function()
		local t0 = os.clock()
		while p.Parent do
			local a = (os.clock() - t0) / 0.4
			if a >= 1 then break end
			p.Size = Vector3.one * (2 + a * 4)
			p.Transparency = 0.2 + a * 0.8
			RunService.Heartbeat:Wait()
		end
	end)
end

function UnitHealthController.start()
	Net.get("UnitHp").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" or not p.placementId then return end
		local rec = ensureBar(p.placementId)
		if not rec then return end
		local pct = math.clamp(p.hpPct or 1, 0, 1)
		rec.fill.Size = UDim2.fromScale(pct, 1)
		rec.fill.BackgroundColor3 = RED:Lerp(GREEN, pct)
	end)

	Net.get("UnitKilled").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" or not p.placementId then return end
		local model = findModel(p.placementId)
		if model then poof(model:GetPivot().Position) end
		local rec = _bars[p.placementId]
		if rec then
			if rec.gui then rec.gui:Destroy() end
			_bars[p.placementId] = nil
		end
	end)
end

return UnitHealthController

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
local PerfSettings = require(script.Parent:WaitForChild("PerfSettings")) -- panel wydajnosci (Damage Counter)

local UnitHealthController = {}

local RED = Color3.fromRGB(220, 60, 60)
local GREEN = Color3.fromRGB(80, 220, 90)
local _bars = {} -- placementId -> { gui, fill, label }

-- skrot liczby HP: 238 / 2.4K / 1.5M (jak na pasku)
local function shortNum(n)
	n = math.max(0, math.floor(n + 0.5))
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1000 then return string.format("%.1fK", n / 1000) end
	return tostring(n)
end

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
	gui.Size = UDim2.fromOffset(70, 20)
	gui.StudsOffsetWorldSpace = Vector3.new(0, model:GetExtentsSize().Y * 0.5 + 1.6, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = model.PrimaryPart
	gui.Parent = model
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 9); back.Position = UDim2.new(0, 0, 1, -9)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 30); back.BorderSizePixel = 0; back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1); fill.BackgroundColor3 = GREEN; fill.BorderSizePixel = 0; fill.Parent = back
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 12); label.Position = UDim2.new(0, 0, 0, -1)
	label.BackgroundTransparency = 1; label.Font = Enum.Font.GothamBold; label.TextScaled = false
	label.TextSize = 12; label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3; label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Text = ""; label.Parent = gui
	rec = { gui = gui, fill = fill, label = label }
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
	-- Damage Counter OFF -> ukryj/nie pokazuj HP jednostek (live-toggle istniejacych barek)
	PerfSettings.onChanged(function(key)
		if key ~= "damageCounter" then return end
		local on = PerfSettings.get("damageCounter")
		for _, rec in pairs(_bars) do
			if rec.gui then rec.gui.Enabled = on end
		end
	end)

	Net.get("UnitHp").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" or not p.placementId then return end
		local rec = ensureBar(p.placementId)
		if not rec then return end
		if not PerfSettings.get("damageCounter") then
			if rec.gui then rec.gui.Enabled = false end
			return -- Damage Counter OFF -> pomijamy pokazywanie/aktualizacje
		end
		if rec.gui and not rec.gui.Enabled then rec.gui.Enabled = true end
		local pct = math.clamp(p.hpPct or 1, 0, 1)
		rec.fill.Size = UDim2.fromScale(pct, 1)
		rec.fill.BackgroundColor3 = RED:Lerp(GREEN, pct)
		local maxHp = p.maxHp or rec.maxHp
		if maxHp then
			rec.maxHp = maxHp
			local cur = p.hp or (maxHp * pct)
			rec.label.Text = shortNum(cur) .. "/" .. shortNum(maxHp)
		end
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

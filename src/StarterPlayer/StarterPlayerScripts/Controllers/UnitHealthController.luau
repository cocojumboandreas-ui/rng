--!nonstrict
-- StarterPlayerScripts/Controllers/UnitHealthController.luau  (KLIENT — faza 5)
-- Pasek HP nad jednostka gdy oberwie (Net.UnitHp, throttled przez serwer) + poof przy smierci
-- (Net.UnitKilled). Serwer jest autorytatywny: liczy HP i decyduje o smierci; tu tylko feedback.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
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

-- SMIERC jednostki: KLON modelu PLYNNIE (TweenService) pada NA PLECY, lezy 2s, potem znika (oryginal usuwa serwer).
local function fallCorpse(model)
	local clone = model:Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
		elseif d:IsA("BillboardGui") or d:IsA("Highlight") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy() -- usun paski HP / otoczki / skrypty z klonu-trupa
		end
	end
	if not clone.PrimaryPart then clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart") end
	if not clone.PrimaryPart then clone:Destroy(); return end
	clone.Parent = Workspace
	local start = model:GetPivot()
	local look = start.LookVector
	local halfH = model:GetExtentsSize().Y * 0.5
	local groundPos = Vector3.new(start.Position.X, start.Position.Y - halfH + 0.3, start.Position.Z)
	local fallen = CFrame.lookAlong(groundPos, look) * CFrame.Angles(math.rad(90), 0, 0) -- na plecy
	task.spawn(function()
		local cv = Instance.new("CFrameValue")
		cv.Value = start
		local conn = cv:GetPropertyChangedSignal("Value"):Connect(function()
			if clone.Parent then clone:PivotTo(cv.Value) end
		end)
		local tw = TweenService:Create(cv, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = fallen })
		tw:Play()
		tw.Completed:Wait()
		conn:Disconnect(); cv:Destroy()
		task.wait(2) -- lezy 2s od przewrocenia
		clone:Destroy()
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
		local pct = math.clamp(p.hpPct or 1, 0, 1)
		-- pasek WIDOCZNY tylko gdy jednostka oberwala (pct<1). Pelne HP -> ukryj (koniec "zupy" pasków).
		if rec.gui then rec.gui.Enabled = pct < 0.999 end
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
		if model then fallCorpse(model) end -- pada na plecy, po 2s znika (klon; oryginal usuwa serwer)
		local rec = _bars[p.placementId]
		if rec then
			if rec.gui then rec.gui:Destroy() end
			_bars[p.placementId] = nil
		end
	end)
end

return UnitHealthController

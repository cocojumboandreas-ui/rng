--!nonstrict
-- StarterPlayerScripts/Controllers/CoreHealthController.luau  (KLIENT)
-- Pasek HP RDZENIA (serduszko bazy) nad WR_CoreAnchor wlasnego plotu. Zrodlo: Net.CoreHP (serwer autorytatywny).
-- Wrogowie ostrzeliwuja rdzen z dystansu (nie wchodza) — CombatService drenuje HP, tu tylko wizualizacja.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local CoreHealthController = {}
local LP = Players.LocalPlayer

local RED = Color3.fromRGB(230, 55, 55)
local GREEN = Color3.fromRGB(90, 225, 95)

local _gui, _fill, _label = nil, nil, nil
local _lastHp, _lastMax = nil, nil

local function shortNum(n)
	n = math.max(0, math.floor(n + 0.5))
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1000 then return string.format("%.1fK", n / 1000) end
	return tostring(n)
end

-- znajdz rdzen wlasnego plotu (WR_CoreAnchor z pasujacym PlotId)
local function findCore()
	local myPlot = LP:GetAttribute("PlotId")
	for _, c in ipairs(CollectionService:GetTagged("WR_CoreAnchor")) do
		if c:IsA("BasePart") and c:GetAttribute("PlotId") == myPlot then return c end
	end
	return nil
end

local function ensureBar()
	if _gui and _gui.Parent and _gui.Adornee and _gui.Adornee.Parent then return true end
	local core = findCore()
	if not core then return false end
	if _gui then _gui:Destroy() end
	local gui = Instance.new("BillboardGui")
	gui.Name = "WR_CoreHpBar"
	gui.Size = UDim2.fromOffset(140, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, core.Size.Y * 0.5 + 3, 0)
	gui.AlwaysOnTop = true; gui.Adornee = core; gui.Parent = core
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 14); title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold; title.TextSize = 13; title.TextColor3 = Color3.fromRGB(255, 120, 130)
	title.TextStrokeTransparency = 0.3; title.Text = "❤ RDZEŃ"; title.Parent = gui
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 11); back.Position = UDim2.new(0, 0, 1, -11)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 26); back.BorderSizePixel = 0; back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1); fill.BackgroundColor3 = GREEN; fill.BorderSizePixel = 0; fill.Parent = back
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 12); label.Position = UDim2.new(0, 0, 1, -12)
	label.BackgroundTransparency = 1; label.Font = Enum.Font.GothamBold; label.TextSize = 12
	label.TextColor3 = Color3.fromRGB(255, 255, 255); label.TextStrokeTransparency = 0.3; label.Text = ""; label.Parent = gui
	_gui, _fill, _label = gui, fill, label
	return true
end

local function apply(hp, maxHp)
	if not ensureBar() then return end
	maxHp = math.max(1, maxHp or 1)
	local pct = math.clamp((hp or maxHp) / maxHp, 0, 1)
	_fill.Size = UDim2.fromScale(pct, 1)
	_fill.BackgroundColor3 = RED:Lerp(GREEN, pct)
	_label.Text = shortNum(hp or maxHp) .. "/" .. shortNum(maxHp)
end

function CoreHealthController.start()
	Net.get("CoreHP").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then return end
		if p.plotId ~= nil and p.plotId ~= LP:GetAttribute("PlotId") then return end -- tylko wlasny rdzen
		_lastHp, _lastMax = p.hp, p.maxHp
		apply(p.hp, p.maxHp)
	end)
	-- rdzen/plot moga pojawic sie po dolaczeniu — retry az zbudujemy pasek z ostatnim znanym HP
	task.spawn(function()
		for _ = 1, 60 do
			if ensureBar() then
				if _lastMax then apply(_lastHp, _lastMax) end
				break
			end
			task.wait(0.3)
		end
	end)
	CollectionService:GetInstanceAddedSignal("WR_CoreAnchor"):Connect(function()
		if ensureBar() and _lastMax then apply(_lastHp, _lastMax) end
	end)
end

return CoreHealthController

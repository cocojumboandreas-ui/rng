--!nonstrict
-- StarterPlayerScripts/Controllers/CoreHealthController.luau  (KLIENT)
-- Pasek HP RDZENIA (serduszko bazy) nad WR_CoreAnchor wlasnego plotu. Zrodlo: Net.CoreHP (serwer autorytatywny).
-- Wrogowie ostrzeliwuja rdzen z dystansu (nie wchodza) — CombatService drenuje HP, tu tylko wizualizacja.
-- KOSMETYKA E: gdy HP rdzenia spada nisko (<=DANGER) — ekranowa CZERWONA WINIETA pulsuje (im nizej HP, tym mocniej).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("Framework"):WaitForChild("Net"))

local CoreHealthController = {}
local LP = Players.LocalPlayer

local RED = Color3.fromRGB(230, 55, 55)
local GREEN = Color3.fromRGB(90, 225, 95)
local DANGER = 0.30 -- ponizej tego % HP rdzenia zaczyna sie ekranowa winieta zagrozenia

local _gui, _fill, _label = nil, nil, nil
local _lastHp, _lastMax = nil, nil
local _pct = 1 -- ostatni % HP rdzenia (dla winiety)

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
	title.TextStrokeTransparency = 0.3; title.Text = "❤ CORE"; title.Parent = gui
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
	maxHp = math.max(1, maxHp or 1)
	local pct = math.clamp((hp or maxHp) / maxHp, 0, 1)
	_pct = pct -- winieta zagrozenia dziala niezaleznie od paska nad rdzeniem
	if not ensureBar() then return end
	_fill.Size = UDim2.fromScale(pct, 1)
	_fill.BackgroundColor3 = RED:Lerp(GREEN, pct)
	_label.Text = shortNum(hp or maxHp) .. "/" .. shortNum(maxHp)
end

-- WINIETA: 4 pasy-gradienty (gora/dol/lewo/prawo), czerwone przy krawedzi, znikaja do srodka.
-- Zwraca funkcje setIntensity(a) — a=0 (niewidoczna) .. 1 (pelna czerwona krawedz).
local function buildVignette(parent)
	local strips = {}
	local function strip(anchor, pos, size, rot)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.fromRGB(210, 30, 30)
		f.BorderSizePixel = 0
		f.AnchorPoint = anchor
		f.Position = pos
		f.Size = size
		f.BackgroundTransparency = 1
		local g = Instance.new("UIGradient")
		g.Rotation = rot
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), -- krawedz = pelna
			NumberSequenceKeypoint.new(1, 1), -- do srodka = znika
		})
		g.Parent = f
		f.Parent = parent
		strips[#strips + 1] = f
	end
	local T = 0.32 -- grubosc pasa (frac ekranu)
	strip(Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0), UDim2.new(1, 0, T, 0), 90) -- gora
	strip(Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.new(1, 0, T, 0), 270) -- dol
	strip(Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.new(T, 0, 1, 0), 0) -- lewo
	strip(Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.new(T, 0, 1, 0), 180) -- prawo
	return function(a)
		local bgt = 1 - math.clamp(a, 0, 1)
		for _, f in ipairs(strips) do
			f.BackgroundTransparency = bgt
		end
	end
end

function CoreHealthController.start()
	-- ekranowa winieta zagrozenia (osobny ScreenGui, pod HUD; nie lapie klikow)
	local vgui = Instance.new("ScreenGui")
	vgui.Name = "WR_CoreDanger"; vgui.ResetOnSpawn = false; vgui.IgnoreGuiInset = true
	vgui.DisplayOrder = 90 -- pod panelami/rewealem, nad swiatem
	vgui.Parent = LP:WaitForChild("PlayerGui")
	local setVignette = buildVignette(vgui)

	Net.get("CoreHP").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then return end
		if p.plotId ~= nil and p.plotId ~= LP:GetAttribute("PlotId") then return end -- tylko wlasny rdzen
		_lastHp, _lastMax = p.hp, p.maxHp
		apply(p.hp, p.maxHp)
	end)

	-- puls winiety: intensywnosc = jak GLEBOKO ponizej progu (0 przy DANGER, 1 przy 0 HP) * oddech sin.
	RunService.Heartbeat:Connect(function()
		local danger01 = math.clamp((DANGER - _pct) / DANGER, 0, 1) -- 0..1
		if danger01 <= 0 then
			setVignette(0)
			return
		end
		local breath = 0.62 + 0.38 * (0.5 + 0.5 * math.sin(os.clock() * 6)) -- 0.24..1 oddech
		setVignette(danger01 * 0.55 * breath) -- cap ~0.55 zeby nie zalewac ekranu
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

--!nonstrict
-- StarterPlayerScripts/Controllers/RollRevealController.luau  (post-bramka task 4 — KLIENT-ONLY)
-- Reveal rolki + kaskada mutacji. Sterowany Net.RollResult (serwer juz rzuca mutacje od Task 5).
-- Fazy (timingi z RevealConfig §4 per revealTier): dim -> build-up (deszcz koniczyn=luck) ->
--   [jesli mutation] kaskada x2->x4->x8 -> reveal jednostki na starburscie ("1 in N" + nazwa) -> settle.
-- Intensywnosc skaluje revealTier (DERYWOWANY z rarityN przez RarityConfig — payload go nie ma).
-- Object pooling elementow VFX (zero Instance.new spam per roll). v1 LEAN — poprawna STRUKTURA faz.
-- Trigger: tymczasowy przycisk ROLL (fires RollRequest). Docelowa "zajebista" animacja Andreasa = polish.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local RARITY_COLOR = {
	[1] = Color3.fromRGB(185, 185, 195), -- common
	[2] = Color3.fromRGB(90, 200, 120), -- uncommon
	[3] = Color3.fromRGB(90, 160, 255), -- rare
	[4] = Color3.fromRGB(195, 110, 255), -- epic
	[5] = Color3.fromRGB(255, 205, 80), -- legendary
}

local RollRevealController = {}

local _stage, _dim, _revealBox, _burst, _titleLbl, _nameLbl, _cascadeHolder
local _cloverPool = {}
local _queue = {}
local _playing = false

-- ── helpers ──
local function deriveTier(rarityN: number): number
	for _, t in ipairs(GameConfig.Rarity.tiers) do
		if rarityN <= t.maxN then
			return t.revealTier
		end
	end
	return 5
end

local function params(tier: number)
	local rc = GameConfig.Reveal.tiers
	if rc[tier] then
		return rc[tier]
	end
	for t = tier, 1, -1 do -- floor do najblizszego zdefiniowanego (2->1, 4->3)
		if rc[t] then
			return rc[t]
		end
	end
	return rc[1]
end

local function tween(obj, t, props, style)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- kaskada: mnozniki od x2 do mult
local function rungsFor(mult: number)
	local r = {}
	local m = 2
	while m <= mult do
		r[#r + 1] = "×" .. m
		m *= 2
	end
	return r
end

-- ── pooling koniczyn ──
local function acquireClover()
	local c = table.remove(_cloverPool)
	if not c then
		c = Instance.new("TextLabel")
		c.BackgroundTransparency = 1
		c.Font = Enum.Font.GothamBold
		c.Text = "🍀"
		c.TextScaled = true
		c.Size = UDim2.fromOffset(38, 38)
		c.ZIndex = 3
		c.Parent = _stage
	end
	c.Visible = true
	c.TextTransparency = 0
	return c
end
local function releaseClover(c)
	c.Visible = false
	table.insert(_cloverPool, c)
end

-- ── fazy ──
local function rainClovers(count: number, duration: number)
	for i = 1, count do
		task.spawn(function()
			local c = acquireClover()
			local x = math.random(5, 90) / 100
			c.Position = UDim2.new(x, 0, -0.1, 0)
			c.Rotation = math.random(-40, 40)
			local fall = duration * (0.6 + math.random() * 0.5)
			tween(c, fall, { Position = UDim2.new(x, 0, 1.1, 0), Rotation = c.Rotation + math.random(-90, 90) }, Enum.EasingStyle.Linear)
			task.wait(fall * 0.7)
			tween(c, fall * 0.3, { TextTransparency = 1 })
			task.wait(fall * 0.3)
			releaseClover(c)
		end)
		task.wait(duration / count * 0.5)
	end
end

local function playCascade(mult: number, color: Color3)
	local rungs = rungsFor(mult)
	for i, txt in ipairs(rungs) do
		local icon = _cascadeHolder:FindFirstChild("R" .. i)
		if not icon then
			icon = Instance.new("TextLabel")
			icon.Name = "R" .. i
			icon.BackgroundTransparency = 1
			icon.Font = Enum.Font.GothamBlack
			icon.TextSize = 44
			icon.Size = UDim2.fromOffset(90, 60)
			icon.Position = UDim2.new(0.5, (i - #rungs / 2 - 0.5) * 96 + 48, 0.5, 0)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.ZIndex = 6
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(255, 230, 120)
			stroke.Thickness = 2
			stroke.Parent = icon
			icon.Parent = _cascadeHolder
		end
		icon.Text = txt
		icon.TextColor3 = color
		icon.Visible = true
		icon.TextTransparency = 0
		icon.Size = UDim2.fromOffset(20, 14)
		tween(icon, 0.18, { Size = UDim2.fromOffset(96, 64) }, Enum.EasingStyle.Back)
		task.wait(0.26)
	end
	task.wait(0.15)
end

local function playReveal(result)
	local tier = deriveTier(result.rarityN)
	local p = params(tier)
	local color = RARITY_COLOR[tier] or RARITY_COLOR[1]
	local unit = GameConfig.Units[result.unitId]
	local name = (unit and unit.displayName) or result.unitId

	-- reset stage
	for _, c in ipairs(_cascadeHolder:GetChildren()) do
		if c:IsA("TextLabel") then c.Visible = false end
	end
	_revealBox.Visible = false

	-- 1) DIM
	_dim.Visible = true
	tween(_dim, 0.18, { BackgroundTransparency = 0.45 })
	task.wait(0.18)

	-- 2) BUILD-UP (deszcz koniczyn = luck) — gestosc skaluje tierem
	local cloverCount = tier >= 5 and 22 or (tier >= 3 and 14 or 6)
	task.spawn(rainClovers, cloverCount, p.buildupSec)
	task.wait(p.buildupSec)

	-- 3) KASKADA MUTACJI (tylko jesli mutation)
	if result.mutation and result.mutation.mult and p.cascade ~= false then
		playCascade(result.mutation.mult, color)
	end

	-- 4) REVEAL na starburscie
	_titleLbl.Text = "1 in " .. tostring(result.rarityN)
	_titleLbl.TextColor3 = color
	_nameLbl.Text = result.mutation and (name .. "  (×" .. result.mutation.mult .. ")") or name
	_burst.TextColor3 = color
	_revealBox.Visible = true
	_revealBox.Size = UDim2.fromScale(0.05, 0.05)
	_burst.Rotation = 0
	tween(_revealBox, 0.32, { Size = UDim2.fromScale(tier >= 5 and 0.72 or 0.5, tier >= 5 and 0.5 or 0.36) }, Enum.EasingStyle.Back)
	tween(_burst, p.holdSec + 0.4, { Rotation = tier >= 5 and 90 or 30 }, Enum.EasingStyle.Linear)
	task.wait(p.holdSec)

	-- 5) SETTLE
	tween(_revealBox, 0.25, { Size = UDim2.fromScale(0.05, 0.05) })
	tween(_dim, 0.3, { BackgroundTransparency = 1 })
	task.wait(0.3)
	_revealBox.Visible = false
	_dim.Visible = false
end

local function pump()
	if _playing then
		return
	end
	_playing = true
	task.spawn(function()
		while #_queue > 0 do
			local result = table.remove(_queue, 1)
			local ok, err = pcall(playReveal, result)
			if not ok then
				warn("[RollReveal] " .. tostring(err))
			end
		end
		_playing = false
	end)
end

function RollRevealController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_RollReveal"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	_dim = Instance.new("Frame")
	_dim.Size = UDim2.fromScale(1, 1); _dim.BackgroundColor3 = Color3.new(0, 0, 0)
	_dim.BackgroundTransparency = 1; _dim.BorderSizePixel = 0; _dim.ZIndex = 1
	_dim.Visible = false; _dim.Parent = gui

	_stage = Instance.new("Frame") -- warstwa VFX (koniczyny)
	_stage.Size = UDim2.fromScale(1, 1); _stage.BackgroundTransparency = 1
	_stage.ZIndex = 2; _stage.Parent = gui

	_cascadeHolder = Instance.new("Frame")
	_cascadeHolder.Size = UDim2.fromScale(1, 0.3); _cascadeHolder.Position = UDim2.fromScale(0, 0.28)
	_cascadeHolder.BackgroundTransparency = 1; _cascadeHolder.ZIndex = 5; _cascadeHolder.Parent = gui

	_revealBox = Instance.new("Frame")
	_revealBox.AnchorPoint = Vector2.new(0.5, 0.5); _revealBox.Position = UDim2.fromScale(0.5, 0.5)
	_revealBox.Size = UDim2.fromScale(0.5, 0.36); _revealBox.BackgroundTransparency = 1
	_revealBox.ZIndex = 8; _revealBox.Visible = false; _revealBox.Parent = gui

	_burst = Instance.new("TextLabel") -- starburst (emoji ✦, skalowany+obrot)
	_burst.Size = UDim2.fromScale(1, 1); _burst.AnchorPoint = Vector2.new(0.5, 0.5)
	_burst.Position = UDim2.fromScale(0.5, 0.5); _burst.BackgroundTransparency = 1
	_burst.Font = Enum.Font.GothamBlack; _burst.Text = "✦"; _burst.TextScaled = true
	_burst.TextTransparency = 0.35; _burst.ZIndex = 8; _burst.Parent = _revealBox

	_titleLbl = Instance.new("TextLabel")
	_titleLbl.Size = UDim2.fromScale(0.9, 0.16); _titleLbl.Position = UDim2.fromScale(0.05, 0.3)
	_titleLbl.BackgroundTransparency = 1; _titleLbl.Font = Enum.Font.GothamBlack; _titleLbl.TextScaled = true
	_titleLbl.Text = ""; _titleLbl.ZIndex = 9; _titleLbl.Parent = _revealBox

	_nameLbl = Instance.new("TextLabel")
	_nameLbl.Size = UDim2.fromScale(0.9, 0.14); _nameLbl.Position = UDim2.fromScale(0.05, 0.52)
	_nameLbl.BackgroundTransparency = 1; _nameLbl.Font = Enum.Font.GothamBold; _nameLbl.TextScaled = true
	_nameLbl.TextColor3 = Color3.new(1, 1, 1); _nameLbl.Text = ""; _nameLbl.ZIndex = 9; _nameLbl.Parent = _revealBox

	-- TYMCZASOWY przycisk ROLL (fires RollRequest). Re-hook do docelowego UI rolki pozniej.
	local rollBtn = Instance.new("TextButton")
	rollBtn.Size = UDim2.fromOffset(200, 56); rollBtn.AnchorPoint = Vector2.new(0.5, 1)
	rollBtn.Position = UDim2.new(0.5, 0, 1, -20)
	rollBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 70); rollBtn.TextColor3 = Color3.new(1, 1, 1)
	rollBtn.Font = Enum.Font.GothamBlack; rollBtn.TextSize = 22; rollBtn.Text = "ROLL"; rollBtn.ZIndex = 40
	rollBtn.Parent = gui
	rollBtn.MouseButton1Click:Connect(function()
		Net.get("RollRequest"):FireServer()
	end)

	Net.get("RollResult").OnClientEvent:Connect(function(result)
		if type(result) ~= "table" or not result.unitId then
			return
		end
		if #_queue < 6 then
			_queue[#_queue + 1] = result
		end
		pump()
	end)
end

-- Hooki TYLKO do testow (headless sanity: sekwencja odpala, pooling zwalnia).
function RollRevealController._QueueForTest(result)
	if #_queue < 6 then
		_queue[#_queue + 1] = result
	end
	pump()
end
function RollRevealController._StateForTest()
	return { playing = _playing, queueLen = #_queue, cloverPool = #_cloverPool }
end

return RollRevealController

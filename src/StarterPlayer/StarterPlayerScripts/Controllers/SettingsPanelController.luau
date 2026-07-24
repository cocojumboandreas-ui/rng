--!nonstrict
-- StarterPlayerScripts/Controllers/SettingsPanelController.luau  (KLIENT)
-- Panel USTAWIEN WYDAJNOSCI: przycisk ⚙ (prawy gorny rog) -> panel z przelacznikami.
-- Kazdy przelacznik pisze do PerfSettings; kontrolery renderu czytaja stan i pomijaja drogie rzeczy.
-- Samodzielny (wlasne ScreenGui) — nie zalezy od HUD ziomka (SideButtons).
local Players = game:GetService("Players")

local PerfSettings = require(script.Parent:WaitForChild("PerfSettings"))

local SettingsPanelController = {}
local LP = Players.LocalPlayer

-- key -> etykieta (ON = efekt widoczny; OFF = oszczedzasz FPS)
local ROWS = {
	{ key = "soldierAnim", label = "Soldier Animations" },
	{ key = "attackAnim", label = "Other Players' Attack FX" },
	{ key = "showOthers", label = "Show Other Players' Units" },
	{ key = "damageCounter", label = "Damage / HP Numbers" },
	{ key = "coinAnim", label = "Gold Coin Animations" },
}

local GREEN = Color3.fromRGB(70, 200, 110)
local GRAY = Color3.fromRGB(90, 90, 100)
local PANEL_BG = Color3.fromRGB(24, 24, 32)

local _pillByKey = {} -- key -> { pill, knob, text }

local function paintPill(key)
	local rec = _pillByKey[key]
	if not rec then return end
	local on = PerfSettings.get(key)
	rec.pill.BackgroundColor3 = on and GREEN or GRAY
	rec.knob.Position = on and UDim2.new(1, -22, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	rec.text.Text = on and "ON" or "OFF"
end

function SettingsPanelController.start()
	local pg = LP:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "WR_SettingsPanel"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = false
	gui.DisplayOrder = 100000; gui.Parent = pg -- NAD HUD-em ziomka (SideButtons) — panel/przelaczniki klikalne

	-- ── przycisk ⚙ (prawy gorny rog) ──
	local openBtn = Instance.new("TextButton")
	openBtn.Name = "Open"; openBtn.Size = UDim2.fromOffset(44, 44)
	openBtn.Position = UDim2.new(1, -54, 0, 10); openBtn.AnchorPoint = Vector2.new(0, 0)
	openBtn.BackgroundColor3 = PANEL_BG; openBtn.BackgroundTransparency = 0.1
	openBtn.Text = "⚙"; openBtn.TextSize = 26; openBtn.TextColor3 = Color3.new(1, 1, 1)
	openBtn.Font = Enum.Font.GothamBold; openBtn.AutoButtonColor = true; openBtn.Parent = gui
	local oc = Instance.new("UICorner"); oc.CornerRadius = UDim.new(0, 10); oc.Parent = openBtn
	local os_ = Instance.new("UIStroke"); os_.Color = Color3.fromRGB(255, 215, 90); os_.Thickness = 1.5; os_.Transparency = 0.4; os_.Parent = openBtn

	-- ── panel ──
	local panel = Instance.new("Frame")
	panel.Name = "Panel"; panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -54, 0, 64); panel.Size = UDim2.fromOffset(320, 44 + #ROWS * 48 + 12)
	panel.BackgroundColor3 = PANEL_BG; panel.BackgroundTransparency = 0.05; panel.BorderSizePixel = 0
	panel.Visible = false; panel.Parent = gui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 12); pc.Parent = panel
	local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(255, 215, 90); ps.Thickness = 1.5; ps.Transparency = 0.4; ps.Parent = panel

	-- naglowek + X
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -44, 0, 40); title.Position = UDim2.fromOffset(14, 4); title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold; title.TextSize = 18; title.TextColor3 = Color3.fromRGB(255, 215, 90)
	title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = "⚙  Performance"; title.Parent = panel
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.fromOffset(30, 30); closeBtn.Position = UDim2.new(1, -38, 0, 8); closeBtn.AnchorPoint = Vector2.new(0, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60); closeBtn.Text = "✕"; closeBtn.TextSize = 16
	closeBtn.TextColor3 = Color3.new(1, 1, 1); closeBtn.Font = Enum.Font.GothamBold; closeBtn.Parent = panel
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = closeBtn

	-- wiersze przelacznikow
	for i, row in ipairs(ROWS) do
		local y = 44 + (i - 1) * 48
		local rowFrame = Instance.new("Frame")
		rowFrame.Size = UDim2.new(1, -24, 0, 42); rowFrame.Position = UDim2.fromOffset(12, y)
		rowFrame.BackgroundColor3 = Color3.fromRGB(38, 38, 48); rowFrame.BackgroundTransparency = 0.2; rowFrame.BorderSizePixel = 0
		rowFrame.Parent = panel
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = rowFrame

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -74, 1, 0); lbl.Position = UDim2.fromOffset(12, 0); lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 14; lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.TextWrapped = true; lbl.Text = row.label; lbl.Parent = rowFrame

		-- pill toggle
		local pill = Instance.new("TextButton")
		pill.Size = UDim2.fromOffset(46, 24); pill.Position = UDim2.new(1, -54, 0.5, 0); pill.AnchorPoint = Vector2.new(0, 0.5)
		pill.BackgroundColor3 = GRAY; pill.Text = ""; pill.AutoButtonColor = false; pill.Parent = rowFrame
		local plc = Instance.new("UICorner"); plc.CornerRadius = UDim.new(1, 0); plc.Parent = pill
		local knob = Instance.new("Frame")
		knob.Size = UDim2.fromOffset(20, 20); knob.AnchorPoint = Vector2.new(0, 0.5); knob.Position = UDim2.new(0, 2, 0.5, 0)
		knob.BackgroundColor3 = Color3.new(1, 1, 1); knob.BorderSizePixel = 0; knob.Parent = pill
		local kc = Instance.new("UICorner"); kc.CornerRadius = UDim.new(1, 0); kc.Parent = knob
		local stateTxt = Instance.new("TextLabel")
		stateTxt.Size = UDim2.new(1, -54, 1, 0); stateTxt.Position = UDim2.new(0, 0, 0, 0); stateTxt.AnchorPoint = Vector2.new(0, 0)
		-- (ukryty tekst ON/OFF na pill nie miesci sie — pokazujemy stan kolorem knoba; text trzymamy do a11y)
		stateTxt.BackgroundTransparency = 1; stateTxt.Visible = false; stateTxt.Text = "ON"; stateTxt.Parent = pill

		_pillByKey[row.key] = { pill = pill, knob = knob, text = stateTxt }
		paintPill(row.key)

		local function flip()
			PerfSettings.toggle(row.key)
			paintPill(row.key)
		end
		pill.MouseButton1Click:Connect(flip)
		-- klik w caly wiersz tez przelacza (wieksza powierzchnia)
		local rowBtn = Instance.new("TextButton")
		rowBtn.Size = UDim2.new(1, -60, 1, 0); rowBtn.Position = UDim2.fromOffset(0, 0); rowBtn.BackgroundTransparency = 1
		rowBtn.Text = ""; rowBtn.Parent = rowFrame
		rowBtn.MouseButton1Click:Connect(flip)
	end

	local function setOpen(open)
		panel.Visible = open
	end
	openBtn.MouseButton1Click:Connect(function() setOpen(not panel.Visible) end)
	closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)

	-- gdy stan zmieni sie skadinad — odswiez pigulki
	PerfSettings.onChanged(function(key)
		paintPill(key)
	end)
end

return SettingsPanelController

--!nonstrict
-- StarterPlayerScripts/Controllers/Notify.luau  (KLIENT)
-- Wspolny TOAST przez DESIGNEROWY szablon SideButtons.TopCanvas.Notifications.Template (ciemny pasek z gradientem).
-- Zastepuje proceduralne powiadomienia "AI" (np. WR_BudgetToast "Board full"). Klon Template -> ustaw tekst ->
-- pop-in (UIScale) -> hold -> fade -> Destroy. Ukladanie w kolumnie przez designerowy UIListLayout (Notifications).
-- Uzycie: local Notify = require(script.Parent:WaitForChild("Notify")); Notify.show("Board full, no free slots!")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Notify = {}
local LP = Players.LocalPlayer

local NOTIFY_CAP = 4 -- max jednoczesnych toastow (anti-spam)
local DEDUP_WINDOW = 0.6 -- ten sam tekst w tym oknie (s) -> pomin (klik-spam)
local _active = 0
local _lastText, _lastAt = nil, 0

local function resolve()
	local pg = LP:FindFirstChild("PlayerGui")
	local sb = pg and pg:FindFirstChild("SideButtons")
	local tc = sb and sb:FindFirstChild("TopCanvas")
	local nf = tc and tc:FindFirstChild("Notifications")
	local tmpl = nf and nf:FindFirstChild("Template")
	return nf, tmpl
end

-- pokaz toast; dur = ile sekund trzymac (domyslnie 2.2)
function Notify.show(text, dur)
	if type(text) ~= "string" or text == "" then return end
	local now = os.clock()
	if text == _lastText and (now - _lastAt) < DEDUP_WINDOW then return end -- dedup klik-spamu
	_lastText, _lastAt = text, now
	if _active >= NOTIFY_CAP then return end
	local holder, tmpl = resolve()
	if not holder or not tmpl then return end
	_active += 1
	local c = tmpl:Clone()
	c.Name = "WR_Notify"
	c.Visible = true
	c.LayoutOrder = -1 -- najnowszy na gorze kolumny
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("TextLabel") then d.Text = text end
	end
	local sc = Instance.new("UIScale"); sc.Scale = 0.6; sc.Parent = c
	c.Parent = holder
	TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	dur = dur or 2.2
	task.delay(dur, function()
		if not c.Parent then
			_active = math.max(0, _active - 1)
			return
		end
		TweenService:Create(c, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("TextLabel") then TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play() end
			if d:IsA("UIStroke") then TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play() end
		end
		task.wait(0.32)
		if c.Parent then c:Destroy() end
		_active = math.max(0, _active - 1)
	end)
end

return Notify

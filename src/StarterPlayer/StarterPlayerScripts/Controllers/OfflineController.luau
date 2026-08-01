--!nonstrict
-- StarterPlayerScripts/Controllers/OfflineController.luau  (post-bramka task 3 — klient)
-- Popup "Witaj z powrotem" na dolaczeniu. STERUJE designerowym StarterGui.OfflineEarn
-- (place-owned; my nic nie tworzymy — tylko odczyt po nazwach + wpiecie danych). Sluchamy
-- Net.OfflineEarnings (S->C {coins, seconds}). Monety juz przyznane serwerowo (Award w
-- ComputeOfflineEarnings) — panel jest tylko informacyjny; "Odbierz" zamyka.
-- Payload ma TYLKO coins+seconds -> sekcje Rolls/BestDrops/DoubleOffline (brak danych) chowamy.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage:WaitForChild("Framework")
local Net = require(Framework:WaitForChild("Net"))

local OfflineController = {}

local function fmtDuration(seconds: number): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then
		return h .. "h " .. m .. "m"
	end
	return m .. "m"
end

local function fmtNum(n)
	n = math.floor(tonumber(n) or 0)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
	else return tostring(n) end
end

-- schodzenie po nazwach z guardem (jak ziomek przemianuje element -> pomijamy, brak crasha)
local function resolve(root, ...)
	local cur = root
	for _, seg in ipairs({ ... }) do
		if not cur then return nil end
		cur = cur:FindFirstChild(seg)
	end
	return cur
end

-- ustaw tekst na labelu I jego zagniezdzonych labelach (kit renderuje tekst warstwowo dla obrysu)
local function setText(inst, txt)
	if not inst then return end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then inst.Text = txt end
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("TextLabel") then c.Text = txt end
	end
end

local function hide(inst)
	if inst then inst.Visible = false end
end

function OfflineController.start()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = pg:WaitForChild("OfflineEarn", 15)
	if not gui then
		warn("[OfflineController] brak PlayerGui.OfflineEarn — popup offline nie znaleziony")
		return
	end
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 190

	local canvas = resolve(gui, "Canvas")
	if not canvas then
		warn("[OfflineController] OfflineEarn.Canvas nie znaleziony")
		return
	end
	canvas.Visible = false

	local content = resolve(canvas, "Content", "Content")
	local moneyVal = content and resolve(content, "Values", "Money", "Value")
	local offlineInfo = content and resolve(content, "OfflineInfo")

	-- statyczne etykiety -> PL (tylko tekst; layout/styl bez zmian)
	setText(resolve(gui, "Canvas", "IconName", "Text"), "Welcome back!")
	setText(content and resolve(content, "Values", "Money", "Text"), "Coins:")

	-- payload nie niesie rolek ani dropow -> chowamy niewypelnione sekcje i przycisk x2
	hide(content and resolve(content, "Values", "Rolls"))
	hide(content and resolve(content, "BestDrops"))
	hide(content and resolve(content, "BottomButtons", "DoubleOffline"))

	-- "Odbierz" (Collect) zamyka panel (monety juz przyznane serwerowo)
	local collect = content and resolve(content, "BottomButtons", "Collect")
	if collect then
		setText(resolve(collect, "TextLabel"), "Collect")
		if collect:IsA("GuiButton") then
			collect.MouseButton1Click:Connect(function() canvas.Visible = false end)
		end
	end

	Net.get("OfflineEarnings").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" or not p.coins or p.coins <= 0 then
			return
		end
		setText(moneyVal, "+" .. fmtNum(p.coins))
		setText(offlineInfo, ("While you were away (%s), you earned:"):format(fmtDuration(p.seconds or 0)))
		canvas.Visible = true
	end)
end

return OfflineController

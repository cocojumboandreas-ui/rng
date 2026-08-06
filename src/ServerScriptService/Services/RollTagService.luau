--!nonstrict
-- ServerScriptService/Services/RollTagService.luau
-- Nad glowa KAZDEGO gracza: laczna liczba rolek (lifetimeRolls) — „🎲 70,576". Serwerowy BillboardGui
-- (replikuje sie do wszystkich, wiec widzisz tez cudze). Aktualizacja na kazdej rolce (RollService.Rolled)
-- + przy spawnie postaci / zaladowaniu profilu.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

local RollTagService = {}
local _profile, _roll
local _tags = {} -- player -> { label = TextLabel }

local function fmt(n)
	n = math.floor((tonumber(n) or 0) + 0.5)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	-- < 1M: pelna liczba z przecinkami (gracze lubia dokladny licznik rolek)
	local s = tostring(n)
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- Ikona kostki — TA SAMA co w „Offline Earnings" (HUD), zescalowana. Spojnosc z reszta UI.
local DICE_ICON = "rbxassetid://83517758689278"
local function buildDie(parent)
	local icon = Instance.new("ImageLabel")
	icon.LayoutOrder = 1
	icon.Size = UDim2.fromOffset(24, 24)
	icon.BackgroundTransparency = 1
	icon.Image = DICE_ICON
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = parent
	return icon
end

local function updateTag(player)
	local t = _tags[player]
	if not t or not t.label.Parent then return end
	local data = _profile.GetProfile(player)
	t.label.Text = fmt(data and data.lifetimeRolls or 0)
end

local function buildTag(player, char)
	local head = char:FindFirstChild("Head") or char:WaitForChild("Head", 5)
	if not head then return end
	local old = head:FindFirstChild("WR_RollTag")
	if old then old:Destroy() end

	-- Czysty styl (jak u wzorca): kostka + biala liczba z czarnym obrysem, BEZ tla.
	local gui = Instance.new("BillboardGui")
	gui.Name = "WR_RollTag"
	gui.Size = UDim2.fromOffset(150, 30)
	gui.StudsOffset = Vector3.new(0, 2.6, 0) -- pod domyslnym nametagiem-nickiem
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Adornee = head
	gui.ResetOnSpawn = false
	gui.Parent = head

	local row = Instance.new("Frame")
	row.Size = UDim2.fromScale(1, 1)
	row.BackgroundTransparency = 1
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = row

	buildDie(row) -- biala kostka (UI) po lewej

	local label = Instance.new("TextLabel")
	label.LayoutOrder = 2
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 26)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(255, 255, 255) -- bialy napis
	label.Text = "0"
	local ls = Instance.new("UIStroke")
	ls.Color = Color3.new(0, 0, 0)
	ls.Thickness = 2.4
	ls.Transparency = 0.05
	ls.Parent = label
	label.Parent = row

	_tags[player] = { label = label }
	updateTag(player)
end

function RollTagService.Init() end

function RollTagService.Start()
	_profile = require(Services:WaitForChild("ProfileService"))
	_roll = require(Services:WaitForChild("RollService"))

	local function hook(player)
		player.CharacterAdded:Connect(function(char)
			task.defer(buildTag, player, char)
		end)
		if player.Character then
			task.defer(buildTag, player, player.Character)
		end
	end
	for _, plr in ipairs(Players:GetPlayers()) do hook(plr) end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(plr) _tags[plr] = nil end)

	-- kazda rolka -> odswiez licznik
	if _roll.Rolled then
		_roll.Rolled:Connect(function(player) updateTag(player) end)
	end
	-- profil zaladowany po spawnie -> upewnij sie ze licznik ma dane
	_profile.ProfileLoaded:Connect(function(player)
		task.defer(function() updateTag(player) end)
	end)
end

return RollTagService

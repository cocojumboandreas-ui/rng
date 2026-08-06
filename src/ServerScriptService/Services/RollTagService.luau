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

local function updateTag(player)
	local t = _tags[player]
	if not t or not t.label.Parent then return end
	local data = _profile.GetProfile(player)
	t.label.Text = "🎲 " .. fmt(data and data.lifetimeRolls or 0)
end

local function buildTag(player, char)
	local head = char:FindFirstChild("Head") or char:WaitForChild("Head", 5)
	if not head then return end
	local old = head:FindFirstChild("WR_RollTag")
	if old then old:Destroy() end

	local gui = Instance.new("BillboardGui")
	gui.Name = "WR_RollTag"
	gui.Size = UDim2.fromOffset(150, 40)
	gui.StudsOffset = Vector3.new(0, 2.8, 0) -- nad domyslnym nametagiem
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Adornee = head
	gui.ResetOnSpawn = false
	gui.Parent = head

	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromScale(1, 0.72)
	pill.BackgroundColor3 = Color3.fromRGB(28, 30, 26)
	pill.BackgroundTransparency = 0.12
	pill.BorderSizePixel = 0
	pill.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 210, 70)
	stroke.Thickness = 1.6
	stroke.Transparency = 0.15
	stroke.Parent = pill

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.92, 0.8)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 225, 90)
	label.Text = "🎲 0"
	local ls = Instance.new("UIStroke")
	ls.Color = Color3.new(0, 0, 0)
	ls.Thickness = 2
	ls.Parent = label
	label.Parent = pill

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

--!nonstrict
-- ServerScriptService/Services/PlotBestService.luau
-- TABLICA-REKORD per plot: znak jest WBITY W PLAC na stałe (workspace.PlotSigns.WR_PlotSign_<id>, tag "WR_PlotSign",
-- attr PlotId), NIE budowany proceduralnie. Ten serwis TYLKO znajduje wypalone znaki i podmienia liczby:
--   • Best wave (zielony)  • DPS: szczytowy sumaryczny DPS jednostek na planszy (żółty)
--   • Health: szczytowe sumaryczne HP wszystkich postawionych jednostek (czerwony)
-- Rekordy ROSNĄ TYLKO W GÓRĘ, zapisane w profilu (bestWave/bestDPS/bestHP) -> przetrwają rejoin. Widoczne dla wszystkich.
-- Aktualizacja: PlacementChanged / UnitLeveled / StatsChanged -> przelicz sumy, podbij jeśli wyżej. Fala: WaveEnded.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Services = ServerScriptService:WaitForChild("Services")

local PlotBestService = {}

local _profile, _grid, _stat, _level, _build, _wave, _plot
local _signs = {} -- [plotId] = { wave=TextLabel, dps=TextLabel, hp=TextLabel }

-- ── formatowanie liczb (K/M/B) ────────────────────────────────────────────────
local function fmt(n)
	n = math.floor((tonumber(n) or 0) + 0.5)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(n)
end

-- ── suma DPS (jednostki bojowe) + suma HP (wszystkie placementy), z mnoznikami/poziomami ──
local function computeTotals(player)
	local placements = _grid.GetPlacements(player)
	if not placements then return 0, 0 end
	local stats = _stat.Get(player)
	local dmgMult = (stats and stats.dmgMult) or 1
	local fireRateMult = (stats and stats.fireRateMult) or 1
	local totalDps, totalHp = 0, 0
	for _, p in pairs(placements) do
		local u = GameConfig.Units[p.unitId]
		if u then
			local hpLvlMult = _level.GetHpLevelMult(player, p.unitId)
			totalHp += (u.hp or 100) * hpLvlMult
			if u.combat then
				local dmgLvlMult = _level.GetLevelMult(player, p.unitId)
				totalDps += (u.combat.dmg or 0) * (u.combat.fireRate or 0) * dmgMult * fireRateMult * dmgLvlMult
			end
		end
	end
	return totalDps, totalHp
end

-- ── render liczb na wypalonym znaku danego plotu ──────────────────────────────
local function renderSign(plotId, data)
	local s = _signs[plotId]
	if not s then return end
	s.wave.Text = fmt(data and data.bestWave or 0)
	s.dps.Text = fmt(data and data.bestDPS or 0)
	s.hp.Text = fmt(data and data.bestHP or 0)
end

local function plotIdOf(player)
	return player:GetAttribute("PlotId")
end

-- ── rekordy DPS/HP: przelicz i podbij jesli wyzej ─────────────────────────────
local function refreshCombatBests(player)
	local data = _profile.GetProfile(player)
	if not data then return end
	local dps, hp = computeTotals(player)
	local changed = false
	if dps > (data.bestDPS or 0) then data.bestDPS = dps; changed = true end
	if hp > (data.bestHP or 0) then data.bestHP = hp; changed = true end
	if changed then
		local pid = plotIdOf(player)
		if pid then renderSign(pid, data) end
	end
end

local function updateBestWave(player, wave)
	local data = _profile.GetProfile(player)
	if not data or not wave then return end
	if wave > (data.bestWave or 0) then
		data.bestWave = wave
		local pid = plotIdOf(player)
		if pid then renderSign(pid, data) end
	end
end

-- ── podepnij wypalone znaki (workspace.PlotSigns, tag WR_PlotSign) -> etykiety wartosci ──
local function bindSign(model)
	local pid = model:GetAttribute("PlotId")
	local board = model:FindFirstChild("Board")
	local surf = board and board:FindFirstChild("Face")
	if not (pid and surf) then return end
	local wave = surf:FindFirstChild("WaveVal", true)
	local dps = surf:FindFirstChild("DpsVal", true)
	local hp = surf:FindFirstChild("HpVal", true)
	if wave and dps and hp then
		_signs[pid] = { wave = wave, dps = dps, hp = hp }
		renderSign(pid, nil) -- start: zera (dopoki gracz nie przyjdzie)
	end
end

-- ── boot ──────────────────────────────────────────────────────────────────────
function PlotBestService.Init() end

function PlotBestService.Start()
	_profile = require(Services:WaitForChild("ProfileService"))
	_grid = require(Services:WaitForChild("GridService"))
	_stat = require(Services:WaitForChild("StatProfileService"))
	_level = require(Services:WaitForChild("LevelService"))
	_build = require(Services:WaitForChild("BuildService"))
	_wave = require(Services:WaitForChild("WaveService"))
	_plot = require(Services:WaitForChild("PlotService"))

	-- podepnij istniejace wypalone znaki (i ewentualne dodane pozniej)
	for _, model in ipairs(CollectionService:GetTagged("WR_PlotSign")) do
		bindSign(model)
	end
	CollectionService:GetInstanceAddedSignal("WR_PlotSign"):Connect(bindSign)

	-- rekordy DPS/HP na zmianę planszy / poziomu / statów
	_build.PlacementChanged:Connect(refreshCombatBests)
	_level.UnitLeveled:Connect(function(player) refreshCombatBests(player) end)
	_stat.StatsChanged:Connect(function(player) refreshCombatBests(player) end)

	-- rekord fali na koniec runu
	_wave.WaveEnded:Connect(function(player, reason, summary)
		if summary and summary.maxWave then updateBestWave(player, summary.maxWave) end
	end)

	-- profil załadowany / plot przydzielony -> pokaż zapisane rekordy tego gracza na jego znaku
	_profile.ProfileLoaded:Connect(function(player)
		task.defer(function()
			local pid = plotIdOf(player)
			if pid then renderSign(pid, _profile.GetProfile(player)) end
			refreshCombatBests(player) -- na wypadek gdyby miał już placementy (restore)
		end)
	end)
	_plot.PlotAssigned:Connect(function(player)
		task.defer(function()
			renderSign(player:GetAttribute("PlotId"), _profile.GetProfile(player))
		end)
	end)
	-- plot zwolniony -> znak na zera
	_plot.PlotReleased:Connect(function(_, plotId)
		renderSign(plotId, nil)
	end)
end

return PlotBestService

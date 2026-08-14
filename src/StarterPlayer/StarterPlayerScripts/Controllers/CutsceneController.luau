--!nonstrict
-- StarterPlayerScripts/Controllers/CutsceneController.luau  (KLIENT — biblioteka, NIE controller z .start())
-- Generyczny sekwencer kamery na SHOT-LIŚCIE (dowolna liczba ujęć), do użycia przez cutscenki
-- (intro, i cokolwiek przyjdzie później). Wzorowany na AtomicStrikeController (Scriptable camera,
-- bary kinowe, hide/restore UI), ale bez 2 zahardkodowanych faz — ujęcia to dane, nie kod.
-- ODPORNOŚĆ NA PRZERWANIE: jeden RenderStepped, cała logika klatki w pcall, jawna flaga
-- `_cancelled` sprawdzana co klatkę, JEDNO miejsce cleanupu (teardown) wołane zawsze —
-- normalne zakończenie i skip w dowolnym ujęciu przechodzą przez tę samą ścieżkę.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CutsceneController = {}
local LP = Players.LocalPlayer

local BAR_SCALE = 0.12
local BAR_TWEEN_T = 0.35

-- ── UI: bary + ukrywanie/przywracanie HUD (wzorzec 1:1 z AtomicStrikeController) ──
local cutGui, topBar, botBar, skipLabel
local function ensureCutGui()
	if cutGui and cutGui.Parent then
		return
	end
	local pg = LP:WaitForChild("PlayerGui")
	cutGui = Instance.new("ScreenGui")
	cutGui.Name = "WR_CutsceneFx"
	cutGui.ResetOnSpawn = false
	cutGui.IgnoreGuiInset = true
	cutGui.DisplayOrder = 480 -- pod WR_AtomicFx (500), nad zwyklym HUD
	cutGui.Parent = pg

	topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1, 0, 0, 0)
	topBar.Position = UDim2.new(0, 0, 0, 0)
	topBar.BackgroundColor3 = Color3.new(0, 0, 0)
	topBar.BorderSizePixel = 0
	topBar.Parent = cutGui

	botBar = Instance.new("Frame")
	botBar.AnchorPoint = Vector2.new(0, 1)
	botBar.Size = UDim2.new(1, 0, 0, 0)
	botBar.Position = UDim2.new(0, 0, 1, 0)
	botBar.BackgroundColor3 = Color3.new(0, 0, 0)
	botBar.BorderSizePixel = 0
	botBar.Parent = cutGui

	skipLabel = Instance.new("TextLabel")
	skipLabel.Name = "SkipHint"
	skipLabel.AnchorPoint = Vector2.new(1, 1)
	skipLabel.Position = UDim2.new(1, -24, 1, -24)
	skipLabel.Size = UDim2.new(0, 280, 0, 28)
	skipLabel.BackgroundTransparency = 1
	skipLabel.TextColor3 = Color3.new(1, 1, 1)
	skipLabel.TextTransparency = 0.15
	skipLabel.Font = Enum.Font.GothamMedium
	skipLabel.TextSize = 18
	skipLabel.TextXAlignment = Enum.TextXAlignment.Right
	skipLabel.Text = ""
	skipLabel.Visible = false
	skipLabel.Parent = cutGui
end

local _hiddenGuis = {}
local function hideUI()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	_hiddenGuis = {}
	for _, g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and g ~= cutGui and g.Enabled then
			g.Enabled = false
			table.insert(_hiddenGuis, g)
		end
	end
end
local function restoreUI()
	for _, g in ipairs(_hiddenGuis) do
		if g.Parent then
			g.Enabled = true
		end
	end
	_hiddenGuis = {}
end

-- ── stan sekwencera (jeden na raz) ──
local _active = false
local _cancelled = false
local _renderConn = nil
local _skipConn = nil
local _onDone = nil -- callback(wasCancelled: boolean), wolany DOKLADNIE raz

local function teardown(prevType: Enum.CameraType, prevCF: CFrame)
	if _renderConn then
		_renderConn:Disconnect()
		_renderConn = nil
	end
	if _skipConn then
		_skipConn:Disconnect()
		_skipConn = nil
	end
	if skipLabel then
		skipLabel.Visible = false
	end
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = prevType
		cam.CFrame = prevCF
	end
	if topBar and botBar then
		TweenService:Create(topBar, TweenInfo.new(BAR_TWEEN_T, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.new(1, 0, 0, 0) }):Play()
		TweenService:Create(botBar, TweenInfo.new(BAR_TWEEN_T, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	end
	task.delay(BAR_TWEEN_T, restoreUI)
	_active = false
	local wasCancelled = _cancelled
	local cb = _onDone
	_onDone = nil
	if cb then
		local ok, err = pcall(cb, wasCancelled)
		if not ok then
			warn("[CutsceneController] onDone padl: " .. tostring(err))
		end
	end
end

-- Przerywa aktywną sekwencję NATYCHMIAST (skip). No-op jesli nic nie leci / juz przerywane.
function CutsceneController.cancel()
	if _active and not _cancelled then
		_cancelled = true
	end
end

function CutsceneController.isActive(): boolean
	return _active
end

-- shots: { {cf: CFrame, duration: number}, ... } — cf gotowe (np. CFrame.lookAt(pos, target))
-- opts.onDone(wasCancelled) / opts.onShotStart(index, shot) / opts.onShotEnd(index, shot) — wszystkie opcjonalne, w pcall.
-- opts.allowSkip(boolean) — pokaz podpowiedz pominiecia (platformowo: Tap na dotyku, Space na PC) i pozwol
-- graczowi anulowac sekwencje w dowolnym momencie; gdy false/nil, pominiecie NIEDOSTEPNE (pierwsze wejscie).
function CutsceneController.play(shots: { { cf: CFrame, duration: number } }, opts: any?): boolean
	if _active then
		warn("[CutsceneController] play() wywolane gdy sekwencja juz leci — ignoruje.")
		return false
	end
	if #shots == 0 then
		warn("[CutsceneController] play() z pusta shot-lista — ignoruje.")
		return false
	end
	opts = opts or {}
	_active = true
	_cancelled = false
	_onDone = opts.onDone

	ensureCutGui()
	hideUI()

	local cam = Workspace.CurrentCamera
	local prevType = cam.CameraType
	local prevCF = cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable

	topBar.Size = UDim2.new(1, 0, 0, 0)
	botBar.Size = UDim2.new(1, 0, 0, 0)
	TweenService:Create(topBar, TweenInfo.new(BAR_TWEEN_T, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, BAR_SCALE, 0) }):Play()
	TweenService:Create(botBar, TweenInfo.new(BAR_TWEEN_T, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, BAR_SCALE, 0) }):Play()

	if opts.allowSkip then
		skipLabel.Text = UserInputService.TouchEnabled and "Tap to skip" or "Press [Space] to skip"
		skipLabel.Visible = true
		_skipConn = UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.Touch then
				CutsceneController.cancel()
			end
		end)
	end

	local shotIdx = 1
	local shotStart = os.clock()
	local fromCF = prevCF

	if opts.onShotStart then
		pcall(opts.onShotStart, 1, shots[1])
	end

	_renderConn = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(function()
			if _cancelled then
				teardown(prevType, prevCF)
				return
			end
			local shot = shots[shotIdx]
			if not shot then
				teardown(prevType, prevCF)
				return
			end
			local t = math.clamp((os.clock() - shotStart) / math.max(shot.duration, 0.001), 0, 1)
			local e = 1 - (1 - t) * (1 - t) -- ease-out quad
			cam.CFrame = fromCF:Lerp(shot.cf, e)
			if t >= 1 then
				if opts.onShotEnd then
					pcall(opts.onShotEnd, shotIdx, shot)
				end
				shotIdx += 1
				shotStart = os.clock()
				fromCF = shot.cf
				local nextShot = shots[shotIdx]
				if nextShot then
					if opts.onShotStart then
						pcall(opts.onShotStart, shotIdx, nextShot)
					end
				else
					teardown(prevType, prevCF)
				end
			end
		end)
		if not ok then
			warn("[CutsceneController] blad w trakcie sekwencji, przerywam czysto: " .. tostring(err))
			_cancelled = true
			teardown(prevType, prevCF)
		end
	end)

	return true
end

return CutsceneController

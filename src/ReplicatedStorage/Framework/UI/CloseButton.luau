--!strict
-- Framework/UI/CloseButton.luau
-- Faza B UI port, Krok 3. Adaptacja source-place CloseButton: klik -> ScreenGui-ancestor -> jego
-- dziecko "Canvas" -> Registered:Close(). Krok 4 wpina dyspozytor CollectionService
-- (WR_UITagDispatcher), ktory wola New()/Destroy() automatycznie dla kazdej instancji z tagiem
-- "CloseButton".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Framework.Maid)
local UIController = require(ReplicatedStorage.Framework.UI.UIController)

local CloseButton = {}
CloseButton.__index = CloseButton

CloseButton.Type = "Tag"
CloseButton.Tag = "CloseButton"

export type Self = typeof(CloseButton) & {
	Button: GuiButton,
	Maid: Maid.Maid,
	Registered: UIController.Window?,
}

function CloseButton.New(Button: GuiButton)
	local self = setmetatable({}, CloseButton) :: Self
	self.Button = Button
	self.Maid = Maid.new()
	self.Registered = nil

	self.Maid:GiveTask(self.Button.Activated:Connect(function()
		local Registered = self.Registered or self:_GetOrRegisterWindow()
		if not Registered then
			return
		end

		self.Registered = Registered
		Registered:Close()
	end))

	task.defer(function()
		self.Registered = self:_GetOrRegisterWindow()
	end)

	return self
end

function CloseButton:_GetWindowName(): string?
	local Screen = self.Button:FindFirstAncestorWhichIsA("ScreenGui")
	if not Screen then
		return nil
	end

	return `{Screen.Name}UI`
end

function CloseButton:_FindRegisteredByFrame(Frame: GuiObject): UIController.Window?
	for _, Registered in pairs(UIController.Registered) do
		if Registered._Instance == Frame then
			return Registered
		end
	end

	return nil
end

function CloseButton:_ResolveWindowFrame(): GuiObject?
	local Screen = self.Button:FindFirstAncestorWhichIsA("ScreenGui")
	if Screen then
		local Canvas = Screen:FindFirstChild("Canvas")
		if Canvas and Canvas:IsA("GuiObject") then
			return Canvas
		end
	end

	local PlayerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not PlayerGui or not Screen then
		return nil
	end

	local PlayerScreen = PlayerGui:FindFirstChild(Screen.Name)
	if not PlayerScreen or not PlayerScreen:IsA("ScreenGui") then
		return nil
	end

	local Canvas = PlayerScreen:FindFirstChild("Canvas")
	if Canvas and Canvas:IsA("GuiObject") then
		return Canvas
	end

	return nil
end

function CloseButton:_GetOrRegisterWindow(): UIController.Window?
	local Frame = self:_ResolveWindowFrame()
	if not Frame then
		return nil
	end

	local RegisteredByFrame = self:_FindRegisteredByFrame(Frame)
	if RegisteredByFrame then
		return RegisteredByFrame
	end

	local Name = self:_GetWindowName()
	if not Name then
		return nil
	end

	local Registered = UIController.Registered[Name]
	if Registered then
		return Registered
	end

	return UIController.Register(Name, Frame)
end

function CloseButton.Destroy(self: Self)
	if self.Maid then
		self.Maid:DoCleaning()
	end
end

return CloseButton

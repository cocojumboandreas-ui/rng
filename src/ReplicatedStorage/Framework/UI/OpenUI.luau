--!strict
-- Framework/UI/OpenUI.luau
-- Faza B UI port, Krok 3. Adaptacja source-place OpenUI: klik przycisku -> z Name/atrybutu buduje
-- "<Name>UI" -> Registered:Toggle(). Krok 4 wpina dyspozytor CollectionService (WR_UITagDispatcher),
-- ktory wola New()/Destroy() automatycznie dla kazdej instancji z tagiem "OpenUI".
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Framework.Maid)
local UIController = require(ReplicatedStorage.Framework.UI.UIController)

local OpenUI = {}
OpenUI.__index = OpenUI

OpenUI.Type = "Tag"
OpenUI.Tag = "OpenUI"

local REGISTER_WAIT_TIMEOUT = 20
local CLICK_WAIT_TIMEOUT = 4

export type UIButton = TextButton & ImageButton

export type Self = typeof(OpenUI) & {
	Button: UIButton,
	Maid: Maid.Maid,
	Registered: UIController.Window?,
	UIName: string,
	WarnedMissing: boolean,
}

function OpenUI:ResolveRegistered(Timeout: number?): UIController.Window?
	local Registered = self.Registered
	if Registered then
		return Registered
	end

	Registered = UIController.Registered[self.UIName]
	if Registered then
		self.Registered = Registered
		return Registered
	end

	if Timeout and Timeout > 0 then
		Registered = UIController.WaitForRegistered(self.UIName, Timeout)
		if Registered then
			self.Registered = Registered
			return Registered
		end
	end

	return nil
end

function OpenUI.New(Button: GuiObject)
	local self = setmetatable({}, OpenUI) :: Self
	self.Button = Button :: UIButton
	self.Maid = Maid.new()
	self.Registered = nil
	self.WarnedMissing = false

	local UIName = Button:GetAttribute("Name") or Button.Name :: string
	if typeof(UIName) ~= "string" then
		warn(`[OpenUI] Attribute Name should be a string, not {typeof(UIName)}`)
		return
	end

	self.UIName = `{UIName}UI`
	self.Registered = UIController.Registered[self.UIName]

	self.Maid:GiveTask((self.Button :: GuiButton).MouseButton1Click:Connect(function()
		local Registered = self:ResolveRegistered(CLICK_WAIT_TIMEOUT)
		if not Registered then
			if not self.WarnedMissing then
				self.WarnedMissing = true
				warn(`[OpenUI] No registered window for {tostring(self.UIName)}`)
			end
			return
		end

		Registered:Toggle()
	end))

	if not self.Registered then
		task.spawn(function()
			local Registered = UIController.WaitForRegistered(self.UIName, REGISTER_WAIT_TIMEOUT)
			if Registered and self.Button.Parent then
				self.Registered = Registered
			end
		end)
	end

	return self
end

function OpenUI.Destroy(self: Self)
	if self.Maid then
		self.Maid:DoCleaning()
	end
end

return OpenUI

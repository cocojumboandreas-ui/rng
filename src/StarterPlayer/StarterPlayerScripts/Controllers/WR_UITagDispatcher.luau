--!strict
-- StarterPlayerScripts/Controllers/WR_UITagDispatcher.luau (CLIENT)
-- Faza B UI port, Krok 4. Lekki dyspozytor tagow CollectionService dla modulow Framework/UI z
-- konwencja Type="Tag"/Tag="<nazwa>" (ButtonUI/OpenUI/CloseButton), zaadaptowany z pelnego
-- Initializer w source-place (TagAdded/TagRemoved przez GetTagged + GetInstanceAddedSignal/
-- RemovedSignal). OKROJONY do samego dyspozytora -- bez Local_Tag, template-filtera, batchingu
-- i telemetrii z zrodla, bo tu nie sa potrzebne. Zastepuje reczne New()/Destroy() z Krokow 2-3
-- (WR_UIPortTestController). GRANICA: dziala tylko na nowoportowanych tagach; zero tagow
-- IsAButton/OpenUI/CloseButton na przyciskach rolla/index/build (Tag rolla to osobny string "Button").
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonUI = require(ReplicatedStorage.Framework.UI.ButtonUI)
local OpenUI = require(ReplicatedStorage.Framework.UI.OpenUI)
local CloseButton = require(ReplicatedStorage.Framework.UI.CloseButton)

local WR_UITagDispatcher = {}

local TAG_MODULES = { ButtonUI, OpenUI, CloseButton }

local function WireTagModule(Module)
	local Tag = Module.Tag
	if typeof(Tag) ~= "string" then
		return
	end

	local Live: { [Instance]: any } = {}

	local function Added(Instance: Instance)
		if Live[Instance] then
			return
		end
		local Ok, Result = pcall(Module.New, Instance)
		if not Ok then
			warn(("[WR_UITagDispatcher] %s.New failed on %s: %s"):format(Tag, Instance:GetFullName(), tostring(Result)))
			return
		end
		Live[Instance] = Result
	end

	local function Removed(Instance: Instance)
		local Self = Live[Instance]
		if not Self then
			return
		end
		Live[Instance] = nil
		if Self.Destroy then
			local Ok, Err = pcall(Self.Destroy, Self)
			if not Ok then
				warn(("[WR_UITagDispatcher] %s.Destroy failed on %s: %s"):format(Tag, Instance:GetFullName(), tostring(Err)))
			end
		end
	end

	for _, Instance in ipairs(CollectionService:GetTagged(Tag)) do
		Added(Instance)
	end
	CollectionService:GetInstanceAddedSignal(Tag):Connect(Added)
	CollectionService:GetInstanceRemovedSignal(Tag):Connect(Removed)
end

function WR_UITagDispatcher.start()
	for _, Module in ipairs(TAG_MODULES) do
		WireTagModule(Module)
	end
end

return WR_UITagDispatcher

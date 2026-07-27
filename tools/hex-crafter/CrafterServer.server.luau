-- Skill Tree Crafter — SERWER: remoty + DataStore (autozapis draftu). Narzedzie dev w tym place.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local saveEv = Instance.new("RemoteEvent")
saveEv.Name = "CrafterSave"
saveEv.Parent = ReplicatedStorage
local loadFn = Instance.new("RemoteFunction")
loadFn.Name = "CrafterLoad"
loadFn.Parent = ReplicatedStorage

local KEY = "tree_v1"
local store = nil
pcall(function()
	store = DataStoreService:GetDataStore("SkillCrafter")
end)

loadFn.OnServerInvoke = function()
	if not store then
		return { api = false }
	end
	local ok, data = pcall(function()
		return store:GetAsync(KEY)
	end)
	if ok then
		return { api = true, json = data }
	end
	return { api = false }
end

saveEv.OnServerEvent:Connect(function(_plr, json)
	if not store or type(json) ~= "string" then
		return
	end
	pcall(function()
		store:SetAsync(KEY, json)
	end)
end)

-- helper do odczytu draftu przez MCP: _G.CrafterDump() zwraca JSON z DataStore
_G.CrafterDump = function()
	if not store then
		return "NO_STORE"
	end
	local ok, data = pcall(function()
		return store:GetAsync(KEY)
	end)
	return (ok and data) or "ERR"
end
print("[Crafter] serwer gotowy (DataStore: " .. tostring(store ~= nil) .. ")")

--!strict
-- Server bootstrap. Rejestruje serwisy z ServerScriptService.Services i startuje Framework.
-- STUB szkieletu. Logika dojdzie z architektura.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Framework = require(ReplicatedStorage:WaitForChild("Framework"))

-- ROUND-TRIP MARKER (do usuniecia po weryfikacji sync):
print("[war-rng] server init OK — rojo/MCP sync round-trip")

-- Auto-rejestracja serwisow (gdy powstana w Services/):
local Services = ServerScriptService:FindFirstChild("Services")
if Services then
	for _, m in ipairs(Services:GetChildren()) do
		if m:IsA("ModuleScript") then
			local ok, svc = pcall(require, m)
			if ok and type(svc) == "table" then
				Framework.register(m.Name, svc)
			else
				warn("[war-rng] nie zaladowano serwisu: " .. m.Name)
			end
		end
	end
end

Framework.start()

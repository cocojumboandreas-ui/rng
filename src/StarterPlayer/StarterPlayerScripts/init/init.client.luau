--!strict
-- Client bootstrap. Rejestruje kontrolery z StarterPlayerScripts.Controllers i startuje Framework.
-- STUB szkieletu. Logika dojdzie z architektura.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Framework = require(ReplicatedStorage:WaitForChild("Framework"))

-- ROUND-TRIP MARKER (do usuniecia po weryfikacji sync):
print("[war-rng] client init OK — rojo/MCP sync round-trip")

local Controllers = script.Parent:FindFirstChild("Controllers")
if Controllers then
	for _, m in ipairs(Controllers:GetChildren()) do
		if m:IsA("ModuleScript") then
			local ok, ctrl = pcall(require, m)
			if ok and type(ctrl) == "table" then
				Framework.register(m.Name, ctrl)
			else
				warn("[war-rng] nie zaladowano kontrolera: " .. m.Name)
			end
		end
	end
end

Framework.start()

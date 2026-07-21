--!nocheck
-- Usun orphany (klony testowe *_TCLONE / *_SPCLONE / *_CLONE / *_OLD) zeby plac == dysk.
-- Kanoniczne 14 serwisow zostaje nietkniete. Uruchom przez StudioBridge:
--   .\Invoke-Studio.ps1 -File tools\clean_orphans.luau
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local SPS = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")

local canonicalServices = {
	ProfileService = true, StatProfileService = true, PlotService = true, EconomyService = true,
	InventoryService = true, IndexService = true, RollService = true, GridService = true,
	BuildService = true, CoreService = true, CombatService = true, WaveService = true,
	SkillService = true, PurchaseService = true,
}
local removed = {}

local services = SSS:FindFirstChild("Services")
if services then
	for _, c in ipairs(services:GetChildren()) do
		if not canonicalServices[c.Name] then
			removed[#removed + 1] = "Services." .. c.Name
			c:Destroy()
		end
	end
end

-- klony w innych folderach kodu (na wszelki wypadek)
local function cleanFolder(folder)
	if not folder then
		return
	end
	for _, c in ipairs(folder:GetChildren()) do
		if string.find(c.Name, "_TCLONE") or string.find(c.Name, "_SPCLONE") or string.find(c.Name, "_CLONE") or string.find(c.Name, "_OLD") then
			removed[#removed + 1] = folder.Name .. "." .. c.Name
			c:Destroy()
		end
	end
end
cleanFolder(RS:FindFirstChild("Framework"))
cleanFolder(RS.Content and RS.Content:FindFirstChild("Config"))
cleanFolder(RS:FindFirstChild("Shared"))
cleanFolder(SPS:FindFirstChild("Controllers"))

return { removed = removed, servicesNow = services and #services:GetChildren() or -1 }

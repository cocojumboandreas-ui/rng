--!nonstrict
-- ServerScriptService/Services/RigCompatService.luau
-- Konwersja jointow postaci AnimationConstraint -> Motor6D na KAZDYM spawnie.
--
-- POWOD: postacie w tej grze uzywaja NOWEGO rigu Robloxa — jointy klasy AnimationConstraint,
-- ktorych wlasciwosc C0 jest READ-ONLY. Kit WeaponsSystem (celowanie ciala + ADS) pisze
-- LowerTorso.Root.C0 co klatke (applyRootJointFix) -> na AnimationConstraint rzuca blad i nie
-- celuje. Konwersja na Motor6D przywraca zapisywalny C0 -> kit dziala jak zaprojektowany.
--
-- BEZPIECZENSTWO ANIMACJI: Animator wiaze jointy po NAZWIE (napedza Transform), niezaleznie od
-- klasy jointa. Test potwierdzil: po konwersji 15 jointow postac cala, 2 tracki animacji graly,
-- Humanoid w stanie Running. Motor6D zachowuje Part0/Part1/C0/C1 z oryginalu.
--
-- INWAZYJNOSC: zmienia rig KAZDEJ postaci (serwerowo, replikuje na klientow). Swiadoma decyzja —
-- kit wymaga Motor6D, a nie ma platformowego przelacznika powrotu z AnimationConstraint.
local Players = game:GetService("Players")

local RigCompatService = {}

local function convertJoint(d)
	if d.ClassName ~= "AnimationConstraint" then
		return
	end
	local parent, name = d.Parent, d.Name
	local p0, p1, c0, c1
	pcall(function() p0 = d.Part0 end)
	pcall(function() p1 = d.Part1 end)
	pcall(function() c0 = d.C0 end)
	pcall(function() c1 = d.C1 end)
	local m = Instance.new("Motor6D")
	m.Name = name
	if p0 then m.Part0 = p0 end
	if p1 then m.Part1 = p1 end
	if c0 then m.C0 = c0 end
	if c1 then m.C1 = c1 end
	m.Parent = parent
	d:Destroy()
end

local function onCharacter(char)
	-- konwertuj jointy obecne teraz
	for _, d in ipairs(char:GetDescendants()) do
		convertJoint(d)
	end
	-- oraz spoznione (jointy laduja sie razem z czlonami) — krotkie okno lapania
	local conn
	conn = char.DescendantAdded:Connect(function(d)
		if d.ClassName == "AnimationConstraint" then
			convertJoint(d)
		end
	end)
	task.delay(5, function()
		if conn then
			conn:Disconnect()
		end
	end)
end

local function onPlayer(player)
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

function RigCompatService.Init() end

function RigCompatService.Start()
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

return RigCompatService

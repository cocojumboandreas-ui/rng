--!nonstrict
-- SKILL TREE CRAFTER (klient) — narzedzie PROJEKTOWE. Buduj drzewo: klik wezel -> "+" w 6 kierunkach
-- dodaje dziecko. Panel: Nazwa / Opis / koszt (moneta) / koszt (kostka). Cofnij (undo), autozapis (DataStore).
-- Wynik odczytuje sie przez MCP (stan w _G lub DataStore). Przeciaganie tla = przesuwanie widoku.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local pg = LP:WaitForChild("PlayerGui")
local COIN = "rbxassetid://5684864491"
local DICE = "rbxassetid://92190657341460"

local DIRS = {
	{ name = "Gora", dx = 0, dy = -1 },
	{ name = "GoraPrawo", dx = 0.9, dy = -0.55 },
	{ name = "DolPrawo", dx = 0.9, dy = 0.55 },
	{ name = "Dol", dx = 0, dy = 1 },
	{ name = "DolLewo", dx = -0.9, dy = 0.55 },
	{ name = "GoraLewo", dx = -0.9, dy = -0.55 },
}
local DIRV = {}
for _, d in ipairs(DIRS) do DIRV[d.name] = { d.dx, d.dy } end
local SP = 150
local NODE = 100
local function shortNum(x)
	x = x or 0
	if x >= 1e9 then return string.format("%.1fB", x / 1e9) end
	if x >= 1e6 then return string.format("%.1fM", x / 1e6) end
	if x >= 1e3 then return string.format("%.1fK", x / 1e3) end
	return tostring(math.floor(x))
end

-- ── stan ──
local nodes = {}
local selId = nil
local history = {}
local nextId = 1
local panX, panY = 0, 0

local function dcopy(t)
	local r = {}
	for k, v in pairs(t) do r[k] = (type(v) == "table") and dcopy(v) or v end
	return r
end

-- ── autozapis ──
local saveEv = ReplicatedStorage:WaitForChild("CrafterSave", 10)
local loadFn = ReplicatedStorage:WaitForChild("CrafterLoad", 10)
local statusLbl
local _pending = false
local apiOn = false
local function serialize()
	return HttpService:JSONEncode({ nodes = nodes, nextId = nextId })
end
local function autosave()
	_G.CrafterState = serialize() -- do odczytu przez MCP w kazdej chwili
	if _pending then return end
	_pending = true
	task.delay(0.5, function()
		_pending = false
		if saveEv then pcall(function() saveEv:FireServer(serialize()) end) end
		if statusLbl then statusLbl.Text = apiOn and "zapisano ✓" or "SESJA (API off — nie zapisze po restarcie)" end
	end)
end
local function pushHistory()
	history[#history + 1] = { nodes = dcopy(nodes), nextId = nextId }
	if #history > 80 then table.remove(history, 1) end
end

-- pozycja wezla wzgledem roota (px)
local function posOf(id)
	local n = nodes[id]
	if not n or not n.parentId then return 0, 0 end
	local px, py = posOf(n.parentId)
	local v = DIRV[n.dir] or { 0, 1 }
	return px + v[1] * SP, py + v[2] * SP
end
local function dirTaken(pid, dirName)
	for _, n in pairs(nodes) do
		if n.parentId == pid and n.dir == dirName then return true end
	end
	return false
end

-- ── GUI ──
local gui = Instance.new("ScreenGui")
gui.Name = "WR_Crafter"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.Parent = pg

local canvas = Instance.new("Frame")
canvas.Size = UDim2.fromScale(1, 1); canvas.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
canvas.BorderSizePixel = 0; canvas.Active = true; canvas.Parent = gui
local world = Instance.new("Frame")
world.Size = UDim2.fromScale(1, 1); world.BackgroundTransparency = 1; world.Parent = canvas

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 40); bar.BackgroundColor3 = Color3.fromRGB(16, 18, 24); bar.BorderSizePixel = 0; bar.Parent = gui
local function tbBtn(txt, x, w, col)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, 30); b.Position = UDim2.fromOffset(x, 5)
	b.BackgroundColor3 = col or Color3.fromRGB(50, 54, 66); b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold; b.TextSize = 14; b.Text = txt; b.Parent = bar
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
	return b
end
local undoBtn = tbBtn("Cofnij", 176, 90)
statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.fromOffset(300, 30); statusLbl.Position = UDim2.fromOffset(276, 5)
statusLbl.BackgroundTransparency = 1; statusLbl.TextColor3 = Color3.fromRGB(150, 200, 150)
statusLbl.Font = Enum.Font.Gotham; statusLbl.TextSize = 13; statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Text = ""; statusLbl.Parent = bar
local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.fromOffset(420, 30); titleLbl.Position = UDim2.new(1, -428, 0, 5)
titleLbl.BackgroundTransparency = 1; titleLbl.TextColor3 = Color3.fromRGB(255, 215, 90)
titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 13; titleLbl.TextXAlignment = Enum.TextXAlignment.Right
titleLbl.Text = "SKILL TREE CRAFTER  —  klik wezel, potem + w kierunku"; titleLbl.Parent = bar

-- panel edycji
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(280, 300); panel.Position = UDim2.new(1, -292, 1, -312)
panel.BackgroundColor3 = Color3.fromRGB(30, 33, 42); panel.BorderSizePixel = 0; panel.Visible = false; panel.Parent = gui
local pcn = Instance.new("UICorner"); pcn.CornerRadius = UDim.new(0, 10); pcn.Parent = panel
local pst = Instance.new("UIStroke"); pst.Color = Color3.fromRGB(255, 215, 90); pst.Thickness = 1.5; pst.Transparency = 0.4; pst.Parent = panel
local function pLabel(txt, y)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -20, 0, 16); l.Position = UDim2.fromOffset(12, y); l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold; l.TextSize = 12; l.TextColor3 = Color3.fromRGB(170, 175, 190)
	l.TextXAlignment = Enum.TextXAlignment.Left; l.Text = txt; l.Parent = panel
end
local function pBox(y, h)
	local b = Instance.new("TextBox")
	b.Size = UDim2.new(1, -24, 0, h); b.Position = UDim2.fromOffset(12, y); b.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	b.TextColor3 = Color3.new(1, 1, 1); b.Font = Enum.Font.Gotham; b.TextSize = 14; b.ClearTextOnFocus = false
	b.Text = ""; b.TextXAlignment = Enum.TextXAlignment.Left; b.TextYAlignment = Enum.TextYAlignment.Top
	b.TextWrapped = true; b.Parent = panel
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
	return b
end
pLabel("Nazwa", 10)
local nameBox = pBox(28, 30)
pLabel("Opis", 64)
local descBox = pBox(82, 96); descBox.MultiLine = true
pLabel("Koszt (moneta / kostka)", 186)
local coinIc = Instance.new("ImageLabel")
coinIc.Size = UDim2.fromOffset(22, 22); coinIc.Position = UDim2.fromOffset(12, 208); coinIc.BackgroundTransparency = 1; coinIc.Image = COIN; coinIc.Parent = panel
local coinBox = pBox(206, 26); coinBox.Size = UDim2.fromOffset(84, 26); coinBox.Position = UDim2.fromOffset(40, 206); coinBox.Text = "0"
local diceIc = Instance.new("ImageLabel")
diceIc.Size = UDim2.fromOffset(22, 22); diceIc.Position = UDim2.fromOffset(146, 208); diceIc.BackgroundTransparency = 1; diceIc.Image = DICE; diceIc.Parent = panel
local diceBox = pBox(206, 26); diceBox.Size = UDim2.fromOffset(84, 26); diceBox.Position = UDim2.fromOffset(174, 206); diceBox.Text = "0"
local deleteBtn = Instance.new("TextButton")
deleteBtn.Size = UDim2.new(1, -24, 0, 34); deleteBtn.Position = UDim2.fromOffset(12, 250); deleteBtn.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
deleteBtn.TextColor3 = Color3.new(1, 1, 1); deleteBtn.Font = Enum.Font.GothamBold; deleteBtn.TextSize = 14; deleteBtn.Text = "Usun wezel (+ dzieci)"; deleteBtn.Parent = panel
local dcc = Instance.new("UICorner"); dcc.CornerRadius = UDim.new(0, 6); dcc.Parent = deleteBtn

-- ── logika (forward decl) ──
local render, selectNode, addNode

function selectNode(id)
	selId = id
	local n = nodes[id]
	panel.Visible = (n ~= nil)
	if n then
		nameBox.Text = n.label or ""
		descBox.Text = n.desc or ""
		coinBox.Text = tostring(n.coin or 0)
		diceBox.Text = tostring(n.roll or 0)
		deleteBtn.Visible = (n.parentId ~= nil)
	end
	render()
end

function addNode(parentId, dirName)
	pushHistory()
	local id = "n" .. nextId
	nextId += 1
	nodes[id] = { id = id, parentId = parentId, dir = dirName, label = "", desc = "", coin = 0, roll = 0 }
	autosave()
	selectNode(id)
end

local function deleteNode(id)
	local n = id and nodes[id]
	if not n or not n.parentId then return end
	pushHistory()
	local toDel = {}
	local function collect(x)
		toDel[x] = true
		for cid, cn in pairs(nodes) do
			if cn.parentId == x then collect(cid) end
		end
	end
	collect(id)
	for x in pairs(toDel) do nodes[x] = nil end
	selId = nil; panel.Visible = false
	autosave(); render()
end

local function applyEdits()
	local n = selId and nodes[selId]
	if not n then return end
	n.label = nameBox.Text
	n.desc = descBox.Text
	n.coin = tonumber(coinBox.Text) or 0
	n.roll = tonumber(diceBox.Text) or 0
	autosave(); render()
end

function render()
	world:ClearAllChildren()
	local vp = world.AbsoluteSize
	local cx, cy = vp.X / 2 + panX, vp.Y / 2 + panY
	-- polaczenia
	for id, n in pairs(nodes) do
		if n.parentId and nodes[n.parentId] then
			local x1, y1 = posOf(id)
			local x2, y2 = posOf(n.parentId)
			local ax, ay, bx, by = cx + x1, cy + y1, cx + x2, cy + y2
			local dx, dy = ax - bx, ay - by
			local len = math.sqrt(dx * dx + dy * dy)
			local line = Instance.new("Frame")
			line.AnchorPoint = Vector2.new(0.5, 0.5); line.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
			line.Size = UDim2.fromOffset(len, 4); line.Rotation = math.deg(math.atan2(dy, dx))
			line.BackgroundColor3 = Color3.fromRGB(80, 88, 110); line.BorderSizePixel = 0; line.ZIndex = 1; line.Parent = world
		end
	end
	-- wezly
	for id, n in pairs(nodes) do
		local x, y = posOf(id)
		local nx, ny = cx + x, cy + y
		local btn = Instance.new("TextButton")
		btn.AnchorPoint = Vector2.new(0.5, 0.5); btn.Position = UDim2.fromOffset(nx, ny); btn.Size = UDim2.fromOffset(NODE, NODE)
		btn.BackgroundColor3 = (id == selId) and Color3.fromRGB(70, 130, 220) or Color3.fromRGB(46, 112, 190)
		btn.AutoButtonColor = true; btn.Text = ""; btn.ZIndex = 3; btn.Parent = world
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = btn
		if id == selId then
			local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(255, 220, 90); st.Thickness = 3; st.Parent = btn
		end
		local lab = Instance.new("TextLabel")
		lab.Size = UDim2.new(1, -8, 0, 44); lab.Position = UDim2.fromOffset(4, 8); lab.BackgroundTransparency = 1
		lab.Font = Enum.Font.GothamBold; lab.TextSize = 13; lab.TextColor3 = Color3.new(1, 1, 1); lab.TextWrapped = true
		lab.Text = (n.label ~= "" and n.label) or (n.parentId and "(bez nazwy)" or "ROOT"); lab.ZIndex = 4; lab.Parent = btn
		if n.parentId then
			local ci = Instance.new("ImageLabel")
			ci.Size = UDim2.fromOffset(15, 15); ci.Position = UDim2.new(0, 6, 1, -22); ci.BackgroundTransparency = 1; ci.Image = COIN; ci.ZIndex = 4; ci.Parent = btn
			local cl = Instance.new("TextLabel")
			cl.Size = UDim2.fromOffset(30, 16); cl.Position = UDim2.new(0, 22, 1, -22); cl.BackgroundTransparency = 1; cl.Font = Enum.Font.GothamBold; cl.TextSize = 12; cl.TextColor3 = Color3.fromRGB(255, 220, 120); cl.TextXAlignment = Enum.TextXAlignment.Left; cl.Text = shortNum(n.coin or 0); cl.ZIndex = 4; cl.Parent = btn; ci.Visible = (n.coin or 0) > 0; cl.Visible = ci.Visible
			local di = Instance.new("ImageLabel")
			di.Size = UDim2.fromOffset(15, 15); di.Position = UDim2.new(0.5, 4, 1, -22); di.BackgroundTransparency = 1; di.Image = DICE; di.ZIndex = 4; di.Parent = btn
			local dl = Instance.new("TextLabel")
			dl.Size = UDim2.fromOffset(28, 16); dl.Position = UDim2.new(0.5, 20, 1, -22); dl.BackgroundTransparency = 1; dl.Font = Enum.Font.GothamBold; dl.TextSize = 12; dl.TextColor3 = Color3.fromRGB(180, 220, 255); dl.TextXAlignment = Enum.TextXAlignment.Left; dl.Text = shortNum(n.roll or 0); dl.ZIndex = 4; dl.Parent = btn; di.Visible = (n.roll or 0) > 0; dl.Visible = di.Visible
		end
		btn.MouseButton1Click:Connect(function() selectNode(id) end)
		if id == selId then
			for _, d in ipairs(DIRS) do
				if not dirTaken(id, d.name) then
					local plus = Instance.new("TextButton")
					plus.AnchorPoint = Vector2.new(0.5, 0.5)
					plus.Position = UDim2.fromOffset(nx + d.dx * (SP * 0.6), ny + d.dy * (SP * 0.6))
					plus.Size = UDim2.fromOffset(30, 30); plus.BackgroundColor3 = Color3.fromRGB(60, 180, 90)
					plus.Text = "+"; plus.TextColor3 = Color3.new(1, 1, 1); plus.Font = Enum.Font.GothamBold; plus.TextSize = 22; plus.ZIndex = 6; plus.Parent = world
					local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(1, 0); pc.Parent = plus
					plus.MouseButton1Click:Connect(function() addNode(id, d.name) end)
				end
			end
		end
	end
end

nameBox.FocusLost:Connect(applyEdits)
descBox.FocusLost:Connect(applyEdits)
coinBox.FocusLost:Connect(applyEdits)
diceBox.FocusLost:Connect(applyEdits)
deleteBtn.MouseButton1Click:Connect(function() deleteNode(selId) end)
undoBtn.MouseButton1Click:Connect(function()
	local h = table.remove(history)
	if not h then statusLbl.Text = "brak cofania"; return end
	nodes = h.nodes; nextId = h.nextId; selId = nil; panel.Visible = false
	autosave(); render(); statusLbl.Text = "cofnieto"
end)

-- pan (przeciaganie tla)
local dragging, lastM = false, nil
canvas.InputBegan:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true; lastM = Vector2.new(inp.Position.X, inp.Position.Y)
	end
end)
UserInputService.InputChanged:Connect(function(inp)
	if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
		local m = Vector2.new(inp.Position.X, inp.Position.Y)
		panX += (m.X - lastM.X); panY += (m.Y - lastM.Y); lastM = m; render()
	end
end)
UserInputService.InputEnded:Connect(function(inp)
	if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
world:GetPropertyChangedSignal("AbsoluteSize"):Connect(render)
_G.Crafter = { select = selectNode, add = addNode, del = deleteNode, dump = serialize } -- hook testowy (MCP)

-- ── ladowanie ──
task.spawn(function()
	local res = loadFn and loadFn:InvokeServer()
	apiOn = (type(res) == "table" and res.api == true)
	if type(res) == "table" and res.json then
		local ok, data = pcall(function() return HttpService:JSONDecode(res.json) end)
		if ok and data and data.nodes then nodes = data.nodes; nextId = data.nextId or 1 end
	end
	if not next(nodes) then
		nodes["root"] = { id = "root", parentId = nil, dir = nil, label = "DRZEWO", desc = "", coin = 0, roll = 0 }
		nextId = 1
	end
	if res and res.api == false then
		statusLbl.Text = "DataStore OFF (wlacz API w Game Settings) - praca w tej sesji"
		statusLbl.TextColor3 = Color3.fromRGB(255, 180, 90)
	end
	render()
end)

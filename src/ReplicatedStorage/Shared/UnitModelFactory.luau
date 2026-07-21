--!nonstrict
-- Shared/UnitModelFactory.luau — JEDNO zrodlo modelu jednostki (server + client).
-- get(unitId) -> template Model:
--   1) jesli RS.Assets.Units[<config.model>] istnieje -> zwroc ten (place-owned, prawdziwy model);
--   2) inaczej ZBUDUJ z kodu placeholder wg config.kind (Enums.UnitKind), teksturowany kolorem tieru:
--        Block  -> jeden zakotwiczony Part (~kafel 6x6, wysokosc ~8);
--        Weapon -> prostopadloscienny korpus (~2x2x5) + mala lufa, zbudowany FRONTEM na +Z
--                  (renderer nakłada faceDirection).
-- Placeholdery budowane w RUNTIME (jak model-agnostyczny renderer wrogow), cache per unitId.
-- Zwracany Model to TEMPLATE (parent=nil) — wolajacy KLONUJE przed uzyciem.
-- NIE tworzy niczego w RS.Assets.Units i nie rusza RNG_MAP/Units/WR_* (place-owned).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared:WaitForChild("Enums"))
local GameConfig = require(
	ReplicatedStorage:WaitForChild("Content"):WaitForChild("Config"):WaitForChild("GameConfig")
)

local UnitModelFactory = {}

local _cache: { [string]: Model } = {} -- placeholder templates per unitId (parent=nil)

-- kolor wg tieru rzadkosci (ta sama paleta co reveal klienta: common->legendary)
local TIER_COLOR = {
	[1] = Color3.fromRGB(185, 185, 195),
	[2] = Color3.fromRGB(90, 200, 120),
	[3] = Color3.fromRGB(90, 160, 255),
	[4] = Color3.fromRGB(195, 110, 255),
	[5] = Color3.fromRGB(255, 205, 80),
}

local function tierColor(rarityN: number): Color3
	for _, t in ipairs(GameConfig.Rarity.tiers) do
		if rarityN <= t.maxN then
			return TIER_COLOR[t.revealTier] or TIER_COLOR[1]
		end
	end
	return TIER_COLOR[5]
end

local function mkPart(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.Color = color
	return p
end

-- Blok: jeden Part wielkosci kafla (GridConfig.cellSize), wysokosc ~8, kolor tieru.
local function buildBlock(u): Model
	local color = tierColor(u.rarityN)
	local cs = GameConfig.Grid.cellSize or 6
	local model = Instance.new("Model")
	local part = mkPart("Block", Vector3.new(cs * 0.92, 8, cs * 0.92), color)
	part.Material = Enum.Material.Concrete
	part.CFrame = CFrame.new(0, 0, 0)
	part.Parent = model
	model.PrimaryPart = part
	return model
end

-- Bron: korpus ~2x2x5 + mala lufa z przodu (+Z). faceDirection nakłada renderer.
local function buildWeapon(u): Model
	local color = tierColor(u.rarityN)
	local model = Instance.new("Model")
	local body = mkPart("Body", Vector3.new(2, 2, 5), color)
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	local barrel = mkPart("Barrel", Vector3.new(0.6, 0.6, 3), color:Lerp(Color3.new(0, 0, 0), 0.35))
	barrel.CFrame = CFrame.new(0, 0.3, 2.5 + 1.5) -- przed korpusem, na +Z
	barrel.Parent = model
	model.PrimaryPart = body
	return model
end

-- get(unitId) -> template Model (prawdziwy z Assets albo placeholder). nil gdy nieznany unit.
function UnitModelFactory.get(unitId: string): Model?
	local u = GameConfig.Units[unitId]
	if not u then
		return nil
	end

	-- 1) prawdziwy model z place-owned Assets.Units (klucz = config.model, nie unitId)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local unitsFolder = assets and assets:FindFirstChild("Units")
	if u.model and unitsFolder then
		local real = unitsFolder:FindFirstChild(u.model)
		if real then
			return real
		end
	end

	-- 2) placeholder (cache per unitId)
	if _cache[unitId] then
		return _cache[unitId]
	end
	local kind = u.kind
	local model
	if kind == Enums.UnitKind.Block then
		model = buildBlock(u)
	else -- Weapon (i domyslnie: cokolwiek innego dostaje ksztalt broni)
		model = buildWeapon(u)
	end
	model.Name = u.displayName or unitId
	_cache[unitId] = model
	return model
end

return UnitModelFactory

--[[
	WandServer/MatterService — MATIÈRE & ENVIRONNEMENT
	Toute matière (décor de la map OU matière créée par un sort : branches, murs de glace) est une
	entité avec un ÉLÉMENT, une SORTE et des POINTS DE VIE proportionnels à sa taille.

	  • Élément de la matière : attribut "Matter" (prioritaire) sinon déduit du MATÉRIAU Roblox
	    (herbe/bois = Nature, pierre = Earth, métal = Steel, glace = Ice...). Le Terrain aussi.
	  • Dégâts reçus = dégâts du sort × AFFINITÉ[élément du sort][élément de la matière].
	  • Réactions : le feu ENFLAMME la nature (et se propage sur les surfaces qui brûlent), la glace
	    ÉTEINT le feu, la foudre a une chance d'enflammer le bois/l'herbe et se PROPAGE dans le métal,
	    le toxique s'embrase au contact du feu, les explosions ARRACHENT la pierre (cratères).
	  • Attributs de map : "Indestructible" = true protège une pièce ; "Matter" / "MatterKind" forcent
	    sa nature.
]]

local VoxelBreak = require(script.Parent:WaitForChild("VoxelBreak"))
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MatterService = {}

local Combat, FXBus
local rng = Random.new()

-- ══ 1. TABLE DES AFFINITÉS (élément du SORT -> élément de la MATIÈRE) ═══════════════════════════════
-- > 1 = super efficace, < 1 = peu efficace, 0 = aucun effet. Absent = 1.
-- (défini dans WandShared/Elements/<Élément>.Affinity)
local Elements = require(game:GetService("ReplicatedStorage").WandShared.Elements)
MatterService.AFFINITY = Elements.Field("Affinity")
-- COMPORTEMENTS déclarés par les éléments : IgnitesMatter, IgniteChance, Extinguishes, ConductsInSteel
local B = Elements.Behavior
local function affinity(attack: string?, matter: string): number
	local def = attack and Elements[attack]
	if def and def.RandomAffinity then
		return rng:NextNumber(0.5, 2)
	end
	local row = MatterService.AFFINITY[attack or ""]
	return row and row[matter] or 1
end
MatterService.Affinity = affinity

-- ══ 2. MATÉRIAUX -> (élément, sorte) ══════════════════════════════════════════════════════════════
local MAT: { [Enum.Material]: { string } } = {}
local function setMat(list, element, kind)
	for _, name in list do
		local ok, mat = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		if ok and mat then
			MAT[mat] = { element, kind }
		end
	end
end
setMat({ "Grass", "LeafyGrass" }, "Nature", "Grass")
setMat({ "Wood", "WoodPlanks", "Fabric", "Cardboard" }, "Nature", "Wood")
setMat({ "Slate", "Rock", "Basalt", "Granite", "Limestone", "Sandstone", "Cobblestone", "Brick", "Concrete",
	"Pavement", "Marble", "Pebble", "CrackedLava", "Asphalt", "Ground", "Mud", "Sand", "Salt" }, "Earth", "Stone")
setMat({ "Metal", "DiamondPlate", "CorrodedMetal", "Foil" }, "Steel", "Metal")
setMat({ "Ice", "Glacier", "Snow" }, "Ice", "Ice")
setMat({ "Glass" }, "Ice", "Glass")
MatterService.Materials = MAT

-- Sortes : multiplicateur de PV, inflammable, destructible
local KIND = {
	Surface = { HP = 0, Destructible = false }, -- tapis d'herbe : brûle (se carbonise) mais ne casse pas
	Leaves = { HP = 0.45 },
	Wood = { HP = 1 },
	Branch = { HP = 1 },
	Stone = { HP = 2.4 },
	Metal = { HP = 4 },
	Ice = { HP = 0.9 },
	Glass = { HP = 0.3 },
}
-- L'HERBE NE BRÛLE PLUS (user 2026-11-22) : seul le bois prend feu
local FLAMMABLE_TERRAIN = { [Enum.Material.WoodPlanks] = true }
local BURNT_TERRAIN = Enum.Material.Ground

-- ══ 3. REGISTRE ════════════════════════════════════════════════════════════════════════════════════
type Rec = { Element: string, Kind: string, HP: number, Max: number, Indestructible: boolean, OnBreak: ((BasePart, string?) -> ())?, Spell: boolean, LastFx: number, LastReact: number }
local recs: { [BasePart]: Rec } = {}
local ignore: { Instance } = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude

local scorchFolder: Folder
local IGNORED_FOLDERS = { "WandProjectiles", "WandZoneMarkers", "WandScorch", "WandDummies", "WandSparks_Local", "WandFX_Local", "WandLights_Local" }

local function refreshFilter()
	table.clear(ignore)
	for _, name in IGNORED_FOLDERS do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	overlap.FilterDescendantsInstances = ignore
end

local function hpFor(part: BasePart, kind: string): number
	local s = part.Size
	local v = math.max(0.2, s.X * s.Y * s.Z)
	return math.clamp(20 * v ^ 0.6 * (KIND[kind] and KIND[kind].HP or 1), 10, 8000)
end

local function classify(part: BasePart): (string?, string?)
	local forced = part:GetAttribute("Matter")
	if type(forced) == "string" then
		return forced, part:GetAttribute("MatterKind") or (if forced == "Nature" then "Wood" elseif forced == "Earth" then "Stone" elseif forced == "Steel" then "Metal" elseif forced == "Ice" then "Ice" else "Wood")
	end
	local m = MAT[part.Material]
	if not m then
		return nil, nil
	end
	local kind = m[2]
	if kind == "Grass" then
		local s = part.Size
		kind = if math.min(s.X, s.Y, s.Z) >= 1.5 then "Leaves" else "Surface"
	end
	return m[1], kind
end

local function isCharacter(inst: Instance): boolean
	local model = inst:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

-- enregistrement d'une matière de SORT (branche, bloc de glace...)
-- Pool (optionnel) : UNE barre de vie partagée par toute une structure (arbre entier) ; chaque pièce
-- ajoutée l'agrandit, et la structure cède d'un bloc quand le pool est vide.
-- OnDamage (optionnel) : la matière d'un SORT ne perd pas de PV, elle perd de la DURÉE de vie
-- (dégâts × LIFE_PER_DAMAGE secondes, après affinité) -> callback(secondes, élément)
MatterService.LIFE_PER_DAMAGE = 0.02 -- (0,05 détruisait les arbres trop vite)
function MatterService.Register(part: BasePart, info: { Element: string, Kind: string?, HP: number?, OnBreak: ((BasePart, string?) -> ())?, Pool: any?, OnDamage: ((number, string?) -> ())? })
	local kind = info.Kind or "Branch"
	local hp = info.HP or hpFor(part, kind)
	if info.Pool then
		info.Pool.HP += hp
		info.Pool.Max += hp
	end
	recs[part] = { Element = info.Element, Kind = kind, HP = hp, Max = hp, Indestructible = false, OnBreak = info.OnBreak, Spell = true, LastFx = 0, LastReact = 0, Pool = info.Pool, OnDamage = info.OnDamage } :: any
	part.Destroying:Once(function()
		recs[part] = nil
	end)
end

local function recordOf(part: BasePart): Rec?
	local r = recs[part]
	if r then
		return r
	end
	if not part:IsA("BasePart") or isCharacter(part) then
		return nil
	end
	local element, kind = classify(part)
	if not element then
		return nil
	end
	local s = part.Size
	local massive = math.max(s.X, s.Y, s.Z) > 80 or s.X * s.Y * s.Z > 20000
	local indestructible = part:GetAttribute("Indestructible") == true or massive or (KIND[kind] and KIND[kind].Destructible == false)
	local hp = hpFor(part, kind)
	r = { Element = element, Kind = kind, HP = hp, Max = hp, Indestructible = indestructible, Spell = false, LastFx = 0, LastReact = 0 }
	recs[part] = r
	part.Destroying:Once(function()
		recs[part] = nil
	end)
	return r
end
MatterService.RecordOf = recordOf

-- ══ 4. FEU : cellules qui brûlent sur les SURFACES et se propagent ═════════════════════════════════════
local CELL = 3 -- taille d'une cellule de feu (studs)
local MAX_CELLS = 140
local BURN_TIME = { 4, 6.5 }
local SPREAD_EVERY = { 0.45, 0.9 }
local CELL_DPS = 10 -- dégâts de feu par seconde sur la matière sous la cellule
type Cell = { Id: number, Key: string, Pos: Vector3, Normal: Vector3, Part: BasePart?, Sub: BasePart?, Terrain: boolean, T: number, Next: number, HurtT: number }
local cells: { [string]: Cell } = {}
local cellCount = 0
local nextCellId = 0
local burnt: { [string]: boolean } = {}
local wet: { [string]: number } = {}
local scorchCount = 0

local function cellKey(pos: Vector3, n: Vector3): string
	local q = CELL
	-- l'orientation fait partie de la clé : le dessus et le flanc d'une poutre brûlent séparément
	return string.format("%d,%d,%d|%d,%d,%d", math.floor(pos.X / q + 0.5), math.floor(pos.Y / q + 0.5), math.floor(pos.Z / q + 0.5),
		math.floor(n.X + 0.5), math.floor(n.Y + 0.5), math.floor(n.Z + 0.5))
end

-- la surface touchée peut-elle brûler ?
local function flammableHit(inst: Instance?, material: Enum.Material?): (boolean, BasePart?, boolean)
	if not inst then
		return false, nil, false
	end
	if inst:IsA("Terrain") then
		return material ~= nil and FLAMMABLE_TERRAIN[material] == true, nil, true
	end
	if not inst:IsA("BasePart") then
		return false, nil, false
	end
	local r = recordOf(inst)
	-- herbe (tapis « Surface » ou bloc « Leaves ») : ne brûle plus ; le bois (Nature) oui
	return r ~= nil and r.Element == "Nature" and r.Kind ~= "Surface" and r.Kind ~= "Leaves", inst, false
end

local function tangentBasis(n: Vector3): (Vector3, Vector3)
	local t = n:Cross(Vector3.yAxis)
	if t.Magnitude < 0.1 then
		t = n:Cross(Vector3.xAxis)
	end
	t = t.Unit
	return t, n:Cross(t).Unit
end

-- trace de brûlure SOUDÉE à sa pièce : elle disparaît / tombe avec elle (jamais de plaque qui flotte)
local function scorch(pos: Vector3, n: Vector3, on: BasePart)
	if scorchCount > 1500 then
		return
	end
	scorchCount += 1
	local t, b = tangentBasis(n)
	local p = Instance.new("Part")
	p.Name = "Scorch"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Slate
	local shade = rng:NextNumber(0.07, 0.13)
	p.Color = Color3.new(shade, shade * 0.85, shade * 0.7)
	local s = CELL * rng:NextNumber(1, 1.25)
	p.Size = Vector3.new(s, 0.06, s)
	local rot = rng:NextNumber(0, math.pi * 2)
	local right = t * math.cos(rot) + b * math.sin(rot)
	p.CFrame = CFrame.fromMatrix(pos + n * (0.03 + rng:NextNumber(0, 0.02)), right, n)
	p.Anchored = false
	p.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = on
	w.Part1 = p
	w.Parent = p
	p.Parent = on
	p.Destroying:Once(function()
		scorchCount -= 1
	end)
end

local function igniteAt(pos: Vector3, n: Vector3, part: BasePart?, terrain: boolean): boolean
	if cellCount >= MAX_CELLS then
		return false
	end
	local key = cellKey(pos, n)
	if cells[key] or burnt[key] then
		return false
	end
	if wet[key] and wet[key] > os.clock() then
		return false
	end
	-- matière toxique : elle ne brûle pas, elle S'EMBRASE (explosion de gaz)
	if part then
		local r = recordOf(part)
		if r and r.Element == "Toxic" then
			if os.clock() - r.LastReact > 1 then
				r.LastReact = os.clock()
				task.defer(Combat.Explode, pos, 6, 18, nil, "Fire")
				FXBus.Push({ k = "Impact", p = pos, n = n, e = "Fire", r = 6, s = 1, x = true, z = 1.4 })
			end
			return false
		end
	end
	nextCellId += 1
	local cell: Cell = { Id = nextCellId, Key = key, Pos = pos, Normal = n, Part = part, Terrain = terrain,
		T = rng:NextNumber(BURN_TIME[1], BURN_TIME[2]), Next = rng:NextNumber(0.2, 0.5), HurtT = 0 }
	-- tapis d'herbe (ne casse pas) : c'est son SUPPORT qui se consume (planche, poutre...)
	if part then
		local r = recordOf(part)
		if r and r.Kind == "Surface" then
			local res = workspace:Raycast(pos - n * 0.05, -n * (math.min(part.Size.X, part.Size.Y, part.Size.Z) + 1.2), params)
			if res and res.Instance ~= part and res.Instance:IsA("BasePart") then
				cell.Sub = res.Instance
			end
		end
	end
	cells[key] = cell
	cellCount += 1
	FXBus.Push({ k = "Ign", i = cell.Id, p = pos, n = n })
	return true
end

-- allume le feu au point d'impact (si la surface est inflammable)
function MatterService.Ignite(pos: Vector3, n: Vector3?, inst: Instance?, material: Enum.Material?)
	local ok, part, terrain = flammableHit(inst, material)
	if ok then
		return igniteAt(pos, n or Vector3.yAxis, part, terrain)
	end
	return false
end

-- sonde le décor autour d'un point et allume ce qui peut brûler (souffle de feu, branche de feu...)
function MatterService.IgniteAround(pos: Vector3, radius: number, tries: number)
	for _ = 1, tries do
		local dir = rng:NextUnitVector()
		if dir.Y > 0.3 then
			dir = Vector3.new(dir.X, -dir.Y, dir.Z) -- surtout vers le bas : le sol prend feu
		end
		local res = workspace:Raycast(pos, dir * radius, params)
		if res then
			MatterService.Ignite(res.Position, res.Normal, res.Instance, res.Material)
		end
	end
end

-- éteint le feu dans un rayon ; les cellules éteintes restent MOUILLÉES quelques secondes
function MatterService.Extinguish(pos: Vector3, radius: number): number
	local n = 0
	for key, cell in cells do
		if (cell.Pos - pos).Magnitude <= radius then
			cells[key] = nil
			cellCount -= 1
			wet[key] = os.clock() + 8
			n += 1
			FXBus.Push({ k = "IgnEnd", i = cell.Id, p = cell.Pos, w = 1 })
		end
	end
	return n
end

-- trouve la surface voisine dans une direction : sur le même plan, au coin intérieur (mur qui monte)
-- ou au coin extérieur (le feu passe par-dessus l'arête et descend sur le flanc)
local function probe(cell: Cell, dir: Vector3): RaycastResult?
	local p, n = cell.Pos, cell.Normal
	local inner = workspace:Raycast(p + n * 0.6, dir * CELL, params)
	if inner then
		return inner
	end
	local flat = workspace:Raycast(p + dir * CELL + n * 1.2, -n * 2.6, params)
	if flat then
		return flat
	end
	return workspace:Raycast(p + dir * CELL * 0.8 - n * 1.2, -dir * CELL, params)
end

local function spread(cell: Cell)
	local t, b = tangentBasis(cell.Normal)
	for _ = 1, 2 do
		local a = rng:NextNumber(0, math.pi * 2)
		local dir = t * math.cos(a) + b * math.sin(a)
		-- sur une paroi verticale, les flammes MONTENT plus volontiers
		if math.abs(cell.Normal.Y) < 0.5 and rng:NextNumber() < 0.55 then
			local up = (Vector3.yAxis - cell.Normal * cell.Normal.Y)
			if up.Magnitude > 0.1 then
				dir = (up.Unit + dir * 0.4).Unit
			end
		end
		if rng:NextNumber() < 0.75 then
			local res = probe(cell, dir)
			if res then
				MatterService.Ignite(res.Position, res.Normal, res.Instance, res.Material)
			end
		end
	end
end

local function burnOut(cell: Cell)
	cells[cell.Key] = nil
	cellCount -= 1
	burnt[cell.Key] = true
	if cell.Terrain then
		-- l'herbe du terrain devient de la terre brûlée
		local region = Region3.new(cell.Pos - Vector3.new(2, 2, 2), cell.Pos + Vector3.new(2, 2, 2)):ExpandToGrid(4)
		workspace.Terrain:ReplaceMaterial(region, 4, Enum.Material.Grass, BURNT_TERRAIN)
		workspace.Terrain:ReplaceMaterial(region, 4, Enum.Material.LeafyGrass, BURNT_TERRAIN)
	elseif cell.Part and cell.Part.Parent then
		scorch(cell.Pos, cell.Normal, cell.Part)
	end
	FXBus.Push({ k = "IgnEnd", i = cell.Id, p = cell.Pos })
end

-- ══ 5. DÉGÂTS, CASSE, EFFONDREMENT ═════════════════════════════════════════════════════════════════════
local function breakPart(part: BasePart, r: Rec, element: string?)
	recs[part] = nil
	local pos, size = part.Position, part.Size
	if r.OnBreak then
		local ok, err = pcall(r.OnBreak, part, element)
		if not ok then
			warn("[Matter] OnBreak :", err)
		end
	else
		FXBus.Push({ k = "MBreak", p = pos, sz = size, c = part.Color:ToHex(), m = r.Kind, e = r.Element, a = element })
		-- ce qui reposait dessus et n'a plus d'appui TOMBE (branches, feuillage, planches, tapis d'herbe)
		local top = CFrame.new(pos + Vector3.new(0, size.Y / 2 + 0.6, 0))
		local above = workspace:GetPartBoundsInBox(top, Vector3.new(size.X + 0.4, 1.4, size.Z + 0.4), overlap)
		part:Destroy()
		for _, q in above do
			if q.Anchored and q ~= part and q.Parent and not isCharacter(q) then
				local qr = recordOf(q)
				if qr and not (qr.Indestructible and qr.Kind ~= "Surface") and not qr.Spell then
					local below = workspace:GetPartBoundsInBox(q.CFrame * CFrame.new(0, -q.Size.Y / 2 - 0.3, 0), Vector3.new(q.Size.X * 0.9, 0.5, q.Size.Z * 0.9), overlap)
					local supported = false
					for _, s in below do
						if s ~= q and s.Anchored and s.Parent then
							supported = true
							break
						end
					end
					if not supported then
						q.Anchored = false
					end
				end
			end
		end
		return
	end
	if part.Parent then
		part:Destroy()
	end
end

-- dégâts sur UNE pièce de matière (impact direct, souffle, cellule de feu...)
function MatterService.DamagePart(part: Instance?, amount: number, element: string?, pos: Vector3?, normal: Vector3?, owner: Player?, opts: any?)
	if not part or not part:IsA("BasePart") or not part.Parent then
		return
	end
	local r = recordOf(part)
	if not r then
		return
	end
	local at = pos or part.Position
	local react = not (opts and opts.NoReact)
	-- ── réactions élémentaires ──
	if react then
		if B(element, "IgnitesMatter") and r.Element == "Nature" then
			igniteAt(at, normal or Vector3.yAxis, part, false)
		elseif B(element, "IgnitesMatter") and r.Element == "Toxic" then
			igniteAt(at, normal or Vector3.yAxis, part, false) -- -> s'embrase
		elseif B(element, "IgniteChance") and r.Element == "Nature" and rng:NextNumber() < B(element, "IgniteChance") then
			igniteAt(at, normal or Vector3.yAxis, part, false)
		elseif B(element, "Extinguishes") then
			MatterService.Extinguish(at, 3.5)
		end
		-- la foudre CONDUIT dans le métal : tout ce qui touche la pièce est électrocuté
		if B(element, "ConductsInSteel") and r.Element == "Steel" and os.clock() - r.LastReact > 0.35 then
			r.LastReact = os.clock()
			local reach = part.Size.Magnitude / 2 + 3
			for _, hum in Combat.HumanoidsInRadius(part.Position, reach, owner) do
				local root = Combat.RootOf(hum)
				if root then
					Combat.Damage(hum, amount * 0.6, owner, "Lightning", root.Position)
					FXBus.Push({ k = "Beam", p = part.Position, d = root.Position, e = "Lightning", w = 0.4, c = "LIGHTNING", j = 1 })
				end
			end
		end
	end
	local mult = affinity(element, r.Element)
	local dmg = amount * mult
	if mult <= 0 then
		return -- aucun effet (ex. acide sur matière acide) : ni son ni éclats
	end
	local now = os.clock()
	if now - r.LastFx > 0.09 and not (opts and opts.Silent) then
		r.LastFx = now
		FXBus.Push({ k = "MHit", p = at, n = normal, m = r.Kind, e = r.Element, a = element, x = if mult >= 1.5 then 1 elseif mult < 0.6 then -1 else 0,
			c = if r.Spell then nil else part.Color:ToHex() })
	end
	if r.Indestructible or dmg <= 0 then
		return
	end
	local onDamage = (r :: any).OnDamage
	if onDamage then
		local ok, err = pcall(onDamage, dmg * MatterService.LIFE_PER_DAMAGE, element)
		if not ok then
			warn("[Matter] OnDamage :", err)
		end
		return
	end
	local pool = (r :: any).Pool
	if pool then
		pool.HP -= dmg
		if pool.HP <= 0 and not pool.Broken then
			pool.Broken = true
			if r.OnBreak then
				local ok, err = pcall(r.OnBreak, part, element)
				if not ok then
					warn("[Matter] OnBreak :", err)
				end
			end
		end
		return
	end
	r.HP -= dmg
	if r.HP <= 0 then
		breakPart(part, r, element)
	end
end

-- impact d'un projectile / rayon sur le décor
function MatterService.Hit(inst: Instance?, amount: number, element: string?, pos: Vector3, normal: Vector3?, owner: Player?, material: Enum.Material?)
	if not inst then
		return
	end
	if inst:IsA("Terrain") then
		if B(element, "IgnitesMatter") or (B(element, "IgniteChance") and rng:NextNumber() < B(element, "IgniteChance")) then
			MatterService.Ignite(pos, normal, inst, material)
		elseif B(element, "Extinguishes") then
			MatterService.Extinguish(pos, 3.5)
		end
		return
	end
	MatterService.DamagePart(inst, amount, element, pos, normal, owner)
end

-- creuse le TERRAIN (cratère) : la pierre est arrachée et projetée
-- reach = rayon du souffle : si le terrain est à portée, le cratère se creuse AU POINT DE CONTACT,
-- d'autant plus petit que l'explosion était loin de la surface
local function carve(pos: Vector3, r: number, reach: number)
	local t = workspace.Terrain
	local tOnly = RaycastParams.new()
	tOnly.FilterType = Enum.RaycastFilterType.Include
	tOnly.FilterDescendantsInstances = { t }
	local best: RaycastResult? = nil
	for _, d in { -Vector3.yAxis, Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis, Vector3.yAxis } do
		local res = workspace:Raycast(pos, d * reach, tOnly)
		if res and (not best or res.Distance < best.Distance) then
			best = res
		end
	end
	if not best then
		return
	end
	local mat = best.Material
	if mat == Enum.Material.Water or mat == Enum.Material.Air then
		return
	end
	r *= math.clamp(1 - best.Distance / reach, 0.35, 1)
	if r < 1.2 then
		return
	end
	pos = best.Position - best.Normal * (r * 0.25) -- centre légèrement DANS la matière : vrai creux
	t:FillBall(pos, r, Enum.Material.Air)
	local color = t:GetMaterialColor(mat)
	FXBus.Push({ k = "Carve", p = pos, r = r, c = color:ToHex(), m = mat.Name })
end

-- ZONE DE MATIÈRE (hors feu, qui brûle déjà via ses cellules) : la matière D'UN SORT posée dans la zone subit
-- l'élément en continu (durée de vie réduite selon l'affinité) + gangue visuelle de l'élément côté client ("MCoat").
-- Le décor de la map n'est pas concerné (une flaque ne détruit pas le niveau).
local COAT_EVERY = 0.45
function MatterService.Afflict(pos: Vector3, radius: number, damage: number, element: string, owner: Player?)
	local count = 0
	for _, part in workspace:GetPartBoundsInRadius(pos, radius, overlap) do
		if count >= 30 then
			break
		end
		local r = part.Parent and not isCharacter(part) and recordOf(part)
		if r and r.Spell and affinity(element, r.Element) > 0 then
			count += 1
			local closest = part.CFrame:PointToWorldSpace(part.CFrame:PointToObjectSpace(pos):Max(-part.Size / 2):Min(part.Size / 2))
			MatterService.DamagePart(part, damage, element, closest, nil, owner, { Silent = true })
			local now = os.clock()
			if now - ((r :: any).LastCoat or 0) > COAT_EVERY then
				(r :: any).LastCoat = now
				FXBus.Push({ k = "MCoat", i = part, e = element, p = closest })
			end
		end
	end
end

-- EXPLOSION / SOUFFLE : abîme toute la matière du rayon, enflamme / éteint, creuse la pierre
function MatterService.Blast(pos: Vector3, radius: number, damage: number, element: string?, owner: Player?, opts: any?)
	if radius <= 0 then
		return
	end
	local count = 0
	for _, part in workspace:GetPartBoundsInRadius(pos, radius, overlap) do
		if count >= 40 then
			break
		end
		if part.Parent and not isCharacter(part) then
			local r = recordOf(part)
			if r then
				count += 1
				local closest = part.CFrame:PointToWorldSpace(part.CFrame:PointToObjectSpace(pos):Max(-part.Size / 2):Min(part.Size / 2))
				local dist = (closest - pos).Magnitude
				local falloff = 1 - 0.6 * math.clamp(dist / radius, 0, 1)
				local away = closest - pos
				MatterService.DamagePart(part, damage * falloff, element, closest, if away.Magnitude > 0.1 then -away.Unit else nil, owner, { Silent = count > 6 or (opts and opts.Silent) })
			end
		end
	end
	if B(element, "IgnitesMatter") then
		MatterService.IgniteAround(pos, radius, math.clamp(math.floor(radius * 1.2), 3, 14))
	elseif B(element, "IgniteChance") and rng:NextNumber() < B(element, "IgniteChance") * 1.4 then
		MatterService.IgniteAround(pos, radius * 0.6, 2)
	elseif B(element, "Extinguishes") then
		MatterService.Extinguish(pos, radius + 2)
	end
	-- ARRACHEMENT : il faut du SOUFFLE (bombe, explosif, gros projectile qui repousse). Une boule de feu
	-- brûle mais ne creuse pas ; une bombe laisse un cratère.
	if not (opts and opts.NoCarve) and radius >= 3 then
		local knock = (opts and opts.Knock) or radius * 4
		local r = radius * 0.32 * (math.max(damage, 5) / 35) ^ 0.35 * math.clamp(knock / 40, 0.3, 1.6)
		if r >= 1.4 then
			carve(pos, math.min(r, 9), radius)
			local _, cubes = VoxelBreak.Hit(pos, math.min(math.max(radius * 0.4, r), 60), 35 + r * 3)
			if cubes and #cubes.L > 0 then
				FXBus.Push({ k = "VoxDebris", p = pos, w = math.floor(35 + r * 3), q = cubes })
			end -- pièces Breakable de la map : destruction par cubes
		end
	end
end

-- ══ 6. BOUCLE ═══════════════════════════════════════════════════════════════════════════════════════════
local filterT = 0
local function step(dt: number)
	filterT -= dt
	if filterT <= 0 then
		filterT = 2
		refreshFilter()
	end
	for _, cell in cells do
		cell.T -= dt
		if cell.T <= 0 then
			burnOut(cell)
			continue
		end
		-- la matière sous la flamme se consume
		if cell.Part then
			if cell.Part.Parent then
				MatterService.DamagePart(cell.Part, CELL_DPS * dt, "Fire", cell.Pos, cell.Normal, nil, { NoReact = true, Silent = true })
			end
			if cell.Sub and cell.Sub.Parent then
				MatterService.DamagePart(cell.Sub, CELL_DPS * dt, "Fire", cell.Pos, cell.Normal, nil, { NoReact = true, Silent = true })
			end
			if not cell.Part.Parent or not cell.Part.Anchored then
				cell.T = math.min(cell.T, 0.3) -- support détruit / qui tombe : la flamme retombe vite
			end
		end
		-- ceux qui marchent dans le feu prennent feu
		cell.HurtT -= dt
		if cell.HurtT <= 0 then
			cell.HurtT = 0.5
			for _, hum in Combat.HumanoidsInRadius(cell.Pos + cell.Normal, 2.4, nil) do
				local root = Combat.RootOf(hum)
				Combat.Damage(hum, 2, nil, "Fire", root and root.Position)
			end
		end
		cell.Next -= dt
		if cell.Next <= 0 then
			cell.Next = rng:NextNumber(SPREAD_EVERY[1], SPREAD_EVERY[2])
			spread(cell)
		end
	end
end

function MatterService.BurningCount(): number
	return cellCount
end

function MatterService.Init(combat, fxBus)
	Combat, FXBus = combat, fxBus
	scorchFolder = workspace:FindFirstChild("WandScorch") or Instance.new("Folder")
	scorchFolder.Name = "WandScorch"
	scorchFolder.Parent = workspace
	refreshFilter()
	RunService.Heartbeat:Connect(step)
end

return MatterService

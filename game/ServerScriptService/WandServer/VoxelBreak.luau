--[[
	WandServer/VoxelBreak — DESTRUCTION PAR CUBES des pièces de la map (prototype)
	Une pièce est cassable si elle a l'attribut Breakable = true (ou un ancêtre Model/Folder avec Breakable = true).
	Seuls les blocs (Part, Shape Block) sont cassés.
	Hit(pos, r) : les blocs touchés sont DIVISÉS en deux le long de leur plus grand axe, récursivement, jusqu'à des cubes
	de VOXEL studs ; les cubes dans la sphère sont arrachés (débris physiques plafonnés, sinon disparition) ; le reste
	du mur reste en GROS blocs (peu de pièces). Réparation : voir ResetAll / attribut VoxelRepair en bas.
	Budgets : MAX_SPLITS nouvelles pièces par coup, MAX_DEBRIS débris physiques pour toute l'arène, MAX_HITS_PER_SEC.
]]
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local VoxelBreak = {}

local VOXEL = 1.5
local MAX_SPLITS = 220
local MAX_DEBRIS = 150
local DEBRIS_LIFE = 4
local MAX_HITS_PER_SEC = 10

local vault = Instance.new("Folder")
vault.Name = "VoxelBreakVault"
vault.Parent = ServerStorage

local originals = {} -- id -> { Clone = Part, Parent = Instance, LastHit = number }
local nextId = 0
local debrisLive = 0
local hitStamps = {}
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude

local function breakable(p: Instance): boolean
	if not p:IsA("Part") or p.Shape ~= Enum.PartType.Block or not p.Anchored then
		return false
	end
	local a: Instance? = p
	while a and a ~= workspace do
		local v = a:GetAttribute("Breakable")
		if v ~= nil then
			return v == true
		end
		a = a.Parent
	end
	return false
end

function VoxelBreak.IsBreakable(p: Instance?): boolean
	return p ~= nil and breakable(p)
end

-- distance sphère / boîte orientée
local function closestDist(p: BasePart, pos: Vector3): number
	local l = p.CFrame:PointToObjectSpace(pos)
	local h = p.Size / 2
	local c = l:Max(-h):Min(h)
	return (l - c).Magnitude
end

local function fullyInside(p: BasePart, pos: Vector3, r: number): boolean
	local h = p.Size / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				if (p.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)) - pos).Magnitude > r then
					return false
				end
			end
		end
	end
	return true
end

local function remember(p: BasePart): number
	local id = p:GetAttribute("BreakId")
	if id and originals[id] then
		return id
	end
	nextId += 1
	id = nextId
	local c = p:Clone()
	-- (bug corrigé) touché PENDANT son fondu de réparation : on garde la VRAIE transparence, pas celle du fondu
	c.Transparency = p:GetAttribute("VoxBaseTr") or p.Transparency
	c.Parent = vault
	originals[id] = { Clone = c, Parent = p.Parent, LastHit = os.clock() }
	p:SetAttribute("BreakId", id)
	return id
end

-- DÉBRIS CÔTÉ CLIENT : le serveur retire le cube et note sa description ; chaque client fabrique ses propres
-- éclats physiques locaux (VFX "VoxDebris") -> aucun coût physique / réseau de pièces pour le serveur.
local MAX_SENT = 90 -- cubes décrits par explosion (au-delà, échantillon)
local sent: { any }? = nil
-- ── CŒUR (v2) : le découpage se fait sur des BOÎTES EN MÉMOIRE (aucune pièce intermédiaire créée / détruite),
-- puis seules les pièces FINALES sont créées et le bloc d'origine remplacé d'un coup (pas de clignotement).
-- Débris : le serveur n'en crée AUCUN ; il envoie la description des volumes arrachés (boîtes) et chaque client
-- fabrique ses éclats selon SA qualité (Bas / Moyen / Haut).
local MAX_SENT = 40 -- boîtes arrachées décrites par explosion (les plus grosses d'abord)
local MAX_BOXES = 900 -- boîtes finales max par explosion (sort Suprême qui rase un mur)
local MAX_FRAGMENTS = 5000 -- pièces de décor découpées max dans toute la map ; au-delà, cubes plus gros
local BUILD_PER_FRAME = 250 -- pièces créées par image (gros coups étalés sur plusieurs images)
local fragments = 0

local function q(v: number): number
	return math.floor(v * 10 + 0.5) / 10
end

-- coupe une boîte en 2 le long de son plus grand axe
local function splitBox(cf: CFrame, size: Vector3)
	local axis, len = Vector3.xAxis, size.X
	if size.Y > len then
		axis, len = Vector3.yAxis, size.Y
	end
	if size.Z > len then
		axis, len = Vector3.zAxis, size.Z
	end
	local half = size - axis * (len / 2)
	local off = axis * (len / 4)
	return cf * CFrame.new(-off), cf * CFrame.new(off), half
end

local function boxDist(cf: CFrame, size: Vector3, pos: Vector3): number
	local l = cf:PointToObjectSpace(pos)
	local h = size / 2
	return (l - l:Max(-h):Min(h)).Magnitude
end

local function boxInside(cf: CFrame, size: Vector3, pos: Vector3, r: number): boolean
	local l = cf:PointToObjectSpace(pos)
	local h = size / 2
	-- coin le plus éloigné du centre de la sphère
	local far = Vector3.new(math.abs(l.X) + h.X, math.abs(l.Y) + h.Y, math.abs(l.Z) + h.Z)
	return far.Magnitude <= r
end

function VoxelBreak.Hit(pos: Vector3, r: number, power: number?): (number, { any }?)
	if r < 0.8 then
		return 0
	end
	local now = os.clock()
	while hitStamps[1] and now - hitStamps[1] > 1 do
		table.remove(hitStamps, 1)
	end
	if #hitStamps >= MAX_HITS_PER_SEC then
		return 0
	end
	local targets = {}
	for _, p in workspace:GetPartBoundsInRadius(pos, r, overlap) do
		if breakable(p) then
			table.insert(targets, p)
		end
	end
	if #targets == 0 then
		return 0
	end
	table.insert(hitStamps, now)
	-- taille des cubes : grandit avec le trou (nombre de pièces ~constant) et quand la map est déjà très découpée
	local voxel = math.max(VOXEL, r / 8)
	if fragments > MAX_FRAGMENTS * 0.6 then
		voxel *= if fragments > MAX_FRAGMENTS then 3 else 2
	end
	local removedBoxes = {}
	local removedCount = 0
	local jobs = {} -- { part, keep = { {cf,size} } }
	local boxes = 0
	for _, p in targets do
		local keep = {}
		local stack = { { p.CFrame, p.Size } }
		local changed = false
		while #stack > 0 do
			local b = table.remove(stack)
			local cf, size = b[1], b[2]
			if boxDist(cf, size, pos) > r then
				table.insert(keep, b) -- hors de la sphère : reste tel quel (gros bloc)
			elseif boxInside(cf, size, pos, r) then
				changed = true
				removedCount += 1
				table.insert(removedBoxes, b)
			elseif size.Magnitude <= voxel * 1.8 or boxes >= MAX_BOXES then
				if (cf.Position - pos).Magnitude <= r then
					changed = true
					removedCount += 1
					table.insert(removedBoxes, b)
				else
					table.insert(keep, b)
				end
			else
				local a, c, half = splitBox(cf, size)
				boxes += 1
				table.insert(stack, { a, half })
				table.insert(stack, { c, half })
			end
		end
		if changed then
			table.insert(jobs, { p, keep })
		end
	end
	-- création des pièces finales (étalée sur plusieurs images si c'est énorme), puis remplacement d'un coup
	local built = 0
	for _, job in jobs do
		local p, keep = job[1], job[2]
		local id = remember(p)
		originals[id].LastHit = now
		local news = table.create(#keep)
		for _, b in keep do
			local n = p:Clone()
			n.Transparency = p:GetAttribute("VoxBaseTr") or p.Transparency
			n.Size = b[2]
			n.CFrame = b[1]
			table.insert(news, n)
			built += 1
			if built % BUILD_PER_FRAME == 0 then
				task.wait()
			end
		end
		if p.Parent then
			local parent = p.Parent
			for _, n in news do
				n.Parent = parent
			end
			fragments += #news - (if p:GetAttribute("VoxFrag") then 1 else 0)
			for _, n in news do
				n:SetAttribute("VoxFrag", true)
			end
			p:Destroy()
		else
			for _, n in news do
				n:Destroy()
			end
		end
	end
	-- description des volumes arrachés pour les débris CLIENT (les plus gros d'abord, plafonné)
	table.sort(removedBoxes, function(a, b)
		return a[2].X * a[2].Y * a[2].Z > b[2].X * b[2].Y * b[2].Z
	end)
	local sample = targets[1]
	local list = {}
	for k = 1, math.min(#removedBoxes, MAX_SENT) do
		local cf, size = removedBoxes[k][1], removedBoxes[k][2]
		local rx, ry, rz = cf:ToOrientation()
		table.insert(list, { q(cf.X), q(cf.Y), q(cf.Z), q(size.X), q(size.Y), q(size.Z), q(rx), q(ry), q(rz) })
	end
	return removedCount, { L = list, C = sample.Color:ToHex(), M = sample.Material.Name, V = q(voxel), N = removedCount }
end

-- ── RÉPARATION ─────────────────────────────────────────────────────────────────────────────
-- 1) Par défaut : AUCUNE réparation pendant le match ; VoxelBreak.ResetAll() remet toute la map à neuf
--    (à appeler entre deux manches ; ServerStorage.VoxelReset:Invoke() pour les tests / le futur gestionnaire de manches).
-- 2) Option : workspace attribut VoxelRepair = N secondes -> réparation en cours de match N s après le dernier coup,
--    SÉCURISÉE : une pièce ne revient jamais sur un joueur (réessai toutes les 2 s tant que quelqu'un est dedans).
local Players = game:GetService("Players")

local function characterIn(part: BasePart): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local chars = {}
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(chars, pl.Character)
		end
	end
	if #chars == 0 then
		return false
	end
	params.FilterDescendantsInstances = chars
	-- (bug corrigé) boîte RÉDUITE : avant, +1 stud de marge -> un joueur simplement DEBOUT sur la pièce
	-- (ex. le Baseplate 2048x2048) comptait comme « dedans » et la réparation n'avait jamais lieu
	return #workspace:GetPartBoundsInBox(part.CFrame, part.Size - Vector3.new(0.6, 0.6, 0.6), params) > 0
end

-- joueurs coincés DANS le volume réparé (au fond d'un cratère) : remontés au-dessus de la surface
local function liftOut(part: BasePart)
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local l = part.CFrame:PointToObjectSpace(root.Position)
			local h = part.Size / 2
			if math.abs(l.X) < h.X and math.abs(l.Z) < h.Z and math.abs(l.Y) < h.Y + 2.5 then
				local top = part.CFrame:PointToWorldSpace(Vector3.new(l.X, h.Y, l.Z))
				ch:PivotTo(CFrame.new(top + Vector3.new(0, 3.2, 0)) * (root.CFrame - root.Position))
			end
		end
	end
end

local function restore(id: number, force: boolean): boolean
	local o = originals[id]
	if not o then
		return true
	end
	local huge = o.Clone.Size.Magnitude > 60 -- sol / grande dalle : on ne bloque jamais, on remonte les joueurs
	if not force and not huge and characterIn(o.Clone) then
		return false
	end
	originals[id] = nil
	-- les morceaux restants du mur restent visibles PENDANT le fondu (sinon le mur entier clignoterait),
	-- puis disparaissent sous la pièce réparée
	local old = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("BreakId") == id then
			if d:GetAttribute("VoxFrag") then
				fragments = math.max(0, fragments - 1)
			end
			d.CanCollide = false
			d.CanQuery = false
			table.insert(old, d)
		end
	end
	local function dropOld()
		for _, d in old do
			d:Destroy()
		end
	end
	if force then
		dropOld()
	else
		task.delay(1.25, dropOld)
	end
	if o.Parent and o.Parent:IsDescendantOf(game) then
		o.Clone:SetAttribute("BreakId", nil)
		-- RÉAPPARITION EN FONDU (user 2026-11-23) : la pièce est SOLIDE dès le départ, le fondu est purement visuel
		local part = o.Clone
		local target = part:GetAttribute("VoxBaseTr") or part.Transparency
		part:SetAttribute("VoxBaseTr", target)
		part.Transparency = 1
		part.Parent = o.Parent
		if huge then
			liftOut(part)
		end
		if not force then
			game:GetService("TweenService"):Create(part, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Transparency = target }):Play()
		else
			part.Transparency = target
		end
	else
		o.Clone:Destroy()
	end
	return true
end

-- remet TOUTE la map à neuf (entre deux manches : les joueurs sont censés être replacés juste après)
function VoxelBreak.ResetAll(): number
	local n = 0
	fragments = 0
	for id in originals do
		restore(id, true)
		n += 1
	end
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("VoxelDebris") then
			d:Destroy()
		end
	end
	return n
end

task.spawn(function()
	while true do
		task.wait(2)
		-- RÉGÉNÉRATION ACTIVE PAR DÉFAUT (user 2026-11-23) : 10 s après le dernier coup ; VoxelRepair = 0 la coupe
		local delay = workspace:GetAttribute("VoxelRepair")
		if delay == nil then
			delay = 10
		end
		if type(delay) == "number" and delay > 0 and next(originals) then
			local now = os.clock()
			for id, o in originals do
				if now - o.LastHit > delay then
					restore(id, false)
				end
			end
		end
	end
end)

local resetFn = Instance.new("BindableFunction")
resetFn.Name = "VoxelReset"
resetFn.OnInvoke = function()
	return VoxelBreak.ResetAll()
end
resetFn.Parent = ServerStorage

return VoxelBreak

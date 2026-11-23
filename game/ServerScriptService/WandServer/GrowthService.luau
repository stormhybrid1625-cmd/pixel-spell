--[[
	WandServer/GrowthService — Sorts PROCÉDURAUX (expérimental) : la Ramure

	FORMULES DES SORTS PROCÉDURAUX (à réutiliser pour tous les futurs sorts de ce type) :
	  • taille  s = ProcScale (Gigantisme, cumulable x3, plafond Limits.MaxProcScale)
	  • épaisseur / pas        x s      et  x sqrt(s)
	  • DURÉE DE PROPAGATION   x (1 + 0.12 * (s - 1))  x min(Prolongation, 2)
	  • ZONE DE DÉTECTION au bout de chaque branche : Sense * s^0.4, bornée [Sense, SenseMax]
	  • ZONE DE CONTACT des éclairs (Foudre) : ZapRange * s^0.4, bornée
	  • durée de vie x Prolongation
	  • COLLISION : TOUTES les branches sont de vrais obstacles, quelle que soit la taille du sort
	  • CUMUL de Tête chercheuse / Cage (x2, x3) : l'arbre se divise en groupes de branches, chacun sur un
	    ennemi DIFFÉRENT ; Ramification = plus de bras et de branches secondaires, pousse plus lente
	  • BASE ENFOUIE : le pied de chaque tronc démarre SOUS la surface (plus profond dans un mur)
	  • CAGE / SELF CAGE : chaque bras reçoit un angle autour de la cible (ennemi le plus proche / lanceur,
	    position LIVE) ; il s'en approche jusqu'au rayon de cage, puis tourne autour en montant et se referme
	    en dôme. Il ne pénètre jamais dans le rayon : les barreaux entourent la cible sans la toucher.

	Comportement :
	  • point visé = SURFACE SOLIDE obligatoire (sinon échec "Fizzle" + carte remboursée) ;
	  • PORTÉ PAR UN PROJECTILE (charge de déclencheur, depth > 0) : la règle de portée est ignorée ;
	    l'arbre s'ancre sur la surface LA PLUS PROCHE du point d'impact (sondes en étoile), sinon
	    droit devant puis dessous, sans limite de distance ;
	  • troncs qui poussent dans l'espace, chacun à son rythme (départs, intervalles, pas, pauses aléatoires) ;
	  • ÉVITEMENT par Spherecast ; IGNORE OBSTACLES (stats.Phase) = aucune sonde, la matière traverse tout ;
	  • Tête chercheuse : verrouillage quand une cible entre dans la zone au bout d'une branche ;
	  • FOUDRE : l'arbre foudroie ce qui entre dans sa zone de contact, l'éclair saute de cible en cible ;
	  • MAINTIEN (HoldTick / EndHold) : une branche naît à chaque tick sur la surface visée ; une seule
	    croissance regroupe le tracé ; sa vie ne s'écoule qu'à partir de la fin du maintien.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.WandShared.Config)
local VoxelBreak = require(script.Parent:WaitForChild("VoxelBreak"))
local Combat = require(script.Parent.Combat)
local FXBus = require(script.Parent.FXBus)
local Matter = require(script.Parent.MatterService)

local Limits = Config.Limits
local BASE_STEPS = 14
local CHAIN_RANGE = 22
local CAGE_RANGE = 60 -- Cage : ennemi cherché dans ce rayon autour du point d'ancrage
local HOLD_ARM_STEPS = 7 -- pas d'une branche née pendant un maintien (haie continue plutôt qu'arbres géants)
local ANCHOR_DIRS = {
	Vector3.new(0, -1, 0), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
	Vector3.new(0, 1, 0), Vector3.new(1, -1, 1).Unit, Vector3.new(-1, -1, 1).Unit, Vector3.new(1, -1, -1).Unit,
	Vector3.new(-1, -1, -1).Unit,
}

local GrowthService = {}
GrowthService.OnRefund = nil :: ((Player, number) -> ())?

local growths = {}
local nextId = 0
local rng = Random.new()
local colliders: Folder
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local function propagationMult(scale: number): number
	return 1 + 0.12 * (scale - 1)
end
local function zoneRadius(base: number, maxR: number, scale: number): number
	return math.clamp(base * scale ^ 0.4, base, maxR)
end
GrowthService.PropagationMult = propagationMult
GrowthService.ZoneRadius = zoneRadius

local function refreshFilter()
	local list = { colliders }
	for _, name in { "WandProjectiles", "WandZoneMarkers", "WandDummies" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	params.FilterDescendantsInstances = list
end

local function tangent(n: Vector3): Vector3
	local t = n:Cross(Vector3.yAxis)
	if t.Magnitude < 0.1 then
		t = n:Cross(Vector3.xAxis)
	end
	return t.Unit
end

local function free(pos: Vector3, d: Vector3, len: number, r: number): (boolean, RaycastResult?)
	local hit = workspace:Spherecast(pos, math.max(0.15, r), d * len, params)
	return hit == nil, hit
end

local function targets(owner: Player?): { BasePart }
	local list = {}
	local function consider(model: Instance?)
		if not model or (owner and owner.Character == model) then
			return
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		local root = hum and Combat.RootOf(hum)
		if hum and root and hum.Health > 0 then
			table.insert(list, root)
		end
	end
	for _, p in Players:GetPlayers() do
		consider(p.Character)
	end
	local dummies = workspace:FindFirstChild("WandDummies")
	if dummies then
		for _, m in dummies:GetChildren() do
			consider(m)
		end
	end
	return list
end

local function newArm(g, pos: Vector3, dir: Vector3, thick: number, step: number, depth: number, delay: number, steps: number?)
	table.insert(g.Arms, {
		Pos = pos, Dir = dir.Unit, Thick = thick, Step = step, Depth = depth, Alive = true,
		Seed = rng:NextNumber(0, 100),
		Wait = delay,
		Bend = rng:NextNumber(0.8, 1.8),
		Lock = nil :: BasePart?,
		Steps = steps or math.huge, -- budget de pas (branches de maintien)
	})
end

-- ══ ACCROCHES UNIVERSELLES (phase 1.6) : la Ramure annonce les mêmes 4 moments que projectiles et rayons ══
--   OnTick = chaque nouvelle branche (ctx.From -> ctx.Pos) | OnHit = une branche blesse une cible
--   OnSurface = l'arbre s'ancre, ou une branche bute sur le décor | OnEnd = l'arbre meurt (bout de la branche la plus avancée)
local PS = nil
local function fireHook(g, name: string, pos: Vector3, normal: Vector3?, dir: Vector3?, from: Vector3?, ...)
	if not (PS and PS.RunHooks and g.HookRec) or g.NoHooks then
		return
	end
	local rec = g.HookRec
	rec.Age = g.Age
	rec.From = from
	PS.RunHooks(rec, name, pos, normal, dir, ...)
end

-- bout de la branche la plus avancée + SENS DE POUSSE de son dernier segment (LookVector du collider)
local function tipOf(g): (Vector3, Vector3)
	local tip, tipDir, far = g.Origin + g.Up * 2, g.Up, -1
	for _, p in g.Colliders do
		if p.Parent then
			local e = p.Position + p.CFrame.LookVector * (p.Size.Z / 2)
			local d = (e - g.Origin).Magnitude
			if d > far then
				tip, tipDir, far = e, p.CFrame.LookVector, d
			end
		end
	end
	return tip, tipDir
end

local function endGrowth(i: number)
	local g = growths[i]
	table.remove(growths, i)
	-- FIN DE L'ARBRE (durée écoulée, détruit par les dégâts, surface détruite...) : prévient le déclencheur « à expiration »
	do -- accroche OnEnd des cartes (fin de l'arbre), au bout de la branche la plus avancée
		local tip, tipDir = tipOf(g)
		fireHook(g, "OnEnd", tip, nil, tipDir)
	end
	if g.OnEnd then
		local tip, tipDir = tipOf(g)
		local ok, err = pcall(g.OnEnd, { Base = g.Origin, Up = g.Up, Tip = tip, TipDir = tipDir })
		if not ok then
			warn("[Growth] fin d'arbre (déclencheur) :", err)
		end
	end
	FXBus.Push({ k = "GrowEnd", g = g.Id, p = g.Origin, e = g.Element })
	-- Charge explosive : les pointes les plus éloignées explosent (6 au plus)
	if (g.ExplodeR or 0) > 0 and not g.NoHooks then
		local tips = {}
		for _, sg in g.Segments do
			table.insert(tips, sg.B)
		end
		table.sort(tips, function(a, b)
			return (a - g.Origin).Magnitude > (b - g.Origin).Magnitude
		end)
		local done = {}
		for _, p in tips do
			if #done >= 6 then
				break
			end
			local far = true
			for _, q in done do
				if (p - q).Magnitude < g.ExplodeR * 1.2 then
					far = false
					break
				end
			end
			if far then
				table.insert(done, p)
			end
		end
		for i, p in done do
			task.delay(0.08 * i, function()
				Combat.Explode(p, g.ExplodeR, g.ExplodeDmg, g.Owner, g.Element or "Fire", if g.Knockback > 0 then g.Knockback else nil, g.DurMult)
				FXBus.Push({ k = "Impact", p = p, n = Vector3.yAxis, e = g.Element or "Fire", r = g.ExplodeR, s = 1 })
			end)
		end
	end
	-- les collisions disparaissent quand le flétrissement visuel est bien entamé
	local parts = g.Colliders
	task.delay(0.5, function()
		for _, p in parts do
			p:Destroy()
		end
	end)
end

local function fizzle(owner: Player?, stats)
	local char = owner and owner.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	FXBus.Push({ k = "Fizzle", p = if root then root.Position else Vector3.zero, u = if owner then owner.UserId else 0 })
	if owner and GrowthService.OnRefund and (stats.Mana or 0) > 0 then
		GrowthService.OnRefund(owner, stats.Mana)
	end
end

local function makeRoom(owner: Player?)
	local mine = 0
	for _, g in growths do
		if g.Owner == owner then
			mine += 1
		end
	end
	if mine >= Limits.MaxGrowthsPerPlayer then
		for i, g in growths do
			if g.Owner == owner and not g.Holding then
				endGrowth(i)
				break
			end
		end
	end
	if #growths >= Limits.MaxGrowthsGlobal then
		for i, g in growths do
			if not g.Holding then
				endGrowth(i)
				break
			end
		end
	end
end

-- Crée l'objet croissance (sans bras). holding = croissance de maintien.
local function newGrowth(stats, owner: Player?, pos: Vector3, n: Vector3, holding: boolean)
	makeRoom(owner)
	nextId += 1
	local spec = stats.Growth
	local scale = math.clamp(stats.ProcScale or stats.ZoneScale or 1, 0.5, Limits.MaxProcScale)
	local durMult = math.clamp(stats.DurationMult or 1, 0.25, 4)
	-- vitesse de pousse : Ramification ralentit (< 1), ACCÉLÉRATION accélère (x1,3 par exemplaire, jusqu'à 2,5)
	-- (bug corrigé : le plafond à 1 annulait toute accélération)
	local growSpeed = math.clamp(stats.GrowSpeed or 1, 0.4, 2.5)
	-- PROPAGATION = base x taille x Élongation / vitesse. (Prolongation ne joue PAS ici : elle allonge la vie
	-- de l'arbre, pas sa pousse.)
	local growMult = math.clamp(stats.GrowTime or 1, 1, 5)
	local growTime = spec.Duration * propagationMult(scale) * growMult / growSpeed
	local g = {
		Id = nextId,
		Owner = owner,
		Element = stats.Element,
		Spec = spec,
		Origin = pos,
		Up = n,
		Scale = scale,
		DurMult = durMult,
		Homing = stats.Homing or 0,
		Knockback = stats.Knockback or 0, -- Recul : les branches repoussent ce qu'elles touchent
		-- Charge explosive : les POINTES des branches explosent quand l'arbre meurt
		ExplodeR = stats.Radius or 0,
		ExplodeDmg = 6 + (stats.Damage or 0), -- (Ramure n'a pas de dégâts d'impact : base 6 par pointe)
		Weight = math.max(0, stats.Gravity or 0), -- Lest (gravité ajoutée) : branches plus basses, plus étalées
		-- SPIRALE : toutes les branches montent en hélice autour du MÊME axe (l'axe de pousse), même sens ;
		-- chaque exemplaire de Spirale élargit l'hélice
		Spiral = stats.Spiral == true,
		SpiralR = (1.6 + (stats.SpiralRadius or 1.4)) * math.sqrt(scale),
		Phase = stats.Phase == true,
		Cage = stats.Cage, -- nil | "Self" | "Enemy"
		CageR = math.min(3.2 + 0.9 * math.sqrt(scale) + math.max((stats.OrbitRadius or 5) - 5, 0), 15), -- Orbite cumulée = cage plus large (max 15)
		CageH = 6 * scale ^ 0.35,
		Solid = true, -- TOUTES les branches sont solides, quelle que soit la taille du sort
		-- cumul de Tête chercheuse / Cage : 1 groupe de branches par exemplaire, chacun sur un ennemi différent
		Groups = math.max(1, stats.HomingTargets or 1),
		CageGroups = if stats.Cage == "Enemy" then math.max(1, stats.CageTargets or 1) else 1,
		GroupT = {}, -- cible verrouillée par groupe (Tête chercheuse)
		CageT = {}, -- cible de chaque cage
		ArmsAdd = stats.ArmsAdd or 0,
		ForkAdd = stats.ForkAdd or 0,
		Sense = zoneRadius(spec.Sense or 9, spec.SenseMax or 16, scale),
		ZapR = zoneRadius(spec.ZapRange or 7, spec.ZapMax or 13, scale),
		Interval = spec.Duration / BASE_STEPS / growSpeed,
		Arms = {},
		Segments = {},
		Colliders = {},
		-- Élongation relève aussi le plafond de segments, sinon l'arbre s'arrêterait avant d'aller plus loin
		MaxSegments = math.floor((if holding then Limits.MaxGrowthSegments * 2 else Limits.MaxGrowthSegments) * growMult),
		Holding = holding,
		-- une cage doit d'abord rejoindre sa cible : un peu plus de temps de pousse
		GrowUntil = if holding then math.huge elseif stats.Cage then growTime * 1.6 else growTime,
		Life = if holding then math.huge else math.max(spec.Life * durMult, growTime + 1.5),
		Age = 0,
		DmgAcc = 0,
		ZapAcc = 0,
		ArcAcc = 0,
		Extent = 2,
	}
	g.HookRec = { Stats = stats, Owner = owner, Engine = "Procedural", HookMem = {} }
	table.insert(growths, g)
	FXBus.Push({ k = "GrowStart", g = g.Id, p = pos, n = n, e = g.Element, z = scale, t = g.Life })
	return g
end

-- Fait jaillir `count` troncs d'un point de surface.
local function seed(g, pos: Vector3, n: Vector3, count: number, steps: number?)
	local t1 = tangent(n)
	local t2 = n:Cross(t1)
	local spec = g.Spec
	local step = (spec.Step or 1.6) * math.sqrt(g.Scale)
	local thick = (spec.Thick or 1.3) * g.Scale
	local turn = rng:NextNumber(0, math.pi * 2)
	-- pied ENFOUI : sous le sol, et encore plus profond dans un mur (le départ est caché)
	-- (réduit : juste assez pour que le pied ne dépasse pas de la surface)
	local sink = if n.Y > 0.6 then thick * 0.3 + 0.1 else thick * 0.5 + 0.25
	local groups = if g.Cage then g.CageGroups else g.Groups
	if g.Cage then
		count = math.min(math.max(count, 8 * groups), 24) -- assez de barreaux pour entourer chaque cible
	end
	local perGroup = math.ceil(count / groups)
	local cageTurn = rng:NextNumber(0, math.pi * 2)
	for i = 1, count do
		local a = turn + (i / count) * math.pi * 2 + rng:NextNumber(-0.45, 0.45)
		local open = rng:NextNumber(0.3, 1.2)
		local d = n + (t1 * math.cos(a) + t2 * math.sin(a)) * open
		newArm(g, pos - n * sink, d, thick * rng:NextNumber(0.75, 1.15), step, 0, rng:NextNumber(0, 0.35), steps)
		local arm = g.Arms[#g.Arms]
		arm.Group = (i - 1) % groups + 1 -- les bras sont répartis en groupes (1 par cible)
		if g.Cage then
			local idx = math.ceil(i / groups)
			arm.Theta = cageTurn + (idx / perGroup) * math.pi * 2 -- place de ce barreau autour de SA cible
			arm.Spin = if idx % 2 == 0 then 1 else -1 -- barreaux croisés : moitié dans chaque sens
			arm.H = rng:NextNumber(0, 0.6)
		end
	end
end

-- Surface d'ancrage :
--   depth = 0 (lancé depuis la baguette) : rayon vers le point visé, portée limitée ;
--   depth > 0 (porté par un projectile)  : surface la plus proche du point d'impact, puis sans limite.
local function anchor(stats, origin: Vector3, dir: Vector3, reach: number?, depth: number?): RaycastResult?
	if (depth or 0) > 0 then
		local best, bestD = nil, math.huge
		for _, d in ANCHOR_DIRS do
			local hit = workspace:Raycast(origin, d * 6, params)
			if hit and not Combat.HumanoidFrom(hit.Instance) and hit.Distance < bestD then
				best, bestD = hit, hit.Distance
			end
		end
		if best then
			return best
		end
		local far = workspace:Raycast(origin, dir * 500, params) or workspace:Raycast(origin, Vector3.new(0, -500, 0), params)
		if far and not Combat.HumanoidFrom(far.Instance) then
			return far
		end
		return nil
	end
	local range = math.clamp(reach or stats.Range, 3, math.max(stats.Range, 10))
	local hit = workspace:Raycast(origin, dir * range, params)
	if hit and Combat.HumanoidFrom(hit.Instance) then
		return nil
	end
	if hit then
		return hit
	end
	-- TROP LOIN / dans le vide (user) : on ne rate plus — on avance depuis le lanceur dans la direction visée
	-- jusqu'au BORD de la portée et on cherche le sol en dessous ; si rien (vide), on recule pas à pas.
	local step = 2
	local dist = range
	while dist >= 2 do
		local p = origin + dir * dist
		local down = workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -60, 0), params)
		if down and not Combat.HumanoidFrom(down.Instance) then
			-- le chemin jusqu'au point ne doit pas traverser un mur
			local block = workspace:Raycast(origin, (down.Position + down.Normal * 0.5) - origin, params)
			if not block or (block.Position - down.Position).Magnitude < 1.5 then
				return down
			end
		end
		dist -= step
	end
	return nil
end

-- onEnd (optionnel) : appelé quand l'arbre disparaît, avec { Base, Up, Tip, TipDir }
-- mark (optionnel) : { Element } -> la branche de départ de la suite scintille de l'élément du sort suivant
function GrowthService.Create(stats, origin: Vector3, dir: Vector3, owner: Player?, reach: number?, depth: number?, onEnd: ((any) -> ())?, mark: any?): Vector3?
	refreshFilter()
	local hit = anchor(stats, origin, dir, reach, depth)
	if not hit then
		fizzle(owner, stats)
		return nil
	end
	local g = newGrowth(stats, owner, hit.Position, hit.Normal, false)
	g.OnEnd = onEnd
	fireHook(g, "OnSurface", hit.Position, hit.Normal, dir) -- l'arbre s'ancre sur sa surface
	g.Mark = mark
	g.MarkT = 0.3
	seed(g, hit.Position, hit.Normal, (stats.Growth.Arms or 5) + g.ArmsAdd, nil)
	return hit.Position + hit.Normal * 0.5
end

-- ── MAINTIEN ──────────────────────────────────────────────────────────────────────────────────
-- state = nil au premier tick ; renvoie le state à repasser au tick suivant.
-- Pas de surface ou trop loin : rien ne pousse ce tick, mais le maintien continue.
function GrowthService.HoldTick(state, stats, origin: Vector3, dir: Vector3, owner: Player?, reach: number?)
	state = state or { G = nil }
	refreshFilter()
	local hit = anchor(stats, origin, dir, reach, 0)
	if not hit then
		return state
	end
	local g = state.G
	if not g or not table.find(growths, g) then
		g = newGrowth(stats, owner, hit.Position, hit.Normal, true)
		state.G = g
	end
	if #g.Segments < g.MaxSegments then
		-- une branche par tick (2 au-delà de x3) : bride la quantité de matière par tick
		seed(g, hit.Position, hit.Normal, if g.Scale >= 3 then 2 else 1, math.floor(HOLD_ARM_STEPS * propagationMult(g.Scale)))
	end
	return state
end

function GrowthService.EndHold(state)
	local g = state and state.G
	if not g or not g.Holding then
		return
	end
	g.Holding = false
	g.GrowUntil = g.Age + g.Spec.Duration -- les dernières branches finissent de pousser
	g.Life = g.Age + math.max(g.Spec.Life * g.DurMult, g.Spec.Duration + 1.5) - (g.HoldDamage or 0)
end

-- ── Croissance ───────────────────────────────────────────────────────────────────────────────
local function addCollider(g, from: Vector3, to: Vector3, thick: number): number?
	if not g.Solid then
		return nil
	end
	local len = (to - from).Magnitude
	if len < 0.1 then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = "Trunk"
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(thick * 0.85, thick * 0.85, len + thick * 0.4)
	p.CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to)
	p.Parent = colliders
	table.insert(g.Colliders, p)
	fireHook(g, "OnTick", to, nil, (to - from).Unit, from, 0) -- « en vol » = une nouvelle branche
	-- MATIÈRE : chaque segment a ses PV (plus il est épais, plus il est solide) et l'élément de
	-- l'arbre (nature par défaut, sinon son infusion). Cassé -> le client retire CE segment.
	g.SegN = (g.SegN or 0) + 1
	local idx = g.SegN
	-- les dégâts sur N'IMPORTE QUELLE branche raccourcissent la DURÉE de vie de TOUT l'arbre
	-- (1 dégât = 0,05 s) ; à zéro, l'arbre flétrit normalement
	Matter.Register(p, {
		Element = g.Element or "Nature",
		Kind = "Branch",
		OnDamage = function(seconds: number)
			if g.Life < math.huge then
				g.Life -= seconds
			else
				g.HoldDamage = (g.HoldDamage or 0) + seconds -- arbre maintenu : décompté au relâchement
			end
		end,
	})
	return idx
end

local function stepArm(g, arm, list, born)
	local spec = g.Spec
	local r = arm.Thick * 0.5
	local interval = g.Interval * rng:NextNumber(0.6, 1.5)
	if rng:NextNumber() < 0.08 then
		interval += g.Interval * rng:NextNumber(1, 2.5)
	end
	local len = arm.Step * rng:NextNumber(0.7, 1.3)

	local t = g.Age * 1.7 + arm.Seed
	local wander = Vector3.new(math.noise(t, 0, arm.Seed), math.noise(0, t, arm.Seed), math.noise(arm.Seed, 0, t)) * arm.Bend
	-- avec Tête chercheuse, les branches s'étalent plus à l'horizontale (elles cherchent) au lieu de monter
	local want = arm.Dir * 1.6 + wander + rng:NextUnitVector() * 0.3 + g.Up * (if g.Homing > 0 then 0.06 else 0.25)
	if g.Spiral then
		-- hélice autour de l'axe g.Up passant par l'origine : composante tangente (tourne), composante
		-- axiale (monte) et rappel radial vers le rayon de l'hélice ; un peu de wander garde l'aspect organique
		local rel = arm.Pos - g.Origin
		local radial = rel - g.Up * rel:Dot(g.Up)
		if radial.Magnitude < 0.3 then
			radial = arm.Dir - g.Up * arm.Dir:Dot(g.Up) -- au pied : part dans la direction de la branche
			if radial.Magnitude < 1e-3 then radial = tangent(g.Up) end
			radial = radial.Unit * 0.3
		end
		local rd = radial.Unit
		local around = g.Up:Cross(rd) -- même sens pour toutes les branches
		local pull = (g.SpiralR - radial.Magnitude) / g.SpiralR -- >0 : trop près de l'axe -> s'écarte
		want = around * 1.5 + g.Up * 0.75 + rd * pull * 1.2 + wander * 0.25
	end
	-- LEST : la ramure est ALOURDIE -> elle monte moins et s'étale davantage au ras du sol (cumulable)
	if g.Weight > 0 then
		-- composante « vers le haut » (normale de la surface) écrasée, mais JAMAIS négative : la ramure rampe
		-- au ras de sa surface sans jamais plonger dedans (avant : Lest x3 poussait SOUS le sol, la sonde de
		-- collision partant du pied enfoui ne voyait pas le sol)
		local k = math.min(g.Weight, 3)
		local mag = want.Magnitude
		local u = want:Dot(g.Up)
		local lateral = want - g.Up * u
		local rise = math.max(u / (1 + k * 1.6), 0.07 * mag)
		local flat = lateral + g.Up * rise
		if flat.Magnitude > 1e-3 then
			want = flat.Unit * mag
		end
		-- encore SOUS la surface (pied enfoui, sol qui remonte) : la branche ressort d'abord, à la verticale
		if not g.Phase then
			local above = workspace:Raycast(arm.Pos + g.Up * 3, -g.Up * 3, params)
			if above and not Combat.HumanoidFrom(above.Instance) then
				want = lateral * 0.3 + g.Up * mag * 1.5
			end
		end
	end

	local locked = false
	-- ── CAGE / SELF CAGE ──
	if g.Cage and arm.Theta then
		local grp = arm.Group or 1
		local T = g.CageT[grp]
		if not (T and T.Parent) or (g.Cage == "Enemy" and T.Parent:FindFirstChildOfClass("Humanoid") and T.Parent:FindFirstChildOfClass("Humanoid").Health <= 0) then
			if g.Cage == "Self" then
				local char = g.Owner and g.Owner.Character
				T = char and char:FindFirstChild("HumanoidRootPart")
			else
				-- l'ennemi le plus proche qui n'est pas déjà encagé par un autre groupe
				local taken = {}
				for k, v in g.CageT do
					if k ~= grp then
						taken[v] = true
					end
				end
				local best, bestD = nil, CAGE_RANGE
				for _, root in targets(g.Owner) do
					local d = (root.Position - g.Origin).Magnitude
					if d < bestD and not taken[root] then
						best, bestD = root, d
					end
				end
				T = best
			end
			g.CageT[grp] = T
		end
		if T then
			local R = g.CageR
			local feet = T.Position - Vector3.new(0, 2.8, 0) -- position LIVE de la cible
			local function slotPos()
				return feet + Vector3.new(math.cos(arm.Theta), 0, math.sin(arm.Theta)) * R + Vector3.yAxis * arm.H
			end
			local slot = slotPos()
			if not arm.Wrapping then
				if (slot - arm.Pos).Magnitude < len * 1.6 then
					arm.Wrapping = true
				end
			else
				-- tourne autour en montant (barreau en hélice), puis se referme au sommet
				arm.Theta += arm.Spin * (len * 0.6) / R
				arm.H += len * 0.6
				slot = slotPos()
				if arm.H > g.CageH then
					slot = feet + Vector3.yAxis * (g.CageH + R * 0.55)
					if (slot - arm.Pos).Magnitude < len * 1.2 then
						arm.Steps = 1 -- dernier pas : le dôme est fermé
					end
				end
			end
			local to = slot - arm.Pos
			want = (if to.Magnitude > 0.05 then to.Unit else arm.Dir) * 2 + wander * 0.25
			-- ne JAMAIS traverser la cage : près de la cible, le barreau la CONTOURNE (tangente) vers sa place
			-- au lieu de foncer à travers ; et il est repoussé s'il entre dans le rayon.
			local hz = Vector3.new(arm.Pos.X - feet.X, 0, arm.Pos.Z - feet.Z)
			local hzM = hz.Magnitude
			if hzM < R * 1.7 and arm.Pos.Y < feet.Y + g.CageH + 1 then
				local out = if hzM > 0.05 then hz / hzM else Vector3.xAxis
				if not arm.Wrapping then
					local s = slot - feet
					local sd = Vector3.new(s.X, 0, s.Z)
					sd = if sd.Magnitude > 0.05 then sd.Unit else out
					local side = out.Z * sd.X - out.X * sd.Z
					local tang = Vector3.new(out.Z, 0, -out.X) * (if side >= 0 then 1 else -1)
					if out:Dot(sd) < 0.8 then -- sa place est de l'autre côté : on tourne autour
						want = tang * 2.2 + out * math.max(0, R * 1.15 - hzM) * 1.5 + to.Unit * 0.4 + wander * 0.2
					end
				end
				if hzM < R * 0.9 then
					want += out * 3
				end
			end
		end
	elseif g.Homing > 0 then
		-- GROUPES : chaque groupe de branches verrouille SON ennemi (différent des autres groupes) quand un
		-- ennemi entre dans la zone au bout d'une de ses branches ; tout le groupe se tend alors vers lui.
		local grp = arm.Group or 1
		local lock = g.GroupT[grp]
		if lock and (not lock.Parent or not table.find(list, lock)) then
			lock = nil
			g.GroupT[grp] = nil
		end
		if not lock then
			local taken = {}
			for k, v in g.GroupT do
				if k ~= grp then
					taken[v] = true
				end
			end
			local best, bestD = nil, g.Sense
			for _, root in list do
				local d = (root.Position - arm.Pos).Magnitude
				if d < bestD and not taken[root] then
					best, bestD = root, d
				end
			end
			if best then
				lock = best
				g.GroupT[grp] = best
				locked = true
			end
		end
		if lock then
			local to = lock.Position - arm.Pos
			if to.Magnitude < r + 1.6 then
				arm.Alive = false
				return interval
			end
			if to.Magnitude < g.Sense * 3 then
				want += to.Unit * (1.4 + g.Homing * 0.35)
			end
		end
	end
	want = want.Unit

	-- Ignore Obstacles : aucune sonde ; la matière traverse le décor et CASSE ce qui est cassable (user)
	if g.Phase then
		g.BreakT = (g.BreakT or 0) + 1
		if g.BreakT % 2 == 0 then -- une découpe toutes les 2 pousses (budget VoxelBreak)
			VoxelBreak.Hit(arm.Pos + want * len * 0.5, r + 1.2, 22)
		end
	end
	if not g.Phase then
		local ok, hit = free(arm.Pos, want, len * 2 + r, r)
		if not ok then
			local away = if hit then hit.Normal else -want
			local found = nil
			for k = 1, 8 do
				local cand = (want * 0.6 + away * (0.6 + k * 0.15) + rng:NextUnitVector() * 0.8).Unit
				if free(arm.Pos, cand, len + r, r) then
					found = cand
					break
				end
			end
			if not found then
				arm.Alive = false
				return interval
			end
			want = found
		end
	end
	local from = arm.Pos
	local to = from + want * len
	arm.Pos = to
	arm.Dir = want
	arm.Steps -= 1
	if arm.Steps <= 0 then
		arm.Alive = false
	end
	table.insert(g.Segments, { A = from, B = to, R = arm.Thick })
	local segIdx = addCollider(g, from, to, arm.Thick)
	g.Extent = math.max(g.Extent, (to - g.Origin).Magnitude + 3)
	FXBus.Push({
		k = "Grow", g = g.Id, p = from, d = to, w = arm.Thick, e = g.Element, n = g.Up,
		t = math.clamp(interval, 0.06, 0.4),
		l = if locked then 1 else nil,
		i = segIdx,
	})
	-- un arbre de FEU enflamme ce qu'il touche en poussant (herbe, bois, autres arbres)
	if g.Element == "Fire" then
		Matter.IgniteAround(to, arm.Thick + 2.5, 2)
	end
	arm.Thick = math.max(0.3 * g.Scale, arm.Thick * rng:NextNumber(0.9, 0.96))
	if arm.Depth < 2 and rng:NextNumber() < (spec.Fork or 0.12) + g.ForkAdd then
		local side = want:Cross(rng:NextUnitVector())
		side = if side.Magnitude > 0.05 then side.Unit else tangent(want)
		table.insert(born, {
			to, (want + side * rng:NextNumber(0.8, 1.6)), arm.Thick * rng:NextNumber(0.6, 0.8), arm.Step * 0.85, arm.Depth + 1,
			if arm.Steps < math.huge then math.ceil(arm.Steps * 0.6) else nil,
			-- en cage, la branche secondaire devient un barreau croisé voisin (au lieu de partir au hasard)
			if arm.Theta then { Theta = arm.Theta + rng:NextNumber(0.3, 0.6) * arm.Spin, Spin = -arm.Spin, H = arm.H, Wrapping = arm.Wrapping } else nil,
			arm.Group,
		})
	end
	return interval
end

local function grow(g, dt: number)
	local list = if g.Homing > 0 then targets(g.Owner) else {}
	local born = {}
	for _, arm in g.Arms do
		if not arm.Alive then
			continue
		end
		arm.Wait -= dt
		local guard = 0
		while arm.Alive and arm.Wait <= 0 and guard < 3 do
			guard += 1
			if #g.Segments >= g.MaxSegments then
				arm.Alive = false
				break
			end
			arm.Wait += stepArm(g, arm, list, born)
		end
	end
	for _, b in born do
		newArm(g, b[1], b[2], b[3], b[4], b[5], rng:NextNumber(0.05, 0.3), b[6])
		g.Arms[#g.Arms].Group = b[8] -- la branche secondaire garde le groupe (la cible) de son parent
		local cage = b[7]
		if cage then
			local a = g.Arms[#g.Arms]
			a.Theta, a.Spin, a.H, a.Wrapping = cage.Theta, cage.Spin, cage.H, cage.Wrapping
		end
	end
	-- ménage : les bras morts ne sont plus parcourus (maintien = beaucoup de bras)
	if #g.Arms > 40 then
		local alive = {}
		for _, arm in g.Arms do
			if arm.Alive then
				table.insert(alive, arm)
			end
		end
		g.Arms = alive
	end
end

local function closestOnSeg(p: Vector3, a: Vector3, b: Vector3): Vector3
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / math.max(ab:Dot(ab), 1e-4), 0, 1)
	return a + ab * t
end

local function hurt(g)
	local spec = g.Spec
	for _, hum in Combat.HumanoidsInRadius(g.Origin, g.Extent, g.Owner) do
		local root = Combat.RootOf(hum)
		if root then
			local c = root.Position
			for _, s in g.Segments do
				local reach = s.R * 0.5 + 1.8
				if (closestOnSeg(c, s.A, s.B) - c).Magnitude < reach
					or (closestOnSeg(c - Vector3.new(0, 2.5, 0), s.A, s.B) - (c - Vector3.new(0, 2.5, 0))).Magnitude < reach
					or (closestOnSeg(c + Vector3.new(0, 1.5, 0), s.A, s.B) - (c + Vector3.new(0, 1.5, 0))).Magnitude < reach then
					Combat.Damage(hum, spec.Damage or 4, g.Owner, g.Element, c + Vector3.new(0, 2.5, 0), g.DurMult)
					if g.Knockback > 0 then -- Recul : poussé loin de la branche (un coup par cible et par seconde)
						g.KnockT = g.KnockT or {}
						if (g.KnockT[hum] or 0) <= os.clock() then
							g.KnockT[hum] = os.clock() + 1
							local away = c - closestOnSeg(c, s.A, s.B)
							away = Vector3.new(away.X, 0, away.Z)
							away = if away.Magnitude > 0.1 then away.Unit else (c - g.Origin) * Vector3.new(1, 0, 1)
							away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
							Combat.Push(hum, away * g.Knockback + Vector3.new(0, g.Knockback * 0.35, 0), true)
						end
					end
					fireHook(g, "OnHit", closestOnSeg(c, s.A, s.B), nil, nil, nil, hum)
					break
				end
			end
		end
	end
end

local function zap(g)
	local spec = g.Spec
	local shots = 0
	for _, hum in Combat.HumanoidsInRadius(g.Origin, g.Extent + g.ZapR, g.Owner) do
		if shots >= 2 then
			break
		end
		local root = Combat.RootOf(hum)
		if not root then
			continue
		end
		local c = root.Position
		local best, bestD = nil, g.ZapR
		for _, s in g.Segments do
			local q = closestOnSeg(c, s.A, s.B)
			local d = (q - c).Magnitude
			if d < bestD then
				best, bestD = q, d
			end
		end
		if best then
			shots += 1
			local dmg = (spec.Damage or 4) * 1.6
			Combat.Damage(hum, dmg, g.Owner, "Lightning", c)
			FXBus.Push({ k = "Beam", p = best, d = c, e = "Lightning", w = 0.5 * math.sqrt(g.Scale), c = "LIGHTNING", j = 1 })
			local hit = { [hum] = true }
			local current = hum
			for _ = 1, spec.Chain or 3 do
				local from = Combat.RootOf(current)
				if not from then
					break
				end
				local nextHum, nextD = nil, CHAIN_RANGE
				for _, h in Combat.HumanoidsInRadius(from.Position, CHAIN_RANGE, g.Owner) do
					local r2 = not hit[h] and Combat.RootOf(h)
					if r2 and (r2.Position - from.Position).Magnitude < nextD then
						nextHum, nextD = h, (r2.Position - from.Position).Magnitude
					end
				end
				if not nextHum then
					break
				end
				hit[nextHum] = true
				dmg *= 0.75
				local to = Combat.RootOf(nextHum).Position
				Combat.Damage(nextHum, dmg, g.Owner, "Lightning", to)
				FXBus.Push({ k = "Beam", p = from.Position, d = to, e = "Lightning", w = 0.4 * math.sqrt(g.Scale), c = "LIGHTNING", j = 1 })
				current = nextHum
			end
		end
	end
end

local function arc(g)
	local segs = g.Segments
	if #segs < 2 then
		return
	end
	local a = segs[rng:NextInteger(1, #segs)]
	local from = a.A:Lerp(a.B, rng:NextNumber())
	local reach = 4 + 2 * math.sqrt(g.Scale)
	for _ = 1, 4 do
		local b = segs[rng:NextInteger(1, #segs)]
		local to = b.A:Lerp(b.B, rng:NextNumber())
		local d = (to - from).Magnitude
		if b ~= a and d > 1.5 and d < reach then
			FXBus.Push({ k = "Beam", p = from, d = to, e = "Lightning", w = 0.18 * math.sqrt(g.Scale), c = "ARC" })
			return
		end
	end
end

local function step(dt: number)
	if #growths == 0 then
		return
	end
	local filtered = false
	for i = #growths, 1, -1 do
		local g = growths[i]
		g.Age += dt
		if g.Age >= g.Life then
			endGrowth(i)
			continue
		end
		-- branche CHARGÉE (déclencheur à expiration -> projectile / rayon) : scintillement de l'infusion du sort suivant
		if g.Mark then
			g.MarkT -= dt
			if g.MarkT <= 0 then
				g.MarkT = 0.25
				local tip, tipDir = tipOf(g)
				FXBus.Push({ k = "TipMark", p = tip, d = tipDir, e = g.Mark.Element })
			end
		end
		if g.Age <= g.GrowUntil then
			if not filtered then
				refreshFilter()
				filtered = true
			end
			local ok, err = pcall(grow, g, dt)
			if not ok then
				warn("[Wand] croissance en erreur :", err)
				g.GrowUntil = 0
			end
		end
		g.DmgAcc += dt
		if g.DmgAcc >= (g.Spec.Interval or 0.4) then
			g.DmgAcc = 0
			local okH, errH = pcall(hurt, g)
			if not okH and not g.HurtWarned then
				g.HurtWarned = true
				warn("[Growth] contact en erreur :", errH)
			end
		end
		if g.Element == "Lightning" then
			g.ZapAcc += dt
			if g.ZapAcc >= 0.55 then
				g.ZapAcc = rng:NextNumber(-0.15, 0.1)
				pcall(zap, g)
			end
			g.ArcAcc += dt
			if g.ArcAcc >= 0.22 then
				g.ArcAcc = rng:NextNumber(-0.1, 0.05)
				pcall(arc, g)
			end
		end
	end
end

function GrowthService.ClearOwner(owner: Player)
	for i = #growths, 1, -1 do
		if growths[i].Owner == owner then
			growths[i].OnEnd = nil -- joueur parti / réinitialisé : on ne lance pas la suite de son deck
			growths[i].NoHooks = true
			endGrowth(i)
		end
	end
end

-- ══ RÉACTIONS D'ARBRE (WandShared/Reactions.Growths) : un coup d'élément touche un arbre infusé ══
-- Appelé par ZoneService.ReactAt (impacts, explosions, bouts de rayon, nouvelles zones). Rapport de taille :
-- les règles Wear demandent assez de contacts (somme des rayons >= 35 % de l'étendue de l'arbre).
local Reactions = require(ReplicatedStorage.WandShared.Reactions)

function GrowthService.ReactAt(pos: Vector3, element: string?, radius: number, owner: Player?): number
	if not element or not Reactions.Growths then
		return 0
	end
	local t = os.clock()
	local fired = 0
	local hitR = math.max(radius, 1.5)
	for _, g in growths do
		if not g.Element or g.Element == element or (g.ReactReady or 0) > t then
			continue
		end
		local rule
		for _, rx in Reactions.Growths do
			if rx.Hit == element and rx.On == g.Element then
				rule = rx
				break
			end
		end
		if not rule or (pos - g.Origin).Magnitude > g.Extent + hitR + 2 then
			continue
		end
		-- point de contact : le plus proche sur les branches
		local contact, best = nil, math.huge
		for _, sg in g.Segments do
			local c = closestOnSeg(pos, sg.A, sg.B)
			local d = (c - pos).Magnitude - sg.R * 0.5
			if d < best then
				best, contact = d, c
			end
		end
		if not contact or best > hitR + 1 then
			continue
		end
		g.ReactReady = t + (rule.Cooldown or 0.3)
		fired += 1
		local up = g.Up or Vector3.yAxis
		local center = g.Origin + up * math.min(g.Extent * 0.35, 6)
		local function setEl(el)
			g.Element = el
			FXBus.Push({ k = "GrowElem", g = g.Id, e = el or "", p = center })
		end
		local api
		api = {
			Pos = contact, Radius = g.Extent, HitRadius = hitR, Size = math.clamp(g.Extent / 3, 0.8, 8), Owner = owner, Element = g.Element,
			Strip = function() setEl(nil) end,
			SetElement = setEl,
			Extinguish = function() pcall(Matter.Extinguish, g.Origin, g.Extent + 1) end,
			Ignite = function() pcall(Matter.IgniteAround, contact, math.min(g.Extent, 10), 4) end,
			Explode = function(r, dmg, el) Combat.Explode(contact + up, r, dmg, owner, el or element) end,
			DamageAround = function(dmg, el) Combat.ZoneDamageInRadius(g.Origin, g.Extent, dmg, owner, el or element) end,
			Visual = function(name, scale) FXBus.Push({ k = "ReactFX", n = name, p = center, s = scale or 1 }) end,
			Label = function(text) FXBus.Push({ k = "React", p = center + up * 2, t = text, e = element }) end,
		}
		local run = rule.Run
		if rule.Wear then
			g.Wear = g.Wear or {}
			g.Wear[rule] = (g.Wear[rule] or 0) + hitR
			if g.Wear[rule] < g.Extent * 0.35 then
				-- pas encore assez : petite réaction AU POINT DE CONTACT
				run = rule.Local
				api.Visual = function(name, scale) FXBus.Push({ k = "ReactFX", n = name, p = contact, s = scale or 1 }) end
			end
		end
		if run then
			local ok, err = pcall(run, api)
			if not ok then
				warn("[Wand] réaction d'arbre " .. tostring(rule.Name) .. " :", err)
			end
		end
	end
	return fired
end

function GrowthService.Count(): number
	return #growths
end

function GrowthService.Init(projectileService)
	PS = projectileService -- accroches universelles (RunHooks)
	colliders = workspace:FindFirstChild("WandGrowthColliders") or Instance.new("Folder")
	colliders.Name = "WandGrowthColliders"
	colliders.Parent = workspace
	projectileService.OnGrowth = GrowthService.Create
	require(script.Parent.ZoneService).GrowthReact = GrowthService.ReactAt -- les coups sur zones touchent aussi les arbres
	RunService.Heartbeat:Connect(step)
end

return GrowthService

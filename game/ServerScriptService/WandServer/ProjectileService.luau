--[[
	WandServer/ProjectileService
	Simulation serveur de TOUS les projectiles dans une seule boucle Heartbeat (pas un script par projectile).

	• Mouvement analytique (vitesse, gravité, homing, orbite, boomerang), collisions par Spherecast entre
	  deux frames : déterministe, pas de tunneling, aucune physique Roblox.
	• Chaque projectile = Part invisible ancrée dans workspace.WandProjectiles ; le client y accroche ses VFX.
	• Tirs INSTANTANÉS (rayon, éclair) : un raycast immédiat, sans Part ; l'éclair saute ensuite de cible en cible.
	• Fin de vie commune (terminate) : explosion, VFX, charge de trigger, ZONE, téléportation, fragmentation.
	• Triggers : Hit (1er contact), Timer (après Delay, le projectile continue), Expire (à la disparition).
	• Plafonds : MaxLivePerPlayer / MaxLiveGlobal -> au-delà, Spawn refuse simplement.
	• Les zones (ZoneService) agissent sur les projectiles via ForEachInRadius / Remove (trou noir, bouclier...).
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.WandShared.Config)
local Combat = require(script.Parent.Combat)
local FXBus = require(script.Parent.FXBus)
local Matter = require(script.Parent.MatterService)
local VoxelBreak = require(script.Parent.VoxelBreak)

local Limits = Config.Limits
local GRAVITY = Config.Physics.Gravity
local HOMING_RANGE = 70
local ORBIT_RADIUS = 5
local CHAIN_RANGE = 22

local Catalog = require(ReplicatedStorage.WandShared.SpellCatalog)
local SpellPower = require(ReplicatedStorage.WandShared.SpellPower)
local runHook -- (accroches des cartes, défini plus bas)
local ProjectileService = {}
-- injectés par SpellEngine / ZoneService (évite les require circulaires)
ProjectileService.OnPayload = nil :: ((any, Vector3, Vector3, Player?, any, number) -> ())?
ProjectileService.OnZone = nil :: ((any, Vector3, Vector3?, Player?, string, Vector3, number?, number?) -> ())?
-- injecté par GrowthService : (stats, origin, dir, owner, reach) -> true si la croissance a pris
ProjectileService.OnGrowth = nil :: ((any, Vector3, Vector3, Player?, number?, number?) -> Vector3?)?
-- Mode MAINTIEN : pendant l'exécution du tir de départ, les sorts procéduraux ne sont pas lancés mais
-- COLLECTÉS ici (avec leurs stats finales) ; WandServer les fait ensuite pousser à chaque tick.
ProjectileService.Collect = nil :: { any }?

local function isProcedural(stats): boolean
	return stats.Growth ~= nil or (stats.Zone ~= nil and stats.Zone.Kind == "IceWall")
end
ProjectileService.IsProcedural = isProcedural

local folder: Folder
local live = {} -- tableau dense de projectiles actifs
local liveCount: { [any]: number } = {}
local nextId = 0
local rng = Random.new()

local function reflect(d: Vector3, n: Vector3): Vector3
	return d - 2 * d:Dot(n) * n
end

local function makeParams(owner: Player?, phase: boolean?)
	local filter = { folder }
	-- IGNORE OBSTACLES : projectiles et rayons traversent la matière GÉNÉRÉE par les sorts (ramure, murs de glace) (user)
	if phase then
		for _, n in { "WandGrowthColliders", "WandIceWalls" } do
			local f = workspace:FindFirstChild(n)
			if f then
				table.insert(filter, f)
			end
		end
	end
	local zones = workspace:FindFirstChild("WandZoneMarkers")
	if zones then
		table.insert(filter, zones)
	end
	if owner and owner.Character then
		table.insert(filter, owner.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true
	return params, filter
end

local function ownerRoot(owner: Player?): BasePart?
	local char = owner and owner.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- ── Fins de vie (partagées par projectiles et tirs instantanés) ───────────────────────────────────────────
-- ctx = { Stats, Owner, Payload, PayloadDone, Depth, Wand, Instant? }

local function releasePayload(ctx, pos: Vector3, dir: Vector3)
	if ctx.PayloadDone then
		return
	end
	ctx.PayloadDone = true
	FXBus.Push({ k = "Trigger", p = pos, e = ctx.Stats.Element, c = ctx.Stats.CardId })
	if ProjectileService.OnPayload then
		local ok, err = pcall(ProjectileService.OnPayload, ctx.Payload, pos, dir, ctx.Owner, ctx.Wand, ctx.Depth + 1)
		if not ok then
			warn("[Wand] erreur charge de trigger :", err)
		end
	end
end

local FRAGMENT_BASE = {
	CardId = "FRAGMENT", Speed = 70, Lifetime = 0.35, Size = 0.3, Radius = 0, Gravity = 0.5, Bounces = 1,
	Pierce = 0, Homing = 0, Trajectory = "Straight", Trigger = nil, Instant = false, Range = 0, Chain = 0,
	Knockback = 0, Fragments = 0, Aura = nil, Zone = nil, Self = false, OnEnd = nil, ZoneScale = 1,
	FxScale = 1, DurationMult = 1, Growth = nil, Mana = 0,
}

local function spawnFragments(ctx, pos: Vector3, normal: Vector3?)
	local s = ctx.Stats
	if (s.Fragments or 0) <= 0 then
		return
	end
	local frag = table.clone(FRAGMENT_BASE)
	frag.Element = s.Element
	frag.Damage = math.max(2, s.Damage * 0.3)
	for _ = 1, math.min(s.Fragments, Limits.MaxFragments) do
		local d = rng:NextUnitVector()
		if normal and d:Dot(normal) < 0 then
			d = -d
		end
		ProjectileService.Spawn(ctx.Owner, frag, pos + (normal or Vector3.zero) * 0.4, d, nil, ctx.Depth, ctx.Wand)
	end
end

local function teleportOwner(owner: Player?, pos: Vector3, normal: Vector3?)
	local root = ownerRoot(owner)
	local hum = root and root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	if not (root and hum and hum.Health > 0) then
		return
	end
	local from = root.Position
	local dest = pos + (normal or Vector3.zero) * 2.5 + Vector3.new(0, 3, 0)
	root.Parent:PivotTo(CFrame.new(dest) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	FXBus.Push({ k = "Teleport", p = from, d = dest })
end

-- collided : true si le projectile a réellement touché quelque chose (le client joue alors le son
-- de collision), false s'il disparaît en l'air (fin de vie) : seule l'explosion éventuelle s'entend.
-- ══ ACCROCHES UNIVERSELLES (cartes de SORT et de MODIFICATEUR : card.Hooks) ═══════════════════════════════════
-- Les 3 moteurs annoncent les MÊMES 4 moments, chacun à sa façon (phase 1.6) :
--   OnTick(ctx, dt)      EN VOL   projectile : chaque image | rayon : chaque segment (ctx.From -> ctx.Pos) | Ramure : chaque nouvelle branche
--   OnHit(ctx, humanoid) CONTACT  le tir touche une cible (projectile, rayon, branche qui blesse)
--   OnSurface(ctx)       SURFACE  le tir touche le décor (impact, rebond de rayon, branche qui s'ancre / bute)
--   OnEnd(ctx)           FIN      le projectile disparaît | bout du rayon | l'arbre meurt
-- Un MODIFICATEUR avec card.Hooks voit ses accroches tourner sur TOUT tir qui le porte (stats.ModStacks),
-- quel que soit le moteur : le moteur n'a jamais à connaître la carte. ctx.Stacks = exemplaires cumulés,
-- ctx.Mem = petite mémoire propre à CE tir et à CETTE carte (cadences, distances parcourues...).
local function hookCtx(rec, pos: Vector3, normal: Vector3?, dir: Vector3?)
	local s = rec.Stats
	local c = {
		Owner = rec.Owner, Stats = s, CardId = s.CardId, Element = s.Element,
		Pos = pos, Normal = normal, Dir = dir or Vector3.zAxis, Age = rec.Age or 0,
		From = rec.From, Engine = rec.Engine or (if rec.Instant then "Beam" else "Projectile"),
		Stacks = 1, Mem = {},
	}
	-- zone persistante (spec : Kind, Radius, Duration, Damage, Interval, Trail...) ; scale = taille (défaut : Gigantisme) ;
	-- element = forcer un élément (ex. traînée de FEU quel que soit le sort)
	function c.CreateZone(spec, scale: number?, element: string?)
		if ProjectileService.OnZone then
			return ProjectileService.OnZone(spec, c.Pos, c.Normal, c.Owner, element or c.Element, c.Dir, scale or s.ZoneScale or 1, s.DurationMult or 1)
		end
	end
	-- dégâts à tous les personnages dans un rayon (élément du sort par défaut) ; renvoie le nombre de cibles
	function c.DamageRadius(radius: number, damage: number, element: string?)
		return Combat.DamageInRadius(c.Pos, radius, damage, c.Owner, element or c.Element, nil, s.DurationMult)
	end
	-- dégâts directs à une cible
	function c.Damage(hum: Humanoid, damage: number, element: string?)
		Combat.Damage(hum, damage, c.Owner, element or c.Element, c.Pos, s.DurationMult)
	end
	-- explosion (dégâts dégressifs + souffle + matière)
	function c.Explode(radius: number, damage: number, element: string?)
		Combat.Explode(c.Pos, radius, damage, c.Owner, element or c.Element, nil, s.DurationMult)
	end
	-- effet visuel / sonore (message FX : k = "Impact", ...)
	function c.FX(msg)
		msg.p = msg.p or c.Pos
		FXBus.Push(msg)
	end
	c.Matter = Matter
	return c
end

-- liste (mise en cache sur les stats) des cartes à accroches portées par un tir : le sort + ses modificateurs
local function hookCards(s): { any }
	local list = s.HookCards
	if list then
		return list
	end
	list = {}
	local card = Catalog.ById[s.CardId]
	if card and card.Hooks then
		table.insert(list, { Card = card, Stacks = 1 })
	end
	for id, n in s.ModStacks or {} do
		local m = Catalog.ById[id]
		if m and m.Hooks and n > 0 then
			table.insert(list, { Card = m, Stacks = n })
		end
	end
	s.HookCards = list
	return list
end

runHook = function(rec, name: string, pos: Vector3, normal: Vector3?, dir: Vector3?, ...)
	local list = hookCards(rec.Stats)
	if #list == 0 then
		return
	end
	local ctx = nil
	for _, h in list do
		local fn = h.Card.Hooks[name]
		if fn then
			ctx = ctx or hookCtx(rec, pos, normal, dir)
			ctx.Stacks = h.Stacks
			rec.HookMem = rec.HookMem or {}
			rec.HookMem[h.Card.Id] = rec.HookMem[h.Card.Id] or {}
			ctx.Mem = rec.HookMem[h.Card.Id]
			ctx.Source = h.Card.Id
			local ok, err = pcall(fn, ctx, ...)
			if not ok then
				warn(("[Wand] accroche %s de %s en erreur : %s"):format(name, tostring(h.Card.Id), tostring(err)))
			end
		end
	end
end
-- pour les autres moteurs (GrowthService) : rec = { Stats, Owner, Age, From, Engine, HookMem }
function ProjectileService.RunHooks(rec, name: string, pos: Vector3, normal: Vector3?, dir: Vector3?, ...)
	runHook(rec, name, pos, normal, dir, ...)
end

local function terminate(ctx, pos: Vector3, normal: Vector3?, dir: Vector3, collided: boolean?)
	local s = ctx.Stats
	if s.Radius > 0 then
		Combat.Explode(pos, s.Radius, s.Damage, ctx.Owner, s.Element, if s.Knockback > 0 then s.Knockback else nil, s.DurationMult, s.SelfDamage)
	end
	-- faisceau MAINTENU : pas d'impact répété à chaque tick (le client anime le point d'arrivée en continu)
	if not s.HoldTick then
		FXBus.Push({ k = "Impact", p = pos, n = normal, e = s.Element, r = s.Radius, s = s.Size, c = s.CardId, x = collided == true, z = s.FxScale,
			kb = if (s.Knockback or 0) >= 20 then 1 else nil }) -- recul : choc sourd en plus
	end
	-- CASSE-STRUCTURES selon la PUISSANCE du sort (carte avec BreakAbove, ex. boule de feu géante)
	do
		local card = s.CardId and Catalog.ById[s.CardId]
		local br = card and card.BreakAbove and SpellPower.BreakRadius(s, card.BreakAbove)
		if br then
			local _, cubes = VoxelBreak.Hit(pos, br, 30)
			if cubes and #cubes.L > 0 then
				FXBus.Push({ k = "VoxDebris", p = pos, w = 30, q = cubes })
			end
		end
	end
	local trig = s.Trigger
	if trig and (trig.Kind == "Expire" or trig.Kind == "Timer" or ctx.Instant) then
		local p, d = pos, dir
		if normal then
			p, d = pos + normal * 0.6, reflect(dir, normal)
		end
		-- MINUTERIE : le délai est TOUJOURS respecté (impact précoce, durée courte, rayon instantané) (user)
		local rem = if trig.Kind == "Timer" then (trig.Delay or 0.3) - (ctx.Age or 0) else 0
		if rem > 0.02 and not ctx.PayloadDone then
			task.delay(rem, releasePayload, ctx, p, d)
		else
			releasePayload(ctx, p, d)
		end
	end
	-- RÉACTIONS DE ZONE : le sort touche une zone au sol d'un autre élément (avant de poser sa propre zone)
	if ProjectileService.OnReact and not s.HoldTick then
		pcall(ProjectileService.OnReact, pos, s.Element, math.max(s.Radius or 0, 2), ctx.Owner)
	end
	-- ACCROCHE OnEnd de la carte (ex. boule de feu : zone au sol)
	if not s.HoldTick then
		runHook(ctx, "OnEnd", pos, normal, dir)
	end
	if s.Zone and ProjectileService.OnZone then
		local ok, err = pcall(ProjectileService.OnZone, s.Zone, pos, normal, ctx.Owner, s.Element, dir, s.ZoneScale or 1, s.DurationMult or 1)
		if not ok then
			warn("[Wand] erreur création de zone :", err)
		end
	end
	if s.OnEnd == "Teleport" then
		teleportOwner(ctx.Owner, pos, normal)
	end
	spawnFragments(ctx, pos, normal)
end

-- ── Tirs instantanés (Rayon, Éclair) ─────────────────────────────────────────────────────────────────
-- Pas de compensation de ping pour l'instant : la cible est jugée à sa position serveur actuelle.
local MAX_INSTANT_REACH = 200

-- reach : distance jusqu'au curseur. Le tir va AU MOINS jusqu'au point visé (borné à 200 studs),
-- sinon un rayon de portée 80 s'arrêtait avant un mur lointain que le joueur visait.
local function fireInstant(owner: Player?, stats, origin: Vector3, dir: Vector3, payload, depth: number, wand, reach: number?)
	local ctx = { Stats = stats, Owner = owner, Payload = payload, PayloadDone = payload == nil, Depth = depth, Wand = wand, Instant = true }
	local params, filter = makeParams(owner, stats.Phase == true)
	local range = math.clamp(math.max(stats.Range, reach or 0), 5, MAX_INSTANT_REACH)
	local endPos, endNormal = origin + dir * range, nil
	local pierce = stats.Pierce
	local lastHum: Humanoid? = nil
	local hit: { [Humanoid]: boolean } = {}

	-- REBOND (modificateur) : le rayon se RÉFLÉCHIT sur le décor et repart avec la portée restante,
	-- une fois par rebond. Chaque segment est affiché, blesse et touche la matière.
	local bouncesLeft = math.clamp(stats.Bounces or 0, 0, 8)
	local segStart, segDir, remaining = origin, dir, range
	local firstSeg = true
	while true do
		local target = segStart + segDir * remaining
		local pos = segStart
		endPos, endNormal = target, nil
		for _ = 1, 14 do -- borné : au plus 13 perforations
			local res = workspace:Raycast(pos, target - pos, params)
			if not res then
				break
			end
			local hum, model = Combat.HumanoidFrom(res.Instance)
			if hum and model then
				if not hit[hum] then
					hit[hum] = true
					-- coup DIRECT (saut de la foudre) sauf si le sort enchaîne déjà lui-même (Éclair)
					Combat.Damage(hum, stats.Damage, owner, stats.Element, res.Position, stats.DurationMult, (stats.Chain or 0) == 0 and not stats.HoldTick)
					if stats.Knockback > 0 then
						Combat.Push(hum, segDir * stats.Knockback + Vector3.new(0, stats.Knockback * 0.3, 0), true)
					end
					-- ACCROCHE OnHit : le rayon touche une cible
					runHook(ctx, "OnHit", res.Position, res.Normal, segDir, hum)
				end
				lastHum = hum
				table.insert(filter, model)
				params.FilterDescendantsInstances = filter
				if pierce <= 0 then
					endPos = res.Position
					break
				end
				pierce -= 1
				pos = res.Position
			else
				-- IGNORE OBSTACLES (user) : le rayon TRAVERSE la matière cassable en la détruisant ; sur une matière
				-- indestructible il REBONDIT (rebond forcé, en plus des rebonds normaux, 4 max)
				if stats.Phase and VoxelBreak.IsBreakable(res.Instance) then
					Matter.Hit(res.Instance, stats.Damage, stats.Element, res.Position, res.Normal, owner, res.Material)
					VoxelBreak.Hit(res.Position, math.clamp((stats.Size or 0.5) * 2.5 * (stats.FxScale or 1) ^ 0.5, 1.6, 6), 30)
					table.insert(filter, res.Instance)
					params.FilterDescendantsInstances = filter
					pos = res.Position + segDir * 0.05
					continue
				end
				endPos, endNormal = res.Position, res.Normal
				if stats.Phase then
					ctx.ForceBounce = (ctx.ForceBounce or 0) + 1
				end
				-- rayon sur le décor : la matière encaisse (un rayon de feu maintenu enflamme l'herbe en continu)
				Matter.Hit(res.Instance, stats.Damage, stats.Element, res.Position, res.Normal, owner, res.Material)
				break
			end
		end
		if firstSeg and stats.HoldTick then
			-- faisceau CONTINU : mise à jour du même faisceau (g = identifiant), pas un nouveau rayon
			FXBus.Push({ k = "HoldBeam", g = stats.HoldId, p = segStart, d = endPos, e = stats.Element, w = stats.Size, c = stats.CardId, n = endNormal })
		else
			FXBus.Push({ k = "Beam", p = segStart, d = endPos, e = stats.Element, w = stats.Size, c = stats.CardId, z = stats.FxScale,
				h = if stats.HoldTick then 1 else nil, j = if firstSeg then nil else 1 })
		end
		-- ACCROCHE OnTick : « en vol » pour un rayon = chaque SEGMENT (ctx.From -> ctx.Pos)
		ctx.From = segStart
		runHook(ctx, "OnTick", endPos, endNormal, segDir, 0)
		-- ACCROCHE OnSurface : chaque surface du décor touchée par le rayon (rebonds compris)
		if endNormal then
			runHook(ctx, "OnSurface", endPos, endNormal, segDir)
		end
		remaining -= (endPos - segStart).Magnitude
		local forced = stats.Phase and endNormal and (ctx.ForceBounce or 0) > 0 and (ctx.ForceBounce or 0) <= 4
		if not endNormal or (bouncesLeft <= 0 and not forced) or remaining < 2 then
			break
		end
		if not forced then
			bouncesLeft -= 1
		end
		segDir = reflect(segDir, endNormal)
		segStart = endPos + endNormal * 0.05
		firstSeg = false
	end
	dir = segDir

	-- Éclair : saute vers la cible la plus proche pas encore touchée (dégâts x0.75 par saut)
	local current = lastHum
	for _ = 1, stats.Chain do
		local fromRoot = current and Combat.RootOf(current)
		if not fromRoot then
			break
		end
		local from = fromRoot.Position
		local best, bestDist = nil, CHAIN_RANGE
		for _, h in Combat.HumanoidsInRadius(from, CHAIN_RANGE, owner) do
			local r = not hit[h] and Combat.RootOf(h)
			if r and (r.Position - from).Magnitude < bestDist then
				best, bestDist = h, (r.Position - from).Magnitude
			end
		end
		if not best then
			break
		end
		hit[best] = true
		local to = Combat.RootOf(best).Position
		Combat.Damage(best, stats.Damage * 0.75, owner, stats.Element, to, stats.DurationMult)
		FXBus.Push({ k = "Beam", p = from, d = to, e = stats.Element, w = stats.Size * 0.8, c = stats.CardId, h = if stats.HoldTick then 1 else nil, j = 1 })
		current = best
		endPos, endNormal = to, nil
	end

	terminate(ctx, endPos, endNormal, dir, endNormal ~= nil or lastHum ~= nil)
	return endPos, endNormal
end
-- (utilisé par le Maintien : un tick de faisceau continu, qui renvoie son point d'arrivée)
ProjectileService.FireInstant = fireInstant
ProjectileService.Reflect = reflect

-- ── Création ─────────────────────────────────────────────────────────────────────────────────────────
-- D'OÙ part la suite du deck quand un ARBRE meurt (déclencheur à expiration) : selon la FAMILLE du sort suivant
--   Projectile / Rayon : du bout de la branche la plus avancée, DANS LE SENS DE LA BRANCHE
--   (viser un ennemi = rôle de Tête chercheuse, pas du déclencheur : la famille décide seulement du POINT DE DÉPART)
--   Procédural / Piège : au pied de l'arbre, sur sa surface (nouvel arbre / piège au même endroit)
--   Sur soi : sans importance (apparaît sur le lanceur)
local function payloadFamily(payload): string
	for _, shot in (payload and payload.Shots) or {} do
		local f = shot.Card and shot.Card.Family
		if f and f ~= "Multicast" then
			return f
		end
	end
	return "Projectile"
end

local function payloadLaunch(payload, tree, owner: Player?, fallbackDir: Vector3): (Vector3, Vector3)
	local fam = payloadFamily(payload)
	if fam == "Procedural" or fam == "Trap" then
		return tree.Base + tree.Up * 0.6, -tree.Up -- la surface la plus proche = celle de l'arbre
	end
	local from = tree.Tip + tree.TipDir * 0.8
	return from, if tree.TipDir.Magnitude > 0.5 then tree.TipDir else fallbackDir
end

function ProjectileService.Spawn(owner: Player?, stats, origin: Vector3, dir: Vector3, payload, depth: number, wand, reach: number?)
	-- Sorts "sur soi" (bouclier, cercle de feu) : pas de projectile, la zone apparaît sur le lanceur.
	if stats.Self then
		local root = ownerRoot(owner)
		local at = if root then root.Position else origin
		if stats.Zone and ProjectileService.OnZone then
			local ok, err = pcall(ProjectileService.OnZone, stats.Zone, at, nil, owner, stats.Element, dir, stats.ZoneScale or 1, stats.DurationMult or 1)
			if not ok then
				warn("[Wand] erreur création de zone :", err)
			end
		end
		if payload then
			local c = { Stats = stats, Owner = owner, Payload = payload, PayloadDone = false, Depth = depth, Wand = wand }
			local t = stats.Trigger
			if t and t.Kind == "Timer" then
				task.delay(t.Delay or 0.3, releasePayload, c, origin, dir)
			else
				releasePayload(c, origin, dir)
			end
		end
		return nil
	end
	-- MAINTIEN : sorts procéduraux ET rayons instantanés (rayon, éclair) sont relancés à chaque tick
	-- PIÈGE : posé sur une surface ; sa charge (cartes suivantes) partira quand il se déclenche.
	-- (Le Maintien ne s'applique pas aux pièges : ils sont posés une seule fois.)
	if stats.Trap then
		if ProjectileService.OnTrap then
			local ok, err = pcall(ProjectileService.OnTrap, stats, origin, dir, owner, reach, depth, payload, wand)
			if not ok then
				warn("[Wand] erreur pose de piège :", err)
			end
		end
		return nil
	end
	if ProjectileService.Collect and depth == 0 and (isProcedural(stats) or (stats.Instant and not stats.Self)) then
		-- on garde aussi la CHARGE (déclencheur) : un rayon maintenu doit continuer à la libérer
		stats.HoldPayload = payload
		table.insert(ProjectileService.Collect, stats)
		return nil
	end
	-- Sort PROCÉDURAL (branche) : pousse depuis le point visé ; la charge éventuelle part de ce point
	-- (déclencheur « à expiration » : la charge part à la MORT de l'arbre, d'un endroit choisi selon la famille du sort suivant)
	if stats.Growth then
		local ok, at = false, nil
		local onEnd, mark = nil, nil
		local trig = stats.Trigger
		if payload and trig and trig.Kind == "Expire" then
			local fam = payloadFamily(payload)
			if fam == "Projectile" or fam == "Beam" then
				-- la branche de départ scintille de l'élément du sort qui va en partir
				local first = payload.Shots[1]
				mark = { Element = (first and first.State and first.State.Element) or (first and first.Card.Element) or "Arcane" }
			end
			local ctx = { Stats = stats, Owner = owner, Payload = payload, PayloadDone = false, Depth = depth, Wand = wand }
			onEnd = function(tree)
				local pos, d = payloadLaunch(payload, tree, owner, dir)
				releasePayload(ctx, pos, d)
			end
		end
		if ProjectileService.OnGrowth then
			local success, res = pcall(ProjectileService.OnGrowth, stats, origin, dir, owner, reach, depth, onEnd, mark)
			if success then
				ok, at = res ~= nil, res
			else
				warn("[Wand] erreur croissance :", res)
			end
		end
		if payload and not (onEnd and ok) then -- (arbre raté : la charge part tout de suite, comme avant)
			releasePayload({ Stats = stats, Owner = owner, Payload = payload, PayloadDone = false, Depth = depth, Wand = wand }, if ok then at else origin, dir)
		end
		return nil
	end
	if stats.Instant then
		fireInstant(owner, stats, origin, dir, payload, depth, wand, reach)
		return nil
	end

	if #live >= Limits.MaxLiveGlobal then
		return nil
	end
	local key = owner or "world"
	local count = liveCount[key] or 0
	if count >= Limits.MaxLivePerPlayer then
		return nil
	end
	liveCount[key] = count + 1
	nextId += 1

	local part = Instance.new("Part")
	part.Name = "P" .. nextId
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * stats.Size
	part.CFrame = CFrame.lookAt(origin, origin + dir)
	part:SetAttribute("Element", stats.Element)
	part:SetAttribute("Card", stats.CardId)
	part:SetAttribute("Size", stats.Size)
	part:SetAttribute("Fx", stats.FxScale or 1)
	-- modificateurs qui changent le SON du vol (le client module la boucle en conséquence)
	if stats.Trajectory ~= "Straight" then
		part:SetAttribute("Traj", stats.Trajectory)
	end
	if stats.Homing > 0 then
		part:SetAttribute("Homing", true)
	end
	if stats.Gravity >= 0.9 then
		part:SetAttribute("Heavy", true)
	end
	part:SetAttribute("Owner", if owner then owner.UserId else 0) -- le client du tireur sait que c'est son tir
	part.Parent = folder

	local params, filter = makeParams(owner, stats.Phase == true)
	local rec = {
		Part = part,
		Owner = owner,
		Key = key,
		Stats = stats,
		Pos = origin, -- position "physique" (Wave/Spiral ne sont qu'un décalage visuel)
		Vel = dir * stats.Speed,
		Speed0 = stats.Speed,
		Age = 0,
		Payload = payload,
		PayloadDone = payload == nil,
		Depth = depth,
		Wand = wand,
		Params = params,
		Filter = filter,
		Bounces = stats.Bounces,
		Pierce = stats.Pierce,
		Hit = {},
		Target = nil,
		Retarget = 0,
		Phase = rng:NextNumber(0, math.pi * 2),
		Angle = math.atan2(dir.Z, dir.X), -- orbite : démarre dans la direction visée
		AuraT = 0,
		Dead = false,
	}
	table.insert(live, rec)
	return rec
end

-- ── Collisions ───────────────────────────────────────────────────────────────────────────────────────
-- Retourne true si le projectile continue (perforation / rebond / scie).
local function onHit(rec, result: RaycastResult): boolean
	local s = rec.Stats
	local dir = if rec.Vel.Magnitude > 1e-3 then rec.Vel.Unit else Vector3.zAxis
	local isHitTrigger = s.Trigger and s.Trigger.Kind == "Hit"
	local hum, model = Combat.HumanoidFrom(result.Instance)

	if hum and model then
		-- on ignore ce personnage pour la suite (sinon le Spherecast le retoucherait à chaque frame)
		table.insert(rec.Filter, model)
		rec.Params.FilterDescendantsInstances = rec.Filter
		if s.Aura then
			rec.Pos = result.Position -- la scie traverse : ce sont ses ticks d'aura qui blessent
			return true
		end
		if not rec.Hit[hum] then
			rec.Hit[hum] = true
			Combat.Damage(hum, s.Damage, rec.Owner, s.Element, result.Position, s.DurationMult, (s.Chain or 0) == 0) -- coup DIRECT
			if s.Knockback > 0 then
				Combat.Push(hum, dir * s.Knockback + Vector3.new(0, s.Knockback * 0.3, 0), true)
			end
			runHook(rec, "OnHit", result.Position, result.Normal, dir, hum)
		end
		if isHitTrigger then
			releasePayload(rec, result.Position, dir)
		end
		if rec.Pierce > 0 then
			rec.Pierce -= 1
			rec.Pos = result.Position
			return true
		end
		terminate(rec, result.Position, nil, dir, true)
		return false
	end

	-- décor : la matière touchée encaisse (bois qui brûle, glace qui fond, pierre écornée...)
	Matter.Hit(result.Instance, s.Damage, s.Element, result.Position, result.Normal, rec.Owner, result.Material)
	-- ACCROCHE OnSurface : le projectile touche le décor (impact ou rebond)
	runHook(rec, "OnSurface", result.Position, result.Normal, dir)
	local bounced = reflect(dir, result.Normal)
	if isHitTrigger then
		releasePayload(rec, result.Position + result.Normal * 0.6, bounced)
	end
	if rec.Bounces > 0 then
		rec.Bounces -= 1
		-- vitesse d'arrivée normale à la surface : un choc franc sonne fort, une glissade presque pas
		local hitSpeed = math.abs(rec.Vel:Dot(result.Normal))
		rec.Vel = bounced * rec.Vel.Magnitude * 0.9
		rec.Pos = result.Position + result.Normal * (s.Size * 0.5 + 0.05)
		FXBus.Push({ k = "Bounce", p = result.Position, n = result.Normal, e = s.Element, c = s.CardId, s = s.Size, z = s.FxScale, v = math.floor(hitSpeed) })
		return true
	end
	terminate(rec, result.Position, result.Normal, dir, true)
	return false
end

-- ── Simulation ─────────────────────────────────────────────────────────────────────────────────────────
-- Avance un projectile d'un pas. Retourne false s'il doit être retiré.
local function update(rec, dt: number): boolean
	local s = rec.Stats
	if rec.Dead or not rec.Part.Parent then
		return false
	end
	rec.Age += dt
	local traj = s.Trajectory

	if traj == "Orbit" then
		-- tourne autour du lanceur (vitesse angulaire dérivée de la vitesse du sort)
		local root = ownerRoot(rec.Owner)
		if root then
			local orR = s.OrbitRadius or ORBIT_RADIUS
			rec.Angle += math.clamp(s.Speed / orR * 0.25, 2, 9) * dt
			local target = root.Position + Vector3.new(math.cos(rec.Angle) * orR, 0.5, math.sin(rec.Angle) * orR)
			rec.Vel = (target - rec.Pos) / math.max(dt, 1e-3)
		end
	else
		if s.Gravity ~= 0 then
			rec.Vel += Vector3.new(0, -GRAVITY * s.Gravity * dt, 0)
		end
		if traj == "Boomerang" and rec.Age > s.Lifetime * 0.35 then
			local root = ownerRoot(rec.Owner)
			if root then
				local back = root.Position - rec.Pos
				if back.Magnitude < 3 and rec.Age > s.Lifetime * 0.45 then
					return false -- rattrapé : disparaît sans effet
				end
				local desired = back.Unit * math.max(rec.Speed0, 20)
				rec.Vel = rec.Vel:Lerp(desired, math.clamp(4 * dt, 0, 1))
			end
		elseif s.Homing > 0 then
			rec.Retarget -= dt
			if rec.Retarget <= 0 then
				rec.Retarget = 0.15 -- recherche de cible 6-7 fois/s seulement
				-- rayon de détection selon la TAILLE du sort (Gigantisme) (user)
				rec.Target = Combat.FindTarget(rec.Pos, HOMING_RANGE * math.clamp((s.FxScale or 1) ^ 0.5, 1, 3) * math.clamp(s.Homing / 6, 1, 3) ^ 0.5, rec.Owner)
			end
			local target = rec.Target
			if target and target.Parent then
				local to = target.Position - rec.Pos
				local speed = rec.Vel.Magnitude
				if to.Magnitude > 0.5 and speed > 1e-3 then
					local newDir = rec.Vel.Unit:Lerp(to.Unit, math.clamp(s.Homing * dt, 0, 1))
					if newDir.Magnitude > 1e-3 then
						rec.Vel = newDir.Unit * speed
					end
				end
			end
		end
	end

	-- ACCROCHE OnTick de la carte (pendant le vol)
	runHook(rec, "OnTick", rec.Pos, nil, if rec.Vel.Magnitude > 1e-3 then rec.Vel.Unit else nil, dt)

	-- aura (disque-scie) : dégâts périodiques autour du projectile
	if s.Aura then
		rec.AuraT -= dt
		if rec.AuraT <= 0 then
			rec.AuraT = s.Aura.Interval or 0.2
			if Combat.DamageInRadius(rec.Pos, s.Aura.Radius * (s.ZoneScale or 1), s.Aura.Damage, rec.Owner, s.Element) > 0 then
				rec.GrindT = 0.35 -- "morsure" : la scie ralentit tant qu'elle déchiquette quelque chose
			end
		end
	end
	local moveScale = 1
	if (rec.GrindT or 0) > 0 then
		rec.GrindT -= dt
		moveScale = 0.15
	end

	local trig = s.Trigger
	if trig and trig.Kind == "Timer" and not rec.PayloadDone and rec.Age >= (trig.Delay or 0.3) then
		releasePayload(rec, rec.Pos, if rec.Vel.Magnitude > 1e-3 then rec.Vel.Unit else Vector3.zAxis)
	end

	local disp = rec.Vel * dt * moveScale
	local result = if disp.Magnitude > 1e-4 then workspace:Spherecast(rec.Pos, math.max(0.1, s.Size * 0.5), disp, rec.Params) else nil
	if result then
		if not onHit(rec, result) then
			return false
		end
	else
		rec.Pos += disp
	end

	if rec.Age >= s.Lifetime then
		terminate(rec, rec.Pos, nil, if rec.Vel.Magnitude > 1e-3 then rec.Vel.Unit else Vector3.zAxis)
		return false
	end

	-- décalage visuel de trajectoire (n'affecte pas la collision)
	local visual = rec.Pos
	local speed = rec.Vel.Magnitude
	if (traj == "Wave" or traj == "Spiral") and speed > 1e-3 then
		local fwd = rec.Vel / speed
		local right = fwd:Cross(Vector3.yAxis)
		right = if right.Magnitude < 1e-3 then Vector3.xAxis else right.Unit
		local up = right:Cross(fwd)
		local t = rec.Age * 14 + rec.Phase
		local ramp = math.min(1, rec.Age * 6)
		if traj == "Wave" then
			visual += right * math.sin(t) * 1.8 * ramp
		else
			visual += (right * math.cos(t) + up * math.sin(t)) * (s.SpiralRadius or 1.4) * ramp -- rayon élargi par le cumul de Spirale
		end
	end
	rec.Part.CFrame = CFrame.lookAt(visual, visual + (if speed > 1e-3 then rec.Vel else Vector3.zAxis))
	return true
end

local function removeAt(i: number)
	local rec = live[i]
	if not rec then
		return
	end
	local n = #live
	live[i] = live[n]
	live[n] = nil
	liveCount[rec.Key] = math.max(0, (liveCount[rec.Key] or 1) - 1)
	rec.Part:Destroy()
end

function ProjectileService.Step(dt: number)
	-- parcours à l'envers + suppression par échange : O(1) par retrait
	-- (un projectile peut en créer / en retirer d'autres pendant sa mise à jour : la liste peut bouger,
	-- on revérifie donc l'indice du projectile avant de le retirer)
	for i = #live, 1, -1 do
		local rec = live[i]
		if not rec then
			continue
		end
		local ok, alive = pcall(update, rec, dt)
		if not ok then
			warn("[Wand] projectile en erreur, supprimé :", alive)
			alive = false
		end
		if not alive then
			local at = if live[i] == rec then i else table.find(live, rec)
			if at then
				removeAt(at)
			end
		end
	end
end

-- ── API pour les zones ──────────────────────────────────────────────────────────────────────────────────
-- Appelle fn(rec) pour chaque projectile vivant dans le rayon. fn peut modifier rec.Vel.
function ProjectileService.ForEachInRadius(pos: Vector3, radius: number, fn: (any) -> ())
	for _, rec in live do
		if not rec.Dead and (rec.Pos - pos).Magnitude <= radius then
			fn(rec)
		end
	end
end

-- Supprime un projectile sans aucun effet de fin (contre-sort, bouclier).
function ProjectileService.Remove(rec)
	if not rec.Dead then
		rec.Dead = true
		FXBus.Push({ k = "Dispel", p = rec.Pos, e = rec.Stats.Element })
	end
end

function ProjectileService.ClearOwner(owner: Player)
	for i = #live, 1, -1 do
		if live[i].Owner == owner then
			removeAt(i)
		end
	end
	liveCount[owner] = nil
end

function ProjectileService.LiveCount(): number
	return #live
end

function ProjectileService.Init()
	folder = workspace:FindFirstChild("WandProjectiles") or Instance.new("Folder")
	folder.Name = "WandProjectiles"
	folder.Parent = workspace
	Combat.Init(folder)
	RunService.Heartbeat:Connect(ProjectileService.Step)
end

return ProjectileService

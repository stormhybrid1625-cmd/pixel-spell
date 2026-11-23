--[[
	WandServer/ZoneService — Zones persistantes (trou noir, gaz, mur de glace, cercle de feu, mine,
	bouclier, contre-sort).

	• Une seule boucle Heartbeat pour toutes les zones ; chaque type a un handler (Tick) déclaré dans KINDS.
	• Réplication : chaque zone a un MARQUEUR (Part invisible, CanQuery = false) dans
	  workspace.WandZoneMarkers avec ses attributs (Kind, Radius, Element, Duration). Le client y accroche ses
	  VFX (sprites animés, étincelles, lumières) et les retire quand le marqueur disparaît.
	• Le mur de glace crée de VRAIES Parts collidables (workspace.WandIceWalls) : elles bloquent
	  déplacements et projectiles.
	• Plafonds : MaxZonesPerPlayer / MaxZonesGlobal (la plus ancienne zone du joueur est retirée).
	• Le lanceur est immunisé contre ses propres zones (comme pour ses projectiles).
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.WandShared.Config)
local Combat = require(script.Parent.Combat)
local FXBus = require(script.Parent.FXBus)
local Matter = require(script.Parent.MatterService)
local ProjectileService = require(script.Parent.ProjectileService)
-- COMPORTEMENTS déclarés par les éléments (WandShared/Elements/<Élément>.Behavior) : PatchFalls (le feu tombe),
-- PatchSticksToWalls (le givre se colle aux murs), Extinguishes (éteint le feu), PatchDurationMult (durée des zones)
local Elements = require(ReplicatedStorage.WandShared.Elements)
local B = Elements.Behavior

local Limits = Config.Limits

local ZoneService = {}

local markers: Folder
local walls: Folder
local zones = {}
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function now(): number
	return workspace:GetServerTimeNow()
end

local function ownerRoot(owner: Player?): BasePart?
	local char = owner and owner.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Point au sol sous `pos` (ou `pos` lui-même si rien en dessous)
local function ground(pos: Vector3, reach: number?): Vector3
	local list = { markers, walls, workspace:FindFirstChild("WandProjectiles") }
	local dummies = workspace:FindFirstChild("WandDummies")
	if dummies then
		table.insert(list, dummies)
	end
	for _, p in game:GetService("Players"):GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -(reach or 40), 0), groundParams)
	return if hit then hit.Position else pos
end

local function newMarker(zone)
	local p = Instance.new("Part")
	p.Name = zone.Kind
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.5
	p.CFrame = CFrame.new(zone.Pos)
	p:SetAttribute("Kind", zone.Kind)
	p:SetAttribute("Radius", zone.Radius)
	p:SetAttribute("Element", zone.Element)
	p:SetAttribute("Trail", if zone.Spec and zone.Spec.Trail then true else nil) -- traînée (TF) : morceaux en ligne
	p:SetAttribute("Duration", zone.Duration)
	p:SetAttribute("Scale", zone.Scale)
	if zone.Kind == "Patch" and zone.Normal then
		p:SetAttribute("Normal", zone.Normal)
	end
	if zone.DropFrom then -- feu qui tombe d'un mur : point de départ + durée de chute pour l'animation
		p:SetAttribute("DropFrom", zone.DropFrom)
		p:SetAttribute("FallTime", zone.FallTime)
	end
	p.Parent = markers
	return p
end

local function isEnemyProjectile(zone, rec): boolean
	return rec.Owner ~= zone.Owner
end

-- ── Comportements par type ──────────────────────────────────────────────────────────────────────────────
-- Init(zone) : préparation ; Tick(zone, dt) : chaque frame ; Expire(zone) : nettoyage spécifique.
local KINDS = {}

KINDS.BlackHole = {
	Tick = function(zone, dt)
		local spec = zone.Spec
		-- aspire les projectiles (alliés compris : c'est ce qui crée les orbites chaotiques)
		ProjectileService.ForEachInRadius(zone.Pos, zone.Radius, function(rec)
			local to = zone.Pos - rec.Pos
			local d = to.Magnitude
			if d < 1.2 then
				ProjectileService.Remove(rec) -- englouti
			else
				local swirl = to.Unit:Cross(Vector3.yAxis) * 0.6
				rec.Vel += (to.Unit + swirl) * spec.Pull * 3 * (1 - d / zone.Radius) * dt
			end
		end)
		-- aspire et broie les personnages, 10 fois par seconde
		zone.Acc += dt
		if zone.Acc >= 0.1 then
			zone.Acc = 0
			for _, hum in Combat.HumanoidsInRadius(zone.Pos, zone.Radius, zone.Owner) do
				local root = Combat.RootOf(hum)
				if root then
					local to = zone.Pos - root.Position
					local k = 1 - math.clamp(to.Magnitude / zone.Radius, 0, 1)
					Combat.Push(hum, to.Unit * spec.Pull * 0.35 * k + Vector3.new(0, 4 * k, 0))
					if to.Magnitude < zone.Radius * 0.35 then
						Combat.ZoneDamage(hum, spec.Damage, zone.Owner, zone.Element, root.Position + Vector3.new(0, 2.5, 0))
					end
				end
			end
		end
	end,
}

KINDS.Gas = {
	Tick = function(zone, dt)
		zone.Acc += dt
		if zone.Acc >= (zone.Spec.Interval or 0.5) then
			zone.Acc = 0
			Combat.ZoneDamageInRadius(zone.Pos, zone.Radius, zone.Spec.Damage, zone.Owner, "Toxic")
		end
	end,
}

-- ZONE AU SOL laissée par la boule de feu (toutes infusions) : le sol brûle / gèle / s'électrise...
-- L'effet passe par Combat.Damage (brûlure, gel, choc, poison, saignement, entrave selon l'élément).
local PATCH_CHAOS = { "Fire", "Ice", "Lightning", "Toxic", "Steel", "Nature", "Arcane" }
-- SUPPORT d'une zone au sol : la surface sous elle existe-t-elle encore ? (branche détruite, mur de glace fondu,
-- terrain creusé...). Rayon court depuis la zone vers sa surface.
local function supported(zone): boolean
	local n = if B(zone.Element, "PatchSticksToWalls") and zone.Normal then zone.Normal else Vector3.yAxis
	ground(zone.Pos) -- (rafraîchit le filtre groundParams : marqueurs, joueurs, projectiles)
	return workspace:Raycast(zone.Pos + n * 0.6, -n * 1.8, groundParams) ~= nil
end
local SUPPORT_EVERY = 0.25

local PATCH_MATTER_DPS = 9 -- dégâts/s sur la matière des sorts (× affinité) ; feu : ~10/s par cellule
KINDS.Patch = {
	Init = function(zone)
		-- HORS FEU : la matière (givre, flaque, éclairs, végétation) ne TOMBE PAS. Sans surface touchée
		-- (explosion dans le vide), elle n'apparaît que si un sol est juste sous l'impact (ex. cible au sol).
		if not B(zone.Element, "PatchFalls") and not zone.Normal then
			local g0 = ground(zone.Pos)
			-- TRAÎNÉE : posée au sol sous le tir jusqu'à 8 studs de haut (un projectile vole à hauteur de torse)
			local reach = if zone.Spec.Trail then 8 else 4.5
			if (g0 - zone.Pos).Magnitude < 0.01 or (g0 - zone.Pos).Magnitude > reach then
				zone.Until = 0
				return
			end
		end
		-- GIVRE : appliqué sur la SURFACE TOUCHÉE (mur, pente, plafond...), pas projeté au sol
		if B(zone.Element, "PatchSticksToWalls") and zone.Normal then
			zone.Pos = zone.Impact + zone.Normal * 0.05
			pcall(Matter.Extinguish, zone.Pos, zone.Radius)
			return
		end
		-- FEU : soumis à la GRAVITÉ — touché sur un mur ou en hauteur, les flammes TOMBENT jusqu'au sol puis y brûlent
		if B(zone.Element, "PatchFalls") then
			local from = zone.Pos -- impact décollé de 0,5 de la surface touchée (le rayon vers le sol ne frôle pas le mur)
			local g = ground(from, 600) -- explosée très haut : le feu retombe quand même (avant : 40 studs max -> zone annulée)
			if (g - from).Magnitude < 0.01 then
				zone.Until = 0 -- aucun sol sous l'impact
				return
			end
			zone.Pos = g
			local h = from.Y - g.Y
			local fall = if h > 1 then math.sqrt(2 * h / (workspace.Gravity * 0.35)) else 0 -- chute lisible (gravité "feu" adoucie)
			if fall > 0 then
				zone.DropFrom = from
				zone.FallTime = fall
				zone.Acc = -fall -- pas de brûlure avant que les flammes touchent le sol
				zone.Until += fall
			end
			if not zone.Spec.Trail then -- (petites flammes de TRAÎNÉE : elles brûlent les cibles, pas le décor ni la Ramure)
				task.delay(fall, function()
					pcall(Matter.IgniteAround, g, zone.Radius, 3) -- l'herbe / le bois de la zone prend feu
				end)
			end
			return
		end
		local g = ground(zone.Pos)
		if not zone.Spec.Trail and (g - zone.Pos).Magnitude > zone.Radius * 1.3 then
			zone.Until = 0 -- explosion en l'air : pas de sol à marquer
			return
		end
		zone.Pos = g
		if B(zone.Element, "Extinguishes") then
			pcall(Matter.Extinguish, g, zone.Radius) -- le givre éteint les flammes
		end
	end,
	Tick = function(zone, dt)
		-- SURFACE DÉTRUITE : la zone disparaît avec elle... sauf le FEU, qui retombe plus bas et continue de brûler
		zone.SupportT = (zone.SupportT or 0) - dt
		if zone.SupportT <= 0 and zone.Acc >= 0 then -- (Acc < 0 : feu encore en chute)
			zone.SupportT = SUPPORT_EVERY
			if not supported(zone) then
				local left = math.max(0, zone.Until - now())
				zone.Until = 0
				if B(zone.Element, "PatchFalls") and left > 0.3 then
					task.defer(function()
						local z2 = ZoneService.Create(zone.Spec, zone.Pos + Vector3.new(0, 0.5, 0), nil, zone.Owner, zone.Element, zone.Dir, zone.Scale, zone.DurMult)
						if z2 and z2.Until > 0 then
							z2.Until = math.min(z2.Until, now() + left + (z2.FallTime or 0))
						end
					end)
				end
				return
			end
		end
		zone.Acc += dt
		if zone.Acc >= (zone.Spec.Interval or 0.5) then
			zone.Acc = 0
			local el = zone.Element
			if el == "Chaos" then
				el = PATCH_CHAOS[math.random(1, #PATCH_CHAOS)]
			end
			-- hauteur limitée : une zone AU SOL ne touche que ceux qui marchent dedans
			for _, hum in Combat.HumanoidsInRadius(zone.Pos + Vector3.new(0, 1.5, 0), zone.Radius, zone.Owner) do
				local root = Combat.RootOf(hum)
				local near = if zone.Normal and B(zone.Element, "PatchSticksToWalls") then (root and (root.Position - zone.Pos).Magnitude < zone.Radius + 2.5) else (root and math.abs(root.Position.Y - zone.Pos.Y) < 5)
				if near then
					Combat.ZoneDamage(hum, zone.Spec.Damage, zone.Owner, el, root.Position + Vector3.new(0, 2.5, 0), zone.DurMult)
				end
			end
			-- la MATIÈRE des sorts (branches de Ramure, murs...) posée dans la zone subit l'élément
			-- (le feu, lui, l'enflamme déjà via ses cellules de feu)
			-- (les TRAÎNÉES n'abîment pas la matière : une traînée sous la Ramure ne doit pas raccourcir sa vie)
			if not B(el, "PatchFalls") and not zone.Spec.Trail then
				local ok, err = pcall(Matter.Afflict, zone.Pos, zone.Radius + 1, PATCH_MATTER_DPS * (zone.Spec.Interval or 0.5), el, zone.Owner)
				if not ok then
					warn("[Zone] Afflict :", err)
				end
			end
		end
	end,
}

KINDS.FireRing = {
	Init = function(zone)
		zone.Pos = ground(zone.Pos)
	end,
	Tick = function(zone, dt)
		zone.Acc += dt
		if zone.Acc >= (zone.Spec.Interval or 0.4) then
			zone.Acc = 0
			Combat.ZoneDamageInRadius(zone.Pos + Vector3.new(0, 2, 0), zone.Radius, zone.Spec.Damage, zone.Owner, "Fire")
		end
	end,
}

KINDS.Mine = {
	Init = function(zone)
		zone.Pos = ground(zone.Pos) + Vector3.new(0, 0.3, 0)
		zone.ArmAt = now() + 0.6
	end,
	Tick = function(zone, dt)
		zone.Acc += dt
		if zone.Acc < 0.1 or now() < zone.ArmAt then
			return
		end
		zone.Acc = 0
		if #Combat.HumanoidsInRadius(zone.Pos, zone.Radius, zone.Owner) > 0 then
			local spec = zone.Spec
			local blast = spec.Blast * zone.Scale
			Combat.Explode(zone.Pos, blast, spec.Damage, zone.Owner, zone.Element)
			FXBus.Push({ k = "Impact", p = zone.Pos, n = Vector3.yAxis, e = zone.Element, r = blast, s = 1, c = "MINE" })
			zone.Until = 0 -- explosée : retirée à la frame suivante
		end
	end,
}

-- ── PIÈGE ADAPTATIF (carte Mine) ──
-- Seul : paillettes, aucun effet. Ce qu'il fait au déclenchement vient de ses stats (modificateurs placés avant
-- lui dans le deck) et de sa CHARGE (cartes placées après), lancée vers l'ennemi qui a déclenché le piège.
KINDS.Trap = {
	Init = function(zone)
		zone.ArmAt = now() + (zone.Spec.Arm or 0.6)
	end,
	Tick = function(zone, dt)
		zone.Acc += dt
		if zone.Acc < 0.1 or now() < zone.ArmAt then
			return
		end
		zone.Acc = 0
		local list = Combat.HumanoidsInRadius(zone.Pos, zone.Radius, zone.Owner)
		if #list == 0 then
			return
		end
		-- cible : l'ennemi le plus proche du piège
		local target, best = nil, math.huge
		for _, hum in list do
			local r = Combat.RootOf(hum)
			if r and (r.Position - zone.Pos).Magnitude < best then
				target, best = r, (r.Position - zone.Pos).Magnitude
			end
		end
		local s = zone.Stats
		local up = zone.Normal or Vector3.yAxis
		if s.Radius > 0 then
			-- Charge explosive (ou autre rayon) : la mine explose
			Combat.Explode(zone.Pos, s.Radius, s.Damage, zone.Owner, zone.Element, if s.Knockback > 0 then s.Knockback else nil, s.DurationMult)
			FXBus.Push({ k = "Impact", p = zone.Pos, n = up, e = zone.Element, r = s.Radius, s = 0.6, z = s.FxScale, x = true })
		elseif s.Damage > 0 or s.Knockback > 0 then
			-- dégâts / recul sans explosion : seulement ce qui est dans le rayon du piège
			for _, hum in list do
				local r = Combat.RootOf(hum)
				if s.Damage > 0 then
					Combat.ZoneDamage(hum, s.Damage, zone.Owner, zone.Element, r and r.Position, s.DurationMult)
				end
				if r and s.Knockback > 0 then
					local away = r.Position - zone.Pos
					away = if away.Magnitude > 0.1 then away.Unit else up
					Combat.Push(hum, (away + up * 0.8).Unit * s.Knockback, true)
				end
			end
		end
		FXBus.Push({ k = "TrapFire", p = zone.Pos, n = up, e = zone.Element, z = s.FxScale })
		-- CHARGE : les cartes placées après la mine partent du piège vers la cible
		if zone.Payload and ProjectileService.OnPayload and target then
			local from = zone.Pos + up * 1.2
			local dir = target.Position - from
			dir = if dir.Magnitude > 0.1 then dir.Unit else up
			local ok, err = pcall(ProjectileService.OnPayload, zone.Payload, from, dir, zone.Owner, zone.Wand, zone.Depth + 1)
			if not ok then
				warn("[Wand] erreur charge de piège :", err)
			end
		end
		zone.Until = 0 -- consommé
	end,
}

KINDS.Shield = {
	Tick = function(zone)
		local root = ownerRoot(zone.Owner)
		if root then
			zone.Pos = root.Position -- suit le lanceur
		end
		ProjectileService.ForEachInRadius(zone.Pos, zone.Radius, function(rec)
			if isEnemyProjectile(zone, rec) then
				ProjectileService.Remove(rec)
			end
		end)
	end,
}

KINDS.Dispel = {
	Init = function(zone)
		ProjectileService.ForEachInRadius(zone.Pos, zone.Radius, function(rec)
			if isEnemyProjectile(zone, rec) then
				ProjectileService.Remove(rec)
			end
		end)
	end,
}

KINDS.IceWall = {
	Init = function(zone)
		local spec = zone.Spec
		local base = ground(zone.Pos)
		zone.Pos = base
		-- mur perpendiculaire à la direction du tir : colonnes de hauteurs, profondeurs et inclinaisons
		-- légèrement différentes (jamais deux murs identiques). Chaque colonne est posée sur le sol
		-- trouvé sous elle (le mur épouse une pente / une marche).
		-- Les Parts serveur sont la COLLISION (invisibles) ; le client dessine la glace et l'anime
		-- (poussée depuis le sol, éclatement à la fin) grâce aux attributs Order / Count.
		local fwd = Vector3.new(zone.Dir.X, 0, zone.Dir.Z)
		fwd = if fwd.Magnitude > 0.05 then fwd.Unit else Vector3.zAxis
		local right = fwd:Cross(Vector3.yAxis).Unit
		local blocks = 7
		local w = spec.Width * zone.Scale / blocks
		local rnd = Random.new()
		zone.Parts = {}
		for i = 1, blocks do
			local edge = math.abs(i - (blocks + 1) / 2) / ((blocks - 1) / 2) -- 0 au centre, 1 aux bords
			local h = spec.Height * zone.Scale * (1 - edge * 0.35) * rnd:NextNumber(0.82, 1.08)
			local column = base + right * ((i - (blocks + 1) / 2) * w) + fwd * rnd:NextNumber(-0.4, 0.4) * zone.Scale
			local foot = ground(column + Vector3.new(0, 2, 0))
			local tilt = CFrame.Angles(rnd:NextNumber(-0.08, 0.08), 0, rnd:NextNumber(-0.1, 0.1))
			local center = foot + Vector3.new(0, h / 2 - 0.6, 0)
			local p = Instance.new("Part")
			p.Name = "IceBlock"
			p.Anchored = true
			p.Size = Vector3.new(w * rnd:NextNumber(1.02, 1.18), h, 2.2 * zone.Scale ^ 0.5 * rnd:NextNumber(0.85, 1.15))
			p.CFrame = CFrame.lookAt(center, center + fwd) * tilt
			p.Material = Enum.Material.SmoothPlastic
			p.Color = Color3.fromHex("8fe3ff")
			p.Transparency = 1 -- visuel dessiné par le client
			p.CastShadow = false
			p:SetAttribute("Order", math.abs(i - (blocks + 1) / 2)) -- le centre pousse en premier
			p:SetAttribute("Scale", zone.Scale)
			p.Parent = walls
			table.insert(zone.Parts, p)
		end
	end,
	Expire = function(zone)
		-- l'éclatement (éclats, fondu) est joué par le client quand les blocs disparaissent
		for _, p in zone.Parts or {} do
			p:Destroy()
		end
	end,
}

-- ── API ──────────────────────────────────────────────────────────────────────────────────────────────────────
local function removeZone(i: number)
	local zone = zones[i]
	table.remove(zones, i)
	local kind = KINDS[zone.Kind]
	if kind and kind.Expire then
		pcall(kind.Expire, zone)
	end
	if zone.Marker then
		zone.Marker:Destroy()
	end
end

-- scale : taille (Gigantisme x1.5 / x3 / x5) appliquée au rayon, au mur, au souffle de la mine...
-- durationMult : Prolongation (x2 par carte)
-- holding : zone de MAINTIEN (tracé) -> pas de colonnes initiales, durée suspendue jusqu'à EndPath
function ZoneService.Create(spec, pos: Vector3, normal: Vector3?, owner: Player?, element: string, dir: Vector3, scale: number?, durationMult: number?, holding: boolean?)
	scale = math.clamp(scale or 1, 0.5, if spec.Kind == "Patch" then Limits.MaxProcScale else Limits.MaxScale) -- zones au sol : jusqu'à x8
	local duration = (spec.Duration or 1) * math.clamp(durationMult or 1, 0.25, 4)
	if spec.Kind == "Patch" then
		duration *= B(element, "PatchDurationMult") or 1 -- ex. zones toxiques plus durables
	end
	local kind = KINDS[spec.Kind]
	if not kind then
		warn("[Wand] type de zone inconnu :", spec.Kind)
		return
	end
	-- plafonds : la plus ancienne zone du joueur laisse sa place
	-- 3 groupes de plafonds séparés : zones normales, zones au sol (6), petites zones de TRAÎNÉE (14, ex. Traînée de
	-- feu) -> une traînée ne chasse jamais le champ de flammes d'une boule de feu
	local function group(kind: string, sp): string
		return if kind ~= "Patch" then "Zone" elseif sp and sp.Trail then "Trail" else "Patch"
	end
	local myGroup = group(spec.Kind, spec)
	local isPatch = spec.Kind == "Patch"
	local mine = 0
	for _, z in zones do
		if z.Owner == owner and group(z.Kind, z.Spec) == myGroup then
			mine += 1
		end
	end
	local cap = if myGroup == "Trail" then 40 elseif myGroup == "Patch" then 6 else Limits.MaxZonesPerPlayer
	if mine >= cap and myGroup == "Trail" then
		-- TRAÎNÉES : éviction ÉQUITABLE. Chaque traînée est identifiée par le tir qui l'a posée (Spec.TrailKey).
		-- On retire un morceau de la traînée qui en a le PLUS (la nouvelle comprise), et dans celle-ci le morceau
		-- le plus COLLÉ à ses voisins : chaque rayon garde sa traînée sur toute sa longueur (plus espacée) au lieu
		-- que les derniers rayons effacent entièrement les premiers.
		local bySrc: { [any]: { number } } = {}
		for i, z in zones do
			if z.Owner == owner and group(z.Kind, z.Spec) == "Trail" then
				local key = z.Spec.TrailKey or z
				bySrc[key] = bySrc[key] or {}
				table.insert(bySrc[key], i)
			end
		end
		local newKey = spec.TrailKey
		local bestKey, bestN = nil, -1
		for key, list in bySrc do
			local n = #list + (if key == newKey then 1 else 0)
			if n > bestN then bestKey, bestN = key, n end
		end
		if newKey ~= nil and bySrc[newKey] == nil and bestN <= 1 then
			bestKey = nil
		end
		local list = bestKey and bySrc[bestKey]
		if list and #list > 0 then
			local victim, minD = list[1], math.huge
			for _, i in list do
				local p = zones[i].Pos
				local nearest = math.huge
				for _, j in list do
					if j ~= i then
						nearest = math.min(nearest, (zones[j].Pos - p).Magnitude)
					end
				end
				if bestKey == newKey then -- le nouveau morceau compte comme voisin
					nearest = math.min(nearest, (pos - p).Magnitude)
				end
				if nearest < minD then victim, minD = i, nearest end
			end
			removeZone(victim)
		end
	elseif mine >= cap then
		for i, z in zones do
			if z.Owner == owner and group(z.Kind, z.Spec) == myGroup then
				removeZone(i)
				break
			end
		end
	end
	if #zones >= Limits.MaxZonesGlobal then
		removeZone(1)
	end

	local zone = {
		Kind = spec.Kind,
		Spec = spec,
		Pos = pos + (normal or Vector3.zero) * 0.5,
		Dir = dir,
		Radius = (spec.Radius or 4) * scale,
		Scale = scale,
		Duration = duration,
		Until = now() + duration,
		Owner = owner,
		Element = element,
		Acc = 0,
		Marker = nil,
		Holding = holding == true,
		DurMult = durationMult,
		Normal = normal,
		Impact = pos,
	}
	if holding then
		zone.Until = math.huge
		zone.Parts = {}
		zone.Pos = ground(zone.Pos)
	elseif kind.Init then
		kind.Init(zone)
	end
	if zone.Until <= now() then
		return nil -- annulée dès l'Init (pas de sol...) : pas de marqueur, sinon le client montre un effet fantôme
	end
	zone.Marker = newMarker(zone)
	table.insert(zones, zone)
	if zone.Kind == "Patch" and not spec.FromReaction and not zone.Holding then
		-- (le feu qui tombe réagit à l'atterrissage)
		task.delay(zone.FallTime or 0, function()
			if zone.Until > now() then
				ZoneService.ReactAt(zone.Pos, zone.Element, zone.Radius, owner, zone)
			end
		end)
	end
	return zone
end

-- ── MAINTIEN : mur de glace TRACÉ en continu ──────────────────────────────────────────────────────────────────────────
-- À chaque tick, des colonnes de glace remplissent l'espace entre le dernier point visé et le nouveau :
-- le mur suit le mouvement de la souris et reste CONNECTÉ (un saut de plus de PATH_GAP studs commence un
-- nouveau tronçon). Une seule zone regroupe tout le tracé ; sa durée ne démarre qu'à la fin du maintien.
local PATH_RANGE = 60
local PATH_GAP = 25
local PATH_MAX_PER_TICK = 8 -- bride : colonnes max posées par tick
local PATH_MAX_BLOCKS = 140

local pathParams = RaycastParams.new()
pathParams.FilterType = Enum.RaycastFilterType.Exclude

local function iceColumn(zone, foot: Vector3, along: Vector3, w: number, order: number)
	local spec = zone.Spec
	local rnd = Random.new()
	local h = spec.Height * zone.Scale * rnd:NextNumber(0.7, 1.05)
	local side = along:Cross(Vector3.yAxis)
	side = if side.Magnitude > 0.05 then side.Unit else Vector3.xAxis
	local center = foot + Vector3.new(0, h / 2 - 0.6, 0)
	local p = Instance.new("Part")
	p.Name = "IceBlock"
	p.Anchored = true
	p.Size = Vector3.new(w * rnd:NextNumber(1.05, 1.25), h, 2.2 * zone.Scale ^ 0.5 * rnd:NextNumber(0.85, 1.15))
	-- la face du mur suit le tracé (axe X = direction du tracé)
	p.CFrame = CFrame.fromMatrix(center, along, Vector3.yAxis, -side) * CFrame.Angles(rnd:NextNumber(-0.08, 0.08), 0, rnd:NextNumber(-0.1, 0.1))
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromHex("8fe3ff")
	p.Transparency = 1
	p.CastShadow = false
	p:SetAttribute("Order", order)
	p:SetAttribute("Scale", zone.Scale)
	p.Parent = walls
	table.insert(zone.Parts, p)
	-- matière de GLACE : fond sous le feu (x1.8), se brise sous l'acier ; casse = le client joue l'éclatement
	-- les dégâts raccourcissent la DURÉE du mur (1 dégât = 0,05 s, feu x1.8 -> fond vite)
	Matter.Register(p, { Element = "Ice", Kind = "Ice", OnDamage = function(seconds: number)
		if zone.Until < math.huge then
			-- un coup qui touche plusieurs colonnes ne compte qu'UNE fois (fenêtre 0,1 s) ; mur plus gros = plus résistant
				seconds /= math.max(1, zone.Scale or 1)
				local now = os.clock()
				if now - (zone.HitWindow or 0) > 0.1 then
					zone.HitWindow, zone.HitMax = now, 0
				end
				if seconds > zone.HitMax then
					zone.Until -= seconds - zone.HitMax
					zone.HitMax = seconds
				end
		end
	end })
end

function ZoneService.PathTick(state, stats, origin: Vector3, dir: Vector3, owner: Player?, reach: number?)
	state = state or { Zone = nil, Last = nil }
	local ignore = { markers, workspace:FindFirstChild("WandProjectiles"), workspace:FindFirstChild("WandDummies"), walls }
	for _, pl in game:GetService("Players"):GetPlayers() do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	pathParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(origin, dir * math.min(reach or PATH_RANGE, PATH_RANGE), pathParams)
	if not hit then
		return state -- trop loin / rien visé : le maintien continue, rien ne pousse ce tick
	end
	local zone = state.Zone
	if not zone or not table.find(zones, zone) then
		zone = ZoneService.Create(stats.Zone, hit.Position, nil, owner, stats.Element, dir, stats.ZoneScale, stats.DurationMult, true)
		if not zone then
			return state
		end
		state.Zone = zone
		state.Last = nil
	end
	if #zone.Parts >= PATH_MAX_BLOCKS then
		return state
	end
	local point = ground(hit.Position + Vector3.new(0, 1, 0))
	local w = zone.Spec.Width * zone.Scale / 7
	local last = state.Last
	if not last or (point - last).Magnitude > PATH_GAP then
		local fwd = Vector3.new(dir.X, 0, dir.Z)
		fwd = if fwd.Magnitude > 0.05 then fwd.Unit else Vector3.zAxis
		iceColumn(zone, point, fwd:Cross(Vector3.yAxis).Unit, w, 0)
		state.Last = point
		return state
	end
	local delta = Vector3.new(point.X - last.X, 0, point.Z - last.Z)
	local dist = delta.Magnitude
	if dist < w * 0.9 then
		return state -- la souris n'a pas assez bougé : on n'empile pas de colonnes au même endroit
	end
	local along = delta.Unit
	local count = math.min(math.floor(dist / w), PATH_MAX_PER_TICK)
	for i = 1, count do
		local at = last + along * (w * i)
		iceColumn(zone, ground(at + Vector3.new(0, 3, 0)), along, w, (i - 1) * 0.6)
	end
	state.Last = last + along * (w * count)
	zone.Pos = state.Last
	if zone.Marker then
		zone.Marker.CFrame = CFrame.new(zone.Pos)
	end
	return state
end

function ZoneService.EndPath(state)
	local zone = state and state.Zone
	if zone and zone.Holding then
		zone.Holding = false
		zone.Until = now() + zone.Duration
	end
end

-- ── Pose d'un piège (ProjectileService.OnTrap) ────────────────────────────────────────────────────────────────────────
-- depth 0 (clic) : sur la surface visée (portée Range) ; depth > 0 (porté par un projectile) : sur la surface
-- la plus proche du point d'arrivée, sans limite de portée. Pas de surface -> échec (étincelles + remboursement).
ZoneService.OnRefund = nil :: ((Player, number) -> ())?
local TRAP_PROBES = {
	Vector3.new(0, -1, 0), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1), Vector3.new(0, 1, 0),
}
local trapParams = RaycastParams.new()
trapParams.FilterType = Enum.RaycastFilterType.Exclude

function ZoneService.PlaceTrap(stats, origin: Vector3, dir: Vector3, owner: Player?, reach: number?, depth: number, payload, wand)
	local ignore = { markers, workspace:FindFirstChild("WandProjectiles"), workspace:FindFirstChild("WandDummies") }
	for _, pl in game:GetService("Players"):GetPlayers() do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	trapParams.FilterDescendantsInstances = ignore
	local hit = nil
	if depth > 0 then
		local best = math.huge
		for _, d in TRAP_PROBES do
			local h = workspace:Raycast(origin, d * 6, trapParams)
			if h and h.Distance < best then
				hit, best = h, h.Distance
			end
		end
		hit = hit or workspace:Raycast(origin, dir * 500, trapParams) or workspace:Raycast(origin, Vector3.new(0, -500, 0), trapParams)
	else
		local range = math.clamp(reach or stats.Range, 3, math.max(stats.Range, 10))
		hit = workspace:Raycast(origin, dir * range, trapParams)
	end
	if not hit then
		local char = owner and owner.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		FXBus.Push({ k = "Fizzle", p = if root then root.Position else origin, u = if owner then owner.UserId else 0 })
		if owner and ZoneService.OnRefund and (stats.Mana or 0) > 0 then
			ZoneService.OnRefund(owner, stats.Mana)
		end
		return nil
	end
	-- plafond de pièges par joueur : le plus ancien disparaît
	local mine = 0
	for _, z in zones do
		if z.Owner == owner and z.Kind == "Trap" then
			mine += 1
		end
	end
	if mine >= Limits.MaxTrapsPerPlayer then
		for i, z in zones do
			if z.Owner == owner and z.Kind == "Trap" then
				removeZone(i)
				break
			end
		end
	end
	local spec = { Kind = "Trap", Radius = stats.Trap.Radius, Duration = stats.Trap.Duration, Arm = stats.Trap.Arm }
	local zone = ZoneService.Create(spec, hit.Position + hit.Normal * 0.1, nil, owner, stats.Element, dir, stats.ZoneScale, stats.DurationMult)
	if zone then
		zone.Normal = hit.Normal
		zone.Stats = stats
		zone.Payload = payload
		zone.Wand = wand
		zone.Depth = depth
	end
	return zone
end

-- ══ RÉACTIONS DE ZONE (phase 2.5) : un sort d'un élément touche une ZONE AU SOL d'un autre élément ══
-- Règles : WandShared/Reactions.Zones (données). GARDE-FOUS : une zone ne réagit qu'une fois (ou après son Cooldown),
-- les zones nées d'une réaction ne déclenchent rien, 8 réactions de zone max par seconde (tous joueurs).
local Reactions = require(ReplicatedStorage.WandShared.Reactions)
local reactCount, reactWindow = 0, 0
local recentClash = {} -- chocs récents venus d'impacts (voir Clash)

function ZoneService.ReactAt(pos: Vector3, element: string?, radius: number, owner: Player?, exclude: any?)
	if not element then
		return 0
	end
	local t = now()
	-- nouvelle zone posée là où l'impact du MÊME sort vient d'effacer une zone : rapport de taille (Clash)
	if type(exclude) == "table" and exclude.Until then
		for i = #recentClash, 1, -1 do
			local rc = recentClash[i]
			if t - rc.T > 1.5 then
				table.remove(recentClash, i)
			elseif rc.El == element and Vector3.new(rc.Pos.X - pos.X, 0, rc.Pos.Z - pos.Z).Magnitude <= rc.R + radius then
				table.remove(recentClash, i)
				local raw = (radius / math.max(rc.R, 0.5)) ^ 2
				if raw <= 2 then
					exclude.Until = 0 -- zones équivalentes : les deux s'annulent
					return 1
				end
				exclude.Until = t + (exclude.Until - t) * (1 - math.clamp(1.4 / raw, 0, 0.9))
			end
		end
	end
	if t - reactWindow > 1 then
		reactWindow, reactCount = t, 0
	end
	local fired = 0
	for i = #zones, 1, -1 do
		local z = zones[i]
		if reactCount >= 8 then
			break
		end
		if z ~= exclude and z.Kind == "Patch" and z.Element ~= element and z.Until > t and (z.ReactReady or 0) <= t
			and (Vector3.new(z.Pos.X - pos.X, 0, z.Pos.Z - pos.Z).Magnitude <= z.Radius + radius * 0.5)
			and math.abs(z.Pos.Y - pos.Y) <= z.Radius + radius + 3 then
			local rule = nil
			for _, rx in Reactions.Zones do
				if rx.Hit == element and rx.On == z.Element then
					rule = rx
					break
				end
			end
			if rule then
				z.ReactReady = if rule.Cooldown then t + rule.Cooldown else math.huge
				reactCount += 1
				fired += 1
				local up = Vector3.new(0, 1, 0)
				-- RAPPORT DE TAILLE : surface du coup / surface de la zone (un petit coup ne remplace pas une grande zone)
				local hitR = math.max(radius, 1.5)
				local contact = Vector3.new(pos.X, z.Pos.Y, pos.Z)
				local api = {
					Pos = z.Pos, Radius = z.Radius, Owner = owner, Element = z.Element,
					HitRadius = hitR, Ratio = math.clamp((hitR / math.max(z.Radius, 0.5)) ^ 2, 0, 1), Contact = contact,
					RawRatio = (hitR / math.max(z.Radius, 0.5)) ^ 2,
					-- la zone qui a provoqué la réaction (nouvelle zone posée dessus), s'il y en a une
					HasHitter = type(exclude) == "table" and exclude.Until ~= nil,
					RemoveHitter = function()
						if type(exclude) == "table" and exclude.Until then
							exclude.Until = 0
						end
					end,
					-- ZONES ÉQUIVALENTES : si la zone posée dessus est de taille comparable (surface x0.5 à x2), elle
					-- disparaît AUSSI (les deux s'annulent) ; bien plus grande, elle ne perd qu'une part
					Clash = function()
						if not (type(exclude) == "table" and exclude.Until) then
							-- choc venu d'un IMPACT : la zone de ce sort sera posée juste après -> on s'en souvient
							table.insert(recentClash, { Pos = z.Pos, R = z.Radius, El = element, T = t })
							return
						end
						local raw = (hitR / math.max(z.Radius, 0.5)) ^ 2
						if raw <= 2 then
							exclude.Until = 0
						else
							exclude.Until = t + (exclude.Until - t) * (1 - math.clamp(1.4 / raw, 0, 0.9))
						end
					end,
					ShrinkHitter = function(frac)
						if type(exclude) == "table" and exclude.Until then
							exclude.Until = t + (exclude.Until - t) * (1 - math.clamp(frac, 0, 0.9))
						end
					end,
					Remove = function() z.Until = 0 end,
					-- ne retire qu'une PART de la zone : sa durée restante diminue de frac (max 90 %)
					Shrink = function(frac) z.Until = t + (z.Until - t) * (1 - math.clamp(frac, 0, 0.9)) end,
					Retry = function(sec) z.ReactReady = t + sec end, -- la zone pourra réagir de nouveau
					ExtinguishAt = function() pcall(Matter.Extinguish, contact, hitR + 1) end,
					VisualAt = function(name, scale) FXBus.Push({ k = "ReactFX", n = name, p = contact + up * 0.5, s = scale or 1 }) end,
					Explode = function(r, dmg, el) Combat.Explode(z.Pos + up, r, dmg, owner, el or element) end,
					DamageIn = function(dmg, el) Combat.ZoneDamageInRadius(z.Pos + up * 1.5, z.Radius, dmg, owner, el or element) end,
					Ignite = function() pcall(Matter.IgniteAround, z.Pos, z.Radius, 4) end,
					Extinguish = function() pcall(Matter.Extinguish, z.Pos, z.Radius + 1) end,
					CreatePatch = function(el, r, dur)
						task.defer(ZoneService.Create, { Kind = "Patch", Radius = r, Duration = dur, Damage = 1.5, Interval = 0.5, FromReaction = true },
							z.Pos + up * 0.5, nil, owner, el, Vector3.zAxis, 1, 1)
					end,
					Visual = function(name, scale) FXBus.Push({ k = "ReactFX", n = name, p = z.Pos + up * 0.5, s = scale or 1 }) end,
					Label = function(text) FXBus.Push({ k = "React", p = z.Pos + up * 3, t = text, e = element }) end,
				}
				local ok, err = pcall(rule.Run, api)
				if not ok then
					warn("[Wand] réaction de zone " .. tostring(rule.Name) .. " en erreur :", err)
				end
			end
		end
	end
	-- les ARBRES (Ramure) réagissent aussi aux coups (GrowthService.ReactAt, branché à l'initialisation)
	if ZoneService.GrowthReact then
		local ok, n = pcall(ZoneService.GrowthReact, pos, element, radius, owner)
		if ok then
			fired += n or 0
		else
			warn("[Wand] réaction d'arbre en erreur :", n)
		end
	end
	return fired
end

function ZoneService.ClearOwner(owner: Player)
	for i = #zones, 1, -1 do
		if zones[i].Owner == owner then
			removeZone(i)
		end
	end
end

local function step(dt: number)
	local t = now()
	for i = #zones, 1, -1 do
		local zone = zones[i]
		if t >= zone.Until then
			removeZone(i)
		else
			local kind = KINDS[zone.Kind]
			if kind.Tick then
				local ok, err = pcall(kind.Tick, zone, dt)
				if not ok then
					warn("[Wand] zone en erreur, supprimée :", err)
					zone.Until = 0
				end
			end
			if zone.Marker and zone.Marker.Parent and (zone.Marker.Position - zone.Pos).Magnitude > 0.05 then
				zone.Marker.CFrame = CFrame.new(zone.Pos) -- zones mobiles (bouclier)
			end
		end
	end
end

function ZoneService.Init()
	markers = workspace:FindFirstChild("WandZoneMarkers") or Instance.new("Folder")
	markers.Name = "WandZoneMarkers"
	markers.Parent = workspace
	walls = workspace:FindFirstChild("WandIceWalls") or Instance.new("Folder")
	walls.Name = "WandIceWalls"
	walls.Parent = workspace
	ProjectileService.OnZone = ZoneService.Create
	ProjectileService.OnTrap = ZoneService.PlaceTrap
	ProjectileService.OnReact = ZoneService.ReactAt -- impacts / explosions / bouts de rayon sur les zones au sol
	RunService.Heartbeat:Connect(step)
end

return ZoneService

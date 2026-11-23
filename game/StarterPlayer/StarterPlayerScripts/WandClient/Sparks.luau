--[[
	WandClient/Sparks — Système d'étincelles physiques (100 % client, purement visuel)

	Pourquoi pas des ParticleEmitter ? Les particules Roblox ne touchent RIEN (elles traversent le sol).
	Ici chaque étincelle est simulée : gravité, frottement de l'air, forces (attracteurs / tourbillons),
	REBONDS sur le décor (Raycast), puis repos au sol comme une braise qui s'éteint.

	Rendu : petites Parts Neon (elles font briller le Bloom) étirées dans le sens de la vitesse
	(= traînées de feu d'artifice), déplacées en un seul appel workspace:BulkMoveTo par frame.
	Couleurs en PALIERS sur la durée de vie (Core -> Mid -> Edge), aucune interpolation.

	Budgets : MAX_SPARKS étincelles vivantes, RAY_BUDGET raycasts par frame (au-delà, une étincelle
	avance sans collision pendant cette frame). Les Parts sont recyclées (pool) : zéro Instance.new en régime.

	API :
	  Sparks.Burst(pos, opts)           -- gerbe d'étincelles
	  Sparks.Emit(pos, vel, opts)       -- une étincelle (traînées de projectiles)
	  Sparks.AddAttractor(pos, strength, radius, swirl, duration) -- force d'aspiration / tourbillon
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Sparks = {}

local MAX_SPARKS = 900

local FXSettings = require(script.Parent:WaitForChild("FXSettings"))
local function applyQuality() -- réglage Qualité des effets (Bas / Moyen / Haut)
	MAX_SPARKS = math.floor(900 * FXSettings.QualityK())
end
applyQuality()
FXSettings.OnChanged(applyQuality)
-- PERFORMANCES : régulateur de densité (si les FPS baissent, une part des NOUVELLES étincelles est
-- ignorée ; remonte tout seul quand ça va mieux) + rien n'est émis loin de la caméra
local CULL_DIST = 180
local density = 1 -- 0.25 .. 1
local frameEma = 1 / 120
local camPos = Vector3.zero
local camLook = Vector3.new(0, 0, -1)
local cosHalf = 0.5 -- cos du demi-angle de vue (horizontal, élargi) : hors de ce cône = hors champ
local frameParity = 0

-- ══ BOUFFÉES SUR ÉMETTEURS ROBLOX (« GPU ») ══════════════════════════════════
-- Les bouffées (Puff : fumée, vapeur, gaz, poussière) n'ont pas besoin de toucher le décor : elles passent par des
-- ParticleEmitter (simulés par le moteur, presque gratuits pour les scripts). Carré blanc pixel teinté, face caméra.
-- Un émetteur par RECETTE (couleurs + options) : couleurs par paliers, grossissement, fondu, gravité, frottement
-- reproduits. Les étincelles qui rebondissent / se posent / sont aspirées restent des Parts.
-- Interrupteur de comparaison : workspace.GpuPuffs = false -> anciennes bouffées en cubes 3D.
local PUFF_TEX = "rbxassetid://103763299233462"
local MAX_EMITTERS = 96
local gpuPuffs = true
local emitHost: Part? = nil
local emitters: { [string]: any } = {}
local emitterCount = 0

local function colorsKey(c: { Color3 }): string
	local t = table.create(#c)
	for i, col in c do
		t[i] = col:ToHex()
	end
	return table.concat(t, ",")
end

local function steppedColors(c: { Color3 }): ColorSequence
	local n = #c
	if n <= 1 then
		return ColorSequence.new(c[1] or Color3.new(1, 1, 1))
	end
	local kps = {}
	for i, col in c do
		local a = (i - 1) / n
		local b = i / n
		table.insert(kps, ColorSequenceKeypoint.new(if i == 1 then 0 else a + 1e-4, col))
		table.insert(kps, ColorSequenceKeypoint.new(if i == n then 1 else b, col))
	end
	return ColorSequence.new(kps)
end

local function emitterFor(opts: any, palette: { Color3 }): any
	-- clé par CONTENU (avant : identité de la table -> un émetteur neuf à chaque appel, les 96 places
	-- saturaient et les bouffées suivantes disparaissaient : « parfois je ne vois pas les particules »)
	local life = opts.Life or NumberRange.new(0.4, 0.8)
	local key = string.format("%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|", opts.Size or 0.18, opts.Grow or 3, opts.Fade0 or 0.45,
		opts.Gravity or 1, opts.Drag or 1.5, life.Min, life.Max) .. colorsKey(palette)
	local e = emitters[key]
	if e then
		e.Used = os.clock()
		return e
	end
	if emitterCount >= MAX_EMITTERS then
		-- recyclage : l'émetteur inutilisé depuis le plus longtemps (ses particules ont fini de vivre)
		local oldK, oldT = nil, math.huge
		for k, v in emitters do
			if v.Used < oldT then oldK, oldT = k, v.Used end
		end
		if oldK and os.clock() - oldT > 3 then
			emitters[oldK].Att:Destroy()
			emitters[oldK] = nil
			emitterCount -= 1
		else
			return nil -- tous utilisés à l'instant : repli sur une Part
		end
	end
	if not emitHost or not emitHost.Parent then
		local h = Instance.new("Part")
		h.Name = "PuffEmitters"
		h.Anchored, h.CanCollide, h.CanQuery, h.CanTouch, h.CastShadow = true, false, false, false, false
		h.Transparency = 1
		h.Size = Vector3.new(1, 1, 1)
		h.CFrame = CFrame.new()
		-- (le dossier `folder` est déclaré plus bas dans ce fichier : on le retrouve par son nom)
		h.Parent = workspace:FindFirstChild("WandSparks_Local") or workspace
		emitHost = h
	end
	local att = Instance.new("Attachment")
	att.Parent = emitHost
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = PUFF_TEX
	pe.Enabled = false
	pe.Rate = 0
	pe.LockedToPart = false
	pe.EmissionDirection = Enum.NormalId.Top
	pe.SpreadAngle = Vector2.zero
	pe.Orientation = Enum.ParticleOrientation.FacingCamera
	pe.LightInfluence = 0
	pe.LightEmission = 0
	pe.Brightness = 1
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-35, 35)
	local size = (opts.Size or 0.18) * 0.65 -- un carré face caméra paraît plus grand qu'un cube de même arête
	local grow = opts.Grow or 3
	pe.Size = NumberSequence.new(size, size * grow)
	local f0 = opts.Fade0 or 0.45
	pe.Transparency = NumberSequence.new(f0, 1)
	pe.Color = steppedColors(palette)
	pe.Lifetime = opts.Life or NumberRange.new(0.4, 0.8)
	pe.Acceleration = Vector3.new(0, -60 * (opts.Gravity or 1), 0) -- (= GRAVITY, déclarée plus bas dans ce fichier)
	pe.Drag = opts.Drag or 1.5
	pe.Parent = att
	e = { Att = att, PE = pe, Used = os.clock() }
	emitters[key] = e
	emitterCount += 1
	return e
end

local function emitGpuPuff(pos: Vector3, vel: Vector3, opts: any, palette: { Color3 }): boolean
	local e = emitterFor(opts, palette)
	if not e then
		return false
	end
	local speed = vel.Magnitude
	if speed > 1e-3 then
		-- l'axe Y de l'attachment (direction d'émission Top) pointe le long de la vitesse
		e.Att.WorldCFrame = CFrame.lookAt(pos, pos + vel) * CFrame.Angles(-math.pi / 2, 0, 0)
	else
		e.Att.WorldCFrame = CFrame.new(pos)
	end
	e.PE.Speed = NumberRange.new(speed)
	e.PE:Emit(1)
	return true
end
local RAY_BUDGET = 260
local GRAVITY = 60
local REST_SPEED = 3 -- en dessous, l'étincelle se pose au sol
local HIDDEN = CFrame.new(0, -1e4, 0)

export type SparkOpts = {
	Count: number?,
	Colors: { Color3 }?, -- paliers de couleur sur la vie (ex. { Core, Mid, Edge })
	Palettes: { { Color3 } }?, -- si fourni : chaque étincelle tire une palette au hasard (feu d'artifice)
	Speed: NumberRange?,
	Life: NumberRange?,
	Normal: Vector3?, -- hémisphère autour de la normale
	Direction: Vector3?, -- cône autour d'une direction
	Spread: number?, -- demi-angle du cône (degrés)
	Shell: boolean?, -- vitesse identique pour toutes = sphère parfaite (feu d'artifice)
	Gravity: number?, -- multiplicateur (négatif = monte)
	Drag: number?,
	Bounce: number?, -- restitution 0..1 ; 0 = pas de collision
	Size: number?, -- épaisseur (studs)
	Crackle: number?, -- probabilité (0..1) d'un petit "pop" secondaire en cours de vie
	Inherit: Vector3?, -- vitesse ajoutée à toutes les étincelles (héritage du projectile)
	Puff: boolean?, -- BOUFFÉE (vapeur, fumée, gaz) : carré qui ne s'étire pas, GROSSIT (Grow x) et s'efface en montant
	Grow: number?, -- taille finale d'une bouffée (x la taille de départ)
	Fade0: number?, -- transparence de départ d'une bouffée (0..1)
	Matte: boolean?, -- matière MATE (vapeur, fumée) : ne brille pas (le Neon + Bloom blanchit toutes les couleurs)
}

type Spark = {
	Part: Part,
	Pos: Vector3,
	Vel: Vector3,
	Age: number,
	Life: number,
	Colors: { Color3 },
	Stage: number,
	Gravity: number,
	Drag: number,
	Bounce: number,
	Size: number,
	Length: number,
	Resting: boolean,
	CrackleAt: number?,
	Faded: boolean,
}

local rng = Random.new()
local folder: Folder
local pool: { Part } = {}
local created = 0
local live: { Spark } = {}
local attractors: { { Pos: Vector3, Strength: number, Radius: number, Swirl: number, Until: number } } = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
local clock = 0

-- ── Pool de Parts ───────────────────────────────────────────────────────────────────────
local function takePart(): Part?
	local p = table.remove(pool)
	if p then
		return p
	end
	if created >= MAX_SPARKS then
		return nil
	end
	created += 1
	p = Instance.new("Part")
	p.Name = "Spark"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false -- invisibles pour tous les raycasts (visée, autres étincelles...)
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = HIDDEN
	p.Parent = folder
	return p
end

local function releasePart(p: Part)
	p.CFrame = HIDDEN
	table.insert(pool, p)
end

-- Longueur de la traînée quantifiée en 4 paliers (changer Size coûte cher : on le fait rarement).
local function lengthFor(speed: number, size: number): number
	if speed > 60 then
		return size * 8
	elseif speed > 30 then
		return size * 5
	elseif speed > 10 then
		return size * 2.5
	end
	return size
end

-- ── Création ─────────────────────────────────────────────────────────────────────────────
function Sparks.Emit(pos: Vector3, vel: Vector3, opts: SparkOpts, colors: { Color3 }?): boolean
	if (pos - camPos).Magnitude > CULL_DIST then
		return false -- trop loin : invisible de toute façon
	end
	if density * math.min(1, FXSettings.QualityK() * 1.3) < 1 and rng:NextNumber() > density * math.min(1, FXSettings.QualityK() * 1.3) then
		return false -- FPS en baisse : densité réduite
	end
	local cap = MAX_SPARKS * (0.4 + 0.6 * density) -- la réserve rétrécit aussi quand les FPS baissent
	if #live > cap * 0.7 and rng:NextNumber() < (#live - cap * 0.7) / (cap * 0.3) then
		return false -- réserve presque pleine : on éclaircit progressivement plutôt que de saturer
	end
	if opts.Puff and gpuPuffs then
		local palette0 = colors or opts.Colors or { Color3.new(1, 1, 1) }
		if emitGpuPuff(pos, vel, opts, palette0) then
			return true
		end
	end
	local part = takePart()
	if not part then
		return false -- budget atteint : l'étincelle est simplement ignorée
	end
	local palette = colors or opts.Colors or { Color3.new(1, 1, 1) }
	local life = opts.Life or NumberRange.new(0.4, 0.8)
	local size = opts.Size or 0.18
	local speed = vel.Magnitude
	local length = if opts.Puff then size else lengthFor(speed, size)
	part.Size = Vector3.new(size, size, length)
	part.Color = palette[1]
	part.Transparency = if opts.Puff then (opts.Fade0 or 0.45) elseif opts.Matte then 0.15 else 0
	local mat = if opts.Matte then Enum.Material.SmoothPlastic else Enum.Material.Neon
	if part.Material ~= mat then
		part.Material = mat
	end
	local spark: Spark = {
		Part = part,
		Pos = pos,
		Vel = vel,
		Age = 0,
		Life = rng:NextNumber(life.Min, life.Max),
		Colors = palette,
		Stage = 1,
		Gravity = opts.Gravity or 1,
		Drag = opts.Drag or 1.5,
		Bounce = opts.Bounce or 0,
		Size = size,
		Length = length,
		Resting = false,
		Parked = false,
		CrackleAt = nil,
		Faded = false,
	}
	if opts.Crackle and rng:NextNumber() < opts.Crackle then
		spark.CrackleAt = spark.Life * rng:NextNumber(0.35, 0.8)
	end
	if opts.Puff then
		-- bouffée : orientation fixe au hasard (pas de grille alignée), grossit et s'efface
		spark.Puff = { Grow = opts.Grow or 3, Fade0 = opts.Fade0 or 0.45, Rot = CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)) }
	end
	table.insert(live, spark)
	return true
end

-- PRIORITÉ : libère `need` places en sacrifiant les étincelles les moins importantes
-- (braises déjà posées au sol d'abord, puis les plus proches de leur fin de vie)
local function evict(need: number)
	if need <= 0 or #live == 0 then
		return
	end
	local order = table.create(#live)
	for i, s in live do
		order[i] = i
	end
	table.sort(order, function(a, b)
		local sa, sb = live[a], live[b]
		if sa.Resting ~= sb.Resting then
			return sa.Resting
		end
		return sa.Age / sa.Life > sb.Age / sb.Life
	end)
	local kill = {}
	for k = 1, math.min(need, #order) do
		kill[order[k]] = true
	end
	local kept = table.create(#live)
	for j, s in live do
		if kill[j] then
			releasePart(s.Part)
		else
			table.insert(kept, s)
		end
	end
	live = kept
end

local function randomDirection(opts: SparkOpts): Vector3
	local v = rng:NextUnitVector()
	if opts.Direction then
		local spread = math.rad(opts.Spread or 25)
		local dir = opts.Direction.Unit
		local up = if math.abs(dir.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
		local cf = CFrame.lookAt(Vector3.zero, dir, up)
		-- point aléatoire dans un cône (distribution uniforme sur la calotte)
		local z = 1 - rng:NextNumber() * (1 - math.cos(spread))
		local a = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(1 - z * z)
		return cf:VectorToWorldSpace(Vector3.new(r * math.cos(a), r * math.sin(a), -z))
	elseif opts.Normal then
		if v:Dot(opts.Normal) < 0 then
			v = -v
		end
		return (v + opts.Normal * 0.35).Unit -- légèrement "soulevé" pour ne pas raser la surface
	end
	return v
end

function Sparks.Burst(pos: Vector3, opts: SparkOpts): number
	local wanted = opts.Count or 20
	-- qualité Basse : on émet MOINS (au lieu de remplir puis d'évincer, ce qui coûte plus cher)
	local qk = FXSettings.QualityK()
	if qk < 1 then
		wanted = math.max(1, math.floor(wanted * qk + 0.5))
	end
	-- gerbe PRIORITAIRE (impacts) : si la réserve est pleine, elle prend la place des étincelles secondaires
	if opts.Priority and #live + wanted > MAX_SPARKS then
		evict(#live + wanted - MAX_SPARKS)
	end
	local count = math.min(wanted, MAX_SPARKS - #live)
	local speed = opts.Speed or NumberRange.new(10, 30)
	local shellSpeed = rng:NextNumber(speed.Min, speed.Max)
	local inherit = opts.Inherit or Vector3.zero
	local emitted = 0
	for _ = 1, count do
		local s = if opts.Shell then shellSpeed * rng:NextNumber(0.92, 1.0) else rng:NextNumber(speed.Min, speed.Max)
		local colors = if opts.Palettes then opts.Palettes[rng:NextInteger(1, #opts.Palettes)] else nil
		if Sparks.Emit(pos, randomDirection(opts) * s + inherit, opts, colors) then
			emitted += 1
		end
	end
	return emitted
end

function Sparks.AddAttractor(pos: Vector3, strength: number, radius: number, swirl: number?, duration: number)
	table.insert(attractors, { Pos = pos, Strength = strength, Radius = radius, Swirl = swirl or 0, Until = clock + duration })
end

local CRACKLE_OPTS: SparkOpts = {
	Colors = { Color3.new(1, 1, 1), Color3.fromRGB(255, 240, 180) },
	Speed = NumberRange.new(4, 9),
	Life = NumberRange.new(0.12, 0.25),
	Gravity = 0.3,
	Drag = 4,
	Size = 0.12,
}

-- ── Simulation ───────────────────────────────────────────────────────────────────────────
local parts: { BasePart } = {}
local cframes: { CFrame } = {}
local filterTimer = 0

local function refreshFilter()
	local list: { Instance } = { folder }
	for _, name in { "WandProjectiles", "WandFX_Local", "WandLights_Local" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	-- les étincelles ne rebondissent pas sur les personnages (pas de "pluie" collée aux joueurs)
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	params.FilterDescendantsInstances = list
end

local function step(dt: number)
	clock += dt
	local cam = workspace.CurrentCamera
	if cam then
		camPos = cam.CFrame.Position
		camLook = cam.CFrame.LookVector
		-- demi-angle HORIZONTAL (plus large que le vertical), +25 % de marge pour les bords
		local vy = math.rad(cam.FieldOfView) * 0.5
		local aspect = cam.ViewportSize.X / math.max(1, cam.ViewportSize.Y)
		local hx = math.atan(math.tan(vy) * aspect) * 1.25
		cosHalf = math.cos(math.min(hx, math.pi * 0.49))
	end
	frameParity = 1 - frameParity
	gpuPuffs = workspace:GetAttribute("GpuPuffs") ~= false
	-- régulateur : vise >= ~75 FPS ; baisse vite la densité, la remonte doucement
	-- sensible aux PICS : monte vite sur une image lente, redescend lentement
	frameEma += (dt - frameEma) * (if dt > frameEma then 0.3 else 0.05)
	if frameEma > 1 / 85 then
		density = math.max(0.25, density - dt * 1.2)
	elseif frameEma < 1 / 115 then
		density = math.min(1, density + dt * 0.35)
	end
	filterTimer -= dt
	if filterTimer <= 0 then
		filterTimer = 1
		refreshFilter()
	end
	for i = #attractors, 1, -1 do
		if attractors[i].Until <= clock then
			table.remove(attractors, i)
		end
	end

	table.clear(parts)
	table.clear(cframes)
	local rays = 0
	local pending: { { Vector3 } } = {}

	local i = 1
	while i <= #live do
		local s = live[i]
		s.Age += dt
		if s.Age >= s.Life then
			releasePart(s.Part)
			live[i] = live[#live]
			live[#live] = nil
			continue
		end

		if not s.Resting then
			local acc = Vector3.new(0, -GRAVITY * s.Gravity, 0)
			for _, a in attractors do
				local d = a.Pos - s.Pos
				local dist = d.Magnitude
				if dist < a.Radius and dist > 0.2 then
					local dir = d / dist
					local k = 1 - dist / a.Radius
					acc += dir * a.Strength * k
					if a.Swirl ~= 0 then
						acc += dir:Cross(Vector3.yAxis) * a.Swirl * k
					end
				end
			end
			s.Vel = (s.Vel + acc * dt) * math.max(0, 1 - s.Drag * dt)
			local move = s.Vel * dt

			local hit = nil
			if s.Bounce > 0 and rays < RAY_BUDGET and move.Magnitude > 1e-3 then
				rays += 1
				hit = workspace:Raycast(s.Pos, move, params)
			end
			if hit then
				local n = hit.Normal
				local reflected = s.Vel - 2 * s.Vel:Dot(n) * n
				-- restitution sur la composante normale, frottement sur la composante tangentielle
				local normalPart = reflected:Dot(n) * n
				s.Vel = normalPart * s.Bounce + (reflected - normalPart) * 0.7
				s.Pos = hit.Position + n * (s.Size * 0.5)
				if s.Vel.Magnitude < REST_SPEED then
					s.Resting = true -- braise posée : plus de physique ni de raycast
					s.Vel = Vector3.zero
				end
			else
				s.Pos += move
			end

			-- longueur de traînée (rarement modifiée) ; les bouffées ne s'étirent jamais
			local length = if s.Puff then s.Length else lengthFor(s.Vel.Magnitude, s.Size)
			if length ~= s.Length then
				s.Length = length
				s.Part.Size = Vector3.new(s.Size, s.Size, length)
			end
		end

		-- couleur en paliers sur la durée de vie
		local frac = s.Age / s.Life
		local stage = math.min(#s.Colors, math.floor(frac * #s.Colors) + 1)
		if stage ~= s.Stage then
			s.Stage = stage
			s.Part.Color = s.Colors[stage]
		end
		if s.Puff then
			-- taille / transparence par PALIERS (12 sur la vie) : écrire ces propriétés à chaque image
			-- pour des centaines de bouffées coûtait plus cher que tout le reste de la simulation
			local q = math.floor(frac * 12)
			if q ~= s.PuffQ then
				s.PuffQ = q
				local f = q / 12
				local sz = s.Size * (1 + (s.Puff.Grow - 1) * f)
				s.Part.Size = Vector3.new(sz, sz, sz)
				s.Part.Transparency = s.Puff.Fade0 + (1 - s.Puff.Fade0) * f
			end
			s.Faded = true
		end
		if not s.Faded and frac > 0.85 then
			s.Faded = true
			s.Part.Transparency = 0.5 -- dernier palier avant extinction
		end

		if s.CrackleAt and s.Age >= s.CrackleAt then
			s.CrackleAt = nil
			table.insert(pending, { s.Pos, s.Vel })
		end

		-- braise POSÉE et déjà placée : elle ne bouge plus, inutile de la redéplacer à chaque image
		if s.Resting and s.Parked then
			i += 1
			continue
		end
		s.Parked = s.Resting

		-- NE PAS ANIMER CE QU'ON NE VOIT PAS : hors du champ de la caméra -> la Part n'est pas déplacée (la
		-- simulation continue : elle réapparaît au bon endroit) ; au-delà de 60 studs -> une image sur deux
		local rel = s.Pos - camPos
		local dist = rel.Magnitude
		if dist > 8 and (rel:Dot(camLook) < dist * cosHalf or (dist > 60 and (i + frameParity) % 2 == 0)) then
			s.Parked = false -- (une braise posée hors champ sera replacée quand elle revient dans le champ)
			i += 1
			continue
		end

		local cf
		if s.Puff then
			cf = CFrame.new(s.Pos) * s.Puff.Rot
		elseif s.Resting or s.Vel.Magnitude < 1e-3 then
			cf = CFrame.new(s.Pos)
		else
			cf = CFrame.lookAt(s.Pos, s.Pos + s.Vel)
		end
		table.insert(parts, s.Part)
		table.insert(cframes, cf)
		i += 1
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged) -- seul mode léger valide (FireNoEvents n'existe pas)
	end

	-- "pops" secondaires (crépitement de feu d'artifice), après la boucle pour ne pas la modifier en cours
	for _, p in pending do
		local inherit = p[2] * 0.3
		for _ = 1, 4 do
			Sparks.Emit(p[1], rng:NextUnitVector() * rng:NextNumber(4, 9) + inherit, CRACKLE_OPTS)
		end
	end
end

function Sparks.Count(): number
	return #live
end

function Sparks.Density(): number
	return density
end

function Sparks.Init()
	folder = Instance.new("Folder")
	folder.Name = "WandSparks_Local"
	folder.Parent = workspace
	refreshFilter()
	RunService.RenderStepped:Connect(step)
	-- PRÉ-CRÉATION de la réserve (400 pièces, 25 par image) : sinon le PREMIER tir crée ses pièces
	-- en direct -> pic de lag au premier projectile
	task.spawn(function()
		local made = {} -- kept aside until the end (takePart would pop them back from the pool)
		for _ = 1, 16 do
			for _ = 1, 25 do
				if #pool > 0 then break end -- real emits already refilled the pool: nothing to do
				local p = takePart()
				if not p then break end
				table.insert(made, p)
			end
			RunService.Heartbeat:Wait()
		end
		for _, p in made do
			table.insert(pool, p)
		end
	end)
end

return Sparks

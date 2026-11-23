local aimDir, burstMotes, elementColors
--[[
	WandClient/IncantFX — CERCLES D'INCANTATION (tous les joueurs voient les cercles de tous les lanceurs)
	Serveur -> FX "IncantStart" { u, n, t, c = { {e = élément, r = rang, m = modificateurs} }, f = formation }
	          "IncantEnd" { u, n = cercles lancés, r = "Release" | "Cancel" | "Death" }
	Progression lue sur les attributs répliqués du lanceur : IncantDone, IncantStart (heure serveur du cercle en
	cours), IncantDur, IncantN, IncantAim (point visé, ~12/s).
	Placement (user) : là où le tir part — empilés devant la baguette le long de la visée ; formation cercle = un
	cercle à chaque point de départ autour du joueur.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MagicCircle = require(script.Parent:WaitForChild("MagicCircle"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Config = require(ReplicatedStorage:WaitForChild("WandShared"):WaitForChild("Config"))
local FXSettings = require(script.Parent:WaitForChild("FXSettings"))

local IncantFX = {}

-- ── SONS : UNIQUEMENT ceux validés à l'écoute par le joueur (2026-11-22) ───────────────────────────
-- Volumes CALIBRÉS sur le niveau moyen mesuré (AudioAnalyzer RmsLevel) : gain = CIBLE / rms.
local function S(id: number, rms: number) return { Id = "rbxassetid://" .. id, Rms = rms } end
local SND = {
	-- pulsations de synthé douces (famille PSE « Pulsing Tone Smooth Mid Range ») : apparition / vie des cercles
	Pulse = {
		S(9117963953, 0.132), S(9117964358, 0.104), S(9117965088, 0.084), S(9117962385, 0.018),
		S(9117962900, 0.014), S(9117963587, 0.015), S(9117962212, 0.013), S(9117965030, 0.077),
	},
	-- apparition d'un cercle : « summon-witch » REJETÉ (user : enfantin, baguette magique à paillettes) ->
	-- retour à la pulsation validée la plus grave et ronde, en attendant mieux
	Appear = S(5232182821, 0.058), -- « Objective_Appear » grave et sourd : CHOISI par le joueur (2026-11-22)
	Bed = S(9117318780, 0.084), -- corde de piano frottée, fantomatique : fond grave de la charge
	BeamCircle = S(121101412739394, 0.106), -- « charge finale » : fin de cercle d'un sort de RAYON
	Release = S(9126232192, 0.018), -- souffle grave qui grince : l'incantation lâche (fort)
	After = S(9114630613, 0.079), -- métal qui chante (gong sans frappe) : résonance après le départ du sort
	Break = S(9114592102, 0.06), -- verre brisé (pas encore validé : à remplacer si besoin)
}
local TARGET = 0.15 -- (user : sons pas assez puissants)
local function gain(s, mul: number?): number
	return math.clamp(TARGET / s.Rms, 0.2, 9) * (mul or 1)
end
task.spawn(function()
	local list = {}
	local function add(s)
		local snd = Instance.new("Sound")
		snd.SoundId = s.Id
		table.insert(list, snd)
	end
	for _, v in SND.Pulse do add(v) end
	for k, v in SND do if k ~= "Pulse" then add(v) end end
	pcall(ContentProvider.PreloadAsync, ContentProvider, list)
end)

-- hauteur selon la TAILLE du cercle : gros cercle = plus grave
local function pitchFor(size: number): number
	return math.clamp(1.12 - (size - 3.2) * 0.025, 0.95, 1.12) -- (user : trop de basses -> on ne descend plus)
end

local function sfxGroup(): SoundGroup?
	return SoundService:FindFirstChild("WandSFXDry") or SoundService:FindFirstChild("WandSFX")
end

-- son ponctuel attaché au lanceur (3D) ; start/len : extrait de l'échantillon
-- ── SONS D'INFUSION RÉUTILISÉS (user 2026-11-22) : chaque cercle sonne comme SON élément, version adoucie ──
-- Profil d'élément (WandShared/Elements/<El>.Sound.Profile) : Cast / Tail / Bounce / Impact -> événements SoundFX.
local SoundFX = require(script.Parent:WaitForChild("SoundFX"))
local ElementProfiles = {}
for _, m in ReplicatedStorage:WaitForChild("WandShared"):WaitForChild("Elements"):GetChildren() do
	if m:IsA("ModuleScript") then
		local ok, def = pcall(require, m)
		if ok and type(def) == "table" and def.Sound and def.Sound.Profile then
			ElementProfiles[m.Name] = def.Sound.Profile
		end
	end
end
local function elemSound(kind: string, el: string?, pos: Vector3, pitchMul: number, volMul: number)
	local p = ElementProfiles[el or ""] or ElementProfiles.Arcane
	local name = p and (p[kind] or p.Cast)
	if name then
		pcall(SoundFX.Play, name, pos, pitchMul, volMul)
	end
end

-- SONS COUPÉS (user 2026-11-22) en attendant des sons pro (Sonniss GDC) : mettre à false pour les réactiver
local MUTED = true

local function oneShot(parent: Instance, snd: any, vol: number, pitch: number, start: number?, len: number?, fade: number?, force: boolean?)
	if MUTED and not force then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = if type(snd) == "table" then snd.Id else snd
	s.Volume = vol
	s.PlaybackSpeed = pitch
	s.RollOffMinDistance = 24 -- (user 2026-11-23 : incantations audibles de plus loin)
	s.RollOffMaxDistance = 260
	s.SoundGroup = sfxGroup()
	s.TimePosition = start or 0
	local eq = Instance.new("EqualizerSoundEffect") -- coupe les basses (user : trop de basses)
	eq.LowGain = -14
	eq.MidGain = 0
	eq.HighGain = -1
	eq.Parent = s
	s.Parent = parent
	s:Play()
	local life = (len or 3) / pitch
	if fade then
		task.delay(math.max(0, life - fade), function()
			if s.Parent then
				game:GetService("TweenService"):Create(s, TweenInfo.new(fade), { Volume = 0 }):Play()
			end
		end)
	end
	task.delay(life + 0.1, function()
		s:Destroy()
	end)
	return s
end

-- ── MANA : la baguette ASPIRE le mana environnant — des points lumineux partent de 8-15 studs autour du lanceur,
-- décrivent une courbe et ACCÉLÈRENT jusqu'au cercle en cours ; leur flux grossit avec la charge et la taille du cercle.
local CameraFX = require(script.Parent:WaitForChild("CameraFX"))
local ScreenFX = require(script.Parent:WaitForChild("ScreenFX"))
local motePool = {}
local liveMotes = 0
local MOTE_GLOBAL = 220
local moteFolder = Instance.new("Folder")
moteFolder.Name = "IncantMana"
moteFolder.Parent = workspace
local function takeMote(): Part
	local p = table.remove(motePool)
	if p then
		return p
	end
	p = Instance.new("Part")
	p.Name = "Mana"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = Vector3.one * 0.2
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.09, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.09, 0)
	a1.Parent = p
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = 0.16
	tr.FaceCamera = true
	tr.LightEmission = 0.25 -- pas de saturation blanche
	tr.Transparency = NumberSequence.new(0.15, 1)
	tr.WidthScale = NumberSequence.new(1, 0.2)
	tr.Parent = p
	p.Parent = moteFolder
	return p
end
local function freeMote(p: Part)
	p.Transparency = 1
	p.CFrame = CFrame.new(0, -1e4, 0)
	p.Trail.Enabled = false
	table.insert(motePool, p)
	liveMotes -= 1
end
local function spawnMote(a, root: BasePart, el: string, scale: number)
	if liveMotes >= MOTE_GLOBAL then
		return
	end
	local core, edge = elementColors(el)
	local p = takeMote()
	liveMotes += 1
	local ang = math.random() * math.pi * 2
	-- STYLE « SPORES » (user : nouvel effet) : petits carrés pixel qui ÉMERGENT DU SOL autour du joueur,
	-- montent en flottant et en scintillant, puis sont ASPIRÉS vers le cercle. Pas de traînée.
	local dist = 5 + math.random() * 11
	local guess = root.Position + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { a.Player.Character, moteFolder }
	local hit = workspace:Raycast(guess + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), rp)
	local start = if hit then hit.Position + Vector3.new(0, 0.15, 0) else guess - Vector3.new(0, 2.8, 0)
	local light = Config.Elements[el] and Config.Elements[el].Core or core
	p.Color = core
	p.Size = Vector3.one * (0.22 + math.random() * 0.16) * math.min(scale, 1.4)
	p.Transparency = 0.05
	p.Trail.Enabled = false
	p.CFrame = CFrame.new(start) * CFrame.Angles(0, math.rad(45 * math.random(0, 1)), math.rad(45 * math.random(0, 1)))
	table.insert(a.Motes, {
		Ang = ang, Dist = dist, Y0 = start.Y - root.Position.Y, Spin = (if math.random() < 0.5 then -1 else 1) * (1.2 + math.random() * 0.8),
		Rise = 1.2 + math.random() * 2.2, RiseT = 0.45 + math.random() * 0.35, Core = core, Light = light, Flick = math.random() * 10,
		Part = p, Start = start, T = 0, Dur = 1.5 + math.random() * 0.9, -- montée lente puis aspiration
		Side = Vector3.new(-math.sin(ang), 0, math.cos(ang)) * (if math.random() < 0.5 then -1 else 1),
		Curve = 3 + math.random() * 5, Lift = math.random() * 4,
	})
end
local function stepMotes(a, target: Vector3, dt: number)
	local i = 1
	while i <= #a.Motes do
		local m = a.Motes[i]
		m.T += dt / m.Dur
		if m.T >= 1 or m.Fly then
			if m.Fly then
				-- projection au départ du sort : vole vers l'avant et s'éteint
				m.FlyT += dt
				m.Pos += m.Vel * dt
				m.Part.CFrame = CFrame.new(m.Pos)
				m.Part.Transparency = math.clamp(m.FlyT / 0.35, 0.1, 1)
				if m.FlyT < 0.35 then
					i += 1
					continue
				end
			end
			freeMote(m.Part)
			a.Motes[i] = a.Motes[#a.Motes]
			a.Motes[#a.Motes] = nil
			continue
		end
		local rise = m.RiseT or 0
		if m.T < rise then
			-- PHASE 1 : la spore monte du sol en flottant, oscille et scintille
			local k = m.T / rise
			local sway = Vector3.new(math.sin(m.Flick + m.T * 9) * 0.25, 0, math.cos(m.Flick + m.T * 7) * 0.25)
			local pos = m.Start + Vector3.new(0, m.Rise * (1 - (1 - k) ^ 2), 0) + sway
			m.Pos = pos
			m.Lift0 = pos
			m.Part.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(45 * (math.floor(m.T * 6) % 2)), 0)
			m.Part.Color = if math.floor((m.Flick + m.T) * 8) % 3 == 0 then m.Light else m.Core
			i += 1
			continue
		end
		local u = (m.T - rise) / math.max(1 - rise, 0.05)
		local e = u ^ 2.4 -- PHASE 2 : aspirée, accélère en approchant
		local from = m.Lift0 or m.Start
		local pos
		if a.Around and a.Center then
			-- GRAVITE autour du joueur : spirale qui se resserre (tour et demi) puis plonge dans le cercle
			local ang = m.Ang + e * math.pi * 2 * m.Spin
			local rr = m.Dist * (1 - e) + 0.6 * e
			local orbit = a.Center + Vector3.new(math.cos(ang) * rr, (from.Y - a.Center.Y) * (1 - e), math.sin(ang) * rr)
			pos = orbit:Lerp(target, e ^ 3)
		else
			pos = from:Lerp(target, e) + m.Side * math.sin(math.pi * e) * m.Curve * 0.5
		end
		-- la spore rétrécit un peu en entrant dans le cercle
		m.Part.Transparency = 0.05 + math.max(0, e - 0.85) * 4
		m.Pos = pos
		m.Part.CFrame = CFrame.new(pos)
		i += 1
	end
end
-- ── VORTEX DE PARTICULES (ParticleEmitter) : une sphère invisible centrée sur le cercle en cours émet VERS
-- L'INTÉRIEUR : les particules naissent tout autour et convergent toutes vers le centre du cercle.
local function vortexEmitter(parent: BasePart, props)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxassetid://103763299233462" -- carré pixel (PIXEL est défini plus bas dans le fichier)
	pe.LightInfluence = 0
	pe.Rate = 0
	pe.Rotation = NumberRange.new(0, 360)
	for k, v in props do
		pe[k] = v
	end
	pe.Parent = parent
	return pe
end
local function buildVortex(el: string)
	local core = elementColors(el)
	local light = Config.Elements[el] and Config.Elements[el].Core or core
	local part = Instance.new("Part")
	part.Name = "ManaVortex"
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Transparency = 1
	part.Size = Vector3.one * 20
	part.Parent = moteFolder
	local inward = vortexEmitter(part, {
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Lifetime = NumberRange.new(0.9), Speed = NumberRange.new(11),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(0.5, 0.32), NumberSequenceKeypoint.new(1, 0.05) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.1), NumberSequenceKeypoint.new(0.85, 0.15), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(core, light), LightEmission = 0.35, RotSpeed = NumberRange.new(-220, 220),
	})
	local glints = vortexEmitter(part, {
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Lifetime = NumberRange.new(0.25, 0.5), Speed = NumberRange.new(0.5, 2),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1, 1), Color = ColorSequence.new(light, core), LightEmission = 0.45,
		SpreadAngle = Vector2.new(180, 180),
	})
	local glintPart = Instance.new("Part")
	glintPart.Name = "ManaGlints"
	glintPart.Anchored, glintPart.CanCollide, glintPart.CanQuery, glintPart.CanTouch, glintPart.CastShadow = true, false, false, false, false
	glintPart.Transparency = 1
	glintPart.Size = Vector3.one * 4
	glintPart.Parent = moteFolder
	glints.Parent = glintPart
	return { Part = part, GlintPart = glintPart, Inward = inward, Glints = glints }
end
local function setVortexColor(v, el: string)
	local core = elementColors(el)
	local light = Config.Elements[el] and Config.Elements[el].Core or core
	v.Inward.Color = ColorSequence.new(core, light)
	v.Glints.Color = ColorSequence.new(light, core)
end
-- INTENSITÉ PAR RANG (user 2026-11-23) : nombre ET vitesse des particules d'incantation
local RANK_K = { Moyen = 0.65, Superieur = 1.2, Supreme = 1.7 }
local function stepVortex(v, center: Vector3, circleSize: number, prog: number, rk: number?)
	rk = rk or 1
	local r = 7 + circleSize * 0.8 -- rayon de capture : tout l'espace autour, suit la taille du cercle
	local life = 0.95 / math.sqrt(rk) -- rang élevé = particules plus rapides
	v.Part.Size = Vector3.one * (r * 2)
	v.Part.CFrame = CFrame.new(center)
	v.GlintPart.Size = Vector3.one * math.max(circleSize, 2)
	v.GlintPart.CFrame = CFrame.new(center)
	v.Inward.Speed = NumberRange.new(r / life * 0.97) -- arrive pile au centre en fin de vie
	v.Inward.Lifetime = NumberRange.new(life)
	local q = FXSettings.QualityK()
	v.Inward.Rate = (35 + prog * 110) * q * rk
	v.Glints.Rate = (10 + prog * 30) * q * rk
end
local function endVortex(v, burst: boolean)
	if not v then
		return
	end
	v.Inward.Rate = 0
	v.Glints.Rate = 0
	if burst then
		v.Inward.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		v.Inward.Speed = NumberRange.new(18, 34)
		v.Part.Size = Vector3.one * 2
		v.Inward:Emit(math.floor(50 * FXSettings.QualityK()))
	end
	task.delay(1.2, function()
		v.Part:Destroy()
		v.GlintPart:Destroy()
	end)
end

function burstMotes(a, forward: boolean)
	local dir = Vector3.new(0, 1, 0)
	if forward then
		local _, d = aimDir(a.Player)
		dir = d or dir
	end
	for _, m in a.Motes do
		if not m.Fly then
			m.Fly = true
			m.FlyT = 0
			m.Pos = m.Pos or m.Start
			local spread = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			m.Vel = if forward then (dir * 40 + spread * 18) else spread * 30
		end
	end
end

-- ── AURA : particules de l'élément du deck qui tournent / s'agitent autour du lanceur ────────────
local PIXEL = "rbxassetid://103763299233462"
function elementColors(el: string): (Color3, Color3)
	-- MID (saturé) -> EDGE : on reconnaît l'élément (le CORE est presque blanc pour tous les éléments)
	local e = Config.Elements[el] or Config.Elements.Neutral
	return e.Mid or e.Core or Color3.new(1, 1, 1), e.Edge or e.Mid or Color3.new(1, 1, 1)
end

local function buildAura(pl: Player, elements: { string })
	local anchor = Instance.new("Part")
	anchor.Name = "IncantAura"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Parent = workspace
	local orbits = {}
	local qk = FXSettings.QualityK()
	-- au moins 6 orbites au total (deck d'un seul élément = 6 traînées), 2 par élément en qualité Basse
	local perEl = if qk < 1 then 2 else math.max(3, math.ceil(6 / math.max(#elements, 1)))
	for ei, el in elements do
		local core, edge = elementColors(el)
		for k = 1, perEl do
			local att = Instance.new("Attachment")
			att.Parent = anchor
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = PIXEL
			pe.Color = ColorSequence.new(core, edge)
			pe.LightEmission = 0.2 -- pas de saturation blanche (règle : aucun flash / bloom)
			pe.LightInfluence = 0
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.24), NumberSequenceKeypoint.new(0.6, 0.15), NumberSequenceKeypoint.new(1, 0) })
			pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
			pe.Lifetime = NumberRange.new(0.5, 1.1)
			pe.Speed = NumberRange.new(0.2, 1.2)
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.Drag = 3
			pe.Rate = 0
			pe.Rotation = NumberRange.new(0, 360)
			pe.Parent = att
			table.insert(orbits, {
				Att = att, Pe = pe,
				Angle = math.random() * math.pi * 2,
				Tilt = (ei - 1) * 0.9 + (k - 1) * 2.1 + math.random() * 0.5,
				Radius = 2 + (k - 1) * 0.45 + math.random() * 0.3,
				Height = -0.6 + (k - 1) * 0.9,
				Dir = if (ei + k) % 2 == 0 then 1 else -1,
				Seed = math.random() * 100,
			})
		end
	end
	return { Anchor = anchor, Orbits = orbits, Q = qk }
end

local function stepAura(aura, pl: Player, progress: number, t: number, dt: number)
	local ch = pl.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	aura.Anchor.CFrame = CFrame.new(root.Position)
	local speed = 1.6 + progress * 5 -- tourne de plus en plus vite
	local agit = 0.15 + progress * 0.55 -- s'agite de plus en plus
	local rate = (8 + progress * 26) * aura.Q
	for _, o in aura.Orbits do
		o.Angle += dt * speed * o.Dir
		local r = o.Radius * (1 - progress * 0.25) + math.noise(o.Seed, t * 2.3) * agit
		local h = o.Height + math.sin(t * 2.1 + o.Seed) * (0.25 + agit) + math.noise(t * 3, o.Seed) * agit
		local flat = Vector3.new(math.cos(o.Angle) * r, 0, math.sin(o.Angle) * r)
		local tilted = CFrame.Angles(math.sin(o.Tilt) * 0.5, o.Tilt, math.cos(o.Tilt) * 0.35):VectorToWorldSpace(flat)
		o.Att.Position = tilted + Vector3.new(0, h, 0)
		o.Pe.Rate = rate
	end
end

local function endAura(aura, burst: boolean)
	if not aura then
		return
	end
	for _, o in aura.Orbits do
		o.Pe.Rate = 0
		if burst then
			o.Pe.Speed = NumberRange.new(6, 14)
			o.Pe:Emit(8)
		end
	end
	task.delay(1, function()
		aura.Anchor:Destroy()
	end)
end
local active = {} -- [userId] = { Player, Circles = {}, Formation }

local SIZE = { Moyen = 4.0, Superieur = 4.5, Supreme = 6.2 } -- (user : cercles plus grands, +35 % ; Moyen +25 % le 2026-11-23)

function aimDir(pl: Player): (Vector3?, Vector3?)
	local ch = pl.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil, nil
	end
	local head = root.Position + Vector3.new(0, 1.5, 0)
	local aim = pl:GetAttribute("IncantAim")
	local dir = if typeof(aim) == "Vector3" then aim - head else root.CFrame.LookVector
	dir = if dir.Magnitude > 1 then dir.Unit else root.CFrame.LookVector
	return head, dir
end

local function stop(uid: number, released: number?)
	local a = active[uid]
	if not a then
		return
	end
	active[uid] = nil
	if a.Bed then
		local bed = a.Bed
		game:GetService("TweenService"):Create(bed, TweenInfo.new(0.5), { Volume = 0 }):Play()
		task.delay(0.55, function()
			bed:Destroy()
		end)
	end
	local root = a.Player.Character and a.Player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		if released and released > 0 then
			elemSound("Cast", a.Els[1], root.Position, 0.8, 1.2) -- départ : lancement de l'élément principal, plus grave
			local power = math.clamp(released / 3, 0.35, 1.2) * math.clamp((a.Sizes[1] or 3) / 3.3, 0.7, 1.6)
			task.delay(0.04, function()
				elemSound("Impact", a.Els[1], root.Position, 0.8, 1.3 + power * 0.5) -- coup de puissance au départ
			end)
			pcall(CameraFX.ShakeAt, root.Position, 0.45 + power * 0.5, 45, a.Els[1], a.Player == Players.LocalPlayer)
			if a.Player == Players.LocalPlayer then
				pcall(ScreenFX.Pulse, math.clamp(0.18 + power * 0.2, 0.15, 0.45))
			end
			burstMotes(a, true)
		else
			elemSound("Bounce", a.Els[1], root.Position, 0.7, 1.0) -- rupture : rebond de l'élément, grave et court
			burstMotes(a, false)
		end
		if released and released > 0 then
			-- l'incantation LÂCHE : souffle grave (fort), puis le métal qui chante une fois le sort parti
			-- RELÂCHEMENT selon la FAMILLE du sort du 1er cercle (user) ; puissance selon la taille du cercle
			local pw = math.clamp((a.Sizes[1] or 4) / 4.5, 0.8, 2)
			local fam = a.Fams[1] or "Projectile"
			local pos = root.Position
			local function after(pitch: number, vol: number)
				task.delay(0.18, function()
					if root.Parent then
						oneShot(root, SND.After, gain(SND.After, vol), pitch, 0, 3.2, 1.6, true)
					end
				end)
			end
			if fam == "Beam" then
				-- RAYON : décharge nette — charge finale + son de rayon de l'élément + métal plus aigu
				oneShot(root, SND.BeamCircle, gain(SND.BeamCircle, 1.4 * pw), 0.9, 0, 1, 0.3, true)
				local prof = ElementProfiles[a.Els[1] or ""] or {}
				pcall(SoundFX.Play, prof.Beam or "Beam.Laser", pos, 0.9, 0.9 * pw)
				after(1.25, 0.7)
			elseif fam == "Procedural" then
				-- PROCÉDURAL : poussée qui sort du sol — souffle grave + pousse + métal grave
				oneShot(root, SND.Release, gain(SND.Release, 1.5 * pw), 0.8, 0, 1.8, 0.6, true)
				pcall(SoundFX.Play, "Grow.Start", pos, 0.85, 1.2 * pw)
				after(0.85, 0.9)
			elseif fam == "Trap" then
				oneShot(root, SND.Release, gain(SND.Release, 0.9), 1.15, 0, 1.2, 0.4, true)
				pcall(SoundFX.Play, "Trap.Set", pos, 0.9, 1.1)
				after(1.1, 0.5)
			elseif fam == "Self" then
				oneShot(root, SND.Release, gain(SND.Release, 0.9), 1.15, 0, 1.2, 0.4, true)
				pcall(SoundFX.Play, "Zone.ShieldUp", pos, 0.95, 1.1)
				after(1.1, 0.5)
			else
				-- PROJECTILE (et le reste) : souffle + détonation sèche + métal qui résonne
				oneShot(root, SND.Release, gain(SND.Release, 1.5 * pw), 1.0, 0, 1.6, 0.5, true)
				pcall(SoundFX.Play, if pw > 1.3 then "Explosion.Big" else "Explosion.Medium", pos, 1.15, 0.55 * pw)
				after(1.0, 0.9)
			end
		else
			oneShot(root, SND.Break, gain(SND.Break, 0.45), 1, 0, 1.2, 0.4)
		end
	end
	endAura(a.Aura, released ~= nil and released > 0)
	endVortex(a.Vortex, released ~= nil and released > 0)
	if #a.Motes > 0 then
		burstMotes(a, released ~= nil and released > 0)
		local motes = a.Motes
		task.spawn(function()
			local holder = { Motes = motes }
			local t0 = os.clock()
			while #holder.Motes > 0 and os.clock() - t0 < 1 do
				local dt = RunService.RenderStepped:Wait()
				stepMotes(holder, Vector3.zero, dt)
			end
			for _, m in holder.Motes do
				freeMote(m.Part)
			end
		end)
	end
	for i, c in a.Circles do
		if released and i <= released then
			c:Release()
		else
			c:Break()
		end
	end
end

local function start(msg)
	local pl = Players:GetPlayerByUserId(tonumber(msg.u) or 0)
	if not pl or type(msg.c) ~= "table" then
		return
	end
	stop(pl.UserId)
	local n = math.clamp(#msg.c, 1, 12)
	local circles = {}
	local stackOffset = 0
	-- rayon de la formation : assez grand pour le plus gros cercle
	local biggest = 0
	for k = 1, n do
		local inf = msg.c[k]
		biggest = math.max(biggest, (SIZE[tostring(inf.r or "Moyen")] or SIZE.Moyen) * (tonumber(inf.s) or 1))
	end
	local ringR = math.max(4.2, 2.2 + biggest * 0.7) -- (user 2026-11-23 : plus espacés)
	local aboveOffset = 0
	for i = 1, n do
		local info = msg.c[i]
		local rank = tostring(info.r or "Moyen")
		local around = msg.m == "Around"
		local procK = if around and info.f == "Procedural" then 1.6 else 1 -- sorts procéduraux AUTOUR du joueur : cercles plus gros
		local size = math.clamp((SIZE[rank] or SIZE.Moyen) * (tonumber(info.s) or 1) * procK, 2.2, if around then 34 else 26)
		local idx = i
		local origin
		if around then
			-- AUTOUR DU JOUEUR : 1er cercle AU SOL sous lui, les suivants empilés AU-DESSUS de sa tête (à plat)
			local height = aboveOffset
			if idx > 1 then
				aboveOffset += 1.7 + size * 0.22 -- (user 2026-11-23 : plus espacés)
			end
			origin = function()
				local ch = pl.Character
				local r = ch and ch:FindFirstChild("HumanoidRootPart")
				if not r then
					return nil
				end
				if idx == 1 then
					local rp = RaycastParams.new()
					rp.FilterType = Enum.RaycastFilterType.Exclude
					rp.FilterDescendantsInstances = { ch, workspace:FindFirstChild("IncantMana") }
					local hit = workspace:Raycast(r.Position, Vector3.new(0, -12, 0), rp)
					local gy = if hit then hit.Position.Y + 0.12 else r.Position.Y - 3
					return Vector3.new(r.Position.X, gy, r.Position.Z), Vector3.yAxis
				end
				return r.Position + Vector3.new(0, 5.2 + height, 0), Vector3.yAxis -- (user 2026-11-23 : plus haut)
			end
		elseif msg.f == "Circle" then
			origin = function()
				local head, dir = aimDir(pl)
				if not head then
					return nil
				end
				local flat = Vector3.new(dir.X, 0, dir.Z)
				flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
				local frac = tonumber(info.a) or ((idx - 1) / n)
				local d = CFrame.Angles(0, frac * math.pi * 2, 0):VectorToWorldSpace(flat)
				return head + d * (ringR + (tonumber(info.o) or 0) * (1.8 + size * 0.5)), d
			end
		else
			local offset = stackOffset
			stackOffset += 1.2 + size * 0.42 -- (user 2026-11-23 : plus espacés)
			origin = function()
				local head, dir = aimDir(pl)
				if not head then
					return nil
				end
				return head + dir * (2.5 + offset + size * 0.15), dir
			end
		end
		circles[i] = MagicCircle.new({ Element = tostring(info.e or "Neutral"), Size = size, Kind = rank, Origin = origin, Runes = info.m })
	end
	local fracs = {}
	for k = 1, n do
		fracs[k] = tonumber(msg.c[k].d) or (1 / n)
	end
	local elements, seen = {}, {}
	for k = 1, n do
		local el = tostring(msg.c[k].e or "Neutral")
		if not seen[el] and #elements < 3 then
			seen[el] = true
			table.insert(elements, el)
		end
	end
	local aura = buildAura(pl, elements)
	local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
	local els = {}
	for k = 1, n do
		els[k] = tostring(msg.c[k].e or "Neutral")
	end
	local sizes, fams, ranks = {}, {}, {}
	for k = 1, n do
		local inf = msg.c[k]
		ranks[k] = RANK_K[tostring(inf.r or "Moyen")] or 1
		sizes[k] = math.clamp((SIZE[tostring(inf.r or "Moyen")] or SIZE.Moyen) * (tonumber(inf.s) or 1) * (if msg.m == "Around" and inf.f == "Procedural" then 1.6 else 1), 2.2, if msg.m == "Around" then 34 else 26)
		fams[k] = inf.f
	end
	-- SON DU MANA (user : son dynamique tout du long) : corde de piano frottée validée, SANS descente dans le grave
	-- (hauteur normale -> plus aigu avec la charge), basses coupées ; son volume suit le flux de particules.
	local bed
	if root then
		bed = Instance.new("Sound")
		bed.SoundId = SND.Bed.Id
		bed.Volume = 0
		bed.PlaybackSpeed = 1.05
		bed.Looped = true
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = -16
		eq.MidGain = 0
		eq.HighGain = -2
		eq.Parent = bed
		bed.RollOffMinDistance = 24
		bed.RollOffMaxDistance = 260
		bed.SoundGroup = sfxGroup()
		bed.Parent = root
		bed:Play()
		-- (volume piloté chaque image par le flux de mana)
	end
	active[pl.UserId] = { Player = pl, Circles = circles, Fracs = fracs, Aura = aura, Els = els, Sizes = sizes, Fams = fams, Ranks = ranks, Bed = bed,
		T0 = os.clock(), LastDone = 0, NextPulse = 0, Started = 0, PulseIdx = math.random(1, #SND.Pulse), Motes = {}, MoteAcc = 0, Around = msg.m == "Around", Vortex = buildVortex(els[1] or "Neutral") }
end

function IncantFX.Handle(msg)
	if msg.k == "IncantStart" then
		local ok, err = pcall(start, msg)
		if not ok then
			warn("[IncantFX]", err)
		end
	elseif msg.k == "IncantEnd" then
		stop(tonumber(msg.u) or 0, if msg.r == "Release" then tonumber(msg.n) else nil)
	end
end

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	for uid, a in active do
		local pl = a.Player
		local n = pl.Parent and pl:GetAttribute("IncantN")
		if not n then
			-- l'incantation a disparu sans message de fin (déconnexion...) : on casse les cercles
			if os.clock() - (a.Missing or os.clock()) > 0.5 then
				stop(uid)
			else
				a.Missing = a.Missing or os.clock()
			end
			continue
		end
		a.Missing = nil
		local done = pl:GetAttribute("IncantDone") or 0
		local segStart = pl:GetAttribute("IncantStart") or now
		local dur = pl:GetAttribute("IncantDur") or 1
		-- progression GLOBALE (0..1) au prorata des durées des cercles
		local overall = 0
		for i = 1, #a.Circles do
			local f = a.Fracs[i] or (1 / math.max(n, 1))
			if i <= done then
				overall += f
			elseif i == done + 1 then
				overall += f * math.clamp((now - segStart) / math.max(dur * f, 0.01), 0, 1)
			end
		end
		local t = os.clock() - a.T0
		-- flux de MANA vers le cercle en cours (sa position réelle), plus dense avec la charge et la taille
		do
			local root2 = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			local cur = math.min(done + 1, #a.Circles)
			local circle = a.Circles[cur]
			local target = circle and circle.Part and circle.Part.Position
			if not target then
				local head, d = aimDir(pl)
				target = head and (head + d * 2.5) or (root2 and root2.Position)
			end
			if target and root2 then
				local curEl = a.Els[cur] or "Neutral"
				if a.CurEl ~= curEl then
					a.CurEl = curEl
					local core, edge = elementColors(curEl)
					local TS = game:GetService("TweenService")
					for _, m in a.Motes do
						if not m.Fly then
							TS:Create(m.Part, TweenInfo.new(0.4), { Color = core }):Play()
							m.Part.Trail.Color = ColorSequence.new(core, edge)
						end
					end
					for _, o in (a.Aura and a.Aura.Orbits or {}) do
						o.Pe.Color = ColorSequence.new(core, edge)
					end
					if a.Vortex then
						setVortexColor(a.Vortex, curEl)
					end
				end
				if a.Vortex then
					local fv = a.Fracs[cur] or (1 / math.max(n, 1))
					local pv = math.clamp((now - segStart) / math.max(dur * fv, 0.01), 0, 1)
					stepVortex(a.Vortex, target, a.Sizes[cur] or 4, pv, a.Ranks[cur])
				end
				local f = a.Fracs[cur] or (1 / math.max(n, 1))
				local prog = math.clamp((now - segStart) / math.max(dur * f, 0.01), 0, 1)
				local scale = math.clamp((a.Sizes[cur] or 3) / 3.3, 0.8, 1.8)
				local rate = (5 + prog * 12) * scale * FXSettings.QualityK() * (a.Ranks[cur] or 1) -- spores (pièces) : couche secondaire, le vortex de particules fait l'essentiel
				a.MoteAcc += rate / 60
				while a.MoteAcc >= 1 do
					a.MoteAcc -= 1
					spawnMote(a, root2, a.Els[cur] or "Neutral", scale)
				end
				a.Center = root2.Position
				stepMotes(a, target, 1 / 60)
				if a.Bed then
					-- MONTÉE : chaque cercle repart un peu plus haut que le précédent et monte jusqu'à sa fin
					local flow = math.clamp(#a.Motes / 50, 0, 1)
					local want = gain(SND.Bed, 0.55 + 0.6 * prog + 0.35 * flow)
					a.Bed.Volume += (want - a.Bed.Volume) * 0.1
					a.Bed.PlaybackSpeed = 1.0 + prog * 0.55 + (cur - 1) * 0.06
					local eq = a.Bed:FindFirstChildOfClass("EqualizerSoundEffect")
					if eq then
						eq.HighGain = -8 + prog * 9 -- le son « s'ouvre » en approchant de la fin du cercle
					end
				end
			end
		end
		if a.Aura then
			stepAura(a.Aura, pl, overall, t, 1 / 60)
		end
		local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local function nextPulse()
				a.PulseIdx = a.PulseIdx % #SND.Pulse + 1 -- jamais deux fois la même variante d'affilée
				return SND.Pulse[a.PulseIdx]
			end
			local cur = done + 1
			-- APPARITION d'un cercle (début de sa charge) : une pulsation pleine, hauteur selon sa taille
			if cur <= #a.Circles and cur > a.Started then
				a.Started = cur
				-- son de LANCEMENT de l'élément du cercle, un peu plus grave et plus doux (plus grave si gros cercle)
				-- apparition du cercle : une PULSATION de synthé validée par le joueur (même famille pour tous les éléments)
				oneShot(root, SND.Appear, gain(SND.Appear, 1.6), pitchFor(a.Sizes[cur] or 3), 0, 2.6, 0.6, true) -- (user : plus fort)
				a.NextPulse = os.clock() + 0.5
			end
			-- PENDANT la charge : pulsations plus discrètes qui se RAPPROCHENT et montent avec la charge du cercle
			if cur <= #a.Circles and os.clock() >= a.NextPulse then
				local f = a.Fracs[cur] or (1 / math.max(n, 1))
				local segDur = dur * f
				local prog = math.clamp((now - segStart) / math.max(segDur, 0.01), 0, 1)
				a.NextPulse = os.clock() + math.clamp(0.75 - prog * 0.5, 0.25, 0.75)
				local p = nextPulse()
				oneShot(root, p, gain(p, 0.12 + prog * 0.16), pitchFor(a.Sizes[cur] or 3) * (1 + prog * 0.12), 0, 1.1, 0.5)
			end
			-- FIN d'un cercle : rayon = son de charge propre aux rayons ; autres = pulsation ronde et forte
			if done > a.LastDone then
				a.LastDone = done
				local sz = a.Sizes[done] or 3
				-- fin du cercle : traînée de l'élément (ou son lancement, un peu plus aigu)
				local prof = ElementProfiles[a.Els[done] or ""] or ElementProfiles.Arcane
				if prof and prof.Tail then
					elemSound("Tail", a.Els[done], root.Position, 1.0, 1.0)
				else
					elemSound("Cast", a.Els[done], root.Position, 1.12, 0.9)
				end
				if a.Fams[done] == "Beam" then
					oneShot(root, SND.BeamCircle, gain(SND.BeamCircle, 1.1), pitchFor(sz), 0, 1, 0.3, true) -- charge finale des rayons (réactivée)
				else
					-- CERCLE TERMINÉ : métal qui chante, court et clair (validé par le joueur pour l'après-sort)
					oneShot(root, SND.After, gain(SND.After, 0.75), 1.3 * pitchFor(sz) / 1.12, 0, 1.5, 0.9, true)
				end
				oneShot(root, SND.Release, gain(SND.Release, 0.6), 1.35, 0, 0.9, 0.4, true) -- souffle court : le cercle « avale » le mana
				for _, o in (a.Aura and a.Aura.Orbits or {}) do
					o.Pe:Emit(4)
				end
			end
		end
		for i, c in a.Circles do
			local seg = dur * (a.Fracs[i] or (1 / math.max(n, 1)))
			local p = if i <= done then 1 elseif i == done + 1 then math.clamp((now - segStart) / math.max(seg, 0.01), 0, 1) else 0
			c:SetProgress(p)
		end
	end
end)

return IncantFX

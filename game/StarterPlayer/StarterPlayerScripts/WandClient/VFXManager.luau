--[[
	WandClient/VFXManager — assembleur d'effets

	Lit les RECETTES (FXRecipes) et combine les briques :
	  • ParticleEmitter / Trail / Beam natifs (cœur, halo, flash, anneau, bouche de tir) ;
	  • Sparks    : étincelles physiques qui rebondissent (gerbes, traînées, braises, feux d'artifice) ;
	  • LightPool : lumières dynamiques budgétées (le sort ÉCLAIRE la scène) ;
	  • Ambience  : facteur Glow (scène sombre = effets émissifs à fond, plein jour = calmés).

	Direction artistique : formes nettes, couleurs en PALIERS (jamais de fondu), cœur blanc très chaud
	entouré d'un halo coloré, lumière qui décroît par paliers.

	Réseau : le serveur ne réplique que des Parts invisibles (workspace.WandProjectiles) + des messages
	SpellFX groupés. Chaque projectile serveur est suivi par un PROXY local lissé qui porte les effets.
	Textures : Config.Elements[...].Textures ; "rbxassetid://0" = carré natif net.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("WandShared"):WaitForChild("Config"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local FXRecipes = require(script.Parent:WaitForChild("FXRecipes"))
local LightPool = require(script.Parent:WaitForChild("LightPool"))
local Sparks = require(script.Parent:WaitForChild("Sparks"))
local Ambience = require(script.Parent:WaitForChild("Ambience"))
local Flipbook = require(script.Parent:WaitForChild("Flipbook"))
local SoundFX = require(script.Parent:WaitForChild("SoundFX"))

local PIXEL = Config.Textures.Pixel
local PLACEHOLDER = Config.Textures.Placeholder
local MAX_ACTIVE_FX = 140

local FXSettings = require(script.Parent:WaitForChild("FXSettings"))
local function applyQuality() -- réglage Qualité des effets (Bas / Moyen / Haut)
	MAX_ACTIVE_FX = math.floor(140 * FXSettings.QualityK())
end
applyQuality()
FXSettings.OnChanged(applyQuality)
local SMOOTHING = 60 -- lissage très court (16 ms) : la position est déjà extrapolée (dead reckoning)
local LOCAL_USER_ID = game:GetService("Players").LocalPlayer.UserId
-- Les traînées s'arrêtent au-delà de ce nombre d'étincelles vivantes : le reste du budget (Sparks
-- MAX_SPARKS) est RÉSERVÉ aux explosions, qui restent ainsi toujours pleines même en plein chaos.
local TRAIL_SPARK_CAP = 420
local rng = Random.new()

local VFX = {}

local fxFolder: Folder
local activeFx = 0

type Proxy = {
	Proxy: Part,
	Emitters: { ParticleEmitter },
	Light: any,
	LastPos: Vector3,
	SparkAcc: number,
	Recipe: any,
	SparkOpts: Sparks.SparkOpts,
	SparkRate: number,
	Rocket: boolean,
	Core: ParticleEmitter?,
	StopLoop: (() -> ())?,
	ServerPos: Vector3,
	ServerTime: number,
	ServerVel: Vector3,
	Frozen: number?, -- instant où il a été calé sur son point d'impact (ne bouge plus pendant 0.15 s)
	Blink: boolean?,
	BlinkT: number,
	BlinkOn: boolean,
}
local proxies: { [BasePart]: Proxy } = {}

local function vec(v: any): Vector3?
	return if typeof(v) == "Vector3" then v else nil
end

-- ── Utilitaires ───────────────────────────────────────────────────────────────────────────────────────
local function tex(id: string?): string
	if id == nil or id == "" or id == PLACEHOLDER then
		return PIXEL
	end
	return id
end

local function palette(element: any)
	return Config.Elements[element] or Config.Elements.Arcane
end

local function sparkColors(P): { Color3 }
	return P.SparkColors or P.Flicker or { P.Core, P.Mid, P.Edge }
end

local function sparkStyle(element: any)
	return FXRecipes.ElementSparks[element] or FXRecipes.ElementSparks.Arcane
end

-- ColorSequence / NumberSequence en PALIERS nets (aucune interpolation visible).
local function stepColors(colors: { Color3 }): ColorSequence
	local n = math.min(#colors, 10)
	if n == 1 then
		return ColorSequence.new(colors[1])
	end
	local kps = {}
	for i = 1, n do
		local t1 = if i == n then 1 else i / n - 0.001
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / n, colors[i]))
		table.insert(kps, ColorSequenceKeypoint.new(t1, colors[i]))
	end
	return ColorSequence.new(kps)
end

local function stepNumbers(values: { number }): NumberSequence
	local n = math.min(#values, 10)
	if n == 1 then
		return NumberSequence.new(values[1])
	end
	local kps = {}
	for i = 1, n do
		local t1 = if i == n then 1 else i / n - 0.001
		table.insert(kps, NumberSequenceKeypoint.new((i - 1) / n, values[i]))
		table.insert(kps, NumberSequenceKeypoint.new(t1, values[i]))
	end
	return NumberSequence.new(kps)
end

local function scaled(values: { number }, k: number): { number }
	local out = table.create(#values)
	for i, v in values do
		out[i] = v * k
	end
	return out
end

local function emitter(parent: Instance, p): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = p.Texture or PIXEL
	e.Color = p.Color
	e.Size = p.Size
	e.Transparency = p.Transparency or NumberSequence.new(0)
	e.Lifetime = p.Lifetime
	e.Speed = p.Speed or NumberRange.new(0)
	e.SpreadAngle = p.Spread or Vector2.new(180, 180)
	e.Rotation = p.Rotation or NumberRange.new(0)
	e.RotSpeed = NumberRange.new(0)
	e.Drag = p.Drag or 0
	e.Acceleration = p.Acceleration or Vector3.zero
	e.Rate = p.Rate or 0
	e.LockedToPart = p.Locked or false
	e.LightInfluence = 0
	e.LightEmission = p.LightEmission or 0
	e.Brightness = p.Brightness or 1
	e.ZOffset = p.ZOffset or 0
	e.EmissionDirection = p.Direction or Enum.NormalId.Top
	if p.Shape then
		e.Shape = p.Shape
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	end
	e.Parent = parent
	return e
end

-- Ancre invisible locale ; son axe Y (face Top) est aligné sur la normale de la surface.
local function newAnchor(pos: Vector3, normal: Vector3?, life: number, size: Vector3?): Part
	local p = Instance.new("Part")
	p.Name = "FX"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size or Vector3.new(0.2, 0.2, 0.2)
	local up = if normal and normal.Magnitude > 0.5 then normal.Unit else Vector3.yAxis
	local right = up:Cross(Vector3.zAxis)
	if right.Magnitude < 0.01 then
		right = up:Cross(Vector3.xAxis)
	end
	right = right.Unit
	p.CFrame = CFrame.fromMatrix(pos, right, up, right:Cross(up))
	p.Parent = fxFolder
	activeFx += 1
	task.delay(life, function()
		p:Destroy()
		activeFx -= 1
	end)
	return p
end

-- Ancre locale PERSISTANTE (détruite par l'appelant, en général via fadeAway).
local function holderPart(pos: Vector3): Part
	local p = Instance.new("Part")
	p.Name = "Holder"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.new(pos)
	p.Parent = fxFolder
	return p
end

-- Part visible locale (glace, branches, feuilles...)
local function visPart(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = fxFolder
	return p
end

local function tween(inst: Instance, t: number, props, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end

-- DISPARITION DOUCE : rien ne s'efface d'un coup. Images et Parts fondent, les sprites changent de
-- taille (sizeMul > 1 = se dissipe en s'étendant, < 1 = s'effondre), les émetteurs s'arrêtent et
-- laissent finir leurs particules. Puis destruction.
local function fadeAway(root: Instance, dur: number, sizeMul: number?)
	local function each(inst: Instance)
		if inst:IsA("ImageLabel") then
			tween(inst, dur, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		elseif inst:IsA("BillboardGui") then
			if sizeMul then
				local s = inst.Size
				tween(inst, dur, { Size = UDim2.fromScale(s.X.Scale * sizeMul, s.Y.Scale * sizeMul) })
			end
		elseif inst:IsA("BasePart") then
			if inst.Transparency < 1 then
				tween(inst, dur, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		elseif inst:IsA("ParticleEmitter") then
			-- extinction PROGRESSIVE (plus de coupure nette) : le débit baisse, puis l'émetteur s'arrête
			if dur >= 0.8 and inst.Enabled and inst.Rate > 0 then
				tween(inst, dur * 0.7, { Rate = 0 })
				task.delay(dur * 0.7, function()
					inst.Enabled = false
				end)
			else
				inst.Enabled = false
			end
		elseif inst:IsA("Trail") then
			inst.Enabled = false
		elseif inst:IsA("Light") then
			tween(inst, dur, { Brightness = 0 })
		elseif inst:IsA("Beam") then
			tween(inst, dur * 0.6, { Width0 = 0, Width1 = 0 })
		end
	end
	each(root)
	for _, d in root:GetDescendants() do
		each(d)
	end
	task.delay(dur + 0.6, function()
		root:Destroy()
	end)
end
VFX.FadeAway = fadeAway

-- Apparition douce d'un sprite (BillboardGui) : petit -> taille finale avec un léger rebond.
local function popIn(bb: BillboardGui, t: number?)
	local s = bb.Size
	bb.Size = UDim2.fromScale(s.X.Scale * 0.15, s.Y.Scale * 0.15)
	tween(bb, t or 0.3, { Size = s }, Enum.EasingStyle.Back)
end

-- Flash "2 images" : un carré blanc très chaud puis un carré coloré plus grand.
local function flash(att: Attachment, P, size: number, rotation: number)
	local glow = Ambience.Glow()
	local f = emitter(att, {
		Texture = tex(P.Textures.Flash), Color = ColorSequence.new(P.Core), Size = NumberSequence.new(size),
		Lifetime = NumberRange.new(0.05), Locked = true, LightEmission = 1, Brightness = 3 * glow, ZOffset = 2,
		Rotation = NumberRange.new(rotation),
	})
	f:Emit(1)
	task.delay(0.05, function()
		f.Color = ColorSequence.new(P.Mid)
		f.Size = NumberSequence.new(size * 1.4)
		f.Brightness = 1.5 * glow
		f:Emit(1)
	end)
end

-- ── Projectiles ───────────────────────────────────────────────────────────────────────────────────────
-- ── SIGNATURE DES INFUSIONS sur les projectiles ─────────────────────────────────────────────────────────────────────
-- Chaque élément ajoute SA traînée (en plus des étincelles) et SON impact, quel que soit le sort :
--   Feu = fumée qui monte + flamme au sol à l'impact     Glace = givre + éclats qui tombent, gerbe de cristaux
--   Foudre = arc qui crépite autour de l'orbe, éclairs     Toxique = gouttes + vapeur, petit nuage à l'impact
--   Arcane = motes qui spiralent autour, anneau            Acier = éclats métalliques, gerbe d'étincelles
--   Chaos = étincelles erratiques multicolores, pops      Nature = feuilles (voir plus haut)
local SMOKE: Sparks.SparkOpts = { Colors = { Color3.fromHex("7a7a7a"), Color3.fromHex("55555a"), Color3.fromHex("34343a") }, Gravity = -0.25, Drag = 2, Life = NumberRange.new(0.7, 1.3), Size = 0.22 }
local FROST: Sparks.SparkOpts = { Colors = { Color3.new(1, 1, 1), Color3.fromHex("d8f8ff"), Color3.fromHex("8fe3ff") }, Gravity = 0.05, Drag = 3, Life = NumberRange.new(0.3, 0.6), Size = 0.1 }
local ICE_FALL: Sparks.SparkOpts = { Colors = { Color3.fromHex("f0fdff"), Color3.fromHex("8fe3ff"), Color3.fromHex("2f7fd6") }, Gravity = 1.5, Drag = 0.5, Bounce = 0.5, Life = NumberRange.new(0.5, 0.9), Size = 0.14 }
local DRIPS: Sparks.SparkOpts = { Colors = { Color3.fromHex("d6ff78"), Color3.fromHex("7bdc2a"), Color3.fromHex("2f6b1f") }, Gravity = 1.5, Drag = 0.4, Life = NumberRange.new(0.5, 0.9), Size = 0.12 }
local VAPOR: Sparks.SparkOpts = { Colors = { Color3.fromHex("b6ff5a"), Color3.fromHex("4e9a2a") }, Gravity = -0.1, Drag = 2.5, Life = NumberRange.new(0.6, 1.1), Size = 0.16 }
local MOTES: Sparks.SparkOpts = { Colors = { Color3.fromHex("fbe8ff"), Color3.fromHex("c56bff"), Color3.fromHex("7a3fd6") }, Gravity = 0, Drag = 4, Life = NumberRange.new(0.3, 0.6), Size = 0.11 }
local GLINT: Sparks.SparkOpts = { Colors = { Color3.new(1, 1, 1), Color3.fromHex("fff3a1"), Color3.fromHex("ff9a2e") }, Gravity = 1.2, Drag = 1, Bounce = 0.4, Life = NumberRange.new(0.2, 0.4), Size = 0.1 }
local CHAOS_POP: Sparks.SparkOpts = { Colors = Config.Elements.Chaos.Flicker, Gravity = 0.3, Drag = 1.5, Life = NumberRange.new(0.2, 0.5), Size = 0.12, Crackle = 0.4 }

local function perp(v: Vector3): (Vector3, Vector3)
	local f = if v.Magnitude > 1e-3 then v.Unit else Vector3.zAxis
	local s = f:Cross(Vector3.yAxis)
	s = if s.Magnitude < 0.1 then f:Cross(Vector3.xAxis).Unit else s.Unit
	return s, s:Cross(f)
end

-- traînée : Rate par seconde (x racine du Gigantisme), Fn(entry, pos, vel)
-- traînée par élément : définie dans WandShared/Elements/<Élément>/Visuals (V.Trail) — remplie en fin de fichier
local ELEMENT_TRAIL = {}

-- impact : Fn(pos, up, big, glow)
local function shortArcs(pos: Vector3, count: number, reach: number)
	local anchor = holderPart(pos)
	for _ = 1, count do
		local prev = Instance.new("Attachment")
		prev.Parent = anchor
		local dir = rng:NextUnitVector()
		for k = 1, 3 do
			local at = Instance.new("Attachment")
			at.Parent = anchor
			at.Position = dir * reach * k / 3 + rng:NextUnitVector() * reach * 0.15
			local b = Instance.new("Beam")
			b.Attachment0, b.Attachment1 = prev, at
			b.Width0, b.Width1 = 0.16, 0.08
			b.FaceCamera = true
			b.Segments = 1
			b.LightInfluence = 0
			b.LightEmission = 1
			b.Brightness = 4
			b.Color = ColorSequence.new(Color3.fromHex("fffbe0"))
			b.Parent = anchor
			prev = at
		end
	end
	fadeAway(anchor, 0.15)
end

-- impact par élément : défini dans WandShared/Elements/<Élément>/Visuals (V.Impact) — rempli en fin de fichier
local ELEMENT_IMPACT = {}
-- zone au sol de la boule de feu par élément (V.Patch)
local ELEMENT_PATCH = {}

local function attachProjectile(server: BasePart)
	if proxies[server] then
		return
	end
	local element = server:GetAttribute("Element")
	local size = server:GetAttribute("Size") or 0.6
	local recipe = FXRecipes.Get(server:GetAttribute("Card"))
	local P = palette(element)
	local T = P.Textures
	local rot = NumberRange.new(P.Rotation)
	local glow = Ambience.Glow()

	local proxy = Instance.new("Part")
	proxy.Name = "Proj"
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanQuery = false
	proxy.CanTouch = false
	proxy.CastShadow = false
	proxy.Transparency = 1
	proxy.Size = Vector3.one * 0.2
	proxy.CFrame = server.CFrame
	proxy.Parent = fxFolder

	local att = Instance.new("Attachment")
	att.Parent = proxy
	local emitters = {}
	local core: ParticleEmitter? = nil
	if recipe.Sprite then
		-- sprite pixel art animé (ex. disque-scie) porté par le proxy
		Flipbook.Billboard(proxy, recipe.Sprite, recipe.SpriteSize or size * 2.5, { Brightness = 1.2 })
	end
	if recipe.Core ~= false then
	-- Cœur blanc très chaud (seul élément au-dessus du seuil du Bloom) + halo coloré net.
	core = emitter(att, {
		Texture = tex(T.Particle), Color = stepColors(P.Flicker or { P.Core }), Size = NumberSequence.new(size * 0.9),
		Lifetime = NumberRange.new(0.05), Rate = 60, Locked = true, Rotation = rot,
		LightEmission = 1, Brightness = 3 * glow, ZOffset = 1,
	})
	table.insert(emitters, core :: ParticleEmitter)
	table.insert(emitters, emitter(att, {
		Texture = tex(T.Particle), Color = ColorSequence.new(P.Mid), Size = NumberSequence.new(size * 1.9),
		Transparency = NumberSequence.new(0.35), Lifetime = NumberRange.new(0.05), Rate = 60, Locked = true,
		Rotation = rot, LightEmission = 1, Brightness = 1.2 * glow, ZOffset = 0,
	}))
	end
	-- poussière de pixels (complète les étincelles physiques, ne coûte presque rien)
	table.insert(emitters, emitter(att, {
		Texture = tex(T.Particle), Color = stepColors(sparkColors(P)), Size = stepNumbers(scaled({ 0.45, 0.3, 0.15 }, size)),
		Lifetime = NumberRange.new(0.2, 0.35), Rate = 30, Speed = NumberRange.new(0.5, 2), Drag = 3,
		Rotation = rot, LightEmission = 0.6, Brightness = 1.5 * glow,
	}))

	-- Ruban (Trail) : couleurs franches, sans texture = aplat net.
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.35, 0)
	a0.Parent = proxy
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.35, 0)
	a1.Parent = proxy
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.12
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightInfluence = 0
	trail.LightEmission = 0.7
	trail.Brightness = 1.5 * glow
	trail.Color = stepColors({ P.Core, P.Mid, P.Edge })
	trail.Transparency = stepNumbers({ 0, 0, 0.45 })
	trail.WidthScale = stepNumbers({ 1, 0.65, 0.35 })
	local trailTex = tex(T.Trail)
	if trailTex ~= PIXEL then
		trail.Texture = trailTex
	end
	trail.Parent = proxy

	-- Le projectile ÉCLAIRE le décor (lumière budgétée et scintillante)
	local light = LightPool.Attach(proxy, P.Mid, (8 + size * 6) * recipe.Light, 1.8 * recipe.Light, recipe.Flicker)

	-- Options d'étincelles de traînée (pré-calculées : aucune allocation par étincelle)
	local style = sparkStyle(element)
	local rocket = recipe.Trail == "Rocket"
	local sparkOpts: Sparks.SparkOpts = {
		Colors = if rocket then { Color3.fromHex("fff3a1"), Color3.fromHex("ff8f26"), Color3.fromHex("8a2a14") } else sparkColors(P),
		Life = if rocket then NumberRange.new(0.3, 0.6) else NumberRange.new(style.Life.Min * 0.6, style.Life.Max * 0.6),
		Gravity = style.Gravity,
		Drag = style.Drag,
		Bounce = style.Bounce,
		Size = 0.12 + size * 0.05,
	}

	proxies[server] = {
		Proxy = proxy,
		Emitters = emitters,
		Light = light,
		LastPos = proxy.Position,
		SparkAcc = 0,
		Recipe = recipe,
		SparkOpts = sparkOpts,
		-- (Nature : deux fois plus de particules, le sort lâche des feuilles derrière lui)
		SparkRate = recipe.TrailSparks * math.sqrt(math.clamp(server:GetAttribute("Fx") or 1, 0.5, 5)) * (if element == "Nature" then 2 else 1),
		Rocket = rocket,
		Core = core,
		-- son de VOL (boucle) selon la carte et l'élément ; s'arrête en fondu à la disparition
		StopLoop = SoundFX.Travel(proxy, server:GetAttribute("Card"), element, size, server:GetAttribute("Owner") == LOCAL_USER_ID, {
			Traj = server:GetAttribute("Traj"), Homing = server:GetAttribute("Homing"), Heavy = server:GetAttribute("Heavy"),
		}),
		ServerPos = server.Position,
		ServerTime = 0,
		ServerVel = Vector3.zero,
		Blink = recipe.Blink,
		BlinkT = 0,
		BlinkOn = false,
		-- signature de l'infusion
		ElemTrail = ELEMENT_TRAIL[element or ""],
		ElemAcc = 0,
		ElemRate = (ELEMENT_TRAIL[element or ""] and ELEMENT_TRAIL[element].Rate or 0) * math.sqrt(math.clamp(server:GetAttribute("Fx") or 1, 0.5, 5)),
		Size = size,
		Seed = rng:NextNumber(0, 100),
		Arc = nil,
	}
	-- Foudre : un arc électrique crépite en permanence autour de l'orbe
	if element == "Lightning" then
		local a1 = Instance.new("Attachment")
		a1.Parent = proxy
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = att, a1
		beam.Width0, beam.Width1 = 0.14 + size * 0.05, 0.06
		beam.FaceCamera = true
		beam.Segments = 1
		beam.LightInfluence = 0
		beam.LightEmission = 1
		beam.Brightness = 3.5 * glow
		beam.Color = ColorSequence.new(Color3.fromHex("fffbe0"), Color3.fromHex("ffe94f"))
		beam.Parent = proxy
		proxies[server].Arc = { Att = a1, Beam = beam, T = 0 }
	end
end

local function detachProjectile(server: BasePart)
	local entry = proxies[server]
	if not entry then
		return
	end
	proxies[server] = nil
	for _, e in entry.Emitters do
		e.Enabled = false -- les particules déjà émises finissent leur vie
	end
	entry.Light.Release()
	if entry.StopLoop then
		entry.StopLoop()
	end
	task.delay(0.5, function()
		entry.Proxy:Destroy()
	end)
end

local function updateProxies(dt: number)
	local alpha = 1 - math.exp(-SMOOTHING * dt)
	for server, entry in proxies do
		if not server.Parent then
			detachProjectile(server)
			continue
		end
		local proxy = entry.Proxy
		if entry.Frozen then
			if os.clock() - entry.Frozen < 0.15 then
				entry.LastPos = proxy.Position
				continue
			end
			entry.Frozen = nil -- le projectile existe toujours côté serveur : ce n'était pas lui, il reprend
		end
		-- DEAD RECKONING : les mises à jour réseau arrivent par -coups ; au lieu de lisser (ce qui mettait
		-- le projectile affiché 4 à 7 studs EN RETARD sur le vrai), on extrapole depuis la dernière position
		-- reçue avec la vitesse mesurée. L'impact (son + flash) tombe ainsi pile quand le projectile arrive.
		local now = os.clock()
		local sp = server.Position
		if sp ~= entry.ServerPos then
			local gap = now - entry.ServerTime
			if entry.ServerTime > 0 and gap > 1e-3 then
				entry.ServerVel = (sp - entry.ServerPos) / gap
			end
			entry.ServerPos = sp
			entry.ServerTime = now
		end
		local ahead = if entry.ServerTime > 0 then math.min(now - entry.ServerTime, 0.08) else 0
		local target = sp + entry.ServerVel * ahead
		proxy.CFrame = server.CFrame.Rotation + proxy.Position:Lerp(target, alpha)
		local pos = proxy.Position
		local vel = if dt > 0 then (pos - entry.LastPos) / dt else Vector3.zero
		entry.LastPos = pos

		-- cœur clignotant (bombe, mine) : blanc / rouge par paliers de 0.12 s
		if entry.Blink and entry.Core then
			entry.BlinkT += dt
			if entry.BlinkT >= 0.12 then
				entry.BlinkT = 0
				entry.BlinkOn = not entry.BlinkOn
				entry.Core.Color = ColorSequence.new(if entry.BlinkOn then Color3.new(1, 1, 1) else Color3.fromHex("ff3030"))
			end
		end

		-- traînée d'étincelles physiques
		entry.SparkAcc += dt * entry.SparkRate
		if Sparks.Count() >= TRAIL_SPARK_CAP then
			entry.SparkAcc = 0
		end
		-- signature de l'infusion (fumée, givre, gouttes, motes...)
		if entry.ElemTrail and Sparks.Count() < TRAIL_SPARK_CAP then
			entry.ElemAcc += dt * entry.ElemRate
			while entry.ElemAcc >= 1 do
				entry.ElemAcc -= 1
				entry.ElemTrail.Fn(entry, pos, vel)
			end
		end
		local arc = entry.Arc
		if arc then
			arc.T -= dt
			if arc.T <= 0 then
				arc.T = 0.05 -- l'arc saute ~20 fois/s
				arc.Att.Position = rng:NextUnitVector() * rng:NextNumber(0.8, 1.8) * math.max(entry.Size, 0.6)
				arc.Beam.Enabled = rng:NextNumber() > 0.2
			end
		end
		while entry.SparkAcc >= 1 do
			entry.SparkAcc -= 1
			local v
			if entry.Rocket then
				-- fusée : jet vers l'arrière, serré
				v = -vel * 0.25 + rng:NextUnitVector() * 5
			else
				v = vel * 0.12 + rng:NextUnitVector() * rng:NextNumber(2, 7)
			end
			Sparks.Emit(pos, v, entry.SparkOpts)
		end
	end
end

-- ── Effets ponctuels ──────────────────────────────────────────────────────────────────────────────────
-- Feu d'artifice : coquille sphérique multicolore + cœur blanc + crépitements + lumière colorée.
function VFX.Firework(pos: Vector3)
	local pals = FXRecipes.FireworkPalettes
	local a = pals[rng:NextInteger(1, #pals)]
	local b = pals[rng:NextInteger(1, #pals)]
	Sparks.Burst(pos, {
		Count = 140, Palettes = { a, a, b }, Speed = NumberRange.new(24, 32), Shell = true,
		Gravity = 0.35, Drag = 1.6, Bounce = 0.3, Life = NumberRange.new(1.1, 1.7), Size = 0.2, Crackle = 0.35,
	})
	Sparks.Burst(pos, {
		Count = 24, Colors = { Color3.new(1, 1, 1), a[1] }, Speed = NumberRange.new(6, 12),
		Gravity = 0.2, Drag = 2, Life = NumberRange.new(0.25, 0.45), Size = 0.16,
	})
	local glow = Ambience.Glow()
	LightPool.Flash(pos, Color3.new(1, 1, 1), 40, 7 * glow, 0.08, { 1 })
	LightPool.Flash(pos, a[2], 45, 4 * glow, 1.4, { 1, 0.6, 0.35, 0.15 }, 0.45)
	if activeFx <= MAX_ACTIVE_FX then
		local anchor = newAnchor(pos, nil, 0.4)
		local att = Instance.new("Attachment")
		att.Parent = anchor
		flash(att, { Core = Color3.new(1, 1, 1), Mid = a[2], Textures = {} }, 2.2, 45)
	end
end

-- Impact standard : flash + gerbe d'étincelles qui rebondissent + anneau + braises + lumière.
local IMPACT_LEAVES = { Color3.fromHex("a8e85a"), Color3.fromHex("8fd94a"), Color3.fromHex("6fbf3a"), Color3.fromHex("4e9a2a"), Color3.fromHex("d8c04a") }

-- fx = facteur Gigantisme (x1.5 / x3 / x5) : tout l'effet grandit (gerbe, vitesse, flash, lumière, anneau).
function VFX.Impact(pos: Vector3, normal: Vector3?, element: string?, radius: number?, size: number?, cardId: string?, fx: number?)
	local recipe = FXRecipes.Get(cardId)
	if recipe.Impact == "Firework" then
		VFX.Firework(pos)
		return
	end
	local P = palette(element)
	local style = sparkStyle(element)
	local r = radius or 0
	local fxs = math.clamp(fx or 1, 0.5, 5)
	local big = math.sqrt(fxs)
	local scale = if r > 0 then math.clamp(r / 4, 0.8, 12) else math.clamp((size or 0.6) * 1.2, 0.5, 6)
	local glow = Ambience.Glow()
	local up = normal or Vector3.yAxis

	-- 1) étincelles physiques (le cœur du "feu d'artifice")
	Sparks.Burst(pos + up * 0.2, {
		Priority = true, -- toujours complète, même réserve pleine (prend la place des braises secondaires)
		Count = math.clamp(math.floor(16 + r * 7), 16, math.floor(90 * big)),
		Colors = sparkColors(P),
		Speed = NumberRange.new(12 * style.Speed * big, (26 + math.min(r, 12) * 3) * style.Speed * big),
		Normal = normal,
		Gravity = style.Gravity, Drag = style.Drag, Bounce = style.Bounce, Life = style.Life,
		Size = (0.16 + math.min(r, 10) * 0.008) * (1 + (fxs - 1) * 0.3),
		Crackle = if r > 0 then math.max(style.Crackle, 0.12) else style.Crackle,
	})
	-- braises lentes qui restent au sol (explosions seulement)
	if r > 0 then
		Sparks.Burst(pos + up * 0.3, {
			Count = math.clamp(math.floor(10 + r * 3), 10, math.floor(40 * big)),
			Colors = { P.Mid, P.Edge, P.Edge }, Speed = NumberRange.new(4 * big, 11 * big), Normal = normal,
			Gravity = 1, Drag = 0.6, Bounce = 0.25, Life = NumberRange.new(1.5, 3), Size = 0.22 * (1 + (fxs - 1) * 0.25),
		})
	end
	-- VRAIE EXPLOSION (user 2026-11-23) : boule de feu + onde au sol + fumée qui remplit TOUT le rayon (+ colonne si énorme)
	if r > 0 then
		local okX, X = pcall(require, script.Parent.ExplosionFX)
		if okX then
			pcall(X.Spawn, pos, up, r, fxs, P, FXSettings and FXSettings.QualityK and FXSettings.QualityK() or 1)
		end
	end
	-- explosion GÉANTE : seconde onde plus lente (coquille) + panache de braises qui monte
	if r >= 14 or (r > 0 and fxs >= 2.5) then
		task.delay(0.06, function()
			Sparks.Burst(pos + up * 0.5, {
				Count = math.floor(40 * big), Colors = { P.Core, P.Mid, P.Mid, P.Edge }, Shell = true,
				Speed = NumberRange.new(r * 0.9, r * 1.4), Gravity = 0.5, Drag = 1.6, Bounce = 0.3,
				Life = NumberRange.new(0.6, 1.2), Size = 0.24, Crackle = 0.15,
			})
			Sparks.Burst(pos + up * 1, {
				Count = math.floor(18 * big), Colors = { P.Mid, P.Edge }, Direction = up, Spread = 25,
				Speed = NumberRange.new(r * 0.6, r * 1.1), Gravity = 0.35, Drag = 1.2,
				Life = NumberRange.new(1, 1.8), Size = 0.26,
			})
		end)
	end

	-- signature de l'infusion à l'impact (flamme au sol, cristaux, arcs, nuage, étincelles...)
	local elemImpact = ELEMENT_IMPACT[element or ""]
	if elemImpact then
		elemImpact(pos, up, big, glow)
	end

	-- 2) lumière : éclair blanc instantané, puis lueur colorée qui décroît par paliers
	LightPool.Flash(pos + up * 1, P.Core, (8 + math.min(r, 20) * 2) * big, 4 * glow, 0.07, { 1 })
	LightPool.Flash(pos + up * 1.5, P.Mid, (10 + math.min(r, 20) * 3) * big, 2.6 * glow, 0.4 + math.min(r, 30) * 0.03, nil, 0.3)
	if r > 0 then
		-- lueur résiduelle des braises : volontairement faible, sinon les explosions successives
		-- s'additionnent et noient toute la pièce dans une seule couleur
		LightPool.Flash(pos + up * 1, P.Edge, r * 1.6 + 4, 0.7 * glow, 2.5, { 1, 0.7, 0.45, 0.25 }, 0.45)
	end

	if activeFx > MAX_ACTIVE_FX then
		return
	end
	-- 3) flash 2 images + anneau plat dans le plan de la surface
	local anchor = newAnchor(pos, normal, 1.2, Vector3.new(0.4, 0.05, 0.4))
	local att = Instance.new("Attachment")
	att.Parent = anchor
	flash(att, P, scale * 2, P.Rotation)
	local ring = emitter(anchor, {
		Texture = tex(P.Textures.Particle), Color = stepColors({ P.Core, P.Mid }),
		Size = stepNumbers(scaled({ 0.6, 0.4 }, math.sqrt(scale))), Lifetime = NumberRange.new(0.2),
		Speed = NumberRange.new(16 * scale), Drag = 9, Rotation = NumberRange.new(P.Rotation),
		LightEmission = 1, Brightness = 1.5 * glow, Shape = Enum.ParticleEmitterShape.Cylinder,
	})
	ring:Emit(math.clamp(math.floor(14 + r * 2), 14, math.floor(40 * big)))
end

-- Bouche du tir : Beam court qui se rétrécit en 2 paliers + cône d'étincelles + éclair de lumière.
function VFX.Cast(pos: Vector3, dir: Vector3, element: string?)
	local P = palette(element)
	local glow = Ambience.Glow()
	Sparks.Burst(pos, {
		Count = 8, Colors = { P.Core, P.Mid }, Direction = dir, Spread = 22, Speed = NumberRange.new(15, 32),
		Gravity = 0.4, Drag = 3, Life = NumberRange.new(0.12, 0.3), Size = 0.12,
	})
	LightPool.Flash(pos, P.Mid, 12, 3 * glow, 0.12, { 1, 0.4 })
	if activeFx > MAX_ACTIVE_FX then
		return
	end
	local anchor = newAnchor(pos, nil, 0.4)
	local a0 = Instance.new("Attachment")
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Parent = anchor
	a1.WorldPosition = pos + dir * 4
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 1.4
	beam.Width1 = 0.2
	beam.Segments = 1
	beam.FaceCamera = true
	beam.LightInfluence = 0
	beam.LightEmission = 1
	beam.Brightness = 2.5 * glow
	beam.Color = stepColors({ P.Core, P.Mid })
	beam.Transparency = NumberSequence.new(0)
	local beamTex = tex(P.Textures.Beam)
	if beamTex ~= PIXEL then
		beam.Texture = beamTex
	end
	beam.Parent = anchor
	task.delay(0.05, function()
		beam.Width0 = 0.7
		beam.Color = ColorSequence.new(P.Mid)
		beam.Brightness = 1.2 * glow
	end)
	task.delay(0.1, function()
		beam.Enabled = false
	end)
end

-- Libération d'une charge de trigger : anneau d'étincelles + flash + lumière.
function VFX.Trigger(pos: Vector3, element: string?)
	local P = palette(element)
	Sparks.Burst(pos, {
		Count = 14, Colors = { P.Core, P.Mid }, Speed = NumberRange.new(10, 16), Gravity = 0.2, Drag = 3,
		Life = NumberRange.new(0.15, 0.3), Size = 0.14,
	})
	LightPool.Flash(pos, P.Core, 14, 4 * Ambience.Glow(), 0.15, { 1, 0.4 })
	if activeFx > MAX_ACTIVE_FX then
		return
	end
	local anchor = newAnchor(pos, nil, 0.4)
	local att = Instance.new("Attachment")
	att.Parent = anchor
	flash(att, P, 1.6, 45)
end

function VFX.Bounce(pos: Vector3, normal: Vector3?, element: string?, fx: number?)
	local P = palette(element)
	local style = sparkStyle(element)
	local big = math.sqrt(math.clamp(fx or 1, 0.5, 5))
	Sparks.Burst(pos, {
		Count = math.floor(7 * big), Colors = sparkColors(P), Normal = normal, Speed = NumberRange.new(8 * big, 16 * big),
		Gravity = style.Gravity, Drag = style.Drag, Bounce = style.Bounce, Life = NumberRange.new(0.2, 0.45), Size = 0.13 * big,
	})
	LightPool.Flash(pos, P.Mid, 10 * big, 2.5 * Ambience.Glow(), 0.12, { 1, 0.4 })
end

-- Chiffres de dégâts : POP (trop gros puis se pose), taille selon la force du coup, flash blanc puis couleur
-- de l'élément, dérive sur le côté en montant, fondu de sortie. Les ticks (brûlure, poison, saignement)
-- sont plus petits et teintés selon leur type : on distingue d'un coup d'œil le coup et l'effet qui dure.
local DOT_COLORS = {
	Burn = { Color3.fromHex("ffcf6a"), Color3.fromHex("8a1f0a") },
	Poison = { Color3.fromHex("c8ff6a"), Color3.fromHex("1d4a12") },
	Bleed = { Color3.fromHex("ff7070"), Color3.fromHex("4a0a10") },
}
function VFX.DamageNumber(pos: Vector3, amount: number, element: string?, dotKind: string?)
	if activeFx > MAX_ACTIVE_FX then
		return
	end
	local P = palette(element)
	local n = math.max(1, math.floor(amount + 0.5))
	local isDot = DOT_COLORS[dotKind or ""] ~= nil
	local core, edge = P.Core, P.Edge
	if isDot then
		core, edge = DOT_COLORS[dotKind][1], DOT_COLORS[dotKind][2]
	end
	local size = if isDot then 15 else math.floor(math.clamp(18 + n * 0.6, 20, 42))
	local anchor = newAnchor(pos + Vector3.new(rng:NextNumber(-0.8, 0.8), rng:NextNumber(-0.2, 0.4), rng:NextNumber(-0.8, 0.8)), nil, 1.1)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 90)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 160
	bb.Adornee = anchor
	bb.Parent = anchor
	local label = Theme.Label(bb, tostring(n), Theme.Big, Color3.new(1, 1, 1), Enum.TextXAlignment.Center)
	label.Size = UDim2.fromScale(1, 1)
	label.TextSize = math.floor(size * (if isDot then 1.2 else 1.7))
	local stroke = Instance.new("UIStroke")
	stroke.Color = edge
	stroke.Thickness = if isDot then 2 else 3
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = label
	-- pop : gros + blanc pendant une image, puis se pose à sa taille et prend sa couleur
	tween(label, 0.16, { TextSize = size }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(0.05, function()
		label.TextColor3 = core
	end)
	-- monte en dérivant sur le côté, puis s'efface
	local drift = (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(0.4, 1.3)
	local cam = workspace.CurrentCamera.CFrame
	tween(bb, 0.8, { StudsOffsetWorldSpace = cam.RightVector * drift + Vector3.new(0, if isDot then 1.4 else 2.6, 0) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	tween(label, 0.3, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.65)
	tween(stroke, 0.3, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.65)
end

-- ── Tirs instantanés : éclair (zigzag régénéré) et rayon (faisceau qui se rétrécit) ────────────────
local function makeBeam(anchor: Instance, a0: Attachment, a1: Attachment, width: number, color: Color3, brightness: number, transparency: number?): Beam
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = width
	beam.Width1 = width
	beam.Segments = 1
	beam.FaceCamera = true
	beam.LightInfluence = 0
	beam.LightEmission = 1
	beam.Brightness = brightness
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(transparency or 0)
	beam.Parent = anchor
	return beam
end

function VFX.Beam(a: Vector3, b: Vector3, element: string?, width: number?, cardId: string?)
	local P = palette(element)
	local style = sparkStyle(element)
	local recipe = FXRecipes.Get(cardId)
	local glow = Ambience.Glow()
	local w = math.max(0.3, width or 0.5)
	local length = (b - a).Magnitude
	local anchor = newAnchor(a, nil, 0.4)
	local mid = a:Lerp(b, 0.5)

	if recipe.Beam == "Lightning" then
		-- polyligne brisée, re-tirée 3 fois en 0.1 s (= 3 images d'éclair)
		local n = math.clamp(math.floor(length / 4), 3, 14)
		local dir = if length > 0.01 then (b - a) / length else Vector3.zAxis
		local side = dir:Cross(Vector3.yAxis)
		side = if side.Magnitude < 0.1 then dir:Cross(Vector3.xAxis).Unit else side.Unit
		local up = side:Cross(dir).Unit
		local atts = {}
		for i = 0, n do
			local at = Instance.new("Attachment")
			at.Parent = anchor
			atts[i] = at
		end
		for i = 1, n do
			makeBeam(anchor, atts[i - 1], atts[i], w * 0.45, P.Core, 4 * glow)
			makeBeam(anchor, atts[i - 1], atts[i], w * 1.4, P.Mid, 1.6 * glow, 0.25)
		end
		local jitter = math.min(2.2, length * 0.08)
		local function reshape()
			for i = 0, n do
				local p = a:Lerp(b, i / n)
				if i > 0 and i < n then
					p += (side * rng:NextNumber(-1, 1) + up * rng:NextNumber(-1, 1)) * jitter
				end
				atts[i].WorldPosition = p
			end
		end
		reshape()
		task.delay(0.05, reshape)
		task.delay(0.1, reshape)
		task.delay(0.16, function()
			for _, child in anchor:GetChildren() do
				if child:IsA("Beam") then
					child.Enabled = false
				end
			end
		end)
		-- la lumière CLIGNOTE avec l'éclair (paliers 1 / 0.3 / 1 / 0.2)
		LightPool.Flash(mid, P.Mid, math.min(45, 12 + length * 0.4), 5 * glow, 0.18, { 1, 0.3, 1, 0.2 })
	else
		-- rayon : cœur blanc + gaine colorée, qui se rétrécissent en 3 paliers
		local a0 = Instance.new("Attachment")
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Parent = anchor
		a1.WorldPosition = b
		local coreBeam = makeBeam(anchor, a0, a1, w * 0.6, P.Core, 4 * glow)
		local outer = makeBeam(anchor, a0, a1, w * 2, P.Mid, 1.5 * glow, 0.3)
		for step, k in { 0.6, 0.3 } do
			task.delay(step * 0.06, function()
				coreBeam.Width0, coreBeam.Width1 = w * 0.6 * k, w * 0.6 * k
				outer.Width0, outer.Width1 = w * 2 * k, w * 2 * k
			end)
		end
		task.delay(0.18, function()
			coreBeam.Enabled = false
			outer.Enabled = false
		end)
		LightPool.Flash(mid, P.Mid, math.min(45, 10 + length * 0.3), 3.5 * glow, 0.18, { 1, 0.6, 0.3 })
	end
	Sparks.Burst(b, {
		Count = 10, Colors = sparkColors(P), Speed = NumberRange.new(8, 20),
		Gravity = style.Gravity, Drag = style.Drag, Bounce = style.Bounce, Life = style.Life, Size = 0.14,
	})
end

-- ── FAISCEAU MAINTENU (carte Maintien + Rayon / Éclair) ─────────────────────────────────────────────────────────────
-- UN SEUL faisceau persistant par maintien : le serveur envoie origine + point d'arrivée à chaque tick
-- (HoldBeam), le client fait GLISSER les extrémités en douceur entre deux ticks. Rayon : cœur + gaine qui
-- pulsent ; Éclair : polyligne re-brisée en continu. Gerbe d'étincelles au point d'arrivée. Fin = fondu.
local holdBeams: { [number]: any } = {}
local HOLD_BEAM_SEGMENTS = 10

local function newHoldBeam(id: number, msg)
	local P = palette(msg.e)
	local recipe = FXRecipes.Get(if type(msg.c) == "string" then msg.c else nil)
	local glow = Ambience.Glow()
	local from, to = vec(msg.p) :: Vector3, vec(msg.d) :: Vector3
	local w = math.max(0.3, tonumber(msg.w) or 0.5)
	local anchor = holderPart(from)
	local hb = {
		Anchor = anchor, P = P, W = w, Lightning = recipe.Beam == "Lightning",
		From = from, To = to, TargetFrom = from, TargetTo = to, Normal = vec(msg.n),
		Atts = {}, Beams = {}, Last = os.clock(), Shape = 0, Spark = 0, T = 0,
		Light = nil, Sound = nil,
	}
	local n = if hb.Lightning then HOLD_BEAM_SEGMENTS else 1
	for i = 0, n do
		local at = Instance.new("Attachment")
		at.Parent = anchor
		hb.Atts[i] = at
	end
	for i = 1, n do
		table.insert(hb.Beams, { makeBeam(anchor, hb.Atts[i - 1], hb.Atts[i], w * 0.5, P.Core, 4 * glow), w * 0.5 })
		table.insert(hb.Beams, { makeBeam(anchor, hb.Atts[i - 1], hb.Atts[i], w * 1.7, P.Mid, 1.5 * glow, 0.3), w * 1.7 })
	end
	local endPart = holderPart(to)
	hb.EndPart = endPart
	hb.Light = LightPool.Attach(endPart, P.Mid, 16, 2.6 * glow, if hb.Lightning then 0.7 else 0.25)
	hb.Sound = SoundFX.HoldBeam(if hb.Lightning then "Lightning" else "Laser", from:Lerp(to, 0.5), msg.e, if type(msg.c) == "string" then msg.c else nil)
	holdBeams[id] = hb
	return hb
end

local function endHoldBeam(id: number)
	local hb = holdBeams[id]
	if not hb then
		return
	end
	holdBeams[id] = nil
	if hb.Light then
		hb.Light.Release(0.2)
	end
	if hb.Sound then
		hb.Sound.Stop()
	end
	fadeAway(hb.Anchor, 0.18) -- le faisceau s'affine jusqu'à disparaître
	fadeAway(hb.EndPart, 0.2)
end

local function updateHoldBeams(dt: number)
	local alpha = 1 - math.exp(-28 * dt)
	for id, hb in holdBeams do
		if os.clock() - hb.Last > 0.6 then
			endHoldBeam(id) -- sécurité : plus de nouvelles du serveur
			continue
		end
		hb.T += dt
		hb.From = hb.From:Lerp(hb.TargetFrom, alpha)
		hb.To = hb.To:Lerp(hb.TargetTo, alpha)
		local a, b = hb.From, hb.To
		hb.EndPart.CFrame = CFrame.new(b)
		if hb.Sound then
			hb.Sound.Move(a:Lerp(b, 0.5), b)
		end
		local pulse = 1 + 0.12 * math.sin(hb.T * 40) -- le faisceau vibre légèrement
		for _, e in hb.Beams do
			e[1].Width0, e[1].Width1 = e[2] * pulse, e[2] * pulse
		end
		local n = #hb.Atts
		if hb.Lightning then
			hb.Shape -= dt
			if hb.Shape <= 0 then
				hb.Shape = 0.045 -- l'éclair se re-brise ~22 fois/s
				local len = (b - a).Magnitude
				local dir = if len > 0.01 then (b - a) / len else Vector3.zAxis
				local side = dir:Cross(Vector3.yAxis)
				side = if side.Magnitude < 0.1 then dir:Cross(Vector3.xAxis).Unit else side.Unit
				local up = side:Cross(dir).Unit
				local jitter = math.min(2, len * 0.07)
				for i = 0, n do
					local p = a:Lerp(b, i / n)
					if i > 0 and i < n then
						p += (side * rng:NextNumber(-1, 1) + up * rng:NextNumber(-1, 1)) * jitter
					end
					hb.Atts[i].WorldPosition = p
				end
			end
		else
			hb.Atts[0].WorldPosition = a
			hb.Atts[n].WorldPosition = b
		end
		-- gerbe continue au point d'arrivée
		hb.Spark += dt * 30
		while hb.Spark >= 1 do
			hb.Spark -= 1
			local nrm = hb.Normal or (a - b).Unit
			Sparks.Emit(b, (nrm + rng:NextUnitVector() * 0.8).Unit * rng:NextNumber(6, 16), {
				Colors = sparkColors(hb.P), Gravity = 0.8, Drag = 1.5, Bounce = 0.4, Life = NumberRange.new(0.15, 0.4), Size = 0.12,
			})
		end
	end
end

function VFX.HoldBeam(msg)
	local id, a, b = tonumber(msg.g), vec(msg.p), vec(msg.d)
	if not (id and a and b) then
		return
	end
	local hb = holdBeams[id] or newHoldBeam(id, msg)
	hb.TargetFrom, hb.TargetTo, hb.Normal, hb.Last = a, b, vec(msg.n), os.clock()
end

function VFX.HoldBeamEnd(msg)
	local id = tonumber(msg.g)
	if id then
		endHoldBeam(id)
	end
end

-- ── Téléportation / contre-sort ───────────────────────────────────────────────────────────────────────────────
local TELEPORT_COLORS = { Color3.new(1, 1, 1), Color3.fromHex("9ff3ff"), Color3.fromHex("5f8bff"), Color3.fromHex("4a2a9e") }

function VFX.Teleport(from: Vector3, to: Vector3)
	local glow = Ambience.Glow()
	for _, pos in { from, to } do
		local anchor = newAnchor(pos, nil, 1)
		Flipbook.Billboard(anchor, "Teleport", 9, { Brightness = 2 * glow })
		Sparks.Burst(pos, {
			Count = 26, Colors = TELEPORT_COLORS, Speed = NumberRange.new(6, 16), Gravity = -0.2, Drag = 2.5,
			Life = NumberRange.new(0.3, 0.7), Size = 0.16,
		})
		LightPool.Flash(pos, Color3.fromHex("8fb0ff"), 18, 4 * glow, 0.4)
	end
	-- traînée de pixels entre le départ et l'arrivée
	local opts: Sparks.SparkOpts = { Colors = TELEPORT_COLORS, Gravity = 0, Drag = 4, Life = NumberRange.new(0.2, 0.45), Size = 0.12 }
	for i = 1, 24 do
		Sparks.Emit(from:Lerp(to, i / 24), rng:NextUnitVector() * 2, opts)
	end
end

function VFX.Dispel(pos: Vector3, element: string?)
	Sparks.Burst(pos, {
		Count = 12, Colors = { Color3.new(1, 1, 1), Color3.fromHex("a8f4ff"), Color3.fromHex("38b6da") },
		Speed = NumberRange.new(6, 14), Gravity = 0.2, Drag = 3, Life = NumberRange.new(0.15, 0.35), Size = 0.13,
	})
	LightPool.Flash(pos, Color3.fromHex("a8f4ff"), 10, 3 * Ambience.Glow(), 0.12, { 1, 0.4 })
end

-- ── Zones persistantes (marqueurs répliqués dans workspace.WandZoneMarkers) ───────────────────────────────
-- Les visuels d'une zone vivent sur un HOLDER local (pas sur le marqueur serveur) : quand le serveur
-- retire la zone, ils peuvent encore s'estomper / s'effondrer en douceur.
type ZoneVisual = { Items: { Instance }, Holder: Part, Light: any?, Tick: ((number) -> ())?, Acc: number, Kind: string, Radius: number, Element: string?, StopLoop: (() -> ())? }
local zoneVisuals: { [BasePart]: ZoneVisual } = {}

local BH_SPARKS: Sparks.SparkOpts = {
	Colors = { Color3.fromHex("fff0ff"), Color3.fromHex("d98bff"), Color3.fromHex("9442f0"), Color3.fromHex("26093f") },
	Gravity = 0, Drag = 0.4, Life = NumberRange.new(0.6, 1.2), Size = 0.14,
}
local FIRE_SPARKS: Sparks.SparkOpts = {
	Colors = { Color3.fromHex("fff3a1"), Color3.fromHex("ff8f26"), Color3.fromHex("c8301c") },
	Gravity = -0.35, Drag = 1.5, Life = NumberRange.new(0.35, 0.8), Size = 0.15,
}
local GAS_SPARKS: Sparks.SparkOpts = {
	Colors = { Color3.fromHex("d6ff78"), Color3.fromHex("86cf38"), Color3.fromHex("1d5419") },
	Gravity = -0.08, Drag = 2, Life = NumberRange.new(0.8, 1.6), Size = 0.18,
}

-- RÉPARTITION ÉQUITABLE des effets des zones au sol (Patch : traînées TF, boules de feu...) :
--   • chaque zone demande des effets proportionnels à SA surface (petites zones de traînée = peu)
--   • au-delà de ZONE_FULL zones actives, TOUTES partagent le même budget (part égale) : quel que soit le
--     nombre de rayons / de traînées, aucun n'est délaissé (pas de « premier arrivé, premier servi »)
local ZONE_FULL = 10
local ZONE_MIN_SHARE = 0.12
local patchCount = 0
local function zoneShare(): number
	return math.clamp(ZONE_FULL * FXSettings.QualityK() / math.max(1, patchCount), ZONE_MIN_SHARE, 1)
end

-- émet `rate` étincelles par seconde via fn(i) (accumulateur pour un débit stable)
local function emitRate(vis: ZoneVisual, dt: number, rate: number, fn: () -> ())
	if vis.IsPatch then
		rate *= (vis.AreaK or 1) * zoneShare()
	end
	vis.Acc += dt * rate
	while vis.Acc >= 1 do
		vis.Acc -= 1
		fn()
	end
end

local function attachZone(marker: BasePart)
	if zoneVisuals[marker] then
		return
	end
	local kind = marker:GetAttribute("Kind")
	local radius = marker:GetAttribute("Radius") or 4
	local duration = marker:GetAttribute("Duration") or 1
	local element = marker:GetAttribute("Element")
	local P = palette(element)
	local glow = Ambience.Glow()
	local holder = holderPart(marker.Position)
	local vis: ZoneVisual = { Items = {}, Holder = holder, Light = nil, Tick = nil, Acc = 0, Kind = kind, Radius = radius, Element = element, StopLoop = nil }
	-- sons de la zone : apparition -> boucle / bip -> disparition (voir SoundFX.ZONE)
	vis.StopLoop = SoundFX.Zone(marker, kind)

	if kind == "BlackHole" then
		popIn(Flipbook.Billboard(holder, "Vortex", radius * 0.9, { Brightness = 1.4 * glow }), 0.45)
		Sparks.AddAttractor(marker.Position, 240, radius * 1.6, 180, duration)
		vis.Light = LightPool.Attach(holder, P.Mid, radius * 2, 2.2 * glow, 0.5)
		vis.Tick = function(dt)
			-- étincelles aspirées en spirale depuis le bord
			emitRate(vis, dt, 45, function()
				local a = rng:NextNumber(0, math.pi * 2)
				local r = radius * rng:NextNumber(0.9, 1.3)
				local p = marker.Position + Vector3.new(math.cos(a) * r, rng:NextNumber(-2, 3), math.sin(a) * r)
				Sparks.Emit(p, Vector3.new(-math.sin(a), 0, math.cos(a)) * 14, BH_SPARKS)
			end)
		end
	elseif kind == "Gas" then
		for i = 1, 4 do
			local off = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 0.5), rng:NextNumber(-1, 1)) * radius * 0.4
			local puff = holderPart(marker.Position + off)
			popIn(Flipbook.Billboard(puff, "Gas", radius * 1.15, { Brightness = 1, Transparency = 0.1, Fps = 5 + i }), 0.5 + i * 0.08)
			table.insert(vis.Items, puff)
		end
		vis.Light = LightPool.Attach(holder, P.Mid, radius * 1.8, 1 * glow, 0.3)
		vis.Tick = function(dt)
			emitRate(vis, dt, 8, function()
				local p = marker.Position + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-1, 1)) * radius * 0.7
				Sparks.Emit(p, Vector3.new(0, rng:NextNumber(1, 3), 0), GAS_SPARKS)
			end)
		end
	elseif kind == "Patch" then
		-- ZONE AU SOL de la boule de feu : chaque infusion a sa matière posée sur le sol
		local base = marker.Position
		-- ACCROCHAGE À LA SURFACE : chaque morceau de matière est PROJETÉ sur la vraie géométrie (rayon le long
		-- de la normale). Au-delà du bord d'un mur / d'une corniche il n'y a rien : le morceau n'est PAS posé
		-- (la matière ne flotte jamais dans le vide).
		local snapParams = RaycastParams.new()
		snapParams.FilterType = Enum.RaycastFilterType.Exclude
		local ignore = { fxFolder }
		for _, name in { "WandProjectiles", "WandZoneMarkers", "WandDummies", "WandSparks_Local", "WandFX_Local" } do
			local f = workspace:FindFirstChild(name)
			if f then
				table.insert(ignore, f)
			end
		end
		for _, plr in game:GetService("Players"):GetPlayers() do
			if plr.Character then
				table.insert(ignore, plr.Character)
			end
		end
		snapParams.FilterDescendantsInstances = ignore
		local function snap(p: Vector3, nrm: Vector3): (Vector3?, Vector3?)
			local hit = workspace:Raycast(p + nrm * 1.5, -nrm * 3.2, snapParams)
			if hit and hit.Normal:Dot(nrm) > 0.5 then
				return hit.Position, hit.Normal
			end
			return nil, nil
		end
		-- point aléatoire de la zone, sur la surface réelle de normale `nrm` (défaut : le sol) ; nil si introuvable
		local function surfacePoint(k: number?, nrm: Vector3?): (Vector3?, Vector3?)
			nrm = nrm or Vector3.yAxis
			local t1 = if math.abs(nrm.Y) < 0.9 then nrm:Cross(Vector3.yAxis).Unit else nrm:Cross(Vector3.xAxis).Unit
			local t2 = nrm:Cross(t1).Unit
			for _ = 1, 6 do
				local a = rng:NextNumber(0, math.pi * 2)
				local r = radius * math.sqrt(rng:NextNumber()) * (k or 0.9)
				local p, n = snap(base + (t1 * math.cos(a) + t2 * math.sin(a)) * r, nrm)
				if p then
					return p, n
				end
			end
			return nil, nil
		end
		-- ÉVENTAIL : point sur N'IMPORTE QUELLE surface autour de l'impact (sol ET mur dans un coin...) — des rayons
		-- partent du point d'impact décollé, dans toutes les directions tournées vers les surfaces ; on garde un
		-- point touché dans le rayon de la zone. La matière suit ainsi la forme réelle (coin, marche, pente).
		local function spreadPoint(k: number?, nrm: Vector3?): (Vector3?, Vector3?)
			-- point tiré UNIFORMÉMENT dans le disque de la zone, puis posé sur la surface (pas de grappe au centre).
			-- Un essai sur deux dans le plan de la surface touchée (mur), l'autre à l'horizontale (sol) :
			-- au pied d'un mur, les deux sont couverts. Jamais à travers un mur (ligne de vue depuis l'impact).
			nrm = nrm or Vector3.yAxis
			local origin = base + nrm * 0.9
			local reach = radius * (k or 0.9)
			local flip = rng:NextInteger(0, 1)
			for t = 1, 10 do
				local toFloor = (t + flip) % 2 == 0
				local n = if toFloor then Vector3.yAxis else nrm
				local t1 = if math.abs(n.Y) < 0.9 then n:Cross(Vector3.yAxis).Unit else n:Cross(Vector3.xAxis).Unit
				local t2 = n:Cross(t1).Unit
				local a = rng:NextNumber(0, math.pi * 2)
				local rr = reach * math.sqrt(rng:NextNumber())
				local planar = (t1 * math.cos(a) + t2 * math.sin(a)) * rr
				local center = if toFloor then Vector3.new(origin.X, base.Y, origin.Z) else base
				local from = center + planar + n * (if toFloor then 2.5 else 1.5)
				local block = workspace:Raycast(origin, from - origin, snapParams)
				if not block then
					local hit = workspace:Raycast(from, -n * (if toFloor then 9 else 3.2), snapParams)
					if hit and hit.Normal:Dot(n) > 0.6 then
						return hit.Position, hit.Normal
					end
				end
			end
			return nil, nil
		end
		-- version « toujours une position » (au pire le centre, qui est sur la surface touchée)
		local function diskPoint(k: number?): Vector3
			local p = surfacePoint(k)
			return p or base
		end
		local spark = function(colors, grav, life, size)
			return { Colors = colors, Gravity = grav, Drag = 2, Life = life, Size = size }
		end
		local el = element or "Fire"
		-- visuels de la zone : définis dans WandShared/Elements/<Élément>/Visuals (V.Patch)
		local patchFn = ELEMENT_PATCH[element or "Fire"]
		-- part équitable de cette zone : surface (traînées) x partage global
		patchCount += 1
		vis.IsPatch = true
		vis.AreaK = if marker:GetAttribute("Trail") then math.clamp((radius / 4.5) ^ 2, 0.2, 1) else 1
		local fx = vis.AreaK * zoneShare()
		if patchFn then
			patchFn({ vis = vis, holder = holder, radius = radius, P = P, glow = glow, base = base, diskPoint = diskPoint, surfacePoint = surfacePoint, spreadPoint = spreadPoint, snap = snap, spark = spark, marker = marker, element = element,
				fx = fx,
				-- nombre d'objets à créer pour CETTE zone (au moins 1 : une zone n'est jamais vide)
				n = function(count: number): number
					return math.max(1, math.floor(count * fx + 0.5))
				end,
				-- facteur courant (évolue avec le nombre de zones) pour les émissions continues hors emitRate
				fxLive = function(): number
					return (vis.AreaK or 1) * zoneShare()
				end })
		end
	elseif kind == "FireRing" then
		local plate = Flipbook.Ground(marker.Position, "FireRing", radius * 2.2, { Brightness = 1.6 * glow }, fxFolder)
		table.insert(vis.Items, plate)
		vis.Light = LightPool.Attach(holder, P.Mid, radius * 2.4, 2.5 * glow, 0.5)
		vis.Tick = function(dt)
			-- braises qui montent du cercle
			emitRate(vis, dt, 32, function()
				local a = rng:NextNumber(0, math.pi * 2)
				local p = marker.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.78 + Vector3.new(0, 0.3, 0)
				Sparks.Emit(p, Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(5, 12), rng:NextNumber(-1, 1)), FIRE_SPARKS)
			end)
		end
	elseif kind == "Mine" then
		popIn(Flipbook.Billboard(holder, "Mine", 1.6, { Brightness = 1.2 }), 0.2)
		vis.Light = LightPool.Attach(holder, Color3.fromRGB(255, 48, 48), 6, 1.2, 0.8)
	elseif kind == "Trap" then
		-- PIÈGE : paillettes qui s'échappent doucement du sol, couleur = élément (gris si neutre)
		local glitter: Sparks.SparkOpts = {
			Colors = { P.Core, P.Mid, P.Mid, P.Edge }, Gravity = -0.04, Drag = 2.4, Life = NumberRange.new(0.6, 1.3), Size = 0.1,
		}
		vis.Light = LightPool.Attach(holder, P.Mid, 5 + radius * 0.6, 0.35 * glow, 0.6)
		vis.Tick = function(dt)
			emitRate(vis, dt, 10 + radius * 1.5, function()
				local a = rng:NextNumber(0, math.pi * 2)
				local r = radius * math.sqrt(rng:NextNumber()) * 0.7
				local p = holder.Position + Vector3.new(math.cos(a) * r, 0.05, math.sin(a) * r)
				Sparks.Emit(p, Vector3.new(rng:NextNumber(-0.4, 0.4), rng:NextNumber(1.2, 3), rng:NextNumber(-0.4, 0.4)), glitter)
			end)
		end
	elseif kind == "Shield" then
		-- assez transparent pour qu'on voie toujours le joueur à l'intérieur
		popIn(Flipbook.Billboard(holder, "Shield", radius * 1.6, { Brightness = 1.2 * glow, Transparency = 0.5 }), 0.25)
		vis.Light = LightPool.Attach(holder, Color3.fromHex("38b6da"), radius * 2, 1.2 * glow, 0.2)
	elseif kind == "IceWall" then
		-- le mur (vraies Parts serveur) n'émet pas de lumière : on lui donne une lueur froide + des éclats de givre
		vis.Light = LightPool.Attach(holder, Color3.fromHex("8fe3ff"), 16, 1.4 * glow, 0.15)
		local frost: Sparks.SparkOpts = {
			Colors = { Color3.new(1, 1, 1), Color3.fromHex("8fe3ff"), Color3.fromHex("2f7fd6") },
			Gravity = 0.3, Drag = 2, Life = NumberRange.new(0.4, 0.9), Size = 0.13,
		}
		vis.Tick = function(dt)
			emitRate(vis, dt, 10, function()
				local p = marker.Position + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(0, 7), rng:NextNumber(-6, 6))
				Sparks.Emit(p, Vector3.new(0, rng:NextNumber(0.5, 2), 0), frost)
			end)
		end
	elseif kind == "Dispel" then
		Sparks.Burst(marker.Position, {
			Count = 30, Colors = { Color3.new(1, 1, 1), Color3.fromHex("a8f4ff"), Color3.fromHex("38b6da") },
			Speed = NumberRange.new(radius * 2, radius * 3), Shell = true, Gravity = 0, Drag = 4,
			Life = NumberRange.new(0.2, 0.35), Size = 0.14,
		})
		LightPool.Flash(marker.Position, Color3.fromHex("a8f4ff"), radius * 2.5, 4 * glow, 0.2, { 1, 0.4 })
	end
	zoneVisuals[marker] = vis
end

local function detachZone(marker: BasePart)
	local vis = zoneVisuals[marker]
	if not vis then
		return
	end
	zoneVisuals[marker] = nil
	if vis.IsPatch then
		patchCount = math.max(0, patchCount - 1)
	end
	vis.Dead = true -- les créations DIFFÉRÉES (task.delay) d'un visuel de zone doivent tester vis.Dead
	if vis.StopLoop then
		vis.StopLoop()
	end
	local kind = vis.Kind
	local pos = vis.Holder.Position
	if kind == "BlackHole" then
		-- le vortex s'EFFONDRE sur lui-même (0.3 s), puis gerbe vers l'extérieur + éclair blanc
		if vis.Light then
			vis.Light.Release(0.3)
		end
		fadeAway(vis.Holder, 0.3, 0.05)
		task.delay(0.28, function()
			Sparks.Burst(pos, { Count = 60, Colors = BH_SPARKS.Colors, Speed = NumberRange.new(20, 34), Shell = true, Gravity = 0.2, Drag = 2, Life = NumberRange.new(0.4, 0.8), Size = 0.18 })
			LightPool.Flash(pos, Color3.new(1, 1, 1), vis.Radius * 3, 6 * Ambience.Glow(), 0.1, { 1 })
		end)
	elseif kind == "Gas" then
		-- le nuage se DISSIPE : il s'étend en s'estompant
		if vis.Light then
			vis.Light.Release(1)
		end
		for i, puff in vis.Items do
			task.delay((i - 1) * 0.12, fadeAway, puff, 1.1, 1.4)
		end
		fadeAway(vis.Holder, 1.2)
	elseif kind == "Shield" then
		if vis.Light then
			vis.Light.Release(0.3)
		end
		fadeAway(vis.Holder, 0.3, 1.25)
	elseif vis.IsPatch then
		-- zone au sol (traînée, flaque) remplacée ou expirée : FONDU long, rien ne disparaît d'un coup (user)
		if vis.Light then
			vis.Light.Release(1.2)
		end
		for i, item in vis.Items do
			task.delay(math.min((i - 1) * 0.03, 0.4), fadeAway, item, 1.2)
		end
		fadeAway(vis.Holder, 1.3)
	else
		if vis.Light then
			vis.Light.Release(0.5)
		end
		for _, item in vis.Items do
			fadeAway(item, 0.5)
		end
		fadeAway(vis.Holder, if kind == "Mine" then 0.15 else 0.5, if kind == "Mine" then 0.4 else nil)
	end
end

local function updateZones(dt: number)
	for marker, vis in zoneVisuals do
		if not marker.Parent then
			detachZone(marker)
		else
			if (vis.Holder.Position - marker.Position).Magnitude > 0.01 then
				vis.Holder.CFrame = CFrame.new(marker.Position) -- zones mobiles (bouclier)
			end
			if vis.Tick then
				vis.Tick(dt)
			end
		end
	end
end

-- ── Mur de glace : poussée depuis le sol, puis éclatement ──────────────────────────────────────────────────────────────
-- Les blocs serveur (workspace.WandIceWalls) sont la collision, invisibles. Chaque bloc est dessiné ici :
-- corps givré + veine lumineuse + crête blanche. Les colonnes jaillissent du sol du centre vers les bords
-- (attribut Order), avec un léger dépassement (Back) ; à la fin elles se fendent, s'enfoncent et fondent.
local ICE_COLORS = { Color3.new(1, 1, 1), Color3.fromHex("bff2ff"), Color3.fromHex("8fe3ff"), Color3.fromHex("2f7fd6") }
local iceBlocks: { [BasePart]: any } = {}

local function attachIce(block: BasePart)
	if iceBlocks[block] or not block:IsA("BasePart") then
		return
	end
	local cf, size = block.CFrame, block.Size
	local order = block:GetAttribute("Order") or 0
	local scale = block:GetAttribute("Scale") or 1
	local parts = {
		{ visPart(size, cf, Color3.fromHex("8fe3ff"), Enum.Material.SmoothPlastic, 0.22), cf },
		{ visPart(Vector3.new(size.X * 0.4, size.Y * 0.82, size.Z * 0.3), cf, Color3.fromHex("bff2ff"), Enum.Material.Neon, 0.78), cf },
	}
	local capCf = cf * CFrame.new(0, size.Y / 2, 0)
	table.insert(parts, { visPart(Vector3.new(size.X * 1.03, 0.2 * math.sqrt(scale), size.Z * 1.03), capCf, Color3.fromHex("bff2ff"), Enum.Material.Neon, 0.55), capCf })
	local sink = Vector3.new(0, size.Y + 0.4, 0)
	local delay = order * 0.05
	for _, e in parts do
		e[1].CFrame = e[2] - sink
		tween(e[1], 0.32, { CFrame = e[2] }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delay)
	end
	local foot = cf.Position - Vector3.new(0, size.Y / 2, 0)
	task.delay(delay, function()
		Sparks.Burst(foot + Vector3.new(0, 0.4, 0), {
			Count = math.floor(10 * math.sqrt(scale)), Colors = ICE_COLORS, Normal = Vector3.yAxis,
			Speed = NumberRange.new(6, 14), Gravity = 1.4, Drag = 0.8, Bounce = 0.5, Life = NumberRange.new(0.4, 0.9), Size = 0.15,
		})
		SoundFX.Play("Ice.Rise", foot)
	end)
	iceBlocks[block] = { Parts = parts, CF = cf, Size = size, Order = order, Scale = scale }
end

local function detachIce(block: BasePart)
	local v = iceBlocks[block]
	if not v then
		return
	end
	iceBlocks[block] = nil
	task.delay(v.Order * 0.045, function()
		local pos = v.CF.Position
		Sparks.Burst(pos, {
			Count = math.floor(16 * math.sqrt(v.Scale)), Colors = ICE_COLORS, Speed = NumberRange.new(8, 18),
			Gravity = 1.5, Drag = 0.6, Bounce = 0.55, Life = NumberRange.new(0.5, 1.2), Size = 0.18,
		})
		LightPool.Flash(pos, Color3.fromHex("bff2ff"), 10, 1.5 * Ambience.Glow(), 0.3, { 1, 0.5, 0.2 })
		SoundFX.Play("Ice.Shatter", pos)
		for _, e in v.Parts do
			local p = e[1]
			tween(p, 0.5, { CFrame = p.CFrame - Vector3.new(0, v.Size.Y * 0.35, 0), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.55, p.Destroy, p)
		end
	end)
end

-- ── États des cibles : en feu (flammes animées), empoisonnées (bulles), qui saignent (gouttes) ──────────────
-- Le serveur pose des attributs booléens sur le Humanoid (Burning / Poisoned / Bleeding).
local SMOKE_SPARKS: Sparks.SparkOpts = {
	Colors = { Color3.fromHex("6b6b6b"), Color3.fromHex("3d3d3d") },
	Gravity = -0.2, Drag = 2, Life = NumberRange.new(0.5, 1), Size = 0.2,
}
-- ÉTATS des cibles : chaque élément déclare le sien dans WandShared/Elements/<Élément>/Visuals (V.Status =
-- { Kind, Rate, Opts, Vel(), Start(s, root)?, Stop(s)? }) ; chargé en bas de ce module dans STATUS_DEF.
-- Seul le SAIGNEMENT (physique, sans élément) est défini ici.
local STATUS_DEF: { [string]: any } = {
	Bleeding = {
		Kind = "Bleeding", Rate = 8,
		Opts = { Colors = { Color3.fromHex("ff4a4a"), Color3.fromHex("b0141e"), Color3.fromHex("5a0a10") },
			Gravity = 1.6, Drag = 0.5, Bounce = 0.1, Life = NumberRange.new(0.4, 0.8), Size = 0.13 },
		Vel = function() return Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(0, 3), rng:NextNumber(-2, 2)) end,
	},
}
local statusVis: { [Humanoid]: { [string]: any } } = {}
local statusPoll = 0

local function startStatus(hum: Humanoid, root: BasePart, kind: string)
	local def = STATUS_DEF[kind] or STATUS_DEF.Bleeding
	local s = { Root = root, Acc = 0, Holder = nil, Light = nil, StopLoop = nil, Rate = def.Rate or 8, Opts = def.Opts, Def = def }
	if def.Start then
		def.Start(s, root) -- flammes / arcs / lumière : remplit s.Holder et s.Light
		if not s.Holder then
			warn("[Wand] l'état " .. kind .. " n'a pas enregistré s.Holder : ses visuels ne seront jamais effacés")
		end
	end
	-- son de l'état (début / boucle / fin) : sur son visuel s'il en a un, SINON sur la cible elle-même
	-- (avant : un état sans visuel propre, comme le poison, restait muet)
	s.StopLoop = SoundFX.Status(s.Holder or root, kind)
	return s
end

local function stopStatus(s, kind: string)
	if s.Holder then
		fadeAway(s.Holder, s.Def.FadeTime or 0.45, 0.5) -- les flammes / arcs se rétractent et s'éteignent
		if s.Def.Stop then
			s.Def.Stop(s) -- ex. feu : bouffée de fumée
		end
	end
	if s.Light then
		s.Light.Release(0.45)
	end
	if s.StopLoop then
		s.StopLoop()
	end
end

local function statusCandidates(): { Model }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local dummies = workspace:FindFirstChild("WandDummies")
	if dummies then
		for _, m in dummies:GetChildren() do
			if m:IsA("Model") then
				table.insert(list, m)
			end
		end
	end
	return list
end

local function updateStatus(dt: number)
	statusPoll -= dt
	if statusPoll <= 0 then
		statusPoll = 0.12
		local seen = {}
		for _, model in statusCandidates() do
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart")
			if hum and root then
				seen[hum] = true
				local map = statusVis[hum]
				for kind in STATUS_DEF do -- tous les états déclarés (brûlure, poison, choc, gel, racines...)
					local on = hum:GetAttribute(kind) == true and hum.Health > 0
					if on and not (map and map[kind]) then
						map = map or {}
						statusVis[hum] = map
						map[kind] = startStatus(hum, root, kind)
					elseif not on and map and map[kind] then
						stopStatus(map[kind], kind)
						map[kind] = nil
					end
				end
			end
		end
		for hum, map in statusVis do
			if not seen[hum] then
				for kind, s in map do
					stopStatus(s, kind)
				end
				statusVis[hum] = nil
			end
		end
	end
	for _, map in statusVis do
		for _, s in map do
			local root = s.Root
			if root.Parent then
				if s.Holder and not s.Def.Static then
					s.Holder.CFrame = CFrame.new(root.Position)
				end
				s.Acc += dt * s.Rate
				while s.Acc >= 1 do
					s.Acc -= 1
					local p = root.Position + Vector3.new(rng:NextNumber(-0.9, 0.9), rng:NextNumber(-2, 1.4), rng:NextNumber(-0.9, 0.9))
					local v = if s.Def.Vel then s.Def.Vel() else Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(3, 8), rng:NextNumber(-1, 1))
					Sparks.Emit(p, v, s.Opts)
				end
			end
		end
	end
end

-- ── Sorts PROCÉDURAUX : branches (GrowthService) ────────────────────────────────────────────────────────────
-- Chaque segment reçu POUSSE (il s'allonge depuis son point de départ) ; l'apparence vient de
-- FXRecipes.Branch[élément] (écorce, veine lumineuse, feuilles, flammes). À la fin, la branche flétrit
-- des pointes vers la base (feu : se carbonise puis tombe en cendres ; glace : se brise).
local MAX_BRANCH_PARTS = 2400 -- sécurité (écorce + sève + feuilles) ; le vrai plafond est en segments (Config)
-- faces LONGUES d'un segment (orienté lookAt : sa longueur suit l'axe Z)
local BARK_FACES = { Enum.NormalId.Top, Enum.NormalId.Bottom, Enum.NormalId.Left, Enum.NormalId.Right }

-- Effets PERMANENTS d'un arbre selon son infusion (émis le long des branches tant qu'il vit)
--   Vel(rng) -> vitesse initiale ; Rate = par seconde et par segment (borné par Max)
-- feuilles : légères (freinage fort, gravité faible = elles planent), variété de verts + quelques jaunes
-- (définies dans WandShared/Elements/<Élément>/Visuals : V.Ambient = { Opts, Rate, Max, Below?, Vel(), Gust?, GustCount? })
local AMBIENT: { [string]: any } = {}
local MAX_BRANCH_FLAMES = 22
local growthVis: { [number]: any } = {}

local function branchStyle(element: string?)
	return FXRecipes.Branch[element or ""] or FXRecipes.Branch.Nature
end

local function newGrowth(id: number, pos: Vector3, element: string?, scale: number)
	local g = { Id = id, Parts = {}, Leaves = {}, Element = element, Scale = scale, Flames = 0, Origin = pos, Holder = holderPart(pos), Acc = 0, Segs = {} }
	growthVis[id] = g
	return g
end

local function growStart(msg)
	local id, pos = tonumber(msg.g), vec(msg.p)
	if not (id and pos) then
		return
	end
	local z = math.clamp(tonumber(msg.z) or 1, 0.5, 5)
	local g = growthVis[id] or newGrowth(id, pos, msg.e, z)
	local P = palette(msg.e)
	local glow = Ambience.Glow()
	local fire = msg.e == "Fire"
	g.Light = LightPool.Attach(g.Holder, P.Mid, 12 * math.sqrt(z), (if fire then 2.2 else 0.9) * glow, if fire then 0.5 else 0.15)
	Sparks.Burst(pos, {
		Count = math.floor(18 * math.sqrt(z)), Colors = sparkColors(P), Normal = vec(msg.n), Speed = NumberRange.new(6, 14),
		Gravity = 0.6, Drag = 2, Life = NumberRange.new(0.4, 0.9), Size = 0.15,
	})
	LightPool.Flash(pos, P.Core, 14, 3 * glow, 0.25, { 1, 0.5, 0.2 })
end

-- ÉCORCE DE BRANCHE (Ramure) : pièce de l'élément + texture d'écorce pixel art non éclairée sur les 4 faces longues.
-- Partagée : les branches de la Ramure ET les racines qui enserrent une cible (Nature.Visuals, via api.BarkPart).
local function barkPart(startCf: CFrame, endCf: CFrame, w: number, full: number, element: string?, grow: number): BasePart
	local st = branchStyle(element)
	local barkHex = st.Bark[rng:NextInteger(1, #st.Bark)]
	local material = if st.Material then Enum.Material[st.Material] else Enum.Material.Neon
	local bark = visPart(Vector3.new(w, w, 0.05), startCf, Color3.fromHex(barkHex), material, st.Transparency or 0)
	tween(bark, grow, { Size = Vector3.new(w, w, full), CFrame = endCf }, Enum.EasingStyle.Linear)
	-- écorce TEXTURÉE : SurfaceGui non éclairé sur les 4 faces longues (lisible dans le noir, pixels nets)
	if FXRecipes.BarkTexture and w >= 0.3 then
		for _, face in BARK_FACES do
			local sg = Instance.new("SurfaceGui")
			sg.Face = face
			sg.LightInfluence = 0
			sg.Brightness = 1
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 16 -- tuile de 32 px = 2 studs
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Size = UDim2.fromScale(1, 1)
			-- faces Haut/Bas : l'axe X de l'image est en travers du tronc -> variante tournée de 90°
			img.Image = if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then FXRecipes.BarkTextureV else FXRecipes.BarkTexture
			img.ScaleType = Enum.ScaleType.Tile
			img.TileSize = UDim2.fromOffset(32, 32)
			img.ResampleMode = Enum.ResamplerMode.Pixelated
			img.ImageColor3 = Color3.fromHex(st.Tint or "ffffff")
			img.ImageTransparency = st.Transparency or 0
			img.Parent = sg
			sg.Parent = bark
		end
	end
	return bark
end

local function growSegment(msg)
	local id, a, b = tonumber(msg.g), vec(msg.p), vec(msg.d)
	if not (id and a and b) then
		return
	end
	local g = growthVis[id] or newGrowth(id, a, msg.e, 1)
	-- même plafond que le SERVEUR (en segments) : chaque branche qui existe est dessinée
	g.SegCount = (g.SegCount or 0) + 1
	if g.SegCount > (Config.Limits.MaxGrowthSegmentsHard or 900) or #g.Parts >= MAX_BRANCH_PARTS then
		return
	end
	local len = (b - a).Magnitude
	if len < 0.05 then
		return
	end
	local w = math.clamp(tonumber(msg.w) or 0.4, 0.08, 4)
	local n = vec(msg.n) or Vector3.yAxis
	local st = branchStyle(g.Element)
	local P = palette(g.Element)
	-- durée de pousse = rythme RÉEL du tronc côté serveur (irrégulier) -> croissance continue, jamais saccadée
	local grow = math.clamp(tonumber(msg.t) or 0.16, 0.06, 0.4)
	local startCf = CFrame.lookAt(a, b)
	local endCf = CFrame.lookAt(a:Lerp(b, 0.5), b)
	local full = len + w * 0.7 -- recouvrement : les jointures restent pleines

	local segList = {} -- parts de CE segment (cassable seul)
	local bark = barkPart(startCf, endCf, w, full, g.Element, grow)
	table.insert(g.Parts, bark)
	g.Barks = g.Barks or {}
	table.insert(g.Barks, bark)
	table.insert(segList, bark)
	if st.Core and w >= 0.22 then -- (sève : inutile sur les brindilles les plus fines, économise des pièces)
		local core = visPart(Vector3.new(w * 0.42, w * 0.42, 0.05), startCf, Color3.fromHex(st.Core), Enum.Material.Neon, st.CoreTransparency or 0.3)
		-- la veine dépasse légèrement de l'écorce côté extérieur : visible sans transparence
		tween(core, grow, { Size = Vector3.new(w * 0.42, w * 1.06, full * 0.96), CFrame = endCf }, Enum.EasingStyle.Linear)
		table.insert(g.Parts, core)
		g.Cores = g.Cores or {}
		table.insert(g.Cores, core)
		table.insert(segList, core)
		if st.Flicker then
			table.insert(g.Segs, core)
		end
	end
	-- feuilles / bourgeons : petits cubes qui éclosent juste derrière la pointe
	if st.Leaf and rng:NextNumber() < (st.LeafChance or 0) then
		local side = n:Cross((b - a).Unit)
		side = if side.Magnitude > 0.05 then side.Unit else Vector3.xAxis
		local s = 0.3 * math.sqrt(g.Scale) * rng:NextNumber(0.8, 1.3)
		local at = b + side * (w * 0.5 + s * 0.4) * (if rng:NextNumber() < 0.5 then -1 else 1) + n * s * 0.4
		local cf = CFrame.new(at) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		local leaf = visPart(Vector3.one * 0.02, cf, Color3.fromHex(st.Leaf[rng:NextInteger(1, #st.Leaf)]), Enum.Material.Neon, 0.25)
		tween(leaf, 0.22, { Size = Vector3.new(s, s * 0.5, s) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, grow * 0.8)
		table.insert(g.Parts, leaf)
		table.insert(segList, leaf)
		table.insert(g.Leaves, leaf)
	end
	-- branches enflammées : des flammes s'accrochent le long de la branche
	if st.Flame and g.Flames < MAX_BRANCH_FLAMES and rng:NextNumber() < 0.55 then
		g.Flames += 1
		local fh = holderPart(b + n * (w * 0.5 + 0.6))
		popIn(Flipbook.Billboard(fh, "Flame", (1.6 + w * 1.5) * rng:NextNumber(0.85, 1.2), { Brightness = 1.6 * Ambience.Glow(), Fps = rng:NextInteger(9, 14) }), 0.25)
		table.insert(g.Parts, fh)
		table.insert(segList, fh)
		g.FlameParts = g.FlameParts or {}
		table.insert(g.FlameParts, fh)
	end
	-- VERROUILLAGE (Tête chercheuse) : la pointe s'illumine quand un ennemi entre dans sa zone
	if msg.l then
		local glow = Ambience.Glow()
		Sparks.Burst(b, {
			Count = 14, Colors = { Color3.new(1, 1, 1), P.Core, P.Mid }, Speed = NumberRange.new(5, 12),
			Gravity = 0.2, Drag = 3, Life = NumberRange.new(0.2, 0.45), Size = 0.14,
		})
		LightPool.Flash(b, P.Core, 12, 3 * glow, 0.3, { 1, 0.5, 0.2 })
	end
	-- étincelles de pousse à la pointe
	local tip: Sparks.SparkOpts = { Colors = sparkColors(P), Gravity = 0.5, Drag = 2.5, Life = NumberRange.new(0.25, 0.5), Size = 0.11 }
	for _ = 1, 2 do
		Sparks.Emit(b, n * rng:NextNumber(1, 4) + rng:NextUnitVector() * 2, tip)
	end
	table.insert(g.Segs, { A = a, B = b, W = w })
	local segIdx = tonumber(msg.i)
	if segIdx then
		g.SegVis = g.SegVis or {}
		g.SegVis[segIdx] = segList
	end
end

-- RÉACTION D'ARBRE : l'arbre change d'infusion (e = "" : perd son infusion). Flammes éteintes (vapeur),
-- veines éteintes, écorce qui vire (carbonisée après le feu, bois brut sinon) ; nouvel élément Feu = flammes qui prennent.
local function growElem(msg)
	local id = tonumber(msg.g)
	local g = id and growthVis[id]
	if not g then
		return
	end
	local old = g.Element
	local new = if msg.e and msg.e ~= "" then msg.e else nil
	if old == new then
		return
	end
	g.Element = new
	for _, fh in g.FlameParts or {} do
		if fh.Parent then
			for _ = 1, 3 do
				Sparks.Emit(fh.Position, Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(2, 5), rng:NextNumber(-1, 1)), {
					Puff = true, Grow = 2.4, Fade0 = 0.65, Colors = { Color3.fromHex("5f676c"), Color3.fromHex("4a5155") },
					Gravity = -0.3, Drag = 2.2, Life = NumberRange.new(0.8, 1.3), Size = 0.4 })
			end
			fadeAway(fh, 0.35)
		end
	end
	g.FlameParts = {}
	g.Flames = 0
	for _, core in g.Cores or {} do
		if core.Parent then
			tween(core, 0.6, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end
	local barkHex = if new then branchStyle(new).Bark[1] elseif old == "Fire" then "2e241d" else "6e5a45"
	local col = Color3.fromHex(barkHex)
	for _, bark in g.Barks or {} do
		if bark.Parent then
			tween(bark, 0.8, { Color = col }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			for _, d in bark:GetDescendants() do
				if d:IsA("ImageLabel") then
					tween(d, 0.8, { ImageColor3 = col:Lerp(Color3.new(1, 1, 1), 0.35) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				end
			end
		end
	end
	if g.Light then
		g.Light.Release(0.6)
		g.Light = nil
	end
	if new then
		local P = palette(new)
		local fire = new == "Fire"
		g.Light = LightPool.Attach(g.Holder, P.Mid, 12 * math.sqrt(g.Scale), (if fire then 2.2 else 0.9) * Ambience.Glow(), if fire then 0.5 else 0.15)
		local st = branchStyle(new)
		if st.Flame then -- l'arbre s'embrase : des flammes prennent le long des branches
			for i, seg in g.Segs do
				if type(seg) == "table" and g.Flames < MAX_BRANCH_FLAMES and rng:NextNumber() < 0.45 then
					g.Flames += 1
					local fh = holderPart(seg.B + Vector3.new(0, (seg.W or 0.4) * 0.5 + 0.6, 0))
					task.delay(i / math.max(#g.Segs, 1) * 0.6, function()
						if fh.Parent then
							popIn(Flipbook.Billboard(fh, "Flame", (1.6 + (seg.W or 0.4) * 1.5) * rng:NextNumber(0.85, 1.2), { Brightness = 1.6 * Ambience.Glow(), Fps = rng:NextInteger(9, 14) }), 0.25)
						end
					end)
					table.insert(g.Parts, fh)
					g.FlameParts = g.FlameParts or {}
					table.insert(g.FlameParts, fh)
				end
			end
		end
	end
end

local function growEnd(msg)
	local id = tonumber(msg.g)
	local g = id and growthVis[id]
	if not g then
		return
	end
	growthVis[id] = nil
	local element = g.Element
	if g.Light then
		g.Light.Release(0.9)
	end
	fadeAway(g.Holder, 0.9)
	local count = #g.Parts
	local ash = Color3.fromHex(if element == "Fire" then "1a1410" else "6b5a48")
	for i = count, 1, -1 do
		local part = g.Parts[i]
		-- des POINTES vers la BASE (les derniers segments poussés flétrissent d'abord)
		local delay = (count - i) / math.max(count, 1) * 0.7 + rng:NextNumber(0, 0.12)
		if part.Name == "Holder" then
			task.delay(delay, fadeAway, part, 0.4, 0.3)
		elseif element == "Ice" then
			tween(part, 0.35, { Transparency = 1, Size = part.Size * 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, delay)
			task.delay(delay + 0.4, part.Destroy, part)
		else
			-- se dessèche / se carbonise, puis s'effrite en s'affinant
			tween(part, 0.3, { Color = ash }, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, delay)
			tween(part, 0.45, { Transparency = 1, Size = part.Size * 0.5 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, delay + 0.3)
			task.delay(delay + 0.8, part.Destroy, part)
		end
	end
	-- débris : feuilles qui tombent / cendres / éclats, sur un échantillon de segments
	local P = palette(element)
	local debris: Sparks.SparkOpts = if element == "Fire"
		then { Colors = { Color3.fromHex("ffcf4a"), Color3.fromHex("ff8f26"), Color3.fromHex("3d3d3d") }, Gravity = -0.2, Drag = 1.6, Life = NumberRange.new(0.6, 1.2), Size = 0.14 }
		elseif element == "Ice" then { Colors = ICE_COLORS, Gravity = 1.5, Drag = 0.6, Bounce = 0.5, Life = NumberRange.new(0.5, 1), Size = 0.14 }
		else { Colors = { Color3.fromHex("8fd94a"), Color3.fromHex("6b5a48"), P.Mid }, Gravity = 0.35, Drag = 2.6, Bounce = 0.1, Life = NumberRange.new(0.9, 1.8), Size = 0.15 }
	for i, seg in g.Segs do
		if type(seg) == "table" and i % 3 == 0 then
			local delay = (#g.Segs - i) / math.max(#g.Segs, 1) * 0.7
			task.delay(delay, function()
				Sparks.Emit(seg.B, Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(0, 3), rng:NextNumber(-2, 2)), debris)
			end)
		end
	end
end

-- ══ MATIÈRE & ENVIRONNEMENT (MatterService) ═══════════════════════════════════════════════════════════════
-- Feu qui court sur les surfaces, éclats à l'impact selon la matière, débris physiques à la casse,
-- cratères dans la pierre, segments de branches qui se brisent.
local fireCells: { [number]: any } = {}
local fireCount = 0
local fireLoops: { any } = {}
local fireLoopT = 0
local EMBER_OPTS: Sparks.SparkOpts = {
	Colors = { Color3.fromHex("fff1a8"), Color3.fromHex("ffcf4a"), Color3.fromHex("ff8f26"), Color3.fromHex("d8481a") },
	Gravity = -0.25, Drag = 1.4, Life = NumberRange.new(0.6, 1.3), Size = 0.11,
}
-- FUMÉE des flammes : mêmes BOUFFÉES que la vapeur (Puff : grossit en montant, s'efface), mais en gris très foncés
local SMOKE_OPTS: Sparks.SparkOpts = {
	Puff = true, Grow = 3.4, Fade0 = 0.55,
	Colors = { Color3.fromHex("625a54"), Color3.fromHex("574f4a"), Color3.fromHex("4c4540"), Color3.fromHex("6d645d") },
	Gravity = -0.32, Drag = 1.8, Life = NumberRange.new(1.4, 2.4), Size = 0.55,
}
local STEAM_OPTS: Sparks.SparkOpts = {
	Colors = { Color3.new(1, 1, 1), Color3.fromHex("e6eef2"), Color3.fromHex("b8c4cc") },
	Gravity = -0.5, Drag = 2.4, Life = NumberRange.new(0.6, 1.2), Size = 0.2,
}

-- ══ FLAMMES VOLUMINEUSES (champ de flammes, incendies) ══
-- flameStack : UNE flamme haute en 3 couches (halo sombre large derrière, corps, cœur clair et rapide),
-- étirée en hauteur ; chaque couche a sa cadence -> la flamme ondule au lieu de clignoter en bloc.
-- flameTongue : langue de feu qui JAILLIT, monte en grossissant puis se rétracte et s'éteint (volume, mouvement).
local FLAME_TONGUES_MAX = 90
local liveTongues = 0
local function tallFlame(holder: BasePart, w: number, h: number, bright: number, fps: number, transp: number?, offY: number?)
	local bb = Flipbook.Billboard(holder, "Flame", w, { Brightness = bright, Fps = fps, Transparency = transp or 0 })
	bb.Size = UDim2.fromScale(w, h)
	bb.StudsOffset = Vector3.new(0, offY or 0, 0)
	return bb
end
-- FLAMME : UN SEUL panneau (BillboardGui) qui contient ses 3 couches (halo, corps, cœur) dans l'ordre.
-- (avant : 3 panneaux séparés au même point -> le moteur les triait mal entre eux, les grands en coupaient les
-- petits, et les grands s'enfonçaient dans le sol : flammes coupées à moitié, bouillie visuelle)
-- Le bas du panneau est posé AU RAS du sol (StudsOffset) : plus rien ne s'enfonce dans la surface.
local function flameStack(holder: BasePart, size: number, glow: number): { BillboardGui }
	local f = rng:NextNumber(0.9, 1.12)
	local W, H = size * 1.8 * f, size * 1.3 * f
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(W, H)
	bb.LightInfluence = 0
	bb.Brightness = 1.7 * glow
	bb.StudsOffset = Vector3.new(0, H * 0.5 - size * 0.45, 0) -- bas du panneau ~ au niveau du sol (porteur à size*0.45)
	bb.Adornee = holder
	bb.Parent = holder
	local function layer(sx: number, sy: number, z: number, color: Color3, transp: number, fps: number)
		local img = Flipbook.Image(bb, "Flame", { Fps = fps, Transparency = transp })
		if img then
			img.AnchorPoint = Vector2.new(0.5, 1)
			img.Position = UDim2.fromScale(0.5, 1)
			img.Size = UDim2.fromScale(sx, sy)
			img.ZIndex = z
			img.ImageColor3 = color
		end
	end
	layer(0.92, 0.95, 1, Color3.fromRGB(140, 60, 35), 0.65, rng:NextInteger(7, 10)) -- halo large, sombre, transparent
	layer(0.78, 0.84, 2, Color3.new(1, 1, 1), 0, rng:NextInteger(10, 14)) -- corps
	layer(0.42, 0.46, 3, Color3.fromRGB(255, 240, 200), 0, rng:NextInteger(15, 20)) -- cœur, au ras du sol
	return { bb }
end
local function flameTongue(at: Vector3, up: Vector3, size: number, glow: number)
	if liveTongues >= FLAME_TONGUES_MAX or activeFx > MAX_ACTIVE_FX then
		return
	end
	liveTongues += 1
	local life = rng:NextNumber(0.45, 0.8)
	local h = holderPart(at)
	local w = size * rng:NextNumber(0.6, 1)
	local bb = tallFlame(h, w * 0.6, w * 0.5, 1.8 * glow, rng:NextInteger(12, 18), 0, 0)
	tween(bb, life * 0.4, { Size = UDim2.fromScale(w * 1.3, w * 1.05) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(life * 0.45, function()
		if bb.Parent then
			tween(bb, life * 0.55, { Size = UDim2.fromScale(w * 0.5, w * 0.6) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
	-- monte moins haut qu'avant (0,9-1,6 x taille) : le feu ondule au-dessus du tapis sans faire de colonnes
	tween(h, life, { CFrame = CFrame.new(at + up * size * rng:NextNumber(0.45, 0.85) + rng:NextUnitVector() * 0.5) }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	task.delay(life, function()
		liveTongues -= 1
		fadeAway(h, 0.12)
	end)
end

local function igniteCell(msg)
	local id, p = tonumber(msg.i), vec(msg.p)
	if not (id and p) or fireCells[id] then
		return
	end
	local n = vec(msg.n) or Vector3.yAxis
	local glow = Ambience.Glow()
	local size = 3 * rng:NextNumber(0.85, 1.25)
	local holder = holderPart(p + n * size * 0.55)
	for _, bb in flameStack(holder, size, glow) do
		popIn(bb, 0.35)
	end
	fireCount += 1
	local cell = { Holder = holder, Pos = p, N = n, Emit = rng:NextNumber(0, 0.3) }
	-- une lumière sur ~1 cellule sur 3 (budget de lumières)
	if fireCount % 2 == 1 then
		cell.Light = LightPool.Attach(holder, Color3.fromHex("ff8f26"), 16, 2.6 * glow, 0.6)
	end
	fireCells[id] = cell
	Sparks.Burst(p + n * 0.3, { Count = 6, Colors = EMBER_OPTS.Colors, Normal = n, Speed = NumberRange.new(3, 7), Gravity = -0.2, Drag = 2, Life = NumberRange.new(0.3, 0.7), Size = 0.12 })
	SoundFX.Play("Fire.Catch", p)
end

local function endCell(msg)
	local id = tonumber(msg.i)
	local cell = id and fireCells[id]
	if not cell then
		return
	end
	fireCells[id] = nil
	if cell.Light then
		cell.Light.Release(0.5)
	end
	fadeAway(cell.Holder, 0.5, 0.4)
	if msg.w then
		-- éteint par la glace : vapeur qui monte + grésillement
		for _ = 1, 6 do
			Sparks.Emit(cell.Pos + cell.N * 0.4, cell.N * rng:NextNumber(2, 5) + rng:NextUnitVector() * 1.5, STEAM_OPTS)
		end
		SoundFX.Play("Zone.Extinguish", cell.Pos)
	else
		for _ = 1, 3 do
			Sparks.Emit(cell.Pos + cell.N * 0.5, cell.N * rng:NextNumber(1, 3) + rng:NextUnitVector(), SMOKE_OPTS)
		end
	end
end

local function updateFire(dt: number)
	for _, cell in fireCells do
		cell.Emit -= dt
		if cell.Emit <= 0 then
			cell.Emit = rng:NextNumber(0.18, 0.4)
			-- langue de feu qui jaillit de la cellule (1 fois sur 2)
			if rng:NextNumber() < 0.5 then
				flameTongue(cell.Pos + cell.N * 0.8 + rng:NextUnitVector() * 0.7, cell.N, 2.6, Ambience.Glow())
			end
			Sparks.Emit(cell.Pos + cell.N * 0.6 + rng:NextUnitVector() * 0.8, cell.N * rng:NextNumber(3, 7) + rng:NextUnitVector() * 1.5, EMBER_OPTS)
			if rng:NextNumber() < 0.5 then -- fumée : part AU-DESSUS des flammes (ne les cache pas)
				Sparks.Emit(cell.Pos + cell.N * 3 + rng:NextUnitVector() * 0.6, cell.N * rng:NextNumber(2, 4) + rng:NextUnitVector() * 0.6, SMOKE_OPTS)
			end
		end
	end
	-- SON : le crépitement d'incendie suit les 3 foyers les plus proches de la caméra
	fireLoopT -= dt
	if fireLoopT <= 0 then
		fireLoopT = 0.35
		local cam = workspace.CurrentCamera.CFrame.Position
		local list = {}
		for _, cell in fireCells do
			table.insert(list, cell)
		end
		table.sort(list, function(a, b)
			return (a.Pos - cam).Magnitude < (b.Pos - cam).Magnitude
		end)
		for i = 1, 3 do
			local cell = list[i]
			local lp = fireLoops[i]
			if cell then
				if not lp then
					lp = SoundFX.PointLoop("Loop.Wildfire", cell.Pos)
					fireLoops[i] = lp
				end
				if lp then
					lp.Move(cell.Pos)
				end
			elseif lp then
				lp.Stop()
				fireLoops[i] = nil
			end
		end
	end
end

-- éclats de matière (impact) : couleur / comportement selon la SORTE de matière
local CHIP = {
	Wood = { Gravity = 1.2, Drag = 0.8, Bounce = 0.35, Life = NumberRange.new(0.4, 0.9), Size = 0.14, Speed = { 6, 14 } },
	Branch = { Gravity = 1.2, Drag = 0.8, Bounce = 0.35, Life = NumberRange.new(0.4, 0.9), Size = 0.14, Speed = { 6, 14 } },
	Leaves = { Gravity = 0.12, Drag = 3, Bounce = 0.1, Life = NumberRange.new(1, 2), Size = 0.18, Speed = { 3, 8 } },
	Surface = { Gravity = 0.3, Drag = 2.6, Bounce = 0.1, Life = NumberRange.new(0.6, 1.2), Size = 0.13, Speed = { 3, 7 } },
	Stone = { Gravity = 1.5, Drag = 0.5, Bounce = 0.4, Life = NumberRange.new(0.5, 1), Size = 0.16, Speed = { 7, 16 } },
	Metal = { Gravity = 0.8, Drag = 0.6, Bounce = 0.6, Life = NumberRange.new(0.15, 0.4), Size = 0.1, Speed = { 12, 26 } },
	Ice = { Gravity = 1.5, Drag = 0.6, Bounce = 0.5, Life = NumberRange.new(0.4, 0.9), Size = 0.15, Speed = { 7, 15 } },
	Glass = { Gravity = 1.5, Drag = 0.5, Bounce = 0.55, Life = NumberRange.new(0.4, 0.9), Size = 0.12, Speed = { 8, 18 } },
}
local LEAF_COLORS = { Color3.fromHex("a8e85a"), Color3.fromHex("6fbf3a"), Color3.fromHex("3f7f22"), Color3.fromHex("d8c04a") }
local METAL_SPARK = { Color3.new(1, 1, 1), Color3.fromHex("fff1a8"), Color3.fromHex("ffcf4a") }

local function matterColors(kind: string, element: string?, hex: string?): { Color3 }
	if kind == "Metal" then
		return METAL_SPARK
	elseif kind == "Leaves" or kind == "Surface" then
		return LEAF_COLORS
	elseif kind == "Ice" or kind == "Glass" then
		return ICE_COLORS
	end
	local list = {}
	if type(hex) == "string" then
		local ok, c = pcall(Color3.fromHex, hex)
		if ok then
			table.insert(list, c)
			table.insert(list, c:Lerp(Color3.new(0, 0, 0), 0.35))
			table.insert(list, c:Lerp(Color3.new(1, 1, 1), 0.25))
		end
	end
	if #list == 0 then
		list = sparkColors(palette(element))
	end
	return list
end

local function matterHit(msg)
	local p = vec(msg.p)
	if not p then
		return
	end
	local kind = if type(msg.m) == "string" then msg.m else "Stone"
	local spec = CHIP[kind] or CHIP.Stone
	local x = tonumber(msg.x) or 0
	local count = if x > 0 then 14 elseif x < 0 then 3 else 7
	local opts: Sparks.SparkOpts = { Colors = matterColors(kind, msg.e, msg.c), Gravity = spec.Gravity, Drag = spec.Drag, Bounce = spec.Bounce, Life = spec.Life, Size = spec.Size }
	local n = vec(msg.n) or Vector3.yAxis
	for _ = 1, count do
		Sparks.Emit(p + n * 0.2, (n * 0.8 + rng:NextUnitVector() * 0.7).Unit * rng:NextNumber(spec.Speed[1], spec.Speed[2]), opts)
	end
	if x < 0 then
		-- PEU EFFICACE : petite bouffée grise, ça glisse sur la matière
		for _ = 1, 3 do
			Sparks.Emit(p + n * 0.3, n * rng:NextNumber(1, 2) + rng:NextUnitVector(), SMOKE_OPTS)
		end
	elseif x > 0 then
		-- SUPER EFFICACE : éclair de la couleur de l'attaque
		LightPool.Flash(p + n * 0.5, palette(msg.a).Core, 10, 2 * Ambience.Glow(), 0.18, { 1, 0.4 })
	end
	SoundFX.Play("Matter.Hit." .. kind, p, if x > 0 then 0.9 elseif x < 0 then 1.15 else 1, if x > 0 then 1.3 elseif x < 0 then 0.6 else 1)
end

-- MATIÈRE D'UN SORT DANS UNE ZONE (hors feu) : une gangue de l'élément recouvre la pièce tant qu'elle subit la zone
-- glace = givre blanc-bleu cristallin | toxique = corrosion verte | foudre = gaine électrique qui grésille | nature = lierre
local COAT = {
	Ice = { Mat = Enum.Material.Glacier, Color = Color3.fromHex("cfefff"), T = 0.35 },
	Toxic = { Mat = Enum.Material.Slate, Color = Color3.fromHex("6fbf3a"), T = 0.45 },
	Lightning = { Mat = Enum.Material.Neon, Color = Color3.fromHex("fff3a0"), T = 0.82, Flicker = true },
	Nature = { Mat = Enum.Material.LeafyGrass, Color = Color3.fromHex("4f8f35"), T = 0.3 },
}
local coats: { [BasePart]: { Part: BasePart, Until: number } } = {}
local function matterCoat(msg)
	local part = msg.i
	local spec = COAT[msg.e]
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part.Parent or not spec then
		return
	end
	local now = os.clock()
	local c = coats[part]
	if c and c.Part.Parent then
		c.Until = now + 0.9 -- toujours dans la zone : la gangue tient
	else
		local g = Instance.new("Part")
		g.Name = "Coat"
		g.Anchored, g.CanCollide, g.CanQuery, g.CanTouch, g.CastShadow = true, false, false, false, false
		if part:IsA("Part") then
			g.Shape = part.Shape
		end
		g.Size = part.Size + Vector3.new(0.14, 0.14, 0.14)
		g.CFrame = part.CFrame
		g.Material, g.Color, g.Transparency = spec.Mat, spec.Color, 1
		g.Parent = fxFolder
		tween(g, 0.35, { Transparency = spec.T })
		c = { Part = g, Until = now + 0.9 }
		coats[part] = c
		task.spawn(function()
			while g.Parent and part.Parent and os.clock() < c.Until do
				g.CFrame = part.CFrame -- suit la branche (chute, croissance)
				if spec.Flicker then
					g.Transparency = spec.T + rng:NextNumber(0, 0.15)
				end
				task.wait(0.05)
			end
			coats[part] = nil
			if g.Parent then
				tween(g, 0.6, { Transparency = 1 })
				task.delay(0.65, function() g:Destroy() end)
			end
		end)
	end
	-- quelques particules de l'élément sur la pièce
	local p = vec(msg.p) or part.Position
	if activeFx <= MAX_ACTIVE_FX then
		local pal = palette(msg.e)
		for _ = 1, 3 do
			Sparks.Emit(p + rng:NextUnitVector() * 0.4, rng:NextUnitVector() * rng:NextNumber(1, 3), { Colors = { pal.Core, spec.Color }, Gravity = if msg.e == "Toxic" then 1.5 else 0.1, Drag = 3, Life = NumberRange.new(0.3, 0.6), Size = 0.12 })
		end
	end
	SoundFX.Play("Tint." .. msg.e, p, 1, 0.7)
end

-- BRANCHE CHARGÉE : le bout de branche d'où partira la suite du deck (Ajout d'expiration) scintille
-- aux couleurs de l'infusion du sort qui va en partir (reçu toutes les 0,25 s tant que l'arbre vit)
local function tipMark(msg)
	local p = vec(msg.p)
	if not p or activeFx > MAX_ACTIVE_FX then
		return
	end
	local pal = palette(msg.e)
	local d = vec(msg.d) or Vector3.yAxis
	-- MÈCHE ALLUMÉE : gerbe d'étincelles crépitantes projetées dans tous les sens, qui retombent,
	-- + braise incandescente au bout (lueur qui palpite). Émise étalée sur l'intervalle (0,25 s) = jet continu.
	local opts = { Colors = { Color3.new(1, 1, 1), Color3.new(1, 1, 1), pal.Core, pal.Mid or pal.Core }, Gravity = 1.1, Drag = 1.2,
		Bounce = 0.3, Life = NumberRange.new(0.35, 0.8), Size = 0.2, Crackle = 0.5 }
	local ember = { Colors = { pal.Core, pal.Mid or pal.Core }, Gravity = -0.15, Drag = 3, Life = NumberRange.new(0.15, 0.3), Size = 0.42 }
	-- lueur douce qui se chevauche d'un envoi à l'autre (0,35 s > 0,25 s) : braise continue, pas de flash
	LightPool.Flash(p, pal.Core, 9, 0.9 * Ambience.Glow(), 0.35, { 1, 0.8 })
	for k = 0, 4 do
		task.delay(k * 0.05, function()
			Sparks.Emit(p, d * 0.6 + rng:NextUnitVector() * 0.3, ember) -- cœur de la mèche
			for _ = 1, 4 do
				local v = (d * rng:NextNumber(0.2, 0.9) + rng:NextUnitVector()).Unit * rng:NextNumber(6, 14)
				Sparks.Emit(p + rng:NextUnitVector() * 0.15, v, opts)
			end
		end)
	end
end

-- RÉACTION ENTRE ÉLÉMENTS : son nom s'élève au-dessus de la cible (« EXPLOSION DE GAZ », « ÉCLATEMENT »...)
local REACTION_FX: { [string]: (Vector3, number) -> () } = {} -- rempli au chargement (WandShared/ReactionVisuals)
local function reactLabel(msg)
	local p = vec(msg.p)
	if not p or typeof(msg.t) ~= "string" then
		return
	end
	local h = holderPart(p)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 26)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = h
	bb.Parent = h
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.Arcade
	t.TextSize = 20
	t.Text = msg.t
	t.TextColor3 = palette(msg.e).Core
	t.TextStrokeTransparency = 0
	t.TextStrokeColor3 = Color3.new(0, 0, 0)
	t.Parent = bb
	tween(h, 1.1, { CFrame = CFrame.new(p + Vector3.new(0, 2.5, 0)) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(0.7, function()
		tween(t, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.delay(0.45, function() h:Destroy() end)
	end)
end

-- DÉBRIS PHYSIQUES locaux (morceaux qui tombent, rebondissent, puis s'effacent)
local liveDebris = 0
local DEBRIS_MAT = { Wood = Enum.Material.Wood, Branch = Enum.Material.Wood, Stone = Enum.Material.Slate, Metal = Enum.Material.Metal,
	Ice = Enum.Material.Ice, Glass = Enum.Material.Glass, Leaves = Enum.Material.LeafyGrass, Surface = Enum.Material.Grass }
local function debrisBurst(center: Vector3, extent: Vector3, colors: { Color3 }, material: Enum.Material, count: number, chunk: number, power: number)
	count = math.min(count, 120 - liveDebris)
	for _ = 1, count do
		liveDebris += 1
		local s = chunk * rng:NextNumber(0.5, 1.2)
		local d = Instance.new("Part")
		d.Size = Vector3.new(s, s * rng:NextNumber(0.5, 1), s * rng:NextNumber(0.6, 1.4))
		d.CFrame = CFrame.new(center + Vector3.new(rng:NextNumber(-0.5, 0.5) * extent.X, rng:NextNumber(-0.5, 0.5) * extent.Y, rng:NextNumber(-0.5, 0.5) * extent.Z))
			* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
		d.Color = colors[rng:NextInteger(1, #colors)]
		d.Material = material
		d.Anchored = false
		d.CanCollide = true
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		d.CustomPhysicalProperties = PhysicalProperties.new(0.05, 0.6, 0.25) -- très léger : ne bouscule personne
		d.AssemblyLinearVelocity = (rng:NextUnitVector() + Vector3.new(0, 1.1, 0)).Unit * power * rng:NextNumber(0.5, 1.1)
		d.AssemblyAngularVelocity = rng:NextUnitVector() * rng:NextNumber(4, 14)
		d.Parent = fxFolder
		local life = rng:NextNumber(2.5, 4)
		tween(d, 0.8, { Transparency = 1, Size = d.Size * 0.4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, life)
		task.delay(life + 0.85, function()
			liveDebris -= 1
			d:Destroy()
		end)
	end
end

local function matterBreak(msg)
	local p = vec(msg.p)
	if not p then
		return
	end
	local kind = if type(msg.m) == "string" then msg.m else "Stone"
	local size = vec(msg.sz) or Vector3.one * 2
	local colors = matterColors(kind, msg.e, msg.c)
	local vol = size.X * size.Y * size.Z
	local count = math.clamp(math.floor(vol ^ 0.5 * 1.4), 5, 18)
	local chunk = math.clamp(vol ^ (1 / 3) * 0.32, 0.3, 1.6)
	debrisBurst(p, size, colors, DEBRIS_MAT[kind] or Enum.Material.Slate, count, chunk, 14 + chunk * 4)
	local spec = CHIP[kind] or CHIP.Stone
	Sparks.Burst(p, { Count = 16, Colors = colors, Speed = NumberRange.new(spec.Speed[1], spec.Speed[2] * 1.2), Gravity = spec.Gravity, Drag = spec.Drag, Bounce = spec.Bounce, Life = spec.Life, Size = spec.Size })
	if kind == "Stone" then
		for _ = 1, 8 do
			Sparks.Emit(p + rng:NextUnitVector() * size.Magnitude * 0.2, rng:NextUnitVector() * rng:NextNumber(1, 4) + Vector3.new(0, 1, 0), SMOKE_OPTS)
		end
	end
	SoundFX.Play("Matter.Break." .. kind, p)
end

-- CRATÈRE : la pierre arrachée part en morceaux + poussière
local function carveFx(msg)
	local p = vec(msg.p)
	if not p then
		return
	end
	local r = math.clamp(tonumber(msg.r) or 2, 1, 10)
	local color = Color3.fromRGB(110, 110, 110)
	if type(msg.c) == "string" then
		local ok, c = pcall(Color3.fromHex, msg.c)
		if ok then
			color = c
		end
	end
	local colors = { color, color:Lerp(Color3.new(0, 0, 0), 0.3), color:Lerp(Color3.new(1, 1, 1), 0.2) }
	debrisBurst(p, Vector3.one * r, colors, Enum.Material.Slate, math.clamp(math.floor(r * 3), 5, 22), math.clamp(r * 0.28, 0.35, 1.5), 18 + r * 3)
	for _ = 1, math.floor(6 + r * 2) do
		Sparks.Emit(p + rng:NextUnitVector() * r * 0.4, rng:NextUnitVector() * rng:NextNumber(2, 5) + Vector3.new(0, 2, 0), SMOKE_OPTS)
	end
	SoundFX.Play("Matter.Carve", p, 1.1 - math.min(r, 8) * 0.04)
end

-- segment de branche brisé (cassé, brûlé, gelé...) : il se détache et tombe
local function growCut(msg)
	local id, idx, p = tonumber(msg.g), tonumber(msg.i), vec(msg.p)
	local g = id and growthVis[id]
	local parts = g and g.SegVis and idx and g.SegVis[idx]
	local burnt = msg.a == "Fire"
	if parts then
		g.SegVis[idx] = nil
		for _, part in parts do
			if part.Parent then
				if part.Name == "Holder" then
					fadeAway(part, 0.3)
				else
					local fall = Vector3.new(rng:NextNumber(-1, 1), -rng:NextNumber(3, 6), rng:NextNumber(-1, 1))
					if burnt then
						tween(part, 0.25, { Color = Color3.fromHex("1a1410") })
					end
					tween(part, 0.7, { CFrame = part.CFrame * CFrame.Angles(rng:NextNumber(-0.8, 0.8), 0, rng:NextNumber(-0.8, 0.8)) + fall, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.05)
					task.delay(0.8, part.Destroy, part)
				end
			end
		end
	end
	if p then
		local P = palette(msg.e)
		local st = branchStyle(msg.e)
		local bark = {}
		for _, hex in st.Bark do
			table.insert(bark, Color3.fromHex(hex))
		end
		if burnt then
			bark = { Color3.fromHex("1a1410"), Color3.fromHex("3d3d3d"), Color3.fromHex("ff8f26") }
		end
		local w = math.clamp(tonumber(msg.w) or 0.6, 0.2, 4)
		debrisBurst(p, Vector3.one * w, bark, if msg.e == "Ice" then Enum.Material.Ice else Enum.Material.Wood, math.clamp(math.floor(3 + w * 2), 3, 10), math.clamp(w * 0.35, 0.2, 1), 10)
		Sparks.Burst(p, { Count = 8, Colors = sparkColors(P), Speed = NumberRange.new(4, 10), Gravity = 0.8, Drag = 1.5, Life = NumberRange.new(0.3, 0.7), Size = 0.13 })
		SoundFX.Play(if msg.e == "Ice" then "Matter.Break.Ice" else "Matter.Break.Branch", p)
	end
end

-- braises qui montent des branches en feu + veines qui scintillent (chaos, foudre)
local function updateGrowths(dt: number)
	for _, g in growthVis do
		-- fumée des flammes accrochées aux branches (arbre en feu)
		local fl = g.FlameParts
		if fl and #fl > 0 and rng:NextNumber() < dt * math.min(#fl, 10) * 0.5 then
			local fh = fl[rng:NextInteger(1, #fl)]
			if fh.Parent then
				Sparks.Emit(fh.Position + Vector3.new(0, 1.8, 0), Vector3.new(rng:NextNumber(-0.5, 0.5), rng:NextNumber(2, 4), rng:NextNumber(-0.5, 0.5)), SMOKE_OPTS)
			end
		end
		local amb = AMBIENT[g.Element or ""]
		-- rafale : une gerbe de feuilles arrachée d'une branche, qui tourbillonne
		if amb and amb.Gust and #g.Segs > 0 then
			g.GustT = (g.GustT or rng:NextNumber(0.3, 1)) - dt
			if g.GustT <= 0 then
				g.GustT = rng:NextNumber(amb.Gust[1], amb.Gust[2])
				local seg = g.Segs[rng:NextInteger(1, #g.Segs)]
				if type(seg) == "table" then
					local c = seg.B
					local wind = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
					wind = if wind.Magnitude > 0.1 then wind.Unit else Vector3.xAxis
					for i = 1, amb.GustCount do
						local a = i / amb.GustCount * math.pi * 2
						local swirl = Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(3, 7)
						Sparks.Emit(c + swirl * 0.15, swirl + wind * rng:NextNumber(4, 9) + Vector3.new(0, rng:NextNumber(2, 6), 0), amb.Opts)
					end
				end
			end
		end
		if amb and #g.Segs > 0 and Sparks.Count() < TRAIL_SPARK_CAP then
			g.Acc += dt * math.min(amb.Max, #g.Segs * amb.Rate)
			while g.Acc >= 1 do
				g.Acc -= 1
				local seg = g.Segs[rng:NextInteger(1, #g.Segs)]
				if type(seg) == "table" then
					local at = seg.A:Lerp(seg.B, rng:NextNumber())
					if amb.Below then
						at -= Vector3.new(0, (seg.W or 0.5) * 0.5, 0) -- les gouttes se détachent du dessous
					end
					Sparks.Emit(at, amb.Vel(), amb.Opts or FIRE_SPARKS)
				end
			end
		end
		if g.Element == "Chaos" or g.Element == "Lightning" then
			for _, seg in g.Segs do
				if typeof(seg) == "Instance" and rng:NextNumber() < dt * 8 then
					local P = palette(g.Element)
					local cols = P.Flicker or { P.Core, P.Mid }
					seg.Color = cols[rng:NextInteger(1, #cols)]
				end
			end
		end
	end
end

-- Piège déclenché : les paillettes jaillissent d'un coup (l'effet réel vient des modificateurs / de la charge)
function VFX.TrapFire(pos: Vector3, element: string?, fx: number?)
	local P = palette(element)
	local big = math.sqrt(math.clamp(fx or 1, 0.5, 8))
	Sparks.Burst(pos + Vector3.new(0, 0.3, 0), {
		Count = math.floor(36 * big), Colors = { Color3.new(1, 1, 1), P.Core, P.Mid, P.Edge }, Direction = Vector3.yAxis, Spread = 55,
		Speed = NumberRange.new(8 * big, 18 * big), Gravity = 0.6, Drag = 1.8, Bounce = 0.3, Life = NumberRange.new(0.5, 1.1), Size = 0.13,
	})
	LightPool.Flash(pos + Vector3.new(0, 1, 0), P.Core, 12 * big, 3 * Ambience.Glow(), 0.25, { 1, 0.5, 0.2 })
end

-- Échec d'un sort (ex. branche sans surface) : étincelles de chaos qui tournoient autour du lanceur.
local FIZZLE_SPARKS: Sparks.SparkOpts = {
	Colors = Config.Elements.Chaos.Flicker, Gravity = 0.15, Drag = 3, Life = NumberRange.new(0.3, 0.6), Size = 0.12,
}
function VFX.Fizzle(pos: Vector3)
	for i = 1, 24 do
		local a = i / 24 * math.pi * 2
		local p = pos + Vector3.new(math.cos(a) * 2.2, rng:NextNumber(-2.2, 1.6), math.sin(a) * 2.2)
		Sparks.Emit(p, Vector3.new(-math.sin(a), rng:NextNumber(0.3, 1.5), math.cos(a)) * rng:NextNumber(4, 8), FIZZLE_SPARKS)
	end
	Sparks.Burst(pos + Vector3.new(0, 1, 0), {
		Count = 14, Colors = Config.Elements.Chaos.Flicker, Speed = NumberRange.new(3, 8), Gravity = 0.3, Drag = 3,
		Life = NumberRange.new(0.25, 0.5), Size = 0.12, Crackle = 0.4,
	})
	LightPool.Flash(pos, Config.Elements.Chaos.Mid, 10, 2 * Ambience.Glow(), 0.3, { 1, 0.3, 0.8, 0.2 })
end

-- ── Routage des messages serveur ─────────────────────────────────────────────────────────────────────────────
-- Au message d'impact, le projectile affiché (le plus proche, à moins de 8 studs) est calé EXACTEMENT
-- sur le point d'impact : la boule visible, le flash et le son arrivent dans la même image.
local function snapProxyTo(pos: Vector3)
	local best, bestDist = nil, 8
	for _, entry in proxies do
		local toImpact = pos - entry.Proxy.Position
		local d = toImpact.Magnitude
		-- seulement un projectile qui SE DIRIGE vers ce point (pas un voisin d'un multicast)
		local heading = d < 0.5 or entry.ServerVel:Dot(toImpact) > 0
		if not entry.Frozen and heading and d < bestDist then
			best, bestDist = entry, d
		end
	end
	if best then
		best.Proxy.CFrame = best.Proxy.CFrame.Rotation + pos
		best.Frozen = os.clock()
	end
end

-- ══ MOUVEMENTS DE BASE : dash = poussière au départ / à l'arrivée, silhouettes fantômes, lignes de vitesse ══
local DUST_COLORS = { Color3.fromHex("6e655b"), Color3.fromHex("5e564e"), Color3.fromHex("7d7368") }
local AIR_COLORS = { Color3.fromHex("d8e2ee"), Color3.fromHex("aab8c8") }
local function moverRoot(u: any): BasePart?
	local pl = if type(u) == "number" then Players:GetPlayerByUserId(u) else nil
	local ch = pl and pl.Character
	return ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
end
local function dustPuff(feet: Vector3, count: number, back: Vector3)
	Sparks.Burst(feet, {
		Puff = true, Count = count, Colors = DUST_COLORS, Speed = NumberRange.new(1.5, 4.5), Gravity = -0.04, Drag = 3,
		Life = NumberRange.new(0.35, 0.65), Size = 0.55, Grow = 2.2, Fade0 = 0.62,
	})
	for _ = 1, count do -- quelques grains projetés vers l'arrière
		Sparks.Emit(feet + Vector3.new(0, 0.2, 0), (back * rng:NextNumber(4, 8)) + Vector3.new(0, rng:NextNumber(2, 5), 0) + rng:NextUnitVector() * 1.5,
			{ Colors = DUST_COLORS, Gravity = 1, Drag = 1.5, Life = NumberRange.new(0.25, 0.45), Size = 0.1, Matte = true })
	end
end
-- silhouette fantôme du personnage (dash) : copie figée des pièces visibles, teinte claire, qui s'efface
local GHOST_COLOR = Color3.fromHex("bcd4f2")
local function ghostOf(ch: Model, life: number, alpha: number)
	local folder = Instance.new("Model")
	folder.Name = "DashGhost"
	for _, part in ch:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 0.9 then
			local g = part:Clone()
			for _, c in g:GetChildren() do
				if not (c:IsA("SpecialMesh") or c:IsA("DataModelMesh")) then c:Destroy() end
			end
			g.Anchored, g.CanCollide, g.CanQuery, g.CanTouch, g.CastShadow = true, false, false, false, false
			g.Material = Enum.Material.SmoothPlastic
			g.Color = GHOST_COLOR
			if g:IsA("MeshPart") then g.TextureID = "" end
			local m = g:FindFirstChildWhichIsA("SpecialMesh")
			if m then m.TextureId = "" m.VertexColor = Vector3.new(0.75, 0.83, 0.95) end
			g.Transparency = alpha
			g.CFrame = part.CFrame
			g.Parent = folder
		end
	end
	folder.Parent = VFX.Folder()
	local t0 = os.clock()
	task.spawn(function()
		while folder.Parent do
			local k = (os.clock() - t0) / life
			if k >= 1 then break end
			for _, g in folder:GetChildren() do (g :: BasePart).Transparency = alpha + (1 - alpha) * k end
			task.wait()
		end
		folder:Destroy()
	end)
end
local dashFovT = 0
local function fovPunch()
	local cam = workspace.CurrentCamera
	if not cam then return end
	dashFovT += 1
	local token = dashFovT
	local base = cam:GetAttribute("BaseFOV") or cam.FieldOfView
	cam:SetAttribute("BaseFOV", base)
	task.spawn(function()
		local t = 0
		while t < 0.45 and token == dashFovT do
			t += task.wait()
			local k = t / 0.45
			local bump = if k < 0.18 then k / 0.18 else 1 - (k - 0.18) / 0.82 -- montée vive, retour souple
			cam.FieldOfView = base + 9 * math.max(bump, 0)
		end
		if token == dashFovT then cam.FieldOfView = base cam:SetAttribute("BaseFOV", nil) end
	end)
end

-- PROPULSION CÉLESTE, impact au sol : onde de poussière en anneau + débris couleur du sol + nuage
local impactRay = RaycastParams.new()
impactRay.FilterType = Enum.RaycastFilterType.Exclude
function VFX.GroundImpact(p: Vector3, speed: number)
	local k = math.clamp(speed / 110, 0.7, 1.6)
	impactRay.FilterDescendantsInstances = { VFX.Folder() }
	local hit = workspace:Raycast(p + Vector3.new(0, 1.5, 0), Vector3.new(0, -4, 0), impactRay)
	local base = if hit and hit.Instance then hit.Instance.Color else Color3.fromHex("7d7368")
	local cols = { base:Lerp(Color3.fromHex("6e655b"), 0.5), base:Lerp(Color3.fromHex("4e463f"), 0.55), base:Lerp(Color3.fromHex("8a7f73"), 0.4) }
	local at = (if hit then hit.Position else p) + Vector3.new(0, 0.2, 0)
	-- shockwave ring: puffs thrown outwards along the ground
	local n = math.floor(18 * k)
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		Sparks.Emit(at + dir * 0.6, dir * rng:NextNumber(9, 14) * k + Vector3.new(0, rng:NextNumber(0.5, 1.5), 0),
			{ Puff = true, Colors = cols, Gravity = -0.02, Drag = 4.5, Life = NumberRange.new(0.5, 0.85),
				Size = rng:NextNumber(0.55, 0.8) * k, Grow = 2.6, Fade0 = 0.45 })
	end
	-- central cloud rising slowly
	Sparks.Burst(at, { Puff = true, Count = math.floor(6 * k), Colors = cols, Speed = NumberRange.new(1, 3), Gravity = -0.06,
		Drag = 2.5, Life = NumberRange.new(0.7, 1.1), Size = 0.8 * k, Grow = 2.2, Fade0 = 0.5 })
	-- debris: small chunks of ground thrown up that fall back
	for _ = 1, math.floor(14 * k) do
		Sparks.Emit(at, rng:NextUnitVector() * Vector3.new(1, 0, 1) * rng:NextNumber(4, 10) * k + Vector3.new(0, rng:NextNumber(6, 13) * k, 0),
			{ Colors = cols, Gravity = 1.3, Drag = 0.8, Life = NumberRange.new(0.45, 0.8), Size = rng:NextNumber(0.1, 0.18), Matte = true })
	end
end

-- RECUL AU SOL : traînée de poussière sous les pieds pendant toute la glissade (suit le personnage)
function VFX.SkidTrail(p: Vector3, d: Vector3?, speed: number, u: any)
	local dir = if d and d.Magnitude > 0.01 then Vector3.new(d.X, 0, d.Z).Unit else Vector3.new(0, 0, 1)
	local k = math.clamp(speed / 50, 0.5, 1.5)
	dustPuff(p - Vector3.new(0, 2.7, 0), math.floor(5 * k), -dir)
	local root = moverRoot(u)
	task.spawn(function()
		local t = 0
		while t < 0.6 do
			t += task.wait(0.05)
			local at = if root and root.Parent then root.Position else p + dir * speed * t * (1 - t / 1.2)
			local fade = 1 - t / 0.6
			if fade < 0.15 then break end
			-- two feet scraping: low puffs pushed forward (against the slide) + grains
			for side = -1, 1, 2 do
				local foot = at - Vector3.new(0, 2.7, 0) + Vector3.new(-dir.Z, 0, dir.X) * 0.5 * side
				Sparks.Emit(foot, -dir * rng:NextNumber(1, 3) * k + Vector3.new(0, rng:NextNumber(0.4, 1.2), 0),
					{ Puff = true, Colors = DUST_COLORS, Gravity = -0.02, Drag = 3, Life = NumberRange.new(0.35, 0.6),
						Size = rng:NextNumber(0.35, 0.55) * k * (0.5 + fade * 0.5), Grow = 2.1, Fade0 = 0.5 })
				if rng:NextNumber() < 0.6 then
					Sparks.Emit(foot, -dir * rng:NextNumber(3, 6) * k + Vector3.new(0, rng:NextNumber(1.5, 3.5), 0),
						{ Colors = DUST_COLORS, Gravity = 1, Drag = 1.2, Life = NumberRange.new(0.25, 0.4), Size = 0.08, Matte = true })
				end
			end
		end
	end)
end

function VFX.MoveDust(kind: string, p: Vector3, d: Vector3?, u: any)
	local root = moverRoot(u)
	local dir = if d and d.Magnitude > 0.01 then d.Unit else Vector3.new(0, 0, -1)
	local at = if root then root.Position else p
	local feet = at - Vector3.new(0, 2.7, 0)
	if kind == "Dash" then
		-- départ : grosse bouffée de poussière + éclats projetés en arrière
		dustPuff(feet, 9, -dir)
		if u == LOCAL_USER_ID then fovPunch() end
		local ch = root and root.Parent :: Model?
		task.spawn(function()
			-- pendant le dash : silhouettes fantômes semées derrière + lignes de vitesse autour du corps
			-- the first ghost waits for the dash pose to be in place: all ghosts share the same silhouette
			task.wait(0.06)
			for i = 1, 5 do
				local r = moverRoot(u)
				if not r then return end
				if ch and i <= 4 then ghostOf(ch, 0.32, 0.45 + i * 0.08) end
				for _ = 1, 6 do
					local off = rng:NextUnitVector() * Vector3.new(1.4, 2.2, 1.4)
					Sparks.Emit(r.Position + off, -dir * rng:NextNumber(38, 60),
						{ Colors = AIR_COLORS, Gravity = 0, Drag = 7, Life = NumberRange.new(0.1, 0.2), Size = 0.07 })
				end
				task.wait(0.055)
			end
			-- arrivée : petite bouffée de poussière là où l'on s'arrête
			local r = moverRoot(u)
			if r then dustPuff(r.Position - Vector3.new(0, 2.7, 0), 5, dir) end
		end)
	end
end

-- ── Débris de destruction par cubes (VoxelBreak) : fabriqués LOCALEMENT, physique locale, plafond selon la qualité ──
local voxLive = 0
local TweenService = game:GetService("TweenService")
local voxProps = PhysicalProperties.new(0.4, 0.6, 0.15) -- légers : ne bousculent pas le joueur
-- Paquet serveur : { L = { {x,y,z, sx,sy,sz, rx,ry,rz} ... } (volumes arrachés, les plus gros d'abord), C = couleur hex,
-- M = matériau, V = taille des cubes, N = nombre total de cubes arrachés }. Le client remplit ces volumes d'éclats.
-- Qualité : Bas = peu d'éclats, vie courte ; Haut = beaucoup. Au-delà de 220 studs : rien (invisible de toute façon).
local VOX_PER_HIT = { [0.5] = 22, [1] = 60, [1.2] = 95 }
local VOX_LIVE = { [0.5] = 50, [1] = 150, [1.2] = 210 }
function VFX.VoxDebris(center: Vector3, power: number, pack: any)
	if type(pack) ~= "table" or type(pack.L) ~= "table" then
		return
	end
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - center).Magnitude > 220 then
		return
	end
	local qk = FXSettings.QualityK()
	local perHit = VOX_PER_HIT[qk] or 60
	local cap = VOX_LIVE[qk] or 150
	local okC, col = pcall(Color3.fromHex, tostring(pack.C))
	col = if okC then col else Color3.fromRGB(140, 130, 120)
	local okM, mat = pcall(function()
		return Enum.Material[tostring(pack.M)]
	end)
	mat = if okM and mat then mat else Enum.Material.Slate
	local voxel = math.clamp(tonumber(pack.V) or 1.5, 0.6, 8)
	-- volume total pour répartir les éclats au prorata de chaque boîte
	local total = 0
	for _, b in pack.L do
		if type(b) == "table" and type(b[4]) == "number" then
			total += b[4] * b[5] * b[6]
		end
	end
	if total <= 0 then
		return
	end
	local want = math.min(perHit, math.max(1, tonumber(pack.N) or 1))
	local life0 = if qk < 1 then 1.4 else 2.4
	local folder = VFX.Folder()
	for _, b in pack.L do
		if voxLive >= cap or want <= 0 then
			break
		end
		if type(b) ~= "table" or type(b[4]) ~= "number" then
			continue
		end
		local size = Vector3.new(b[4], b[5], b[6])
		local cf = CFrame.new(b[1], b[2], b[3]) * CFrame.fromOrientation(b[7] or 0, b[8] or 0, b[9] or 0)
		local share = math.max(1, math.floor(want * (size.X * size.Y * size.Z) / total + 0.5))
		share = math.min(share, math.ceil(size.X * size.Y * size.Z / voxel ^ 3))
		for _ = 1, share do
			if voxLive >= cap then
				break
			end
			local e = math.min(voxel, size.X, size.Y, size.Z) * (0.6 + math.random() * 0.45)
			local local_ = Vector3.new((math.random() - 0.5) * math.max(size.X - e, 0), (math.random() - 0.5) * math.max(size.Y - e, 0), (math.random() - 0.5) * math.max(size.Z - e, 0))
			local pos = cf:PointToWorldSpace(local_)
			local p = Instance.new("Part")
			p.Size = Vector3.one * e
			p.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
			p.Color = col
			p.Material = mat
			p.CanQuery, p.CanTouch, p.CastShadow = false, false, false
			p.CustomPhysicalProperties = voxProps
			p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			local away = pos - center
			away = if away.Magnitude > 0.05 then away.Unit else Vector3.yAxis
			p.AssemblyLinearVelocity = (away + Vector3.new(0, 0.6, 0)).Unit * power * (0.5 + math.random() * 0.7)
			p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14
			p.Parent = folder
			voxLive += 1
			want -= 1
			local life = life0 + math.random() * 1.0
			task.delay(life, function()
				if p.Parent then
					TweenService:Create(p, TweenInfo.new(0.45), { Transparency = 1, Size = p.Size * 0.4 }):Play()
				end
				task.delay(0.5, function()
					p:Destroy()
					voxLive -= 1
				end)
			end)
		end
	end
end

function VFX.Handle(msg: { [string]: any })
	local p = vec(msg.p)
	if not p then
		return
	end
	if msg.k == "Impact" then
		snapProxyTo(p)
	end
	local kind = msg.k
	local cardId = if type(msg.c) == "string" then msg.c else nil
	if kind == "Impact" then
		VFX.Impact(p, vec(msg.n), msg.e, tonumber(msg.r), tonumber(msg.s), cardId, tonumber(msg.z))
	elseif kind == "VoxDebris" then
		if type(msg.q) == "table" then
			VFX.VoxDebris(p, tonumber(msg.w) or 40, msg.q)
		end
	elseif kind == "Cast" then
		local d = vec(msg.d)
		if d then
			VFX.Cast(p, d, msg.e)
		end
	elseif kind == "Trigger" then
		VFX.Trigger(p, msg.e)
	elseif kind == "Bounce" then
		VFX.Bounce(p, vec(msg.n), msg.e, tonumber(msg.z))
	elseif kind == "Dmg" then
		VFX.DamageNumber(p, tonumber(msg.a) or 0, msg.e, if type(msg.t) == "string" then msg.t else nil)
	elseif kind == "Beam" then
		local d = vec(msg.d)
		if d then
			VFX.Beam(p, d, msg.e, tonumber(msg.w), cardId)
		end
	elseif kind == "Teleport" then
		local d = vec(msg.d)
		if d then
			VFX.Teleport(p, d)
		end
	elseif kind == "Dispel" then
		VFX.Dispel(p, msg.e)
	elseif kind == "TrapFire" then
		VFX.TrapFire(p, msg.e, tonumber(msg.z))
	elseif kind == "HoldBeam" then
		VFX.HoldBeam(msg)
	elseif kind == "HoldBeamEnd" then
		VFX.HoldBeamEnd(msg)
	elseif kind == "GrowStart" then
		growStart(msg)
	elseif kind == "Grow" then
		growSegment(msg)
	elseif kind == "GrowEnd" then
		growEnd(msg)
	elseif kind == "GrowElem" then
		growElem(msg)
	elseif kind == "GrowCut" then
		growCut(msg)
	elseif kind == "Ign" then
		igniteCell(msg)
	elseif kind == "IgnEnd" then
		endCell(msg)
	elseif kind == "MHit" then
		matterHit(msg)
	elseif kind == "MCoat" then
		matterCoat(msg)
	elseif kind == "TipMark" then
		tipMark(msg)
	elseif kind == "React" then
		reactLabel(msg)
	elseif kind == "ReactFX" then
		local fn = REACTION_FX[msg.n]
		if fn then
			local ok, err = pcall(fn, p, tonumber(msg.s) or 1)
			if not ok then
				warn("[Wand] effet de réaction " .. tostring(msg.n) .. " :", err)
			end
		end
	elseif kind == "MBreak" then
		matterBreak(msg)
	elseif kind == "Carve" then
		carveFx(msg)
	elseif kind == "Dash" then
		VFX.MoveDust(kind, p, vec(msg.d), msg.u)
	elseif kind == "Launch" then
		-- propulsion céleste : grosse bouffée de poussière au départ
		dustPuff(p - Vector3.new(0, 2.7, 0), 12, Vector3.zero)
	elseif kind == "Land" then
		VFX.GroundImpact(p, tonumber(msg.s) or 100)
	elseif kind == "Skid" then
		VFX.SkidTrail(p, vec(msg.d), tonumber(msg.s) or 30, msg.u)
	elseif kind == "Fizzle" then
		-- pour son propre personnage, on suit sa position locale (pas de retard réseau)
		local at = p
		if msg.u == LOCAL_USER_ID then
			local char = Players.LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				at = root.Position
			end
		end
		VFX.Fizzle(at)
	end
end

function VFX.Folder(): Folder
	return fxFolder
end

function VFX.Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "WandFX_Local"
	fxFolder.Parent = workspace
	LightPool.Init()
	Sparks.Init()
	Flipbook.Init()

	task.spawn(function()
		local zoneFolder = workspace:WaitForChild("WandZoneMarkers")
		for _, child in zoneFolder:GetChildren() do
			if child:IsA("BasePart") then
				attachZone(child)
			end
		end
		zoneFolder.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") then
				attachZone(child)
			end
		end)
		zoneFolder.ChildRemoved:Connect(function(child)
			if child:IsA("BasePart") then
				detachZone(child)
			end
		end)
	end)
	RunService.RenderStepped:Connect(updateZones)
	RunService.RenderStepped:Connect(updateStatus)
	RunService.RenderStepped:Connect(updateGrowths)
	RunService.RenderStepped:Connect(updateHoldBeams)
	RunService.RenderStepped:Connect(updateFire)

	task.spawn(function()
		local walls = workspace:WaitForChild("WandIceWalls")
		for _, child in walls:GetChildren() do
			attachIce(child)
		end
		walls.ChildAdded:Connect(attachIce)
		walls.ChildRemoved:Connect(detachIce)
	end)

	task.spawn(function()
		local projFolder = workspace:WaitForChild("WandProjectiles")
		for _, child in projFolder:GetChildren() do
			if child:IsA("BasePart") then
				attachProjectile(child)
			end
		end
		projFolder.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") then
				attachProjectile(child)
			end
		end)
	end)
	RunService.RenderStepped:Connect(updateProxies)
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(VFX._updateBody, dt) -- (défini plus bas dans ce module)
		if not ok then
			warn("[Wand] états du corps :", err)
		end
	end)
end

-- ══ ÉTATS DU CORPS (décoratifs) : un élément déclare Visuals.Body ; le serveur pose l'attribut Body<Élément> = fin ══
-- Grelottements (rotation des articulations par C0, restaurée à l'arrêt) + buée devant la bouche.
-- Seuls les personnages proches de la caméra (BODY_RANGE) sont animés, BODY_MAX au plus.
local BODY_DEF: { [string]: any } = {}
local BODY_RANGE, BODY_MAX = 80, 12
local bodyVis: { [Model]: { [string]: any } } = {}
local bodyList: { Model } = {}
local bodyPoll = 0

local function stopBody(model: Model, el: string)
	local v = bodyVis[model]
	local e = v and v[el]
	if not e then
		return
	end
	for motor, c0 in e.Motors do
		if motor.Parent then
			motor.C0 = c0 -- articulation remise EXACTEMENT comme avant
		end
	end
	v[el] = nil
	if next(v) == nil then
		bodyVis[model] = nil
	end
end

local function startBody(model: Model, el: string, def)
	local e = { Motors = {}, Seeds = {}, Next = os.clock() + rng:NextNumber(0.2, 0.6) }
	local joints = def.Shiver and def.Shiver.Joints or {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and table.find(joints, d.Name) then
			e.Motors[d] = d.C0
			e.Seeds[d] = rng:NextNumber(0, 1000)
		end
	end
	bodyVis[model] = bodyVis[model] or {}
	bodyVis[model][el] = e
	return e
end

local function updateBody(dt: number)
	local clock = os.clock()
	bodyPoll -= dt
	if bodyPoll <= 0 then
		bodyPoll = 0.25
		table.clear(bodyList)
		local camPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.zero
		local cands = {}
		for _, plr in Players:GetPlayers() do
			if plr.Character then
				table.insert(cands, plr.Character)
			end
		end
		local dummies = workspace:FindFirstChild("WandDummies")
		if dummies then
			for _, d in dummies:GetChildren() do
				table.insert(cands, d)
			end
		end
		local scored = {}
		for _, model in cands do
			local root = model:FindFirstChild("HumanoidRootPart")
			local d = root and (root.Position - camPos).Magnitude
			if d and d < BODY_RANGE then
				table.insert(scored, { model, d })
			end
		end
		table.sort(scored, function(a, b) return a[2] < b[2] end)
		for i = 1, math.min(#scored, BODY_MAX) do
			bodyList[i] = scored[i][1]
		end
		-- hors de portée / disparus : arrêt propre
		for model, v in bodyVis do
			if not model.Parent or not table.find(bodyList, model) then
				for el in v do
					stopBody(model, el)
				end
			end
		end
	end
	local now = workspace:GetServerTimeNow()
	for _, model in bodyList do
		local hum = model:FindFirstChildOfClass("Humanoid")
		for el, def in BODY_DEF do
			local untilT = hum and hum:GetAttribute("Body" .. el) or 0
			local active = hum and hum.Health > 0 and untilT > now and not (def.PauseIf and hum:GetAttribute(def.PauseIf))
			local e = bodyVis[model] and bodyVis[model][el]
			if active then
				e = e or startBody(model, el, def)
				local sh = def.Shiver
				if sh then
					-- plus fort au début, se calme dans les 3 dernières secondes
					local k = 0.45 + 0.55 * math.clamp((untilT - now) / 3, 0, 1)
					for motor, c0 in e.Motors do
						if motor.Parent then
							local sd = e.Seeds[motor]
							local amp = math.rad((if motor.Name == "Neck" then sh.NeckAmp or sh.Amp else sh.Amp) * k)
							local t = clock * sh.Freq
							motor.C0 = c0 * CFrame.Angles(math.noise(t, sd) * 2 * amp, math.noise(sd, t) * 2 * amp, math.noise(t, t * 0.5 + sd) * 2 * amp)
						end
					end
				end
				local br = def.Breath
				local head = model:FindFirstChild("Head")
				if br and head and clock >= e.Next then
					e.Next = clock + rng:NextNumber(br.Every[1], br.Every[2])
					local cf = head.CFrame
					local o = table.clone(br.Opts)
					o.Direction = (cf.LookVector + Vector3.new(0, -0.15, 0)).Unit
					o.Spread = 22
					o.Speed = NumberRange.new(br.Speed * 0.6, br.Speed)
					Sparks.Burst((cf * CFrame.new(0, -0.25, -0.7)).Position, o)
				end
			elseif e then
				stopBody(model, el)
			end
		end
	end
end

VFX._updateBody = updateBody

-- ══ VISUELS PAR ÉLÉMENT : chaque module WandShared/Elements/<Élément>/Visuals reçoit les outils ci-dessous ══
do
	local api = {
		Sparks = Sparks, LightPool = LightPool, Flipbook = Flipbook, rng = rng,
		holderPart = holderPart, visPart = visPart, popIn = popIn, fadeAway = fadeAway, tween = tween,
		shortArcs = shortArcs, emitRate = emitRate, perp = perp,
		flameStack = flameStack, flameTongue = flameTongue, -- flammes volumineuses (feu)
		Glow = function() return Ambience.Glow() end, FIRE_SPARKS = FIRE_SPARKS, SMOKE_SPARKS = SMOKE_SPARKS,
		Sound = function(name, p, pitch, vol) SoundFX.Play(name, p, pitch, vol) end,
		BarkPart = barkPart, -- écorce de Ramure (startCf, endCf, largeur, longueur, élément, durée de pousse)
		BranchStyle = branchStyle,
		Arc = function(a, b) VFX.Handle({ k = "Beam", p = a, d = b, e = "Lightning", w = 0.3, c = "LIGHTNING", j = 1 }) end,
		Opts = { SMOKE = SMOKE, FROST = FROST, ICE_FALL = ICE_FALL, DRIPS = DRIPS, VAPOR = VAPOR, MOTES = MOTES, GLINT = GLINT, CHAOS_POP = CHAOS_POP, IMPACT_LEAVES = IMPACT_LEAVES },
		CanFx = function()
			return activeFx <= MAX_ACTIVE_FX
		end,
		FxFolder = function()
			return fxFolder
		end,
	}
	local folder = ReplicatedStorage:WaitForChild("WandShared"):WaitForChild("Elements")
	for _, mod in folder:GetChildren() do
		local vm = mod:FindFirstChild("Visuals")
		if vm then
			local ok, v = pcall(function()
				return require(vm)(api)
			end)
			if ok and v then
				ELEMENT_TRAIL[mod.Name] = v.Trail
				ELEMENT_IMPACT[mod.Name] = v.Impact
				ELEMENT_PATCH[mod.Name] = v.Patch
				AMBIENT[mod.Name] = v.Ambient -- particules permanentes des arbres de cet élément
				if v.Status then
					STATUS_DEF[v.Status.Kind] = v.Status -- état infligé aux cibles (brûlure, choc, poison)
				end
				BODY_DEF[mod.Name] = v.Body -- état du corps décoratif (grelottements, buée...)
			else
				warn("[Wand] visuels de l'élément " .. mod.Name .. " en erreur :", v)
			end
		end
	end
	-- effets des RÉACTIONS entre éléments (WandShared/ReactionVisuals)
	local rvm = ReplicatedStorage.WandShared:FindFirstChild("ReactionVisuals")
	if rvm then
		local ok, v = pcall(function() return require(rvm)(api) end)
		if ok and v then
			REACTION_FX = v
		else
			warn("[Wand] visuels des réactions en erreur :", v)
		end
	end
end

return VFX

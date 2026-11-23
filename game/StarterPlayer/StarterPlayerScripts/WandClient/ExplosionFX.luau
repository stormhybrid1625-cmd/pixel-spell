--[[
	WandClient/ExplosionFX — VRAIE EXPLOSION (user 2026-11-23)
	Tout se passe DANS le rayon de l'explosion (le trou laissé dans le décor = la taille de la boule) :
	  1) BOULE DE FEU : bouffées de l'élément qui remplissent la sphère et gonflent vers l'extérieur
	  2) ONDE AU SOL : anneau de poussière qui part du centre jusqu'au bord du rayon
	  3) FUMÉE : nuage qui remplit tout le rayon, reste, se dilate et monte doucement
	  4) COLONNE (grosses explosions) : panache qui s'élève au-dessus (champignon)
	ParticleEmitter du moteur, sur une pièce invisible de la TAILLE du rayon (forme Sphère / Disque) :
	indépendant du budget des étincelles -> jamais « avalé » quand beaucoup d'effets jouent.
	Pas de flash ni de bloom saturé : LightEmission modéré, fumée mate.
]]
local ExplosionFX = {}
ExplosionFX.TimeScale = 1 -- (banc de test : 0.1 = ralenti pour capturer chaque phase)

local TEX = "rbxassetid://103763299233462" -- carré pixel du jeu (même texture que les bouffées)
local MAX_LIVE = 10
local live = 0
local folder: Folder? = nil

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "WandExplosions_Local"
	f.Parent = workspace
	folder = f
	return f
end

local function stepped(cols: { Color3 }): ColorSequence
	local kps, n = {}, #cols
	for i, c in cols do
		local a, b = (i - 1) / n, i / n
		table.insert(kps, ColorSequenceKeypoint.new(if i == 1 then 0 else a + 1e-4, c))
		table.insert(kps, ColorSequenceKeypoint.new(if i == n then 1 else b, c))
	end
	return ColorSequence.new(kps)
end

-- BUG MOTEUR : des particules émises dans la MÊME image que la création de leur émetteur ne s'affichent
-- pas (explosions « parfois invisibles »). On émet donc à l'image suivante.
local RunService = game:GetService("RunService")
local function later(e: ParticleEmitter, n: number)
	task.spawn(function()
		RunService.RenderStepped:Wait()
		if e.Parent then
			e:Emit(n)
		end
	end)
end

local function host(cf: CFrame, size: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	p.Parent = getFolder()
	return p
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX
	e.Enabled = false
	e.Rate = 0
	e.LightInfluence = 0
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	for k, v in props do
		(e :: any)[k] = v
	end
	e.TimeScale = ExplosionFX.TimeScale
	e.Parent = parent
	return e
end

-- pos : centre ; up : normale de la surface ; r : rayon d'explosion ; fx : Gigantisme (FxScale) ; P : palette de l'élément
function ExplosionFX.Spawn(pos: Vector3, up: Vector3, r: number, fx: number, P: any, quality: number?)
	if r < 2.5 or live >= MAX_LIVE then
		return
	end
	live += 1
	local q = math.clamp(quality or 1, 0.35, 1)
	r = math.min(r, 60)
	local k = math.sqrt(r / 6) -- 1 pour une boule de feu de base, ~3 pour une bombe colossale
	local core = P.Core or Color3.new(1, 0.9, 0.6)
	local mid = P.Mid or Color3.new(1, 0.5, 0.15)
	local edge = P.Edge or Color3.new(0.6, 0.15, 0.05)
	local side = if math.abs(up:Dot(Vector3.xAxis)) < 0.9 then up:Cross(Vector3.xAxis).Unit else up:Cross(Vector3.zAxis).Unit
	local upCF = CFrame.fromMatrix(pos + up * 0.3, side, up) -- disque couché sur la surface

	-- 1) BOULE DE FEU en 3 COUCHES (profondeur) : enveloppe rouge sombre derrière, corps orange, cœur jaune
	--    devant ; chaque couche a sa taille / vitesse / durée -> la boule a du relief au lieu d'un aplat
	local ballR = r * 0.55
	local ball = host(CFrame.new(pos + up * ballR * 0.45), Vector3.one * (ballR * 2))
	local dark = edge:Lerp(Color3.fromHex("2a1812"), 0.55)
	local function layer(cols, s0, s1, life, sp, z, tr0, count)
		local e = emitter(ball, {
			Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
			Color = stepped(cols),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, r * s0), NumberSequenceKeypoint.new(0.25, r * s1), NumberSequenceKeypoint.new(1, r * s1 * 0.35) }), -- gonfle puis se contracte en refroidissant
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, tr0), NumberSequenceKeypoint.new(0.5, tr0 + 0.1), NumberSequenceKeypoint.new(0.8, 0.85), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = life,
			Speed = sp, Drag = 6,
			Acceleration = up * (r * 0.5),
			ZOffset = z,
			LightEmission = 0, Brightness = 1, -- (pas de saturation blanche)
		})
		later(e, math.floor(count * q))
		return e
	end
	local outer = layer({ edge, edge, dark, dark }, 0.15, 0.3, NumberRange.new(0.5, 0.85 + 0.1 * k), NumberRange.new(r * 1.2, r * 2), 1, 0.05, 16 + 10 * k)
	local body = layer({ mid, mid:Lerp(edge, 0.35), edge, dark }, 0.12, 0.23, NumberRange.new(0.35, 0.6 + 0.08 * k), NumberRange.new(r * 0.9, r * 1.6), 2, 0.05, 20 + 12 * k)
	local hot = layer({ core:Lerp(mid, 0.25), mid:Lerp(core, 0.4), mid }, 0.08, 0.15, NumberRange.new(0.15, 0.32), NumberRange.new(r * 0.4, r * 0.9), 3, 0.1, 10 + 6 * k)
	-- POCHES DE SUIE : quelques carrés sombres DANS la boule -> volume, contraste, rendu pixel-art
	layer({ dark, Color3.fromHex("2a1d18"), Color3.fromHex("3a302b") }, 0.06, 0.11, NumberRange.new(0.3, 0.6), NumberRange.new(r * 0.6, r * 1.3), 2.5, 0.05, 5 + 4 * k)
	-- la boule « roule » encore un instant
	task.delay(0.07 / ExplosionFX.TimeScale, function()
		if body.Parent then
			body:Emit(math.floor((8 + 5 * k) * q))
			outer:Emit(math.floor((6 + 4 * k) * q))
		end
	end)
	-- DÉBRIS : morceaux sombres projetés en cloche qui retombent (une vraie bombe arrache le sol)
	local debris = emitter(ball, {
		Shape = Enum.ParticleEmitterShape.Box, EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(55, 55),
		Color = stepped({ Color3.fromHex("3b3532"), Color3.fromHex("2c2725") }),
		Size = NumberSequence.new(math.clamp(r * 0.04, 0.25, 1.6)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(r * 1.4, r * 2.6), Drag = 0.6,
		Acceleration = Vector3.new(0, -70, 0),
		RotSpeed = NumberRange.new(-300, 300),
		ZOffset = 4,
	})
	debris.Size = NumberSequence.new(math.clamp(r * 0.04, 0.25, 1.6))
	later(debris, math.floor((10 + 8 * k) * q))

	-- 2) ONDE AU SOL : poussière qui file du centre jusqu'au BORD du rayon
	local disc = host(upCF, Vector3.new(r * 0.3, 0.2, r * 0.3))
	local wave = emitter(disc, {
		Shape = Enum.ParticleEmitterShape.Disc, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward, ShapePartial = 1,
		EmissionDirection = Enum.NormalId.Top,
		Color = stepped({ Color3.fromHex("8a8078"), Color3.fromHex("6f6760"), Color3.fromHex("57514c") }),
		Size = NumberSequence.new(r * 0.04, r * 0.1),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(r * 2.2, r * 2.8), Drag = 3.2,
		SpreadAngle = Vector2.new(80, 80), -- quasi à plat
		Acceleration = up * 1.5,
	})
	wave.Orientation = Enum.ParticleOrientation.FacingCamera
	later(wave, math.floor((14 + 10 * k) * q))

	-- 3) FUMÉE qui REMPLIT tout le rayon, reste, se dilate, monte doucement
	local smokeHost = host(CFrame.new(pos + up * r * 0.3), Vector3.one * (r * 1.15)) -- (user : fumée trop grande -> réduite)
	local smoke = emitter(smokeHost, {
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		-- bouffées MOYENNES (taille plafonnée) et nombreuses sur les grosses explosions, brun-gris chaud, assez opaques
		-- (trop transparentes, elles prenaient la couleur du ciel = carrés bleutés)
		Color = stepped({ Color3.fromHex("3d3734"), Color3.fromHex("4a4440"), Color3.fromHex("57524e"), Color3.fromHex("66615d") }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, math.min(r * 0.06, 3.5)), NumberSequenceKeypoint.new(1, math.min(r * 0.13, 7)) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.12), NumberSequenceKeypoint.new(0.65, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.4, 2.2 + 0.4 * k),
		Speed = NumberRange.new(r * 0.3, r * 0.65), Drag = 2.2, -- part VERS LE BORD du rayon, ne reste pas au centre
		Acceleration = up * (1.2 + 0.6 * k),
		RotSpeed = NumberRange.new(-15, 15),
		LightEmission = 0,
	})
	-- la fumée arrive APRÈS le feu (on voit d'abord la boule de feu), et reste derrière elle (ZOffset)
	task.delay(0.3 / ExplosionFX.TimeScale, function()
		if smoke.Parent and r >= 9 then -- (user : sorts de base = pas de fumée)
			smoke:Emit(math.floor((r * 0.55) * q)) -- r 11 -> 6 ; r 60 -> 33 (petites bouffées) -- (user : encore trop -> divisé par ~2,5)
		end
	end)

	-- 4) COLONNE (grosses explosions) : panache qui s'élève au-dessus du nuage
	local colHost: Part? = nil
	if r >= 14 then
		colHost = host(CFrame.new(pos + up * r * 0.5), Vector3.one * (r * 0.5))
		local column = emitter(colHost :: Part, {
			Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(18, 18),
			Color = stepped({ edge, Color3.fromHex("4b4542"), Color3.fromHex("5e5956"), Color3.fromHex("706c69") }),
			Size = NumberSequence.new(math.min(r * 0.07, 4), math.min(r * 0.15, 8)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.7, 0.4), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(2.4, 3.8),
			Speed = NumberRange.new(r * 0.7, r * 1.1), Drag = 1.1,
			Acceleration = up * 2,
		})
		column.Rate = math.floor((4 + r * 0.35) * q)
		column.Enabled = true
		task.delay(0.5 / ExplosionFX.TimeScale, function()
			column.Enabled = false
		end)
	end

	task.delay((6 + 0.6 * k) / ExplosionFX.TimeScale, function()
		ball:Destroy()
		disc:Destroy()
		smokeHost:Destroy()
		if colHost then
			colHost:Destroy()
		end
		live -= 1
	end)
end

return ExplosionFX

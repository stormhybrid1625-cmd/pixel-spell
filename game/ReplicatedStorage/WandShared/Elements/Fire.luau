-- FEU : brûle les cibles (dégâts sur la durée), enflamme herbe et bois, s'étend.
return {
	Infusion = true,
	Palette = {
		Label = "Feu",
		Core = Color3.fromHex("fff3a1"), Mid = Color3.fromHex("ff8f26"), Edge = Color3.fromHex("c8301c"),
		Rotation = 0,
		Accel = Vector3.new(0, 16, 0), -- les braises montent
		Textures = { Particle = "rbxassetid://0", Trail = "rbxassetid://0", Beam = "rbxassetid://0", Flash = "rbxassetid://0" },
	},
	Sparks = { Gravity = 1, Drag = 1.1, Bounce = 0.35, Life = NumberRange.new(0.5, 1.3), Speed = 1.1, Crackle = 0.08 },
	Branch = { Tint = "5e463a", Bark = { "2a221d", "221b17", "30261f" }, Core = "ff8f26", Flame = true, Leaf = { "ffcf4a", "ff8f26" }, LeafChance = 0.15 },
	Affinity = { Nature = 2, Ice = 1.8, Toxic = 1.5, Steel = 0.4, Earth = 0.2, Fire = 0 },
	-- brûlure : 2 dégâts / s pendant 2 s (x Prolongation)
	-- EFFET SUR LA CIBLE (lu par Combat) : BRÛLURE qui se CUMULE (dégâts par tick = Damage x niveaux)
	Status = { Kind = "Dot", Attr = "Burning", DotType = "Burn", Damage = 2, Tick = 0.5, Duration = 2, MaxStacks = 3 },
	-- COMPORTEMENTS de zone / matière (lus par ZoneService et MatterService)
	Behavior = { PatchFalls = true, IgnitesMatter = true },
	-- CAMÉRA : secousse chaude, moyenne
	Camera = { Freq = 9, Rot = 1, Pos = 0.25, Decay = 1.6 },
	-- ÉCRAN : flammes qui lèchent le bas et les côtés quand le joueur BRÛLE (attribut Burning)
	Screen = {
		Status = "Burning",
		Images = { "rbxassetid://99401422285746", "rbxassetid://111998283951267" }, Fps = 7,
		Tint = Color3.fromHex("ffd9b0"), Saturation = 0.05, Contrast = 0.04, Creep = 0.18,
	},
	Sound = {
		-- sons des ÉTATS infligés aux cibles (début / boucle / fin) — lus par SoundFX.Status
		Status = { Burning = { Loop = "Loop.Burn" } },
		Profile = { Cast = "Cast.Fire", Travel = "Travel.Fire", Impact = "Impact.Fire", Bounce = "Bounce.Soft", Tail = "Tail.Fire" },
		Grow = { Start = "Grow.StartFire", Step = "Grow.StepFire", Loop = "Loop.FireRing", Persist = true, End = "Zone.Extinguish" },
		Patch = { Spawn = "Zone.Ignite", Loop = "Loop.FireRing", Tick = "Patch.FireGust", TickEvery = 1.1, End = "Zone.Extinguish" }, -- bouffées : le brasier ronfle
	},
}

-- TOXIQUE : empoisonne (dégâts sur la durée), ronge nature et métal, explose au contact du feu.
return {
	Infusion = true,
	Palette = {
		Label = "Toxique",
		Core = Color3.fromHex("e8ffb0"), Mid = Color3.fromHex("7bdc2a"), Edge = Color3.fromHex("1d5419"),
		Rotation = 0,
		Accel = Vector3.new(0, 6, 0), -- les vapeurs montent
		Textures = { Particle = "rbxassetid://0", Trail = "rbxassetid://0", Beam = "rbxassetid://0", Flash = "rbxassetid://0" },
	},
	Sparks = { Gravity = -0.12, Drag = 2.2, Bounce = 0, Life = NumberRange.new(0.6, 1.4), Speed = 0.5, Crackle = 0 },
	Branch = { Tint = "7f9e60", Bark = { "1d3a12", "28501a" }, Core = "7bdc2a", Leaf = { "b6ff5a", "7bdc2a" }, LeafChance = 0.25 },
	Affinity = { Nature = 1.8, Steel = 1.5, Earth = 0.6, Ice = 0.5, Fire = 0.5, Toxic = 0 },
	-- poison : 2 dégâts / s pendant 2 s (x Prolongation)
	-- EFFET SUR LA CIBLE : POISON qui se cumule (5 niveaux, 4 s) ; la cible empoisonnée subit +10 % de TOUS les dégâts ;
	-- le poison s'ARRÊTE tant que la cible est gelée (réaction Glace)
	Status = { Kind = "Dot", Attr = "Poisoned", DotType = "Poison", Damage = 1, Tick = 0.5, Duration = 4, MaxStacks = 5,
		Vulnerable = 0.10, PausedBy = "Frozen",
		-- RÉGÉNÉRATION : vie seulement, ralentie (x0.5), long (poison + After s)
		Regen = { Hp = 0.5, After = 3 } },
	Behavior = { PatchDurationMult = 1.5 },
	-- CAMÉRA : secousse molle, ondulante
	Camera = { Freq = 5, Rot = 0.7, Pos = 0.15, Decay = 1.4 },
	-- ÉCRAN : bave verte qui coule des bords quand le joueur est EMPOISONNÉ (attribut Poisoned)
	Screen = {
		Status = "Poisoned",
		Images = { "rbxassetid://107325678308512" }, Breathe = 2.2,
		Tint = Color3.fromHex("d4ffb8"), Saturation = 0, Contrast = 0.03, Creep = 0.2,
	},
	Sound = {
		-- sons des ÉTATS infligés aux cibles (début / boucle / fin) — lus par SoundFX.Status
		Status = { Poisoned = { Start = "Status.PoisonIn", Loop = "Loop.Poisoned" } },
		Profile = { Cast = "Cast.Toxic", Travel = "Travel.Toxic", Impact = "Impact.Toxic", Bounce = "Bounce.Soft", Tail = "Tail.Toxic" },
		Grow = { Start = "Grow.StartToxic", Step = "Grow.StepToxic", Loop = "Loop.TreeToxic", Persist = true, Tick = "Tick.Drop", Every = { 0.4, 0.9 }, End = "Tail.Toxic" },
		Patch = { Spawn = "Patch.ToxicSpill", Loop = "Loop.Gas", Tick = "Tick.Drop", TickEvery = 0.6, End = "Tail.Toxic" },
	},
}

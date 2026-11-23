-- FOUDRE : électrocute (immobilise un court instant), se propage par le métal, peut enflammer la nature.
return {
	Infusion = true,
	Palette = {
		Label = "Foudre",
		Core = Color3.fromHex("ffffff"), Mid = Color3.fromHex("ffe94f"), Edge = Color3.fromHex("3a6cff"),
		Rotation = 45,
		Accel = Vector3.new(0, 0, 0),
		Textures = { Particle = "rbxassetid://0", Trail = "rbxassetid://0", Beam = "rbxassetid://0", Flash = "rbxassetid://0" },
	},
	Sparks = { Gravity = 0.2, Drag = 3, Bounce = 0.3, Life = NumberRange.new(0.12, 0.3), Speed = 1.6, Crackle = 0.25 },
	Branch = { Tint = "6c789c", Bark = { "1c2032", "23283c" }, Core = "ffe94f", Flicker = true },
	Affinity = { Steel = 2, Toxic = 1.3, Ice = 1.2, Nature = 1, Earth = 0.3, Lightning = 0 },
	-- choc : immobilisé 0,35 s, état visible "électrocuté" 0,9 s (x Prolongation)
	-- EFFET SUR LA CIBLE : choc (immobilise 0,35 s, au plus toutes les 1,5 s) + SAUT vers 1 cible proche à 60 %
	Status = { Kind = "Shock", Stun = 0.35, StunCooldown = 1.5, Attr = "Shocked", Show = 0.9,
		Chain = { Range = 8, Mult = 0.6, Count = 1, Spreads = { "Toxic" } },
		-- RÉGÉNÉRATION : vie ET mana bloqués, court (choc + After s)
		Regen = { Hp = 0, Mana = 0, After = 1 } },
	Behavior = { IgniteChance = 0.25, ConductsInSteel = true },
	-- CAMÉRA : secousse haute fréquence, saccadée
	Camera = { Freq = 35, Rot = 0.8, Pos = 0.2, Decay = 3.5 },
	-- ÉCRAN : arcs qui crépitent sur les bords quand le joueur est ÉLECTROCUTÉ (attribut Shocked)
	Screen = {
		Status = "Shocked",
		Images = { "rbxassetid://78206042543848", "rbxassetid://132066229491294" }, Fps = 14,
		Tint = Color3.fromHex("fff8d8"), Saturation = 0, Contrast = 0.15, Creep = 0.12,
	},
	Sound = {
		-- sons des ÉTATS infligés aux cibles (début / boucle / fin) — lus par SoundFX.Status
		Status = { Shocked = { Loop = "Loop.Shock" } },
		Profile = { Cast = "Cast.Lightning", Travel = "Travel.Spark", Impact = "Impact.Lightning", Bounce = "Bounce.Arcane", Beam = "Beam.Lightning", Tail = "Tail.Lightning" },
		Grow = { Start = "Grow.StartZap", Step = "Grow.StepZap", Loop = "Loop.TreeZap", Persist = true, End = "Grow.EndZap" },
		Patch = { Spawn = "Patch.ThunderSpawn", Loop = "Loop.Shock", Tick = "Hit.Lightning", TickEvery = 0.9, End = "Grow.EndZap" },
	},
}

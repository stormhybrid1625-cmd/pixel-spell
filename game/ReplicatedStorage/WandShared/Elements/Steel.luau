-- ACIER : plus d'infusion joueur. Reste l'élément de la MATIÈRE métallique (affinités) + sorts internes.
return {
	Infusion = false,
	Palette = {
		Label = "Acier",
		Core = Color3.fromHex("ffffff"), Mid = Color3.fromHex("c9d2e6"), Edge = Color3.fromHex("5a6480"),
		Rotation = 0,
		Accel = Vector3.new(0, -30, 0),
		SparkColors = { Color3.fromHex("fff3a1"), Color3.fromHex("ff9a2e"), Color3.fromHex("8a2a14") },
		Textures = { Particle = "rbxassetid://0", Trail = "rbxassetid://0", Beam = "rbxassetid://0", Flash = "rbxassetid://0" },
	},
	Sparks = { Gravity = 1.3, Drag = 0.8, Bounce = 0.5, Life = NumberRange.new(0.25, 0.6), Speed = 1.3, Crackle = 0 },
	Branch = { Tint = "b4bccc", Bark = { "3a4152", "454d60", "323848" }, Core = "c9d2e6" },
	Affinity = { Nature = 1.5, Ice = 1.5, Earth = 1, Steel = 0.5 },
	Status = { Kind = "Dot", Attr = "Bleeding", DotType = "Bleed", Damage = 1, Tick = 0.5, Duration = 2.5, MaxStacks = 1 },
	Sound = {
		Profile = { Cast = "Cast.Steel", Travel = "Travel.Saw", Impact = "Impact.Steel", Bounce = "Bounce.Metal" },
		Grow = { Start = "Grow.StartSteel", Step = "Grow.StepSteel", Tick = "Tick.Metal", Every = { 0.8, 1.6 }, End = "Grow.End" },
	},
}

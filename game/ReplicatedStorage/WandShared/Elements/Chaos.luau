-- CHAOS : plus d'infusion joueur. Reste pour l'ORBE DU CHAOS et l'effet « Faux » (couleurs qui clignotent).
return {
	Infusion = false,
	Palette = {
		Label = "Chaos",
		Core = Color3.fromHex("f4ff6b"), Mid = Color3.fromHex("ff3ccf"), Edge = Color3.fromHex("3a1150"),
		Rotation = 0,
		Accel = Vector3.new(0, 0, 0),
		Flicker = { Color3.fromHex("f4ff6b"), Color3.fromHex("ff3ccf"), Color3.fromHex("3cf2ff"), Color3.fromHex("ff3ccf"), Color3.fromHex("3a1150") },
		Textures = { Particle = "rbxassetid://0", Trail = "rbxassetid://0", Beam = "rbxassetid://0", Flash = "rbxassetid://0" },
	},
	Sparks = { Gravity = 0.6, Drag = 1.5, Bounce = 0.7, Life = NumberRange.new(0.4, 1), Speed = 1.3, Crackle = 0.3 },
	Branch = { Tint = "9a5aa8", Bark = { "3a1150", "2a0b3c" }, Core = "ff3ccf", Flicker = true },
	Affinity = {}, -- imprévisible : MatterService tire 0,5 à 2 à chaque coup
	RandomAffinity = true,
	Sound = {
		Profile = { Cast = "Cast.Chaos", Travel = "Travel.Chaos", Impact = "Impact.Chaos", Bounce = "Bounce.Chaos", Tail = "Tail.Chaos" },
		Grow = { Start = "Grow.StartChaos", Step = "Grow.StepChaos", Loop = "Loop.TreeChaos", Persist = true, End = "Tail.Chaos" },
	},
}

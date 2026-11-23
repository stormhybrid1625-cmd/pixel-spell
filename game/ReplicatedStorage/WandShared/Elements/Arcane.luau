-- ARCANE : élément NEUTRE PAR DÉFAUT des sorts non infusés (pas de carte d'infusion). Force pure : 1 partout.
return {
	Infusion = false,
	Palette = {
		Label = "Arcane",
		Core = Color3.fromHex("fbe8ff"), Mid = Color3.fromHex("c56bff"), Edge = Color3.fromHex("5a2a9e"),
		Rotation = 0,
		Accel = Vector3.new(0, 0, 0),
		Textures = { Particle = "rbxassetid://0", Trail = "rbxassetid://0", Beam = "rbxassetid://0", Flash = "rbxassetid://0" },
	},
	Sparks = { Gravity = 0.25, Drag = 2.2, Bounce = 0.45, Life = NumberRange.new(0.35, 0.8), Speed = 1, Crackle = 0 },
	Branch = { Tint = "8c74b8", Bark = { "2b1846", "3a2160" }, Core = "c56bff" },
	Affinity = {},
	Sound = {
		Profile = { Cast = "Cast.Arcane", Travel = "Travel.Arcane", Impact = "Impact.Arcane", Bounce = "Bounce.Arcane" },
		Grow = { Start = "Grow.StartArcane", Step = "Grow.StepArcane", Loop = "Loop.TreeArcane", Persist = true, End = "Grow.End" },
	},
}

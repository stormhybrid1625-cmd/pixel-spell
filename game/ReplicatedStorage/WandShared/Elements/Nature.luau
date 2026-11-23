-- NATURE : entrave (racines), forte contre la pierre ; matière végétale.
return {
	Infusion = true,
	Palette = {
		Label = "Nature",
		Core = Color3.fromHex("e9ffb8"), Mid = Color3.fromHex("6fbf3a"), Edge = Color3.fromHex("3b2614"),
		Rotation = 0,
		Accel = Vector3.new(0, -10, 0),
		SparkColors = { Color3.fromHex("c8f27a"), Color3.fromHex("6fbf3a"), Color3.fromHex("2f6b1f") },
		Textures = { Particle = "rbxassetid://0", Trail = "rbxassetid://0", Beam = "rbxassetid://0", Flash = "rbxassetid://0" },
	},
	Sparks = { Gravity = 0.5, Drag = 2.5, Bounce = 0.2, Life = NumberRange.new(0.6, 1.4), Speed = 0.7, Crackle = 0 }, -- feuilles qui planent
	Branch = { Bark = { "443c35", "4d443c", "3c352f" }, Tint = "c9b49a", Leaf = { "6fbf3a", "8fd94a", "4e9a2a" }, LeafChance = 0.45 },
	Affinity = { Earth = 1.6, Toxic = 1.2, Ice = 0.8, Fire = 0.5, Steel = 0.5, Nature = 0.5 },
	-- racines : vitesse x0,3 pendant 0,6 s
	-- EFFET SUR LA CIBLE : racines qui ralentissent ; 3 coups en 3 s = ENRACINÉ 1 s (+50 % si la cible est empoisonnée : pourriture)
	Status = { Kind = "Chill", SlowFactor = 0.3, Duration = 0.6, BuildHits = 3, BuildWindow = 3, LockTime = 1, LockImmune = 1.5, LockAttr = "Rooted",
		LockTimeMultIf = { Toxic = 1.5 } },
	Behavior = {},
	-- CAMÉRA : secousse lente et lourde (le sol bouge)
	Camera = { Freq = 4, Rot = 1.3, Pos = 0.35, Decay = 1.2 },
	-- ÉCRAN : ronces et feuilles qui poussent depuis les coins quand le joueur est ENTRAVÉ (racines)
	Screen = {
		Images = { "rbxassetid://100138852221003" }, Breathe = 1,
		Tint = Color3.fromHex("dcffcc"), Saturation = 0, Contrast = 0.02, Creep = 0.3, Rest = 1.1, Opacity = 0.85,
	},
	Sound = {
		-- sons des ÉTATS infligés aux cibles (début / boucle / fin) — lus par SoundFX.Status
		Status = { Rooted = { Start = "Status.RootGrab", Loop = "Loop.Rooted", End = "Status.RootRelease" } },
		Profile = { Cast = "Cast.Nature", Travel = "Travel.Nature", Impact = "Impact.Nature", Bounce = "Bounce.Soft" },
		Grow = { Start = "Grow.Start", Step = "Grow.Step", Tick = "Tick.Leaves", Every = { 0.6, 1.4 }, End = "Grow.End" },
		Patch = { Spawn = "Patch.LeafSpawn", Tick = "Tick.Leaves", TickEvery = 0.9, End = "Patch.LeafEnd" }, -- tapis de feuilles : aucun son de bois/branche
	},
}

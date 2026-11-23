-- GLACE : ralentit les cibles, éteint le feu, givre les surfaces.
return {
	Infusion = true,
	Palette = {
		Label = "Glace",
		Core = Color3.fromHex("f0fdff"), Mid = Color3.fromHex("8fe3ff"), Edge = Color3.fromHex("2f7fd6"),
		Rotation = 45, -- éclats en losange
		Accel = Vector3.new(0, -40, 0), -- les éclats retombent
		Textures = { Particle = "rbxassetid://0", Trail = "rbxassetid://0", Beam = "rbxassetid://0", Flash = "rbxassetid://0" },
	},
	Sparks = { Gravity = 1.6, Drag = 0.6, Bounce = 0.6, Life = NumberRange.new(0.5, 1.1), Speed = 1, Crackle = 0 },
	Branch = { Tint = "9fe2ff", Bark = { "3f8fb8", "4a9fc8", "357fa6" }, Core = "bff2ff", CoreTransparency = 0.6, Transparency = 0.15 },
	Affinity = { Fire = 2, Lightning = 1.2, Toxic = 1, Nature = 0.8, Steel = 0.7, Earth = 0.4, Ice = 0 },
	-- gel : vitesse x0,5 pendant 1,5 s
	-- EFFET SUR LA CIBLE : ralenti, et 3 coups en 3 s = GEL complet 1,2 s (puis 2 s d'immunité au gel)
	Status = { Kind = "Chill", SlowFactor = 0.55, Duration = 1.5, BuildHits = 3, BuildWindow = 3, LockTime = 1.2, LockImmune = 2, LockAttr = "Frozen",
		-- RÉGÉNÉRATION naturelle (pas les soins) pendant l'effet + After s : vie x0.5, mana BLOQUÉ
		Regen = { Hp = 0.5, Mana = 0, After = 2 },
		-- ÉTAT DU CORPS (décoratif : grelottements, buée — Visuals.Body) : attribut Body<Élément> = fin (ServerTime) ;
		-- même durée que le malus de régénération ; un coup de ces éléments l'arrête net (réchauffé)
		Body = true, BodyClearedBy = { Fire = true } },
	Behavior = { PatchSticksToWalls = true, Extinguishes = true },
	-- CAMÉRA : secousse sèche et courte
	Camera = { Freq = 22, Rot = 0.6, Pos = 0.12, Decay = 3 },
	-- ÉCRAN : givre qui envahit les bords quand le joueur est GELÉ (ralenti par la glace)
	Screen = {
		Images = { "rbxassetid://136132785116825" }, Breathe = 0.8,
		Tint = Color3.fromHex("bfe3ff"), Saturation = -0.12, Contrast = 0.06, Creep = 0.3, Rest = 1.0, Opacity = 0.97,
	},
	Sound = {
		-- sons des ÉTATS infligés aux cibles (début / boucle / fin) — lus par SoundFX.Status
		Status = { Frozen = { Start = "Status.Freeze", Loop = "Loop.Frozen", End = "Status.Thaw" } },
		Profile = { Cast = "Cast.Ice", Travel = "Travel.Ice", Impact = "Impact.Ice", Bounce = "Bounce.Ice", Tail = "Tail.Ice" },
		Grow = { Start = "Grow.StartIce", Step = "Grow.StepIce", Tick = "Tick.Drip", Every = { 0.18, 0.5 }, End = "Zone.IceBreak" },
		Patch = { Spawn = "Patch.FrostSpread", Loop = "Loop.FrostPatch", Tick = "Patch.FrostTick", TickEvery = 1.1, End = "Patch.FrostMelt" },
	},
}

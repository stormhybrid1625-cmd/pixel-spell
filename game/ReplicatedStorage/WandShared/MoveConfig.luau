-- MoveConfig — base player movement (course / dash). Shared client + server.
-- Tuning lives here only. Speeds are multiples of the humanoid's base WalkSpeed.
return {
	SprintMult = 2.9, -- course : vitesse x2,9 (marche 9 -> course 26, user 2026-11-23 ; avant 24) ; lancer un sort arrête la course
	-- (marche de base = StarterPlayer.CharacterWalkSpeed = 9, user 2026-11-23 ; avant 11)

	DashDistance = 19, -- dash : ~19 studs, rapide (pas d'invincibilité)
	DashTime = 0.3,
	DashCooldown = 2,

	-- animations (R6) : marche = remplace la marche par défaut ; course = jouée pendant la course.
	-- Vitesse de lecture = vitesse réelle / Ref (1,0 quand on avance à Ref studs/s) : pieds qui ne glissent pas.
	WalkAnimId = "rbxassetid://92368124125158",
	RunAnimId = "rbxassetid://108035494281737",
	-- moments où chaque pied touche le sol dans le cycle (0..1), mesurés sur les animations :
	-- un pas est joué quand l'animation passe ce repère -> rythme parfaitement régulier
	WalkSteps = { 0.43, 0.93 },
	RunSteps = { 0.02, 0.52 },
	WalkAnimRef = 10.6, -- marche 9 -> lecture 0,85 (même cadence de pas qu'avant la baisse de vitesse)
	RunAnimRef = 24,

	StepRange = 70, -- bruits de pas / poussière des joueurs à moins de 70 studs
	-- PROPULSION CÉLESTE (MoveAPI) : une propulsion d'au moins CelestialSpeed studs/s envoie le
	-- personnage en ragdoll dans les airs ; il se relève GetUpDelay s après avoir touché le sol
	CelestialSpeed = 80, -- MoveAPI.Kick : puissance < 80 = RECUL AU SOL, >= 80 = PROPULSION CÉLESTE
	GetUpDelay = 0.7,
	RagdollMaxTime = 6, -- sécurité : relevé forcé
	-- RECUL AU SOL (MoveAPI.Propel) : poussé violemment en arrière sans quitter le sol, freine sur ses
	-- jambes. Durée fixe ; distance ~ vitesse x SkidTime / 2 (ex. 40 studs/s -> ~12 studs)
	SkidTime = 0.6,
	SkidMax = 80, -- vitesse max du recul au sol

	Keys = { Sprint = Enum.KeyCode.LeftShift, Dash = Enum.KeyCode.Q },

	AnimRange = 120, -- animations procédurales des joueurs à moins de 120 studs (12 max)
	AnimMax = 12,
}

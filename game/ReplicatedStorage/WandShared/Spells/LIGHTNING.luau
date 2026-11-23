-- LIGHTNING — Éclair (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "LIGHTNING", Name = "Éclair", Short = "EC", Type = "Projectile", Element = "Lightning",
		Mana = 38, CastDelay = 0.6, Desc = "Frappe instantanément, puis saute vers 3 cibles proches. Choc : immobilise 0,35 s.",
		Proj = proj({ Damage = 12, Instant = true, Range = 25, Chain = 3, Size = 0.5 }) }
	card.Order = 41 -- position dans le grimoire
	card.Family = "Beam" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Cast = false, Beam = "Beam.Lightning", Impact = "Impact.Lightning" }
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { Beam = "Lightning" }
	return card
end

-- LASER — Rayon (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "LASER", Name = "Rayon", Short = "RA", Type = "Projectile", Element = "Arcane",
		Mana = 12, CastDelay = 0.12, Desc = "Rayon instantané qui transperce jusqu'à 3 cibles alignées.",
		Proj = proj({ Damage = 12, Instant = true, Range = 80, Pierce = 3, Size = 0.6 }) }
	card.Order = 42 -- position dans le grimoire
	card.Family = "Beam" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Cast = false, Beam = "Beam.Laser", Impact = "Impact.Arcane" }
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { Beam = "Laser" }
	return card
end

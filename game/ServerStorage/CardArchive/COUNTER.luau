-- COUNTER — Contre-sort (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "COUNTER", Name = "Contre-sort", Short = "CS", Type = "Projectile", Element = "Arcane",
		Mana = 20, CastDelay = 0.1, Desc = "Projectile rapide qui efface tous les projectiles ennemis dans un rayon de 8 là où il s'arrête.",
		Proj = proj({ Damage = 0, Speed = 140, Lifetime = 0.5, Size = 0.5, Zone = { Kind = "Dispel", Radius = 8, Duration = 0.2 } }) }
	card.Order = 54 -- position dans le grimoire
	card.Family = "Projectile" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Cast = "Cast.Snap", Travel = "Travel.Spark", Impact = false }
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { TrailSparks = 20 }
	return card
end

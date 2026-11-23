-- SPARK_BOLT — Étincelle (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "SPARK_BOLT", Name = "Étincelle", Short = "ET", Type = "Projectile", Element = "Arcane",
		Mana = 5, CastDelay = 0.05, Desc = "Petit trait d'arcane rapide et peu coûteux.",
		Proj = proj({ Damage = 6, Speed = 150, Lifetime = 0.9, Size = 0.6, Spread = 1 }) }
	card.Order = 1 -- position dans le grimoire
	card.Family = "Projectile" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Travel = "Travel.Spark" }
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { TrailSparks = 8 }
	return card
end

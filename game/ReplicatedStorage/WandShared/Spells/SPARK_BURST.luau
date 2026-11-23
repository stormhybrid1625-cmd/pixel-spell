-- SPARK_BURST — Gerbe d'étincelles (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "SPARK_BURST", Name = "Gerbe d'étincelles", Short = "GE", Type = "Projectile", Element = "Arcane",
		Mana = 12, CastDelay = 0.08, Copies = 6,
		Desc = "Crache 6 petites étincelles en éventail qui rebondissent une fois. Idéal pour le volume.",
		Proj = proj({ Damage = 3, Speed = 120, Lifetime = 0.6, Size = 0.4, Bounces = 1, Spread = 4 }) }
	card.Order = 5 -- position dans le grimoire
	card.Family = "Projectile" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Travel = "Travel.Spark" }
	return card
end

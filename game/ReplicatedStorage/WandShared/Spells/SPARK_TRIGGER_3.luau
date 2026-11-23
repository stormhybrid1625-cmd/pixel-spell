-- SPARK_TRIGGER_3 — Étincelle à triple déclencheur (Sort à charge (déclencheur))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "SPARK_TRIGGER_3", Name = "Étincelle à triple déclencheur", Short = "E3", Type = "Trigger", Element = "Arcane",
		Mana = 22, Recharge = 0.2, CastDelay = 0.2, Desc = "À l'impact, libère les 3 cartes suivantes.",
		Proj = proj({ Damage = 5, Speed = 150, Lifetime = 0.9, Size = 0.6, Spread = 1 }),
		Trigger = { Kind = "Hit", Draw = 3 } }
	card.Order = 10 -- position dans le grimoire
	card.Family = "Projectile" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Travel = "Travel.Spark" }
	return card
end

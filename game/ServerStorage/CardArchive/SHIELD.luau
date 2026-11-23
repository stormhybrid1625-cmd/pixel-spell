-- SHIELD — Bouclier (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "SHIELD", Name = "Bouclier", Short = "BC", Type = "Projectile", Element = "Ice",
		Mana = 40, CastDelay = 0.35, Recharge = 0.4, Desc = "Bouclier de 2,5 s qui te suit et détruit les projectiles ennemis qui y entrent.",
		Proj = proj({ Damage = 0, Self = true, Zone = { Kind = "Shield", Radius = 6, Duration = 2.5, Follow = true } }) }
	card.Order = 53 -- position dans le grimoire
	card.Family = "Self" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Cast = false }
	return card
end

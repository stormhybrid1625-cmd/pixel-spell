-- DURATION_PLUS — Prolongation (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "DURATION_PLUS", Name = "Prolongation", Short = "D>", Type = "Modifier",
		Mana = 29, CastDelay = 0.12, Desc = "Durée x2 : les projectiles volent deux fois plus longtemps avant d'expirer (pas les rayons) ; zones, murs, arbres et pièges restent deux fois plus longtemps ; brûlure, poison et saignement durent deux fois plus longtemps.",
		Mod = { DurationMult = 2, LifetimeMult = 2 } }
	card.Order = 19 -- position dans le grimoire
	return card
end

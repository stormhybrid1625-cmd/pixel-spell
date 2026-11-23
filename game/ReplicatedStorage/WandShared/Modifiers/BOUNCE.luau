-- BOUNCE — Rebond (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "BOUNCE", Name = "Rebond", Short = "RB", Type = "Modifier",
		Mana = 6, Desc = "+3 rebonds sur les surfaces. Rayons : portée x1,5 pour les rebonds.", Mod = { BouncesAdd = 3, LifetimeMult = 1.5, RangeMult = 1.5 } }
	card.Order = 24 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

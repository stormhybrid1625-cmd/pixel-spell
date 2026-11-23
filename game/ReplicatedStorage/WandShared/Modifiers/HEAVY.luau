-- HEAVY — Lest (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "HEAVY", Name = "Lest", Short = "LT", Type = "Modifier",
		Mana = 4, Desc = "Forte gravité, dégâts x1,4, durée de vie x1,5. Ramure : pousse plus bas, étalée au ras du sol. Rayons : portée x0,7, dégâts x1,4.", Mod = { GravityAdd = 1, DamageMult = 1.4, LifetimeMult = 1.5, RangeMult = 0.7 } }
	card.Order = 23 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Procedural", "Beam" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

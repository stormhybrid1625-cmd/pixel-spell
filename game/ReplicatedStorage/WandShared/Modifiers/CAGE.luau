-- CAGE — Cage (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "CAGE", Name = "Cage", Short = "CG", Type = "Modifier", Category = "Procedural",
		Mana = 55, Recharge = 0.2, CastDelay = 0.3,
		Desc = "Sorts procéduraux : la matière vise l'ennemi le plus proche (position en direct) et l'ENCERCLE de tous les côtés en barreaux croisés, puis se referme en dôme. Toujours solide.",
		Mod = { Cage = "Enemy" } }
	card.Order = 50 -- position dans le grimoire
	card.AppliesTo = { "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

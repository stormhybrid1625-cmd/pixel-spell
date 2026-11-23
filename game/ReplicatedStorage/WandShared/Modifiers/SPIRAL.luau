-- SPIRAL — Spirale (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "SPIRAL", Name = "Spirale", Short = "SP", Type = "Modifier",
		Mana = 4, Desc = "Trajectoire en spirale autour de l'axe de tir. Sorts procéduraux : toutes les branches poussent en hélice autour d'un même axe. Cumulable : chaque exemplaire élargit la spirale.", Mod = { Trajectory = "Spiral", SpiralAdd = 1 } }
	card.Order = 22 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

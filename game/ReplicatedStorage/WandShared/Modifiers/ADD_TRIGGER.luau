-- ADD_TRIGGER — Ajout de déclencheur (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "ADD_TRIGGER", Name = "Ajout de déclencheur", Short = "+T", Type = "Modifier",
		Mana = 10, CastDelay = 0.08, Desc = "Le prochain projectile devient un déclencheur : à l'impact, il libère la carte qui le suit.",
		Mod = { AddTrigger = table.freeze({ Kind = "Hit", Draw = 1 }) } }
	card.Order = 31 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

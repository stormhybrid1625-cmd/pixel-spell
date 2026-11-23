-- BRANCH_PLUS — Élongation (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "BRANCH_PLUS", Name = "Élongation", Short = "EL", Type = "Modifier", Category = "Procedural",
		Mana = 18, CastDelay = 0.15,
		Desc = "Sorts procéduraux : la matière pousse 60 % plus longtemps et va donc plus LOIN, un peu plus lentement (-15 %). Cumulable 3 fois.",
		Mod = { GrowTimeMult = 1.6, GrowSpeedMult = 0.85 } }
	card.Order = 49 -- position dans le grimoire
	card.AppliesTo = { "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

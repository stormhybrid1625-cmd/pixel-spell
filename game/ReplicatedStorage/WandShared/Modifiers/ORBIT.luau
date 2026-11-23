-- ORBIT — Orbite (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "ORBIT", Name = "Orbite", Short = "OR", Type = "Modifier",
		Mana = 10, Desc = "Les sorts qui suivent tournent autour de toi au lieu de partir (durée x3). Sorts procéduraux : la matière se construit en CAGE autour de toi, sans jamais te toucher.", Mod = { Trajectory = "Orbit", LifetimeMult = 3 } }
	card.Order = 56 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

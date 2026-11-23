-- SPEED_PLUS — Accélération (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "SPEED_PLUS", Name = "Accélération", Short = "V+", Type = "Modifier",
		Mana = 24, CastDelay = 0.04, Desc = "Vitesse x1,5. Sorts procéduraux : la matière pousse 30 % plus VITE (même portée). Rayons : portée x1,5. Cumulable 3 fois.", Mod = { SpeedMult = 1.5 } }
	card.Order = 15 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Procedural", "Beam" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

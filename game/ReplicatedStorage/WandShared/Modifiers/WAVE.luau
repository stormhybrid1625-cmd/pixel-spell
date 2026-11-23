-- WAVE — Ondulation (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "WAVE", Name = "Ondulation", Short = "~", Type = "Modifier",
		Mana = 2, Desc = "Trajectoire en vague (sinusoïde).", Mod = { Trajectory = "Wave" } }
	card.Order = 21 -- position dans le grimoire
	card.AppliesTo = { "Projectile" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

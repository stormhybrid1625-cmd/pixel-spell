-- DIVIDE_3 — Divisé par 3 (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "DIVIDE_3", Name = "Divisé par 3", Short = "/3", Type = "Modifier",
		Mana = 38, Recharge = 0.25, CastDelay = 0.3, Desc = "Le prochain projectile est lancé en 3 copies (dégâts x0,6 chacune).",
		Mod = { Divide = 3, DivideDamage = 0.6 } }
	card.Order = 35 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam", "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

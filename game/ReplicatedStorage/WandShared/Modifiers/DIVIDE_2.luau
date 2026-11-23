-- DIVIDE_2 — Divisé par 2 (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "DIVIDE_2", Name = "Divisé par 2", Short = "/2", Type = "Modifier",
		Mana = 23, Recharge = 0.15, CastDelay = 0.2, Desc = "Le prochain projectile est lancé en 2 copies (dégâts x0,75 chacune).",
		Mod = { Divide = 2, DivideDamage = 0.75 } }
	card.Order = 34 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam", "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

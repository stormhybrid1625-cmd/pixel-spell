-- DIVIDE_4 — Divisé par 4 (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "DIVIDE_4", Name = "Divisé par 4", Short = "/4", Type = "Modifier",
		Mana = 53, Recharge = 0.35, CastDelay = 0.4, Desc = "Le prochain projectile est lancé en 4 copies (dégâts x0,5 chacune).",
		Mod = { Divide = 4, DivideDamage = 0.5 } }
	card.Order = 36 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam", "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

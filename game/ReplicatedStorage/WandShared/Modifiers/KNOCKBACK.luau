-- KNOCKBACK — Recul (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "KNOCKBACK", Name = "Recul", Short = "RE", Type = "Modifier",
		Mana = 6, Desc = "Les sorts qui suivent repoussent violemment les cibles touchées (Ramure : les branches repoussent ce qu'elles touchent).", Mod = { Knockback = 45 } }
	card.Order = 55 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam", "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

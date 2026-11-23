-- PIERCE — Perforation (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "PIERCE", Name = "Perforation", Short = "PF", Type = "Modifier",
		Mana = 10, CastDelay = 0.05, Desc = "Traverse 2 cibles supplémentaires.", Mod = { PierceAdd = 2 } }
	card.Order = 25 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

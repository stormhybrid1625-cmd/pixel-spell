-- DAMAGE_PLUS — Dégâts accrus (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "DAMAGE_PLUS", Name = "Dégâts accrus", Short = "D+", Type = "Modifier",
		Mana = 8, CastDelay = 0.14, Desc = "+5 dégâts aux sorts qui suivent.", Mod = { DamageAdd = 5 } }
	card.Order = 14 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam", "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

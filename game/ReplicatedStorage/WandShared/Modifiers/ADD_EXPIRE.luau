-- ADD_EXPIRE — Ajout d'expiration (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "ADD_EXPIRE", Name = "Ajout d'expiration", Short = "+X", Type = "Modifier",
		Mana = 10, CastDelay = 0.08, Desc = "Le prochain sort libère la carte qui le suit quand il disparaît. Cumulable (3 max) : chaque exemplaire libère une carte de plus. Sort procédural (Ramure) : quand l'arbre meurt ou est détruit ; un projectile ou un rayon part alors du bout de la branche, dans son sens de pousse, un sort procédural ou un piège repousse au pied de l'arbre.",
		Mod = { AddTrigger = table.freeze({ Kind = "Expire", Draw = 1 }) } }
	card.Order = 33 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam", "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

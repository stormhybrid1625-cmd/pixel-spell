-- EXPLOSIVE — Charge explosive (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "EXPLOSIVE", Name = "Charge explosive", Short = "CE", Type = "Modifier",
		Mana = 15, CastDelay = 0.12, Desc = "Les sorts qui suivent explosent à l'impact (+4 de rayon, +4 dégâts). Ramure : les pointes des branches explosent quand l'arbre meurt.", Mod = { RadiusAdd = 4, DamageAdd = 4 } }
	card.Order = 59 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam", "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

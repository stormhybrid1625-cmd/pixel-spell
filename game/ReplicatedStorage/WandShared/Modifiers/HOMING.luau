-- HOMING — Tête chercheuse (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "HOMING", Name = "Tête chercheuse", Short = "TC", Type = "Modifier",
		Mana = 30, CastDelay = 0.12, Desc = "Les projectiles se courbent vers la cible la plus proche (cumulable : virage plus serré et détection plus large). Sorts procéduraux : chaque exemplaire cumulé ajoute un groupe de branches qui vise un ennemi différent.", Mod = { Homing = 6 } }
	card.Order = 20 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Procedural" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	card.Icon = "rbxassetid://89743458413168"
	return card
end

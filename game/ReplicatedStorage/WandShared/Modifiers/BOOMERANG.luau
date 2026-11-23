-- BOOMERANG — Boomerang (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "BOOMERANG", Name = "Boomerang", Short = "BM", Type = "Modifier",
		Mana = 6, Desc = "Les sorts qui suivent font demi-tour et reviennent vers toi (durée x2).", Mod = { Trajectory = "Boomerang", LifetimeMult = 2 } }
	card.Order = 57 -- position dans le grimoire
	card.AppliesTo = { "Projectile" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

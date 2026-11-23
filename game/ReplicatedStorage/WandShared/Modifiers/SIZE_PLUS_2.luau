-- SIZE_PLUS_2 — Gigantisme II (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "SIZE_PLUS_2", Name = "Gigantisme II", Short = "G2", Type = "Modifier",
		Mana = 65, Recharge = 0.15, CastDelay = 0.35, Desc = "Taille x3 des effets, explosions, zones et sorts procéduraux. Dégâts x1,4, vitesse x0,85. Le projectile lui-même est plafonné.",
		Mod = { SizeMult = 3, RadiusMult = 3, DamageMult = 1.4, SpeedMult = 0.85 } }
	card.Order = 17 -- position dans le grimoire
	card.Icon = "rbxassetid://79656969230948"
	card.IconTag = "II"
	return card
end

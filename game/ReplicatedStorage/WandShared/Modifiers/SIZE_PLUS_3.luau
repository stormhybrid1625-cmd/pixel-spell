-- SIZE_PLUS_3 — Gigantisme III (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "SIZE_PLUS_3", Name = "Gigantisme III", Short = "G3", Type = "Modifier",
		Mana = 140, CastDelay = 0.6, Recharge = 0.45, Desc = "Taille x5 des effets, explosions, zones et sorts procéduraux (colossaux). Dégâts x1,8, vitesse x0,7. Le projectile lui-même est plafonné.",
		Mod = { SizeMult = 5, RadiusMult = 5, DamageMult = 1.8, SpeedMult = 0.7 } }
	card.Order = 18 -- position dans le grimoire
	card.Icon = "rbxassetid://79656969230948"
	card.IconTag = "III"
	return card
end

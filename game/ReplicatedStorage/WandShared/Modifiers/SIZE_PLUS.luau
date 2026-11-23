-- SIZE_PLUS — Gigantisme I (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "SIZE_PLUS", Name = "Gigantisme I", Short = "G1", Type = "Modifier",
		Mana = 18, CastDelay = 0.1, Desc = "Taille x1,5 des effets, explosions, zones et sorts procéduraux. Dégâts x1,15. Le projectile lui-même est plafonné. Cumulable 3 fois.",
		Mod = { SizeMult = 1.5, RadiusMult = 1.5, DamageMult = 1.15 } }
	card.Order = 16 -- position dans le grimoire
	card.Icon = "rbxassetid://79656969230948"
	card.IconTag = "I"
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = {}
	return card
end

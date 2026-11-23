-- DOUBLE — Double sort (Multi-tir)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "DOUBLE", Name = "Double sort", Short = "x2", Type = "Multicast",
		Mana = 0, Recharge = 0.15, CastDelay = 0.1, Desc = "Lance les 2 sorts suivants en même temps.", Draw = 2, Spread = 6 }
	card.Order = 11 -- position dans le grimoire
	card.Family = "Multicast" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	return card
end

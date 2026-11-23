-- TRIPLE — Triple sort (Multi-tir)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "TRIPLE", Name = "Triple sort", Short = "x3", Type = "Multicast",
		Mana = 2, Recharge = 0.3, CastDelay = 0.18, Desc = "Lance les 3 sorts suivants en même temps.", Draw = 3, Spread = 12 }
	card.Order = 12 -- position dans le grimoire
	card.Family = "Multicast" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	return card
end

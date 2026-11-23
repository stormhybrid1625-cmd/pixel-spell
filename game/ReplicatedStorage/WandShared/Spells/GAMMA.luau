-- GAMMA — Gamma (Multi-tir)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "GAMMA", Name = "Gamma", Short = "GA", Type = "Multicast", Greek = "Gamma", Draw = 0,
		Mana = 30, Recharge = 0.2, CastDelay = 0.3, Desc = "Lance une copie de la DERNIÈRE carte de la baguette." }
	card.Order = 63 -- position dans le grimoire
	card.Family = "Multicast" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	return card
end

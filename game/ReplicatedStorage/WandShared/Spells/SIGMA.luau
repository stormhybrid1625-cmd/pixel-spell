-- SIGMA — Sigma (Multi-tir)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "SIGMA", Name = "Sigma", Short = "SI", Type = "Multicast", Greek = "Sigma", Draw = 0,
		Mana = 90, Recharge = 0.3, CastDelay = 0.4, Desc = "Lance une copie de TOUS les sorts de zone de la baguette (trou noir, gaz, mur, mine...)." }
	card.Order = 67 -- position dans le grimoire
	card.Family = "Multicast" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	return card
end

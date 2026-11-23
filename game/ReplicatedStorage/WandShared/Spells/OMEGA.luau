-- OMEGA — Oméga (Multi-tir)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "OMEGA", Name = "Oméga", Short = "OM", Type = "Multicast", Greek = "Omega", Draw = 0,
		Mana = 250, CastDelay = 0.8, Recharge = 1, Desc = "Lance une copie de TOUTES les cartes de la baguette. Le sort ultime." }
	card.Order = 68 -- position dans le grimoire
	card.Family = "Multicast" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	return card
end

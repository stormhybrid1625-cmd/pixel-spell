-- MU — Mu (Multi-tir)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "MU", Name = "Mu", Short = "MU", Type = "Multicast", Greek = "Mu", Draw = 0,
		Mana = 120, Recharge = 0.4, CastDelay = 0.45, Desc = "Applique une copie de TOUS les modificateurs de la baguette aux sorts qui suivent." }
	card.Order = 65 -- position dans le grimoire
	card.Family = "Multicast" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	return card
end

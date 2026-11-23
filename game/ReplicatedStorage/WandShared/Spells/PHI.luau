-- PHI — Phi (Multi-tir)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "PHI", Name = "Phi", Short = "PH", Type = "Multicast", Greek = "Phi", Draw = 0,
		Mana = 120, Recharge = 0.4, CastDelay = 0.45, Desc = "Lance une copie de TOUS les projectiles de la baguette." }
	card.Order = 66 -- position dans le grimoire
	card.Family = "Multicast" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	return card
end

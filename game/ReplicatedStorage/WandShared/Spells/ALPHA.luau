-- ALPHA — Alpha (Multi-tir)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "ALPHA", Name = "Alpha", Short = "AL", Type = "Multicast", Greek = "Alpha", Draw = 0,
		Mana = 30, Recharge = 0.2, CastDelay = 0.3, Desc = "Lance une copie de la PREMIÈRE carte de la baguette." }
	card.Order = 62 -- position dans le grimoire
	card.Family = "Multicast" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	return card
end

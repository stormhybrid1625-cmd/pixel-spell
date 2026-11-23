-- TAU — Tau (Multi-tir)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "TAU", Name = "Tau", Short = "TA", Type = "Multicast", Greek = "Tau", Draw = 0,
		Mana = 35, Recharge = 0.2, CastDelay = 0.25, Desc = "Lance une copie des 2 cartes suivantes, sans les consommer : elles seront aussi lues normalement." }
	card.Order = 64 -- position dans le grimoire
	card.Family = "Multicast" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	return card
end

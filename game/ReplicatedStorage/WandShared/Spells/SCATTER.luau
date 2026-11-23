-- SCATTER — Éventail (Multi-tir)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "SCATTER", Name = "Éventail", Short = "x4", Type = "Multicast",
		Mana = 5, Recharge = 0.35, CastDelay = 0.2, Desc = "Lance les 4 sorts suivants en large éventail.", Draw = 4, Spread = 32 }
	card.Order = 13 -- position dans le grimoire
	card.Family = "Multicast" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	return card
end

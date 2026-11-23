-- FORMATION_CIRCLE — Formation en cercle (Multi-tir)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "FORMATION_CIRCLE", Name = "Formation en cercle", Short = "O6", Type = "Multicast",
		Mana = 10, Recharge = 0.6, CastDelay = 0.35, Desc = "Lance les 6 sorts suivants dans toutes les directions autour de toi.", Draw = 6, Formation = "Circle" }
	card.Order = 60 -- position dans le grimoire
	card.Family = "Multicast" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	return card
end

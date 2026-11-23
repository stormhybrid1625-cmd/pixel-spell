-- DURATION_ZERO — Durée nulle (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
-- Durée de vie du projectile ramenée au minimum du moteur (0,05 s) : il disparaît presque aussitôt.
-- Usage : déclencher TOUT DE SUITE une expiration (Ajout d'expiration, Étincelle d'expiration...) au bout de la baguette.
return function(proj)
	local card = { Id = "DURATION_ZERO", Name = "Durée nulle", Short = "D0", Type = "Modifier",
		Mana = 10, Desc = "Le projectile disparaît presque aussitôt tiré (durée de vie quasi nulle). Combine-le avec une expiration pour libérer sa charge immédiatement, au bout de la baguette.",
		Mod = { LifetimeMult = 0 } }
	card.Order = 20 -- position dans le grimoire
	card.AppliesTo = { "Projectile" } -- les rayons sont instantanés, les autres familles n'ont pas de durée de vie de vol
	return card
end

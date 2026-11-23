-- CHAOS_ORB — Orbe du chaos (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "CHAOS_ORB", Name = "Orbe du chaos", Short = "CH", Type = "Projectile", Element = "Chaos",
		Mana = 20, CastDelay = 0.18, Desc = "Rebondit 4 fois. Dégâts imprévisibles (x0.4 à x2.2).",
		Proj = proj({ Damage = 12, Speed = 70, Lifetime = 2.5, Size = 1.2, Radius = 3, Bounces = 4 }) }
	card.Order = 4 -- position dans le grimoire
	card.Family = "Projectile" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { TrailSparks = 22, Flicker = 0.5 }
	return card
end

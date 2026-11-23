-- FIRE_TIMER — Boule de feu à retardement (Sort à charge (déclencheur))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "FIRE_TIMER", Name = "Boule de feu à retardement", Short = "BF", Type = "Trigger", Element = "Fire",
		Mana = 35, CastDelay = 0.25, Desc = "Après 0.35 s, libère la carte suivante puis continue sa course.",
		Proj = proj({ Damage = 8, Speed = 85, Lifetime = 1.6, Size = 1.3, Radius = 6, Gravity = 0.25 }),
		Trigger = { Kind = "Timer", Draw = 1, Delay = 0.35 } }
	card.Order = 7 -- position dans le grimoire
	card.Family = "Projectile" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { TrailSparks = 30, Flicker = 0.35, Light = 1.3 }
	return card
end

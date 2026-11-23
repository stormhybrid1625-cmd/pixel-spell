-- ARCANE_EXPIRE — Orbe à expiration (Sort à charge (déclencheur))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "ARCANE_EXPIRE", Name = "Orbe à expiration", Short = "OA", Type = "Trigger", Element = "Arcane",
		Mana = 15, CastDelay = 0.1, Desc = "Orbe lent. Quand il disparaît (impact ou fin de vie), libère la carte suivante.",
		Proj = proj({ Damage = 4, Speed = 45, Lifetime = 0.8, Size = 1 }),
		Trigger = { Kind = "Expire", Draw = 1 } }
	card.Order = 8 -- position dans le grimoire
	card.Family = "Projectile" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { TrailSparks = 16 }
	return card
end

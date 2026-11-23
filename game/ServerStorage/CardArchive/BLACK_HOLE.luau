-- BLACK_HOLE — Trou noir (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "BLACK_HOLE", Name = "Trou noir", Short = "TN", Type = "Projectile", Element = "Arcane",
		Mana = 60, CastDelay = 0.6, Recharge = 0.6,
		Desc = "Orbe lent qui s'effondre en trou noir pendant 3 s : aspire ennemis ET projectiles, et broie ce qui atteint le centre.",
		Proj = proj({ Damage = 0, Speed = 22, Lifetime = 1.2, Size = 1, Zone = { Kind = "BlackHole", Radius = 14, Duration = 3, Damage = 4, Pull = 55 } }) }
	card.Order = 43 -- position dans le grimoire
	card.Family = "Projectile" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Cast = "Cast.Heavy", Travel = "Travel.Void", Impact = false }
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { TrailSparks = 24, Light = 1.4, Flicker = 0.4 }
	card.Rank = "Superieur"
	return card
end

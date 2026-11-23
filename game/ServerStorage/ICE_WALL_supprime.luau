-- ICE_WALL — Mur de glace (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "ICE_WALL", Name = "Mur de glace", Short = "MG", Type = "Projectile", Element = "Ice",
		Mana = 35, CastDelay = 0.25, Desc = "Érige un mur de glace là où il s'arrête pendant 6 s. Bloque déplacements et projectiles.",
		Proj = proj({ Damage = 0, Speed = 70, Lifetime = 0.6, Size = 0.7, Zone = { Kind = "IceWall", Width = 14, Height = 8, Duration = 6 } }) }
	card.Order = 45 -- position dans le grimoire
	card.Family = "Projectile" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Cast = "Cast.Ice", Impact = false }
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { TrailSparks = 14 }
	return card
end

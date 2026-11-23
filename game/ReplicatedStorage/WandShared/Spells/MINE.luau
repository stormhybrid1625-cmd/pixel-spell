-- MINE — Mine (Sort à charge (déclencheur))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "MINE", Name = "Mine", Short = "MI", Type = "Trigger", Category = "Trap", Element = "Neutral",
		Mana = 20, CastDelay = 0.25,
		Desc = "PIÈGE ADAPTATIF. Se pose sur la surface visée (ou là où son projectile porteur s'arrête). Seule, elle ne fait rien : ce sont les modificateurs placés avant elle et la carte placée après qui décident de ce qu'elle déclenche quand un ennemi approche.",
		Proj = proj({ Damage = 0, Range = 70, Size = 0.6, Trap = { Radius = 4.5, Duration = 20, Arm = 0.6 } }),
		Trigger = { Kind = "Trap", Draw = 1 } }
	card.Order = 46 -- position dans le grimoire
	card.Family = "Trap" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	card.Icon = "rbxassetid://89301568903827"
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Cast = "Cast.Lob", Travel = false, Impact = "Impact.Thud" }
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { Blink = true, TrailSparks = 6 }
	return card
end

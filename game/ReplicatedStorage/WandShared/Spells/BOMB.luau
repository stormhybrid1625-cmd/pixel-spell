-- BOMB — Bombe (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "BOMB", Name = "Bombe", Short = "BO", Type = "Projectile", Element = "Fire",
		Mana = 45, Recharge = 0.2, CastDelay = 0.7, Desc = "Rebondit partout puis explose violemment au bout de 1,8 s, ou dès qu'elle touche un ennemi. Te blesse aussi (50 %) si tu es dans l'explosion.",
		Proj = proj({ Damage = 14, Speed = 45, Lifetime = 1.8, Size = 1.1, Radius = 11, Gravity = 1, Bounces = 10, Knockback = 60 }) }
	card.Order = 40 -- position dans le grimoire
	card.SelfDamage = 0.5 -- NERF : l'explosion rend 50 % de ses dégâts au lanceur s'il est dedans
	card.Family = "Projectile" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Cast = "Cast.Lob", Travel = "Travel.Fuse", Bounce = "Bounce.Heavy", Body = "Bounce.BodyHeavy", Impact = "Impact.Thud" }
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { Blink = true, TrailSparks = 8, Light = 1.2 }
	return card
end

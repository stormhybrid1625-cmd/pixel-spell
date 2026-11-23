-- FIREBALL — Boule de feu (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "FIREBALL", Name = "Boule de feu", Short = "BF", Type = "Projectile", Element = "Fire",
		Mana = 30, CastDelay = 0.28, Desc = "Lente, légèrement lestée, explose à l'impact et enflamme.",
		Proj = proj({ Damage = 9, Speed = 85, Lifetime = 1.6, Size = 1.4, Radius = 7, Gravity = 0.25 }) }
	card.Order = 2 -- position dans le grimoire
	-- CASSE-STRUCTURES : au-delà d'une taille ET d'une puissance (SpellPower), l'explosion casse les pièces Breakable
	card.BreakAbove = { Size = 3.2, Power = 60, Radius = 2.2, MaxRadius = 7 } -- (user : seuil beaucoup plus haut)
	card.Family = "Projectile" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	card.Icon = "rbxassetid://125221178104384"
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { TrailSparks = 30, Flicker = 0.35, Light = 1.3 }
	-- ACCROCHES : comportement spécial de la carte (voir ProjectileService, runHook)
	card.Hooks = {
		-- (taille : suit le rayon d'explosion avec une courbe forte -> Gigantisme = zone bien plus grande, plafond x8)
		-- l'explosion laisse une ZONE AU SOL de son élément (feu, givre, flaque toxique, sol électrisé, ronces).
		-- Visuels et sons de chaque zone : WandShared/Elements/<Élément> (Visuals.Patch, Sound.Patch).
		OnEnd = function(ctx)
			if ctx.Stats.Radius > 0 then
				ctx.CreateZone({ Kind = "Patch", Radius = 4.5, Duration = 3.5, Damage = 1, Interval = 0.5 }, math.clamp((ctx.Stats.Radius / 7) ^ 1.35, 0.5, 8))
			end
		end,
	}
	return card
end

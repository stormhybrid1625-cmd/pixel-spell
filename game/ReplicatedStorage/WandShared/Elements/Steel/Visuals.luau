-- VISUELS de l'élément (client) : traînée des projectiles, impact, zone au sol de la boule de feu.
-- Chargé par WandClient.VFXManager, qui fournit ses outils dans `api`.
return function(api)
	local Sparks, LightPool, Flipbook, rng = api.Sparks, api.LightPool, api.Flipbook, api.rng
	local holderPart, visPart, popIn, fadeAway, tween = api.holderPart, api.visPart, api.popIn, api.fadeAway, api.tween
	local shortArcs, emitRate, perp = api.shortArcs, api.emitRate, api.perp
	local O = api.Opts
	local SMOKE, FROST, ICE_FALL, DRIPS, VAPOR, MOTES, GLINT, CHAOS_POP, IMPACT_LEAVES =
		O.SMOKE, O.FROST, O.ICE_FALL, O.DRIPS, O.VAPOR, O.MOTES, O.GLINT, O.CHAOS_POP, O.IMPACT_LEAVES
	local V = {}
	-- traînée : Rate par seconde (x racine du Gigantisme), Fn(entry, pos, vel)
	V.Trail = { Rate = 9, Fn = function(e, pos, vel)
		Sparks.Emit(pos, -vel * 0.05 + rng:NextUnitVector() * 4, GLINT)
	end }
	-- impact : Fn(pos, up, big, glow)
	V.Impact = function(pos, up, big)
		Sparks.Burst(pos, { Count = math.floor(22 * big), Colors = GLINT.Colors, Normal = up, Speed = NumberRange.new(10 * big, 22 * big),
			Gravity = 1.3, Drag = 0.8, Bounce = 0.45, Life = NumberRange.new(0.2, 0.5), Size = 0.11 })
	end
	-- ARBRE d'acier : petites étincelles métalliques
	V.Ambient = { Opts = { Colors = { Color3.new(1, 1, 1), Color3.fromHex("c9d2e6") }, Gravity = 1, Drag = 1, Bounce = 0.4, Life = NumberRange.new(0.2, 0.4), Size = 0.1 },
		Rate = 0.25, Max = 10, Vel = function() return rng:NextUnitVector() * 3 end }
	return V
end

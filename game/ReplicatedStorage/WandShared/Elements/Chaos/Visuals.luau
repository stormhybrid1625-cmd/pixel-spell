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
	V.Trail = { Rate = 14, Fn = function(e, pos, vel)
		Sparks.Emit(pos, rng:NextUnitVector() * rng:NextNumber(4, 10), CHAOS_POP)
	end }
	-- impact : Fn(pos, up, big, glow)
	V.Impact = function(pos, up, big)
		for k = 1, 3 do
			task.delay(k * 0.07, function()
				Sparks.Burst(pos + rng:NextUnitVector() * 1.2 * big, { Count = math.floor(8 * big), Colors = CHAOS_POP.Colors,
					Speed = NumberRange.new(4, 12), Gravity = 0.3, Drag = 1.6, Life = NumberRange.new(0.2, 0.45), Size = 0.12, Crackle = 0.5 })
			end)
		end
	end
	-- ARBRE du chaos : éclats multicolores qui crépitent
	V.Ambient = { Opts = { Colors = require(game:GetService("ReplicatedStorage").WandShared.Config).Elements.Chaos.Flicker, Gravity = 0, Drag = 2.5, Life = NumberRange.new(0.3, 0.7), Size = 0.12, Crackle = 0.2 },
		Rate = 0.5, Max = 20, Vel = function() return rng:NextUnitVector() * rng:NextNumber(3, 8) end }
	return V
end

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
	V.Trail = { Rate = 24, Fn = function(e, pos, vel)
		-- motes qui SPIRALENT autour de l'orbe
		local s, u = perp(vel)
		local a = os.clock() * 16 + e.Seed
		local off = (s * math.cos(a) + u * math.sin(a)) * (0.5 + 0.4 * e.Size)
		Sparks.Emit(pos + off, off * 2, MOTES)
	end }
	-- impact : Fn(pos, up, big, glow)
	V.Impact = function(pos, up, big)
		Sparks.Burst(pos + up * 0.4, { Count = math.floor(18 * big), Colors = MOTES.Colors, Shell = true, Speed = NumberRange.new(5 * big, 8 * big),
			Gravity = 0, Drag = 3.5, Life = NumberRange.new(0.35, 0.6), Size = 0.12 })
	end
	-- ARBRE arcanique : poussière lumineuse qui s'élève
	V.Ambient = { Opts = { Colors = { Color3.fromHex("fbe8ff"), Color3.fromHex("c56bff"), Color3.fromHex("5a2a9e") }, Gravity = -0.15, Drag = 2, Life = NumberRange.new(0.8, 1.5), Size = 0.12 },
		Rate = 0.4, Max = 16, Vel = function() return Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(1, 3), rng:NextNumber(-1, 1)) end }
	return V
end

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
	V.Trail = { Rate = 12, Fn = function(e, pos, vel)
		if rng:NextNumber() < 0.5 then
			Sparks.Emit(pos, Vector3.new(0, -1, 0) + rng:NextUnitVector() * 0.5, DRIPS)
		else
			Sparks.Emit(pos + rng:NextUnitVector() * 0.4 * e.Size, Vector3.new(0, rng:NextNumber(0.5, 1.5), 0), VAPOR)
		end
	end }
	-- impact : Fn(pos, up, big, glow)
	V.Impact = function(pos, up, big, glow)
		if api.CanFx() then
			local h = holderPart(pos + up * 0.8)
			popIn(Flipbook.Billboard(h, "Gas", 3.2 * big, { Brightness = glow, Transparency = 0.2, Fps = 8 }), 0.25)
			task.delay(0.4, fadeAway, h, 0.8, 1.5)
		end
		Sparks.Burst(pos + up * 0.3, { Count = math.floor(12 * big), Colors = DRIPS.Colors, Normal = up, Speed = NumberRange.new(4, 9),
			Gravity = 1.4, Drag = 0.6, Life = NumberRange.new(0.5, 1), Size = 0.13 })
	end
	-- zone au sol laissée par la boule de feu : ctx = état de la zone (VFXManager.attachZone)
	V.Patch = function(ctx)
		local vis, holder, radius, P, glow, base, diskPoint, spark, marker, element =
			ctx.vis, ctx.holder, ctx.radius, ctx.P, ctx.glow, ctx.base, ctx.diskPoint, ctx.spark, ctx.marker, ctx.element
			-- FLAQUE TOXIQUE : nappe de gaz couchée au sol + petites bouffées + bulles qui éclatent
			-- plusieurs petites FLAQUES, chacune posée sur la surface réelle (une grande nappe débordait dans le vide)
			-- création ÉTALÉE sur plusieurs images (évite un pic de lag)
			local big = math.clamp((radius / 4.5) ^ 0.8, 1, 5) -- flaques et nuages PLUS GROS, grandissent avec la zone
			-- PERFORMANCES : moins de flaques, mais plus grandes (les traînées posent des dizaines de zones)
			for k = 1, ctx.n(math.clamp(math.floor(radius * 0.45), 2, 9)) do
				task.delay(k * 0.035, function()
					local at = ctx.spreadPoint(0.8)
					if at and not vis.Dead then -- (zone déjà retirée pendant la création étalée : rien, sinon flaque orpheline éternelle)
						local plate = Flipbook.Ground(at + Vector3.new(0, 0.06, 0), "Gas", rng:NextNumber(4.4, 6.4) * big, { Brightness = glow, Transparency = 0.25, Fps = rng:NextInteger(5, 7) }, api.FxFolder())
						table.insert(vis.Items, plate)
					end
				end)
			end
			for i = 1, ctx.n(math.clamp(math.floor(radius * 0.3), 1, 4)) do
				local h = holderPart(diskPoint(0.7) + Vector3.new(0, 1.2, 0))
				popIn(Flipbook.Billboard(h, "Gas", rng:NextNumber(4.5, 7) * math.min(big, 4), { Brightness = glow, Transparency = 0.35, Fps = rng:NextInteger(5, 8) }), 0.4)
				table.insert(vis.Items, h)
			end
			vis.Light = LightPool.Attach(holder, P.Mid, radius * 1.8, 0.9 * glow, 0.3)
			local bubbles = spark({ P.Core, P.Mid, P.Edge }, -0.05, NumberRange.new(0.4, 0.9), 0.22)
			vis.Tick = function(dt)
				emitRate(vis, dt, 3 + radius * 0.8, function()
					Sparks.Emit(diskPoint() + Vector3.new(0, 0.1, 0), Vector3.new(0, rng:NextNumber(1, 2.5), 0), bubbles)
				end)
			end
	end
	-- ARBRE toxique : gouttes vertes + vapeurs
	V.Ambient = { Opts = { Colors = { Color3.fromHex("d6ff78"), Color3.fromHex("7bdc2a"), Color3.fromHex("2f6b1f") }, Gravity = 0.9, Drag = 1, Life = NumberRange.new(0.6, 1.2), Size = 0.13 },
		Rate = 0.5, Max = 18, Below = true, Vel = function() return Vector3.new(0, rng:NextNumber(-1, 1), 0) end }
	-- ÉTAT « empoisonné » : bulles vertes qui montent
	V.Status = { Kind = "Poisoned", Rate = 10,
		Opts = { Colors = { Color3.fromHex("e8ffb0"), Color3.fromHex("7bdc2a"), Color3.fromHex("1d5419") }, Gravity = -0.15, Drag = 2.5, Life = NumberRange.new(0.5, 1), Size = 0.15 } }
	return V
end

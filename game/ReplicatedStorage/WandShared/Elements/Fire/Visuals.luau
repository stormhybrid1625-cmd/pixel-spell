-- VISUELS de l'élément (client) : traînée des projectiles, impact, zone au sol de la boule de feu.
-- Chargé par WandClient.VFXManager, qui fournit ses outils dans `api`.
return function(api)
	local Sparks, LightPool, Flipbook, rng = api.Sparks, api.LightPool, api.Flipbook, api.rng
	local holderPart, visPart, popIn, fadeAway, tween = api.holderPart, api.visPart, api.popIn, api.fadeAway, api.tween
	local shortArcs, emitRate, perp = api.shortArcs, api.emitRate, api.perp
	local flameStack, flameTongue = api.flameStack, api.flameTongue
	local O = api.Opts
	local SMOKE, FROST, ICE_FALL, DRIPS, VAPOR, MOTES, GLINT, CHAOS_POP, IMPACT_LEAVES =
		O.SMOKE, O.FROST, O.ICE_FALL, O.DRIPS, O.VAPOR, O.MOTES, O.GLINT, O.CHAOS_POP, O.IMPACT_LEAVES
	local V = {}
	-- traînée : Rate par seconde (x racine du Gigantisme), Fn(entry, pos, vel)
	V.Trail = { Rate = 14, Fn = function(e, pos, vel)
		Sparks.Emit(pos - vel * 0.02 + rng:NextUnitVector() * 0.3 * e.Size, Vector3.new(0, rng:NextNumber(1, 3), 0) + rng:NextUnitVector(), SMOKE)
	end }
	-- impact : Fn(pos, up, big, glow)
	V.Impact = function(pos, up, big, glow)
		-- une flamme reste un instant là où la boule s'écrase, puis la fumée monte
		if api.CanFx() then
			local h = holderPart(pos + up * 0.9 * big)
			popIn(Flipbook.Billboard(h, "Flame", 2.4 * big, { Brightness = 1.6 * glow, Fps = 14 }), 0.15)
			task.delay(0.45, fadeAway, h, 0.4, 0.4)
		end
		-- (user 2026-11-23 : la fumée restait collée au point d'impact et cachait l'explosion -> retirée ;
		--  la fumée d'explosion est gérée par ExplosionFX, répartie dans tout le rayon)
	end
	-- zone au sol laissée par la boule de feu : ctx = état de la zone (VFXManager.attachZone)
	V.Patch = function(ctx)
		local vis, holder, radius, P, glow, base, diskPoint, spark, marker, element =
			ctx.vis, ctx.holder, ctx.radius, ctx.P, ctx.glow, ctx.base, ctx.diskPoint, ctx.spark, ctx.marker, ctx.element
			-- GRAVITÉ : touchée sur un mur / en hauteur, la boule de feu se déverse — des flammes TOMBENT
			-- du point d'impact jusqu'au sol (chute accélérée), puis le brasier prend au sol
			local dropFrom = marker:GetAttribute("DropFrom")
			local fall = marker:GetAttribute("FallTime") or 0
			if typeof(dropFrom) == "Vector3" and fall > 0 then
				-- le BRASIER tombe : grosses boules de flammes qui chutent en s'étirant, traînée de braises, puis s'écrasent au sol
				local falling = math.clamp(math.floor(radius * 1.4), 5, 14)
				local trail = { Colors = { P.Core, P.Mid, P.Edge }, Gravity = 0.3, Drag = 1.5, Life = NumberRange.new(0.3, 0.6), Size = 0.16 }
				for i = 1, ctx.n(falling) do
					local start = dropFrom + Vector3.new(rng:NextNumber(-1.2, 1.2), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-1.2, 1.2))
					local land = diskPoint(0.6) + Vector3.new(0, 0.6, 0)
					local t = fall * rng:NextNumber(0.85, 1.15)
					local h = holderPart(start)
					local sz = rng:NextNumber(1.8, 2.8) * math.clamp(radius / 4.5, 0.8, 1.8)
					task.delay(rng:NextNumber(0, 0.1), function()
						for _, bb in flameStack(h, sz, glow) do
							popIn(bb, 0.08)
						end
						tween(h, t, { CFrame = CFrame.new(land) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
						local t0 = os.clock()
						task.spawn(function()
							while h.Parent and os.clock() - t0 < t do
								Sparks.Emit(h.Position + rng:NextUnitVector() * 0.4, Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(1, 3), rng:NextNumber(-1, 1)), trail)
								task.wait(0.05)
							end
						end)
						task.delay(t, function()
							Sparks.Burst(land, { Count = 8, Colors = { P.Core, P.Mid, P.Edge }, Speed = NumberRange.new(3, 7), Gravity = 1, Drag = 1, Bounce = 0.3,
								Life = NumberRange.new(0.3, 0.7), Size = 0.15 })
							fadeAway(h, 0.2)
						end)
					end)
				end
				-- braises qui se détachent du mur et chutent
				Sparks.Burst(dropFrom, { Count = math.floor(14 + radius * 2), Colors = { P.Core, P.Mid, P.Edge }, Speed = NumberRange.new(2, 6),
					Gravity = 1, Drag = 0.6, Bounce = 0.3, Life = NumberRange.new(0.6, 1.2), Size = 0.14 })
			end
			local startAt = os.clock() + fall
			-- CHAMP DE FLAMMES : un tapis dense de GRANDES flammes en 3 couches (halo, corps, cœur), plus hautes au
			-- centre qu'au bord, + des langues de feu qui jaillissent en continu, + fumée sombre au-dessus
			local big = math.clamp(radius / 4.5, 0.8, 2.2)
			local n = math.clamp(math.floor(radius * 1.4), 3, 28) -- (x2,6 / 55 max : trop de flammes, le brasier devenait illisible) -- (min 10 : une petite flamme de traînée affichait un brasier entier)
			-- répartition ESPACÉE : chaque flamme garde une distance minimale avec les autres (sinon les grandes
			-- recouvraient les petites en bouillie) ; tailles un peu plus resserrées
			local placed = {}
			for i = 1, ctx.n(n) do
				local at
				for _ = 1, 8 do
					local c = diskPoint()
					local ok = true
					for _, q in placed do
						if (Vector3.new(c.X - q.X, 0, c.Z - q.Z)).Magnitude < 2.2 * big then
							ok = false
							break
						end
					end
					at = c
					if ok then
						break
					end
				end
				table.insert(placed, at)
				local edge = math.clamp((at - base).Magnitude / math.max(radius, 1), 0, 1)
				local sz = rng:NextNumber(2.6, 3.6) * big * (1.1 - 0.35 * edge) -- un peu plus haut au cœur du brasier
				local h = holderPart(at + Vector3.new(0, sz * 0.45, 0))
				task.delay(fall + rng:NextNumber(0, 0.35), function()
					for _, bb in flameStack(h, sz, glow) do
						popIn(bb, 0.25)
					end
				end)
				table.insert(vis.Items, h)
			end
			vis.Light = LightPool.Attach(holder, P.Mid, radius * 3.2, 3.6 * glow, 0.4) -- le brasier ÉCLAIRE vraiment les alentours
			local embers = spark({ P.Core, P.Mid, P.Edge }, 1, NumberRange.new(0.6, 1.3), 0.13) -- soumises à la gravité
			-- fumée : fines volutes grises bien AU-DESSUS des flammes (les gros carrés sombres masquaient le feu)
			-- (bouffées de vapeur en gris très foncés, plus grosses si le brasier est grand)
			local smoke = { Puff = true, Grow = 3.6, Fade0 = 0.55,
				Colors = { Color3.fromHex("625a54"), Color3.fromHex("574f4a"), Color3.fromHex("4c4540"), Color3.fromHex("6d645d") },
				Gravity = -0.32, Drag = 1.6, Life = NumberRange.new(1.6, 2.8), Size = math.min(0.6 * math.sqrt(big), 1.2) }
			vis.Tick = function(dt)
				if os.clock() < startAt then
					return -- le feu n'a pas encore touché le sol
				end
				emitRate(vis, dt, 2 + radius * 3, function() -- braises proportionnelles à la taille
					Sparks.Emit(diskPoint() + Vector3.new(0, 0.4, 0), Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(4, 9), rng:NextNumber(-1, 1)), embers)
				end)
				-- langues de feu : le brasier BOUGE et monte
				vis.TongueAcc = (vis.TongueAcc or 0) + dt * math.clamp(radius * 0.8, 1, 12)
				while vis.TongueAcc >= 1 do
					vis.TongueAcc -= 1
					flameTongue(diskPoint(0.85) + Vector3.new(0, 0.6 * big, 0), Vector3.yAxis, rng:NextNumber(2.6, 4) * big, glow)
				end
				-- fumée sombre qui s'élève au-dessus des flammes
				vis.SmokeAcc = (vis.SmokeAcc or 0) + dt * math.clamp(radius * 0.35, 1, 7) * ctx.fxLive() -- (user : moins de fumée) -- (compteur séparé : emitRate partage vis.Acc)
				while vis.SmokeAcc >= 1 do
					vis.SmokeAcc -= 1
					Sparks.Emit(diskPoint(0.6) + Vector3.new(0, 5.5 * big, 0), Vector3.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(1.5, 3), rng:NextNumber(-0.6, 0.6)), smoke)
				end
			end
	end
	-- ARBRE en feu : braises qui montent des branches (couleurs = étincelles de feu du moteur)
	V.Ambient = { Opts = nil, Rate = 1.2, Max = 30, Vel = function() return Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(4, 10), rng:NextNumber(-1, 1)) end }
	-- ÉTAT « en feu » sur une cible : 3 flammes décalées (jamais la même image en même temps), lumière, braises
	V.Status = {
		Kind = "Burning", Rate = 22, Opts = api.FIRE_SPARKS,
		Start = function(s, root)
			local glow = api.Glow()
			local holder = holderPart(root.Position)
			for i = 1, 3 do
				local bb = Flipbook.Billboard(holder, "Flame", 2.4 + i * 0.35, { Brightness = 1.7 * glow, Fps = 9 + i * 2 })
				bb.StudsOffset = Vector3.new((i - 2) * 0.65, -0.4 + (i % 2) * 0.9, 0)
				popIn(bb, 0.25)
			end
			s.Holder = holder
			s.Light = LightPool.Attach(holder, Color3.fromHex("ff8f26"), 14, 1.8 * glow, 0.6)
		end,
		Stop = function(s) -- les flammes s'éteignent dans une bouffée de fumée
			Sparks.Burst(s.Holder.Position + Vector3.new(0, 1, 0), {
				Count = 10, Colors = api.SMOKE_SPARKS.Colors, Direction = Vector3.yAxis, Spread = 40,
				Speed = NumberRange.new(2, 5), Gravity = -0.2, Drag = 2, Life = NumberRange.new(0.5, 1), Size = 0.2,
			})
		end,
	}
	return V
end

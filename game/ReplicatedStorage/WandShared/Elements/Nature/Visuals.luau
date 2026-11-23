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
	-- zone au sol laissée par la boule de feu : ctx = état de la zone (VFXManager.attachZone)
	-- impact : une gerbe de feuilles s'envole et retombe en planant
	V.Impact = function(pos, up, big)
		Sparks.Burst(pos + up * 0.4, {
			Count = math.floor(22 * big), Colors = IMPACT_LEAVES, Normal = up, Speed = NumberRange.new(5 * big, 12 * big),
			Gravity = 0.1, Drag = 3.2, Bounce = 0.1, Life = NumberRange.new(1.4, 2.6), Size = 0.2,
		})
	end
	V.Patch = function(ctx)
		local vis, holder, radius, P, glow, base, diskPoint, spark, marker, element =
			ctx.vis, ctx.holder, ctx.radius, ctx.P, ctx.glow, ctx.base, ctx.diskPoint, ctx.spark, ctx.marker, ctx.element
			-- TAPIS DE FEUILLES : des feuilles tombent en voletant et se posent au sol (aucune pièce, que des particules)
			local LEAF = { Colors = { Color3.fromHex("7fbf3a"), Color3.fromHex("4e8a2a"), Color3.fromHex("a8c94a"), Color3.fromHex("c9a43a"), Color3.fromHex("8a5a2a") },
				Gravity = 0.12, Drag = 2.6, Bounce = 0.05, Life = NumberRange.new(2.6, 4.2), Size = 0.2 } -- Bounce > 0 = collision : la feuille se POSE sur le sol
			local function leaf(h)
				Sparks.Emit(diskPoint() + Vector3.new(0, h, 0), Vector3.new(rng:NextNumber(-1.2, 1.2), rng:NextNumber(-0.6, 0.2), rng:NextNumber(-1.2, 1.2)), LEAF)
			end
			for _ = 1, math.clamp(math.floor(radius * 4), 14, 60) do -- tapis initial : posé presque au ras du sol
				leaf(rng:NextNumber(0.2, 0.9))
			end
			vis.Light = LightPool.Attach(holder, P.Mid, radius * 1.4, 0.45 * glow, 0.3)
			vis.Tick = function(dt)
				-- renouvellement : le tapis reste plein tant que la zone dure
				emitRate(vis, dt, math.clamp(radius * 3.2, 10, 40), function()
					leaf(rng:NextNumber(0.6, 2))
				end)
			end
	end
	-- ARBRE nature : BEAUCOUP de feuilles qui planent, + RAFALES (une gerbe de feuilles arrachée qui tourbillonne)
	V.Ambient = { Opts = {
			Colors = { Color3.fromHex("a8e85a"), Color3.fromHex("8fd94a"), Color3.fromHex("6fbf3a"), Color3.fromHex("4e9a2a"), Color3.fromHex("d8c04a") },
			Gravity = 0.1, Drag = 3.2, Bounce = 0.1, Life = NumberRange.new(1.6, 2.8), Size = 0.2 },
		Rate = 0.6, Max = 28, Vel = function() return Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-1, 2), rng:NextNumber(-4, 4)) end,
		Gust = { 1.1, 2.2 }, GustCount = 16 }
	-- ÉTAT « enraciné » (blocage après 3 coups) : racines qui sortent du sol et enserrent les jambes
	V.Status = {
		Kind = "Rooted", Static = true, Rate = 4, FadeTime = 0.35,
		Opts = { Colors = { Color3.fromHex("8fd94a"), Color3.fromHex("4e9a2a"), Color3.fromHex("6b4a2a") }, Gravity = 0.6, Drag = 2, Life = NumberRange.new(0.5, 1), Size = 0.14 },
		Vel = function() return Vector3.new(rng:NextNumber(-1.5, 1.5), rng:NextNumber(0, 2), rng:NextNumber(-1.5, 1.5)) end,
		Start = function(s, root)
			-- RACINES QUI ATTRAPENT : 4 racines sortent du sol autour des pieds et S'ENROULENT en spirale autour des
			-- jambes jusqu'à la taille, segment après segment, avec l'écorce texturée de la RAMURE (api.BarkPart)
			local holder = holderPart(root.Position)
			local c = root.Position
			-- hauteur RÉELLE du sol sous la cible (la taille des personnages varie) : les racines partent du sol
			local gp = RaycastParams.new()
			gp.FilterType = Enum.RaycastFilterType.Exclude
			gp.FilterDescendantsInstances = { root.Parent, api.FxFolder() }
			local gh = workspace:Raycast(c, Vector3.new(0, -14, 0), gp)
			local groundY = if gh then gh.Position.Y else c.Y - 3
			local span = math.max(1.5, (c.Y - groundY) * 0.95) -- du sol jusqu'à la taille
			local LEAF = { Color3.fromHex("6fbf3a"), Color3.fromHex("8fd94a"), Color3.fromHex("4e9a2a") }
			local STEPS = 5
			for k = 1, 4 do
				local a0 = k / 4 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
				local dir = if k % 2 == 0 then 1 else -1 -- deux sens d'enroulement : elles se croisent
				local prev = nil
				for i = 0, STEPS do
					local t = i / STEPS
					local ang = a0 + dir * t * math.pi * 1.1 -- un peu plus d'un demi-tour autour des jambes
					local rad = 1.9 - t * 0.55 -- part large au sol, se resserre CONTRE les jambes (1,35 = juste à l'extérieur du corps)
					local pt = Vector3.new(c.X + math.cos(ang) * rad, groundY - 0.2 + t * span, c.Z + math.sin(ang) * rad)
					if prev then
						local from, to = prev, pt -- copies FIGÉES (prev change avant que le segment différé apparaisse)
						local w = 0.55 - t * 0.2
						local len = (to - from).Magnitude
						local delay = (i - 1) * 0.06
						task.delay(delay, function()
							if not holder.Parent then
								return
							end
							local bark = api.BarkPart(CFrame.lookAt(from, to), CFrame.lookAt(from:Lerp(to, 0.5), to), w, len + w * 0.7, "Nature", 0.07)
							bark.Parent = holder
							if i == STEPS or (i == 3 and k % 2 == 1) then -- feuilles au bout des racines
								local lf = Instance.new("Part")
								lf.Anchored, lf.CanCollide, lf.CanQuery, lf.CanTouch, lf.CastShadow = true, false, false, false, false
								lf.Material = Enum.Material.Neon
								lf.Transparency = 0.25
								lf.Color = LEAF[rng:NextInteger(1, #LEAF)]
								lf.Size = Vector3.new(0.05, 0.05, 0.05)
								lf.CFrame = CFrame.new(to) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
								lf.Parent = holder
								tween(lf, 0.18, { Size = Vector3.new(0.45, 0.22, 0.45) })
							end
						end)
					end
					prev = pt
				end
			end
			local feet = Instance.new("Part") -- la lueur au niveau des PIEDS éclaire l'écorce des racines
			feet.Anchored, feet.CanCollide, feet.CanQuery, feet.CanTouch, feet.Transparency = true, false, false, false, 1
			feet.Size = Vector3.one * 0.2
			feet.CFrame = holder.CFrame * CFrame.new(0, -1.8, 0)
			feet.Parent = holder
			s.Holder = holder -- OBLIGATOIRE : c'est ce support que le moteur efface à la fin de l'état
			s.Light = LightPool.Attach(feet, Color3.fromHex("b8e07a"), 8, 1.4 * api.Glow(), 0.3)
		end,
	}
	return V
end

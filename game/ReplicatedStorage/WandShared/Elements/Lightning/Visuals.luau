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
	-- impact : Fn(pos, up, big, glow)
	V.Impact = function(pos, up, big)
		if api.CanFx() then
			shortArcs(pos + up * 0.4, 4, 2.4 * big)
		end
	end
	-- zone au sol laissée par la boule de feu : ctx = état de la zone (VFXManager.attachZone)
	V.Patch = function(ctx)
		local vis, holder, radius, P, glow, base, spark = ctx.vis, ctx.holder, ctx.radius, ctx.P, ctx.glow, ctx.base, ctx.spark
		local surfacePoint = ctx.surfacePoint
		-- SOL ÉLECTRISÉ (bien visible) : CICATRICES lumineuses qui grésillent sur le sol + arcs fréquents qui
		-- rampent + éclairs qui jaillissent vers le haut + gerbes d'étincelles. Tout est posé sur la surface réelle.
		local scars = {}
		local nScars = math.clamp(math.floor(radius * 1.8), 8, 40)
		for _ = 1, nScars do
			local at, n = surfacePoint(0.8)
			if at then
				-- une cicatrice = marche aléatoire de petits segments néon couchés sur la surface
				local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
				dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.xAxis
				local p = at
				for _ = 1, rng:NextInteger(4, 8) do
					dir = (dir + Vector3.new(rng:NextNumber(-0.8, 0.8), 0, rng:NextNumber(-0.8, 0.8))).Unit
					local len = rng:NextNumber(0.5, 1.1)
					local nextP = p + dir * len
					local q = ctx.snap(nextP, n)
					if not q then
						break -- bord : la cicatrice s'arrête (rien dans le vide)
					end
					local mid = (p + q) / 2
					local seg = visPart(Vector3.new(0.22, 0.05, (q - p).Magnitude + 0.05), CFrame.lookAt(mid + n * 0.03, q + n * 0.03),
						if rng:NextNumber() < 0.5 then Color3.fromHex("ffe94f") else Color3.fromHex("9fd0ff"), Enum.Material.Neon, 0)
					table.insert(scars, seg)
					table.insert(vis.Items, seg)
					p = q
				end
			end
		end
		vis.Light = LightPool.Attach(holder, P.Mid, radius * 2.6, 2.6 * glow, 0.3)
		local zap = spark({ Color3.new(1, 1, 1), P.Core, P.Mid }, 0.6, NumberRange.new(0.12, 0.3), 0.12)
		local arcAcc, boltAcc, flickAcc = 0, 0, 0
		vis.Tick = function(dt)
			-- les cicatrices GRÉSILLENT (allumées / éteintes très vite)
			flickAcc += dt
			if flickAcc >= 0.05 then
				flickAcc = 0
				for _, seg in scars do
					if seg.Parent then
						seg.Transparency = if rng:NextNumber() < 0.25 then 0.8 else 0
					end
				end
			end
			-- arcs qui rampent au ras du sol, fréquents
			arcAcc += dt
			if arcAcc >= 0.06 then
				arcAcc = 0
				if api.CanFx() then
					local at = surfacePoint(0.9)
					if at then
						shortArcs(at + Vector3.new(0, 0.15, 0), 2, rng:NextNumber(2, 3.5))
					end
				end
			end
			-- éclairs qui JAILLISSENT vers le haut
			boltAcc += dt
			if boltAcc >= 0.35 then
				boltAcc = 0
				if api.CanFx() then
					local at = surfacePoint(0.7)
					if at then
						shortArcs(at + Vector3.new(0, 0.6, 0), 1, rng:NextNumber(3, 5))
					end
				end
			end
			emitRate(vis, dt, 26 + radius * 3, function()
				local at = surfacePoint(0.9)
				if at then
					Sparks.Emit(at + Vector3.new(0, 0.1, 0), Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(3, 8), rng:NextNumber(-5, 5)), zap)
				end
			end)
		end
	end
	-- ARBRE foudre : étincelles brèves qui jaillissent (en plus des arcs)
	V.Ambient = { Opts = { Colors = { Color3.new(1, 1, 1), Color3.fromHex("ffe94f"), Color3.fromHex("3a6cff") }, Gravity = 0.3, Drag = 3, Life = NumberRange.new(0.12, 0.3), Size = 0.11 },
		Rate = 0.6, Max = 24, Vel = function() return rng:NextUnitVector() * rng:NextNumber(6, 12) end }
	-- ÉTAT « électrocuté » : arcs animés qui parcourent la cible, lumière, étincelles projetées dans tous les sens
	V.Status = {
		Kind = "Shocked", Rate = 26, FadeTime = 0.2,
		Opts = { Colors = { Color3.new(1, 1, 1), Color3.fromHex("fffbe0"), Color3.fromHex("ffe94f"), Color3.fromHex("5f9bff") },
			Gravity = 0.3, Drag = 3, Bounce = 0.3, Life = NumberRange.new(0.1, 0.25), Size = 0.1, Crackle = 0.3 },
		Vel = function() return rng:NextUnitVector() * rng:NextNumber(6, 14) end,
		Start = function(s, root)
			local glow = api.Glow()
			local holder = holderPart(root.Position)
			for i = 1, 2 do
				local bb = Flipbook.Billboard(holder, "Shock", if i == 1 then 4.2 else 3.2, { Brightness = 2 * glow, Fps = if i == 1 then 16 else 22 })
				bb.StudsOffset = Vector3.new((i - 1.5) * 0.8, if i == 1 then 0.2 else 1.3, 0)
				bb.AlwaysOnTop = false
				popIn(bb, 0.08)
			end
			s.Holder = holder
			s.Light = LightPool.Attach(holder, Color3.fromHex("ffe94f"), 14, 2.4 * glow, 1)
		end,
	}
	return V
end

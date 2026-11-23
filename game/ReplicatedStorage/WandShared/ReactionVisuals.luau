--[[
	WandShared/ReactionVisuals — EFFETS VISUELS ET SONORES DES RÉACTIONS (client)
	Chargé par WandClient.VFXManager (même boîte à outils `api` que les visuels d'éléments).
	Chaque effet : fn(pos, scale) ; scale = taille de la réaction (1 = sur une cible, plus grand = réaction de ZONE).
	Le serveur envoie { k = "ReactFX", n = nom, p = position, s = taille }.
]]
return function(api)
	local Sparks, LightPool, rng, holderPart, fadeAway, flameStack = api.Sparks, api.LightPool, api.rng, api.holderPart, api.fadeAway, api.flameStack
	local V = {}

	-- VAPEUR : des BOUFFÉES DE PIXELS blanc-gris qui jaillissent, grossissent en montant et s'effacent (style pixel du jeu)
	V.Steam = function(p: Vector3, scale: number)
		-- scale = rayon de zone / 2.5 (1.2 sur une cible) : la vapeur couvre TOUTE la zone, bouffées plus grosses si grande
		local k = math.clamp(scale, 0.6, 10)
		local r = 2.5 * k -- rayon couvert
		local big = math.sqrt(k)
		-- gris MOYENS : les bouffées sont lumineuses (lisibles dans le noir), un gris clair « brûle » en blanc à l'écran
		-- (gris FONCÉS + transparents : en zone, des dizaines de bouffées se superposent et saturaient en blanc)
		-- (user 2026-11-23 : trop foncée) gris CLAIRS mais MATES (pas de Neon -> pas de saturation blanche)
		local puff = { Puff = true, Matte = true, Grow = 4.2, Fade0 = 0.72,
			Colors = { Color3.fromHex("c9d0d4"), Color3.fromHex("bcc4c9"), Color3.fromHex("aeb6bb"), Color3.fromHex("a0a8ad") },
			Gravity = -0.35, Drag = 2, Life = NumberRange.new(1.4, 2.4 + 0.15 * k), Size = math.min(0.9 * big, 2.6), Priority = true }
		local function disc(): Vector3
			local a2, d = rng:NextNumber(0, math.pi * 2), r * math.sqrt(rng:NextNumber())
			return p + Vector3.new(math.cos(a2) * d, 0.4, math.sin(a2) * d)
		end
		-- jaillissement : plusieurs foyers répartis sur la zone
		local spots = math.clamp(math.floor(k * 1.5), 1, 12)
		for i = 1, spots do
			puff.Count = math.clamp(math.floor(26 * k / spots), 6, 30)
			puff.Direction = Vector3.yAxis
			puff.Spread = 45
			puff.Speed = NumberRange.new(8 * big, 17 * big)
			Sparks.Burst(if i == 1 then p + Vector3.new(0, 0.4, 0) else disc(), puff)
		end
		task.spawn(function() -- la vapeur continue de s'échapper de toute la zone
			local n = math.clamp(math.floor(10 + 5 * k), 10, 60)
			for _ = 1, n do
				task.wait(0.09)
				for _ = 1, if k > 3 then 2 else 1 do
					Sparks.Emit(disc(), Vector3.new(rng:NextNumber(-1.5, 1.5), rng:NextNumber(5, 10) * big, rng:NextNumber(-1.5, 1.5)), puff)
				end
			end
		end)
		Sparks.Burst(p + Vector3.new(0, 0.5, 0), { Count = math.floor(10 * math.min(k, 6)), Colors = { Color3.fromHex("e8f6ff"), Color3.fromHex("bfe4f5") },
			Direction = Vector3.yAxis, Spread = 70, Speed = NumberRange.new(6 * big, 12 * big), Gravity = 0.8, Drag = 1.5, Life = NumberRange.new(0.3, 0.6), Size = 0.1, Priority = true })
		LightPool.Flash(p + Vector3.new(0, 1, 0), Color3.fromHex("e8f4ff"), math.min(r * 2.4, 60), 0.6 * api.Glow(), 0.6, { 1, 0.6, 0.3 })
		api.Sound("Zone.Extinguish", p, 1.1, math.min(1.4 + 0.15 * k, 2.6))
	end

	-- EXPLOSION DE GAZ : boule de feu verdâtre + onde de gaz toxique qui s'enflamme
	V.GasBlast = function(p: Vector3, scale: number)
		local k = math.clamp(scale, 0.8, 5)
		Sparks.Burst(p, { Count = math.floor(40 * k), Colors = { Color3.new(1, 1, 0.8), Color3.fromHex("ffd23a"), Color3.fromHex("ff7b1c"), Color3.fromHex("5a7a1a") },
			Speed = NumberRange.new(14 * math.sqrt(k), 34 * math.sqrt(k)), Gravity = 0.6, Drag = 1.6, Bounce = 0.3, Life = NumberRange.new(0.5, 1.1), Size = 0.22, Crackle = 0.25, Priority = true })
		Sparks.Burst(p, { Count = math.floor(22 * k), Colors = { Color3.fromHex("b6ff5a"), Color3.fromHex("7bdc2a"), Color3.fromHex("3d6b1f") }, Shell = true,
			Speed = NumberRange.new(10 * k, 13 * k), Gravity = -0.1, Drag = 2, Life = NumberRange.new(0.6, 1.2), Size = 0.3, Priority = true })
		LightPool.Flash(p + Vector3.new(0, 1, 0), Color3.fromHex("ffcf5a"), 16 * k, 3 * api.Glow(), 0.35, { 1, 0.5, 0.2 })
		-- détonation (taille selon la réaction) + le gaz qui s'embrase
		api.Sound(if k >= 2 then "Explosion.Big" else "Explosion.Medium", p, 0.9, 1.3)
		api.Sound("Explosion.Toxic", p, 0.9, 1)
		api.Sound("Zone.Ignite", p, 1, 1.2)
	end

	-- ÉCLATEMENT : la glace vole en éclats (cristaux qui rebondissent) + crac
	V.Shatter = function(p: Vector3, scale: number)
		local k = math.clamp(scale, 0.8, 4)
		Sparks.Burst(p + Vector3.new(0, 1, 0), { Count = math.floor(36 * k), Colors = { Color3.new(1, 1, 1), Color3.fromHex("d8f8ff"), Color3.fromHex("8fe3ff"), Color3.fromHex("3f9fd6") },
			Speed = NumberRange.new(10, 24), Gravity = 1.4, Drag = 0.6, Bounce = 0.45, Life = NumberRange.new(0.6, 1.2), Size = 0.2, Priority = true })
		LightPool.Flash(p + Vector3.new(0, 1, 0), Color3.fromHex("bfeaff"), 12 * k, 2 * api.Glow(), 0.25, { 1, 0.4 })
		api.Sound("Matter.Break.Ice", p, 1, 1.4)
		api.Sound("Explosion.Ice", p, 1.15, 0.7)
	end

	-- RACINES EN FEU : bois qui s'embrase d'un coup (flammes basses + braises et copeaux qui jaillissent)
	V.Blaze = function(p: Vector3, scale: number)
		local k = math.clamp(scale, 0.8, 3)
		local h = holderPart(p + Vector3.new(0, -1.2, 0))
		for _, bb in flameStack(h, 2.6 * k, api.Glow()) do
			bb.Enabled = true
		end
		task.delay(0.7, fadeAway, h, 0.4, 0.4)
		Sparks.Burst(p, { Count = math.floor(28 * k), Colors = { Color3.fromHex("fff3a1"), Color3.fromHex("ff8f26"), Color3.fromHex("6b4a2a") },
			Direction = Vector3.yAxis, Spread = 60, Speed = NumberRange.new(6, 16), Gravity = 0.5, Drag = 1.2, Bounce = 0.3, Life = NumberRange.new(0.5, 1.1), Size = 0.18, Priority = true })
		api.Sound("Fire.Catch", p, 0.9, 1.5)
	end

	-- FLAQUE ÉLECTRIFIÉE : arcs qui courent sur toute la zone + grésillement
	V.Electrify = function(p: Vector3, scale: number)
		local r = math.clamp(scale, 1, 12) -- ici scale = rayon de la zone
		for _ = 1, math.clamp(math.floor(r * 1.5), 4, 16) do
			local a = p + Vector3.new(rng:NextNumber(-r, r), 0.3, rng:NextNumber(-r, r))
			local b = a + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(0.5, 2), rng:NextNumber(-3, 3))
			api.Arc(a, b)
		end
		Sparks.Burst(p + Vector3.new(0, 0.5, 0), { Count = math.floor(10 * r), Colors = { Color3.new(1, 1, 1), Color3.fromHex("ffe94f"), Color3.fromHex("5f9bff") },
			Speed = NumberRange.new(6, 16), Gravity = 0.3, Drag = 3, Life = NumberRange.new(0.15, 0.35), Size = 0.12, Priority = true })
		LightPool.Flash(p + Vector3.new(0, 1, 0), Color3.fromHex("fff3a0"), r * 1.6, 0.9 * api.Glow(), 0.3, { 1, 0.4, 0.7, 0.2 })
		api.Sound("Beam.Lightning", p, 1.1, 0.9)
		api.Sound("Hit.Lightning", p, 0.9, 1.4) -- grésillement de la flaque
	end

	return V
end

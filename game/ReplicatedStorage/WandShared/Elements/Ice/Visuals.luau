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
	V.Trail = { Rate = 18, Fn = function(e, pos, vel)
		if rng:NextNumber() < 0.35 then
			Sparks.Emit(pos, -vel * 0.04 + rng:NextUnitVector() * 2, ICE_FALL)
		else
			Sparks.Emit(pos + rng:NextUnitVector() * 0.5 * e.Size, rng:NextUnitVector() * 0.8, FROST)
		end
	end }
	-- impact : Fn(pos, up, big, glow)
	V.Impact = function(pos, up, big)
		Sparks.Burst(pos + up * 0.3, { Count = math.floor(18 * big), Colors = ICE_FALL.Colors, Normal = up, Speed = NumberRange.new(6 * big, 14 * big),
			Gravity = 1.6, Drag = 0.5, Bounce = 0.55, Life = NumberRange.new(0.5, 1.1), Size = 0.16 })
		Sparks.Burst(pos + up * 0.3, { Count = math.floor(14 * big), Colors = FROST.Colors, Speed = NumberRange.new(2, 5),
			Gravity = 0.02, Drag = 3, Life = NumberRange.new(0.5, 0.9), Size = 0.12 })
	end
	-- zone au sol laissée par la boule de feu : ctx = état de la zone (VFXManager.attachZone)
	V.Patch = function(ctx)
		local vis, holder, radius, P, glow, base, marker = ctx.vis, ctx.holder, ctx.radius, ctx.P, ctx.glow, ctx.base, ctx.marker
		local surfacePoint = ctx.spreadPoint -- éventail : sol ET mur au pied d'un mur, la matière suit le coin
		-- SOL GIVRÉ : plaques TEXTURÉES de cristaux (dendrites pixel art, PixelSpell/tools/gen_frost.js) projetées
		-- sur TOUTES les surfaces autour de l'impact (éventail : sol + mur dans un coin), orientées selon LEUR normale ; le givre S'ÉTEND depuis le point d'impact (chaque
		-- plaque pousse avec un délai selon sa distance). Éclats de cristal en relief + scintillement.
		local FROST = { "rbxassetid://136518518075924", "rbxassetid://116032913477454", "rbxassetid://117335120558229" }
		local nrm = marker:GetAttribute("Normal")
		nrm = if typeof(nrm) == "Vector3" and nrm.Magnitude > 0.1 then nrm.Unit else Vector3.yAxis
		local function frameFor(n: Vector3): CFrame
			local t1 = if math.abs(n.Y) < 0.9 then n:Cross(Vector3.yAxis).Unit else n:Cross(Vector3.xAxis).Unit
			return CFrame.fromMatrix(Vector3.zero, t1, n, -n:Cross(t1).Unit) -- Y local = normale
		end
		local scale = math.clamp((radius / 4.5) ^ 0.8, 0.9, 5) * 1.35 -- plaques plus grandes : surface givrée plus large -- images de givre plus GRANDES : elles couvrent toute la zone glissante
		local count = math.clamp(math.floor(radius * 1.2), 6, 30) -- densité réduite (plaques plus grandes) -- moins d'images (elles sont plus grandes)
		for k = 1, ctx.n(count) do
			-- les premières plaques sont près du centre : le givre part de l'impact
			local at, n = surfacePoint(if k <= 3 then 0.25 else 1.05, nrm)
			if at then
				local d = (at - base).Magnitude
				local w = rng:NextNumber(3.4, 5.6) * scale
				local plate = visPart(Vector3.new(0.05, 0.02, 0.05), CFrame.new(at + n * (0.03 + k * 0.002)) * frameFor(n) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
					Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, 1)
				local sg = Instance.new("SurfaceGui")
				sg.Face = Enum.NormalId.Top
				sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
				sg.CanvasSize = Vector2.new(64, 64)
				sg.LightInfluence = 0.35 -- lisible dans le noir sans éblouir
				sg.Brightness = 1.7 * glow
				sg.AlwaysOnTop = false
				sg.Parent = plate
				local img = Instance.new("ImageLabel")
				img.BackgroundTransparency = 1
				img.Size = UDim2.fromScale(1, 1)
				img.Image = FROST[rng:NextInteger(1, #FROST)]
				img.ResampleMode = Enum.ResamplerMode.Pixelated
				img.ImageTransparency = 0.15
				img.Parent = sg
				-- one-sided SurfaceGui: mirror on the back face (frost on walls / thin parts seen from behind)
				local back = sg:Clone()
				back.Face = Enum.NormalId.Bottom
				back.Parent = plate
				table.insert(vis.Items, plate)
				-- le givre GAGNE du terrain : la plaque pousse depuis rien, plus tard si elle est loin du centre
				task.delay(d / math.max(radius, 1) * 0.5, function()
					if plate.Parent then
						tween(plate, 0.35, { Size = Vector3.new(w, 0.02, w) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					end
				end)
				-- éclats de cristal en relief, qui jaillissent
				if rng:NextNumber() < 0.18 then
					local hgt = rng:NextNumber(0.4, 1.1) * math.sqrt(scale)
					local tilt = CFrame.Angles(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0, 6.28), rng:NextNumber(-0.45, 0.45))
					local shard = visPart(Vector3.new(0.16, 0.05, 0.16), CFrame.new(at + n * 0.02) * frameFor(n) * tilt,
						Color3.fromHex(if rng:NextNumber() < 0.5 then "eafcff" else "bff2ff"), Enum.Material.Glass, 0.15)
					table.insert(vis.Items, shard)
					local cf0 = shard.CFrame
					task.delay(d / math.max(radius, 1) * 0.5 + 0.1, function()
						if shard.Parent then
							tween(shard, 0.25, { Size = Vector3.new(0.16, hgt, 0.16), CFrame = cf0 * CFrame.new(0, hgt / 2, 0) }, Enum.EasingStyle.Back)
						end
					end)
				end
			end
		end
		vis.Light = LightPool.Attach(holder, Color3.fromHex("8fe3ff"), math.min(radius * 2.6, 44), 2.0 * glow, 0.2) -- le givre éclaire bien
		-- scintillement du givre : AUCUNE gravité, les éclats restent collés à la surface
		local frost = { Colors = { Color3.new(1, 1, 1), Color3.fromHex("d8f8ff"), Color3.fromHex("8fe3ff") }, Gravity = 0, Drag = 6, Life = NumberRange.new(0.3, 0.8), Size = 0.1 }
		vis.Tick = function(dt)
			emitRate(vis, dt, 3 + radius * 0.9, function()
				local at, n = surfacePoint(0.9, nrm)
				if at then
					Sparks.Emit(at + n * 0.1, n * rng:NextNumber(0.03, 0.2), frost)
				end
			end)
		end
	end
	-- ARBRE de glace qui FOND : gouttes bleues qui tombent du dessous des branches
	V.Ambient = { Opts = { Colors = { Color3.fromHex("e6fbff"), Color3.fromHex("8fe3ff"), Color3.fromHex("3f9fd6") }, Gravity = 1.4, Drag = 0.4, Bounce = 0.1, Life = NumberRange.new(0.6, 1.2), Size = 0.12 },
		Rate = 0.6, Max = 22, Below = true, Vel = function() return Vector3.new(0, rng:NextNumber(-2, 0), 0) end }
	-- ÉTAT « gelé » (blocage après 3 coups) : gangue de glace autour de la cible + éclats de givre
	V.Status = {
		Kind = "Frozen", Static = true, Rate = 6, FadeTime = 0.3,
		Opts = { Colors = { Color3.new(1, 1, 1), Color3.fromHex("d8f8ff"), Color3.fromHex("8fe3ff") }, Gravity = 0.4, Drag = 2, Life = NumberRange.new(0.4, 0.8), Size = 0.12 },
		Vel = function() return Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) end,
		Start = function(s, root)
			local holder = holderPart(root.Position)
			local block = Instance.new("Part")
			block.Anchored, block.CanCollide, block.CanQuery, block.CanTouch, block.CastShadow = true, false, false, false, false
			-- glace LUMINEUSE et translucide (en Glacier elle restait noire dans la pénombre)
			block.Material = Enum.Material.Neon
			block.Color = Color3.fromHex("7fc8ea")
			block.Size = Vector3.new(3.2, 5.6, 3.2)
			block.Transparency = 1
			block.CFrame = holder.CFrame * CFrame.new(0, -0.3, 0)
			block.Parent = holder
			tween(block, 0.12, { Transparency = 0.62 })
			s.Holder = holder
			s.Light = LightPool.Attach(holder, Color3.fromHex("8fe3ff"), 10, 1.2 * api.Glow(), 0.3)
		end,
		Stop = function(s) -- la glace se brise en éclats
			Sparks.Burst(s.Holder.Position, { Count = 18, Colors = { Color3.new(1, 1, 1), Color3.fromHex("bfeaff"), Color3.fromHex("8fe3ff") },
				Speed = NumberRange.new(6, 14), Gravity = 1.4, Drag = 0.5, Bounce = 0.4, Life = NumberRange.new(0.5, 1), Size = 0.16 })
		end,
	}
	-- ÉTAT DU CORPS « refroidi » (décoratif, Status.Body) : le personnage GRELOTTE et souffle de la BUÉE.
	-- Lu par VFXManager (moteur générique des états du corps). Pause pendant le gel (bloc de glace).
	V.Body = {
		PauseIf = "Frozen",
		-- grelottements : petites rotations rapides des articulations (degrés, Hz), plus fortes au début
		Shiver = { Joints = { "Neck", "Left Shoulder", "Right Shoulder", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "Waist" },
			Amp = 3.2, Freq = 17, NeckAmp = 2.4 },
		-- buée : petite bouffée devant la bouche toutes les Every s
		Breath = { Every = { 1.1, 1.7 },
			Opts = { Puff = true, Grow = 2.6, Fade0 = 0.7, Count = 4,
				Colors = { Color3.fromHex("56636c"), Color3.fromHex("4c5861"), Color3.fromHex("424d55") },
				Gravity = -0.12, Drag = 2.8, Life = NumberRange.new(0.7, 1.1), Size = 0.32 },
			Speed = 3.2 },
	}
	return V
end
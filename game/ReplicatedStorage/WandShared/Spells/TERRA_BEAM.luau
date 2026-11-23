-- TERRA_BEAM — Rayon tellurique (Beam)
-- Rayon instantané qui REBONDIT ; à chaque surface touchée (rebonds + point final) il fait naître
-- une zone de MATIÈRE de son élément (Patch) : Nature = ronces, Feu = flammes (tombent), Glace = givre
-- glissant, Foudre = sol électrifié, Toxique = flaques. Gigantisme agrandit les zones.
return function(proj)
	local card = { Id = "TERRA_BEAM", Name = "Rayon tellurique", Short = "RT", Type = "Projectile", Element = "Nature",
		Mana = 18, Recharge = 0.15, CastDelay = 0.3,
		Desc = "Rayon qui rebondit 2 fois. Chaque surface touchée fait naître une zone de matière de son élément (ronces sans infusion). Gigantisme : zones plus grandes.",
		Proj = proj({ Damage = 6, Instant = true, Range = 70, Pierce = 1, Bounces = 2, Size = 0.5 }) }
	card.Order = 69
	card.Family = "Beam" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	card.Sound = { Cast = false, Beam = "Beam.Laser" }
	card.FX = { Beam = "Laser" }

	-- anti-spam en MAINTIEN : une zone par endroit, au plus toutes les 0,6 s
	local last: { [any]: { t: number, p: Vector3 } } = {}
	local function allowed(owner, pos: Vector3): boolean
		local now = os.clock()
		local key = owner or 0
		local list = last[key] or {}
		last[key] = list
		for i = #list, 1, -1 do
			local e = list[i]
			if now - e.t > 0.6 then
				table.remove(list, i)
			elseif (e.p - pos).Magnitude < 3 then
				return false
			end
		end
		table.insert(list, { t = now, p = pos })
		return true
	end

	card.Hooks = {
		-- appelé à CHAQUE surface du décor touchée par le rayon (rebonds compris)
		OnSurface = function(ctx)
			if not allowed(ctx.Owner, ctx.Pos) then
				return
			end
			-- taille : Gigantisme grossit le rayon (Size) -> zones plus grandes (jusqu'à x8)
			local s = ctx.Stats
			local scale = math.clamp(math.max(s.ZoneScale or 1, (s.Size or 0.5) / 0.5) ^ 1.35, 0.5, 8)
			ctx.CreateZone({ Kind = "Patch", Radius = 3.2, Duration = 3.5, Damage = 1.5, Interval = 0.5 }, scale)
		end,
	}
	return card
end

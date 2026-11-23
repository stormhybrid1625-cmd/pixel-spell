-- TRAIL_FIRE — Traînée élémentaire (Modificateur à COMPORTEMENT, phase 1.6) — l'Id reste TRAIL_FIRE (decks existants)
-- Modificateur UNIVERSEL : une seule accroche OnTick (« en vol »), et il marche sur les 3 moteurs :
--   projectile = le long de sa trajectoire | rayon = le long de chaque segment | Ramure = sous chaque nouvelle branche.
-- La traînée prend l'ÉLÉMENT DU SORT (son infusion) : feu, givre, poison, foudre, ronces. Sans infusion qui pose une
-- zone au sol, c'est du feu. Chaque morceau est une petite zone au sol (plafond séparé « Trail » dans ZoneService).
-- Elle est posée jusqu'à la FIN du sort : pas de limite par tir ; au-delà de 24 morceaux, ils s'espacent (x2, puis x3)
-- pour rester légers sur les très longs tirs.
return function(proj)
	local card = { Id = "TRAIL_FIRE", Name = "Traînée élémentaire", Short = "TF", Type = "Modifier",
		Mana = 16, Recharge = 0.1, CastDelay = 0.15,
		Desc = "Le sort laisse une traînée de son élément derrière lui, jusqu'à sa fin : le long de sa trajectoire, de son rayon ou de ses branches. Feu sans infusion. Cumulable : traînée plus large. Raccourcit un peu la durée du sort (-8 %, puis -3 % par projectile en plus dans le clic, max -35 %).",
		Mod = {} }
	card.Order = 70 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam", "Procedural" } -- comportement universel : les 3 moteurs (pas le Bouclier)

	-- éléments qui ont une zone au sol (visuels + sons + comportement : Elements/<El>.Visuals.Patch)
	local HAS_PATCH = { Fire = true, Ice = true, Toxic = true, Lightning = true, Nature = true }
	local STEP = 3 -- un morceau tous les 3 studs parcourus...
	local function stepFor(n: number): number
		return if n < 24 then STEP elseif n < 48 then STEP * 2 else STEP * 3 -- ...puis plus espacés sur les longs tirs
	end
	local function drop(ctx, at: Vector3)
		ctx.Mem.N = (ctx.Mem.N or 0) + 1
		ctx.Pos, ctx.Normal = at, nil
		local el = if HAS_PATCH[ctx.Element] then ctx.Element else "Fire"
		ctx.CreateZone({ Kind = "Patch", Radius = 1.4 + 0.5 * (ctx.Stacks - 1), Duration = 2.6, Damage = 1.5, Interval = 0.5, Trail = true, TrailKey = ctx.Mem }, 1, el) -- TrailKey : 1 traînée = 1 tir (éviction équitable)
	end

	card.Hooks = {
		OnTick = function(ctx)
			-- segment parcouru depuis le dernier appel : rayon / branche = From -> Pos ; projectile = dernière position mémorisée
			local from = ctx.From or ctx.Mem.Last
			ctx.Mem.Last = ctx.Pos
			if not from then
				return
			end
			local seg = ctx.Pos - from
			local len = seg.Magnitude
			if len < 1e-3 then
				return
			end
			-- Acc = distance parcourue depuis le dernier morceau
			local acc = ctx.Mem.Acc or STEP * 0.5
			local d = stepFor(ctx.Mem.N or 0) - acc -- distance le long du segment jusqu'au prochain morceau
			while d <= len do
				drop(ctx, from + seg.Unit * math.max(d, 0))
				d += stepFor(ctx.Mem.N or 0)
			end
			ctx.Mem.Acc = len - (d - stepFor(ctx.Mem.N or 0))
		end,
	}
	return card
end

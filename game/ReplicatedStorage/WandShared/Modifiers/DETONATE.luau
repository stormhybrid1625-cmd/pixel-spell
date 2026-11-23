-- DETONATE — Détonation (Modificateur à COMPORTEMENT, phase 1.6)
-- Exemple de modificateur UNIVERSEL : une seule accroche OnHit (« au contact »), et il marche sur les 3 moteurs :
-- projectile qui touche, rayon qui traverse une cible, branche de Ramure qui blesse -> une explosion sur la cible.
return function(proj)
	local card = { Id = "DETONATE", Name = "Détonation", Short = "DT", Type = "Modifier",
		Mana = 14, CastDelay = 0.1,
		Desc = "Chaque cible touchée par le sort explose (rayon 3, 5 dégâts, de l'élément du sort). Marche aussi avec les rayons et les branches. Cumulable : explosion plus grosse.",
		Mod = {} }
	card.Order = 71 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam", "Procedural" } -- comportement universel : les 3 moteurs (pas le Bouclier)

	card.Hooks = {
		OnHit = function(ctx, hum: Humanoid)
			-- une branche blesse en continu : au plus une explosion par cible toutes les 0,6 s
			local last = ctx.Mem[hum]
			if last and os.clock() - last < 0.6 then
				return
			end
			ctx.Mem[hum] = os.clock()
			local r = 3 + ctx.Stacks
			ctx.Explode(r, 5 * ctx.Stacks)
			ctx.FX({ k = "Impact", n = Vector3.yAxis, e = ctx.Element, r = r, s = 1, c = "BOMB", x = true })
		end,
	}
	return card
end

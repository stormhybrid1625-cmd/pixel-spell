--[[
	WandShared/Incantation — RÈGLES DE L'INCANTATION (partagées serveur / client : même décision des deux côtés)
	Règles (user 2026-11-22) :
	  • possible seulement si le COÛT du deck dépasse le mana MAXIMUM de la baguette (pas le mana actuel) ;
	  • seulement avec une baguette au-dessus de Moyenne (Tier ~= "Moyenne") ;
	  • coût max incantable = OverflowCap x mana ACTUEL (baguette : Supérieure 1,1-1,5, Suprême 2-2,5) ;
	  • impossible sous 25 % du mana max ;
	  • durée = BASE + dépassement / mana max x PER_MAX, divisée par IncantSpeed ; le dépassement est compté depuis
	    le mana ACTUEL (barre basse = incantation plus longue).
	  • + PER_MANA s par point de mana du deck (chaque carte rallonge selon son coût) ;
	  • chaque cercle dure au prorata de son POIDS (coût du sort + de ses modificateurs) ;
	  • un cercle par tir du premier niveau du deck (max MAX_CIRCLES), chargés un par un ; relâcher tôt = seuls les
	    cercles terminés partent, et on ne paie que leur part.
]]
local Incantation = {}

Incantation.MIN_MANA_FRAC = 0.25
Incantation.BASE = 1.0 -- s
Incantation.PER_MAX = 4.0 -- s par « mana max » de dépassement
Incantation.PER_MANA = 0.01 -- s par point de mana du deck : chaque carte rallonge selon son coût (user)
Incantation.MAX_TIME = 14.0 -- s
Incantation.MAX_CIRCLES = 12

export type Verdict = { Ok: boolean, Reason: string?, Duration: number?, Overflow: number? }

-- wand : stats de baguette (ManaMax, Tier, IncantSpeed, OverflowCap) ; cost : coût du tir ; mana : mana actuel
function Incantation.Check(wand: any, cost: number, mana: number): Verdict
	local max = wand.ManaMax or 0
	if cost <= max then
		return { Ok = false, Reason = "NotOver" } -- payable avec une barre pleine : tir normal (ou attendre la régén)
	end
	local tier = wand.Tier or "Moyenne"
	if tier == "Moyenne" then
		return { Ok = false, Reason = "Tier" }
	end
	-- l'incantation ne peut ASSIMILER qu'un multiple du mana ACTUEL (pas du max) : OverflowCap par baguette
	-- (Supérieure classique 1,1 à 1,5 ; Suprême 2 à 2,5)
	if cost > mana * (wand.OverflowCap or 1.5) then
		return { Ok = false, Reason = "Cap" }
	end
	if mana < max * Incantation.MIN_MANA_FRAC then
		return { Ok = false, Reason = "LowMana" }
	end
	local overflow = cost - mana
	local dur = (Incantation.BASE + overflow / math.max(max, 1) * Incantation.PER_MAX + cost * Incantation.PER_MANA) / math.max(wand.IncantSpeed or 1, 0.1)
	return { Ok = true, Duration = math.min(dur, Incantation.MAX_TIME), Overflow = overflow }
end

-- liste APLATIE des tirs à incanter : chaque tir du premier niveau, suivi des sorts que son déclencheur
-- transporte (en profondeur). Root = indice du tir du premier niveau auquel le cercle appartient.
function Incantation.Flatten(plan: any): { { Shot: any, Root: number } }
	local out = {}
	local function walk(node, root: number?)
		for i, shot in (node and node.Shots) or {} do
			if #out >= Incantation.MAX_CIRCLES then
				return
			end
			local r = root or i
			table.insert(out, { Shot = shot, Root = r })
			if shot.Payload then
				walk(shot.Payload, r)
			end
		end
	end
	walk(plan and plan.Root, nil)
	return out
end

-- nombre de cercles d'un plan (tous les sorts, charges des déclencheurs comprises)
function Incantation.Circles(plan: any): number
	return math.clamp(#Incantation.Flatten(plan), 1, Incantation.MAX_CIRCLES)
end

return Incantation

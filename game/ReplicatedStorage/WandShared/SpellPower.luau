--[[
	WandShared/SpellPower — PUISSANCE GÉNÉRALE d'un sort, APRÈS modificateurs (user 2026-11-23)
	Un seul nombre pour dire « à quel point ce sort est fort » : sert à décider s'il casse les structures,
	et servira plus tard partout où il faut comparer des sorts entre eux.
	Puissance = Dégâts x Taille x sqrt(Vitesse / 80)   (vitesse plancher 20 : un sort lent garde du poids)
	Repères : Boule de feu de base ~15 ; + Gigantisme I ~25 ; + Gigantisme I + D+ ~38.
]]
local SpellPower = {}

function SpellPower.Of(stats): number
	local dmg = math.max(stats.Damage or 0, 0)
	local size = math.max(stats.Size or 0.5, 0.1)
	local speed = math.max(stats.Speed or 80, 20)
	return dmg * size * math.sqrt(speed / 80)
end

-- casse-structures : rayon de destruction si le sort dépasse le seuil de la carte (card.BreakAbove), sinon nil
function SpellPower.BreakRadius(stats, rule): number?
	if not rule then
		return nil
	end
	if (stats.Size or 0) < (rule.Size or 0) then
		return nil
	end
	local p = SpellPower.Of(stats)
	if p < (rule.Power or 0) then
		return nil
	end
	return math.clamp((rule.Radius or 2) * math.sqrt(p / rule.Power), 1.2, rule.MaxRadius or 7), p
end

return SpellPower

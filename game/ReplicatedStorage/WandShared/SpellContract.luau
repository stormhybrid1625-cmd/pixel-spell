--[[
	WandShared/SpellContract — CONTRAT DE SORT (ce qu'un sort doit respecter pour que les modificateurs marchent)

	1) Chaque sort déclare sa FAMILLE (card.Family) : Projectile | Beam | Procedural | Trap | Self | Multicast.
	   La famille dit quel MOTEUR exécute le sort et donc quelles STATS il lit (READS ci-dessous).
	2) Un modificateur agit sur un sort par 4 voies, toutes génériques (aucune exception codée dans le sort) :
	     S = STATS   : il change des stats résolues (SpellPlanner.Resolve) que le moteur de la famille LIT ;
	     H = ACCROCHE: il ajoute des accroches universelles (OnTick / OnHit / OnSurface / OnEnd), appelées par TOUS
	                   les moteurs (ctx.Engine dit lequel) ;
	     C/T = TIR   : copies (Divisé par N), déclencheurs (Ajout de déclencheur / minuterie / expiration) ;
	     L = LANCEMENT : délai, recharge, mana, mode (Rapidité, Recharge éclair, Ajout de mana, Maintien).
	   + R = RÉACTION SPÉCIALE : card.ModReactions[modId] (le sort réinterprète le modificateur, ex. Orbite sur Ramure).
	3) card.AppliesTo (sur le modificateur) = familles où il a un effet ; l'UI s'en sert pour dire « sans effet ».
	   La DÉCLARATION doit correspondre à la RÉALITÉ : WandTools.Coverage() vérifie les deux sens.
	4) Un NOUVEAU sort qui respecte le contrat reçoit automatiquement tous les modificateurs de sa famille.
	   S'il a besoin d'une stat nouvelle, on l'ajoute au moteur de la famille + à READS (jamais un cas particulier).
]]
local function set(s: string)
	local t = {}
	for k in s:gmatch("%w+") do
		t[k] = true
	end
	return t
end
local PROJ = "Bounces Chain Damage DurationMult Element Fragments FxScale Gravity Homing Knockback Lifetime OrbitRadius Phase Pierce SelfDamage Radius Size Speed SpiralRadius Trajectory ZoneScale"
local Contract = {}
-- stats lues par le moteur de chaque famille (relevées dans ProjectileService / fireInstant / GrowthService)
Contract.Reads = {
	Projectile = set(PROJ),
	Trap = set(PROJ), -- le piège transmet tout à ce qu'il déclenche
	Beam = set("Bounces Chain Damage DurationMult Element Fragments FxScale Knockback Phase Pierce Range Size"), -- Phase : Ignore Obstacles (casse / rebondit) -- (Fragments : éclats au bout du rayon, vérifié au banc)
	Procedural = set("ArmsAdd CageTargets OrbitRadius DurationMult Element ForkAdd Gravity GrowSpeed GrowTime Homing HomingTargets Knockback Phase ProcScale Radius Range ZoneScale Damage Spiral SpiralRadius"),
	Self = set("DurationMult Element ZoneScale FxScale"),
}
-- ce que chaque famille accepte EN PLUS des stats (nil = tout) :
-- déclencheurs ajoutés (Ajout de déclencheur / minuterie / expiration), copies (Divisé par N), accroches (traînée, détonation)
Contract.Triggers = { Procedural = { ADD_EXPIRE = true }, Self = {} } -- l'arbre ne connaît que la fin (expiration)
Contract.NoCopies = { Self = true } -- un bouclier n'est jamais dupliqué
Contract.NoHooks = { Self = true } -- un bouclier n'a ni trajet ni impact
Contract.Transmits = { Trap = true } -- le piège transmet TOUT à ce qu'il déclenche (jamais d'incohérence)
return Contract

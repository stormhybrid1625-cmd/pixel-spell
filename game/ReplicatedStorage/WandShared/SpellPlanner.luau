--[[
	WandShared/SpellPlanner — Lecture du deck (PURE, partagée client / serveur)

	Le MÊME code sert :
	  • au serveur (SpellEngine) pour décider ce qui est réellement lancé ;
	  • au client (WandUI) pour l'APERÇU "prochain clic" -> l'aperçu est exact par construction.
	Le client ne décide jamais rien : le serveur recalcule toujours son propre plan.

	RÈGLES DE LECTURE :
	  • Un groupe pioche `draw` cartes ; le curseur est partagé par tout l'arbre (une carte = lue 1 fois par clic).
	  • Projectile : 1 tir. Carte avec Copies = N : N projectiles identiques en éventail.
	  • Modifier   : s'applique à TOUS les projectiles qui le suivent dans le groupe, rend sa pioche (+1).
	      Exceptions "ONE-SHOT" (consommées par le PROCHAIN projectile seulement) :
	        AddTrigger   -> transforme ce projectile en déclencheur (il emporte la carte suivante) ;
	        Divide       -> ce projectile est lancé en N copies (se multiplie si plusieurs Divide) ;
	        DivideDamage -> malus de dégâts appliqué aux copies.
	  • Multicast  : ajoute `Draw` pioches au groupe + dispersion.
	  • Trigger    : 1 tir dont la CHARGE = sous-groupe construit avec les cartes suivantes
	                 (nouvel état : la charge n'hérite pas des modificateurs du parent).
	  • Fin de deck : la lecture peut boucler UNE fois au début, puis la baguette recharge.

	GARDE-FOUS (Config.Limits) : MaxIterations, MaxDepth, MaxProjectilesPerCast.
	Les copies (Divide / Copies) comptent avec leur charge : 3 copies d'un trigger qui emporte
	2 projectiles = 3 x (1 + 2) = 9 projectiles. Si la limite est atteinte, le plan est TRONQUÉ proprement.
]]

local Shared = script.Parent
local Config = require(Shared.Config)
local Catalog = require(Shared.SpellCatalog)

local Limits = Config.Limits

local Planner = {}

-- ── État de modificateurs ─────────────────────────────────────────────────────────────────
export type ModState = {
	DamageAdd: number, DamageMult: number,
	SpeedMult: number, SizeMult: number,
	RadiusAdd: number, RadiusMult: number,
	LifetimeMult: number, GravityAdd: number,
	Homing: number, BouncesAdd: number, PierceAdd: number, SpreadAdd: number,
	Fragments: number, Knockback: number, DurationMult: number,
	Trajectory: string?, Element: string?,
	-- one-shot
	AddTrigger: { Kind: string, Draw: number, Delay: number? }?,
	Divide: number,
	DivideDamage: number,
	-- CUMUL (expérimental) : exemplaires déjà appliqués par carte modificatrice dans ce groupe
	Stacks: { [string]: number },
}

-- Un même modificateur se CUMULE jusqu'à MAX_STACK fois dans un groupe de tir (3 x Gigantisme I = x3,4).
-- Au-delà, l'exemplaire est lu (et payé) mais n'a plus d'effet. Les INFUSIONS ne se cumulent pas :
-- une 2e infusion identique est sans effet (une infusion différente remplace l'élément, comme avant).
local MAX_STACK = 3
Planner.MaxStack = MAX_STACK

local ADDITIVE = { SpiralAdd = true, DamageAdd = true, RadiusAdd = true, GravityAdd = true, Homing = true, BouncesAdd = true, PierceAdd = true, SpreadAdd = true, Fragments = true, Knockback = true, ArmsAdd = true, ForkAdd = true }
local MULTIPLY = { DamageMult = true, SpeedMult = true, SizeMult = true, RadiusMult = true, LifetimeMult = true, DurationMult = true, Divide = true, DivideDamage = true, GrowSpeedMult = true, GrowTimeMult = true, RangeMult = true }
local OVERRIDE = { Trajectory = true, Element = true, AddTrigger = true, Phase = true, CastMode = true, Cage = true }

local function newState(): ModState
	return {
		DamageAdd = 0, DamageMult = 1, SpeedMult = 1, SizeMult = 1, RadiusAdd = 0, RadiusMult = 1,
		LifetimeMult = 1, GravityAdd = 0, Homing = 0, BouncesAdd = 0, PierceAdd = 0, SpreadAdd = 0,
		Fragments = 0, Knockback = 0, DurationMult = 1, ArmsAdd = 0, ForkAdd = 0, GrowSpeedMult = 1, GrowTimeMult = 1,
		RangeMult = 1, -- portée des RAYONS (seuls Accélération, Lest, Rebond la changent ; plus la durée de vie : Orbite/Boomerang n'agissent pas)
		SpiralAdd = 0, -- exemplaires de Spirale cumulés : chaque exemplaire élargit le rayon de la spirale
		Trajectory = nil, Element = nil,
		AddTrigger = nil, Divide = 1, DivideDamage = 1,
		Stacks = {},
		Phase = false, -- Ignore Obstacles (sorts procéduraux uniquement)
		CastMode = nil,
	}
end

local function applyMod(state: ModState, mod: { [string]: any })
	for key, value in mod do
		if ADDITIVE[key] then
			state[key] += value
		elseif MULTIPLY[key] then
			state[key] *= value
		elseif key == "AddTrigger" and value.Kind == "Expire" and state.AddTrigger and state.AddTrigger.Kind == "Expire" then
			-- Ajout d'expiration CUMULÉ : chaque exemplaire libère UNE carte de plus à l'expiration (max 3 = 3 sorts)
			state.AddTrigger = { Kind = "Expire", Draw = state.AddTrigger.Draw + value.Draw }
		elseif OVERRIDE[key] then
			state[key] = value
		end
	end
end

-- ── Budget / lecteur ────────────────────────────────────────────────────────────────────────
type Budget = {
	Iterations: number, Projectiles: number, Mana: number, CastDelay: number, Recharge: number,
	Truncated: boolean, Reason: string?,
}

local function truncate(budget: Budget, reason: string)
	if not budget.Truncated then
		budget.Truncated = true
		budget.Reason = reason
	end
end

type Reader = { Deck: { string }, Size: number, Cursor: number, Used: { [number]: boolean }, Wrapped: boolean, Injected: { any } }

-- Renvoie (carte, injectée?). Les copies injectées par les lettres grecques passent en premier.
local function draw(reader: Reader, budget: Budget)
	if #reader.Injected > 0 then
		budget.Iterations += 1
		if budget.Iterations > Limits.MaxIterations then
			truncate(budget, "MaxIterations")
			return nil, false
		end
		local e = table.remove(reader.Injected, 1)
		return e.Card, true, e.N
	end
	local guard = 0
	while true do
		guard += 1
		if guard > reader.Size * 2 + 2 then
			return nil -- garde locale : impossible de tourner en rond
		end
		budget.Iterations += 1
		if budget.Iterations > Limits.MaxIterations then
			truncate(budget, "MaxIterations")
			return nil
		end
		if reader.Cursor > reader.Size then
			if reader.Wrapped then
				return nil
			end
			reader.Wrapped = true -- bouclage unique vers le début
			reader.Cursor = 1
		end
		local index = reader.Cursor
		if reader.Used[index] then
			return nil -- tout le deck a déjà été lu pendant ce clic
		end
		reader.Cursor += 1
		local card, n = Catalog.ParseSlot(reader.Deck[index])
		if card then
			reader.Used[index] = true
			return card, false, n -- n = exemplaires empilés sur ce slot (1 à 3)
		end
	end
end

-- ── Lettres grecques (Alpha, Gamma, Tau, Oméga, Mu, Phi, Sigma) ──────────────────────────────────────
-- Elles INJECTENT des copies de cartes du deck dans la file de lecture. Les copies sont lues avant le
-- deck, ne coûtent rien, ne consomment aucun slot et ne peuvent jamais être des lettres grecques
-- (aucune récursion possible). Le deck est lu SANS être consommé.
local MAX_COPIES = 26

-- renvoie une entrée { Card, N } (la copie garde le cumul du slot)
local function copyable(entry: string?)
	local card, n = Catalog.ParseSlot(entry)
	if card and not card.Greek then
		return { Card = card, N = n }
	end
	return nil
end

local function greekCopies(reader: Reader, kind: string): { any }
	local deck = reader.Deck
	local out = {}
	if kind == "Alpha" then
		for i = 1, reader.Size do
			local c = copyable(deck[i])
			if c then
				return { c }
			end
		end
	elseif kind == "Gamma" then
		for i = reader.Size, 1, -1 do
			local c = copyable(deck[i])
			if c then
				return { c }
			end
		end
	elseif kind == "Tau" then
		-- les 2 cartes suivantes (en bouclant), sans avancer le curseur
		for step = 0, reader.Size - 1 do
			local i = (reader.Cursor - 1 + step) % math.max(reader.Size, 1) + 1
			local c = copyable(deck[i])
			if c then
				table.insert(out, c)
				if #out == 2 then
					break
				end
			end
		end
	else
		for i = 1, reader.Size do
			local c = copyable(deck[i])
			if c then
				local k = c.Card
				local take = kind == "Omega"
					or (kind == "Mu" and k.Type == "Modifier")
					or (kind == "Phi" and (k.Type == "Projectile" or k.Type == "Trigger") and not (k.Proj and (k.Proj.Zone or k.Proj.Self or k.Proj.Growth)))
					or (kind == "Sigma" and k.Proj ~= nil and (k.Proj.Zone ~= nil or k.Proj.Growth ~= nil))
				if take and #out < MAX_COPIES then
					table.insert(out, c)
				end
			end
		end
	end
	return out
end

local function hasCardFrom(reader: Reader): boolean
	for i = reader.Cursor, reader.Size do
		if (Catalog.ParseSlot(reader.Deck[i])) then
			return true
		end
	end
	return false
end

-- ── Arbre de tir ────────────────────────────────────────────────────────────────────────────
export type Shot = {
	Card: any,
	State: ModState,
	Trigger: { Kind: string, Draw: number, Delay: number? }?,
	Payload: CastNode?,
	Copies: number,
}
export type CastNode = { Shots: { Shot }, Spread: number, Formation: string? }

local function fragmentsOf(shot): number
	return math.min(shot.State.Fragments, Limits.MaxFragments)
end

-- Nombre total de projectiles d'un nœud, charges comprises.
function Planner.Count(node: CastNode): number
	local n = 0
	for _, shot in node.Shots do
		n += shot.Copies * (1 + fragmentsOf(shot) + (if shot.Payload then Planner.Count(shot.Payload) else 0))
	end
	return n
end

local function buildNode(reader: Reader, budget: Budget, drawCount: number, depth: number): CastNode
	local node: CastNode = { Shots = {}, Spread = 0, Formation = nil }
	local state = newState()
	local pending = drawCount

	while pending > 0 and not budget.Truncated do
		local card, injected, count = draw(reader, budget)
		if not card then
			break
		end
		count = if card.Type == "Modifier" then math.max(1, count or 1) else 1
		pending -= 1
		local growing = card.Type == "Modifier" and card.ManaGrowth ~= nil
		if not injected then -- une copie ne coûte rien ; un slot empilé coûte N fois
			if not growing then
				-- EMPILEMENT sur un slot (user) : somme x multiplicateur (x1 / x1,15 / x1,35 / +0,2 par carte ensuite)
				local stackMult = if count <= 1 then 1 elseif count == 2 then 1.15 elseif count == 3 then 1.35 else 1.35 + (count - 3) * 0.2
				budget.Mana += math.floor(card.Mana * count * stackMult + 0.5)
			end -- (coût CROISSANT : payé exemplaire par exemplaire plus bas)
			budget.CastDelay += card.CastDelay * count
			budget.Recharge += card.Recharge * count
		end

		if card.Type == "Modifier" then
			for _ = 1, count do
				local n = (state.Stacks[card.Id] or 0) + 1
				local limit = if card.Mod.Element then 1 else (card.MaxStack or MAX_STACK)
				if growing and not injected then
					-- exemplaire n : Mana x Croissance^(n-1) (Rapidité : 3, 6, 12, 24, 48, 96)
					local c = card.Mana * card.ManaGrowth ^ (math.min(n, limit) - 1)
					budget.Mana += c
					-- ce coût ne compte PAS dans le délai de mana (sinon Rapidité annulerait son propre effet)
					budget.SpeedMana = (budget.SpeedMana or 0) + c
				end
				if n <= limit then
					state.Stacks[card.Id] = n
					applyMod(state, card.Mod)
					if card.DelayCut then -- réduction PROPORTIONNELLE et EXPONENTIELLE du délai et de la recharge (Rapidité)
						local cut = math.clamp(card.DelayCut * (card.DelayCutGrowth or 1) ^ (n - 1), 0, 0.8)
						budget.DelayMult = (budget.DelayMult or 1) * (1 - cut)
					end
					-- mode de lancement : seul le groupe RACINE décide comment le joueur lance (clic / maintien)
					if card.Mod.CastMode and depth == 0 then
						budget.CastMode = card.Mod.CastMode
					end
				else
					budget.Capped = (budget.Capped or 0) + 1 -- exemplaire en trop : sans effet
					if not injected then -- ... y compris sur le délai (sinon 7 Rapidité réduiraient plus que 6)
						budget.CastDelay -= card.CastDelay
						budget.Recharge -= card.Recharge
						-- ... et un exemplaire en trop ne REMBOURSE plus de mana (abus : 10 x Ajout de mana = -300)
						if card.Mana < 0 and not growing then
							budget.Mana -= card.Mana
						end
					end
				end
			end
			pending += 1 -- un modificateur ne compte pas comme un tir
		elseif card.Greek then
			-- lettre grecque : ses copies passent en tête de file et sont lues comme des cartes normales
			local copies = greekCopies(reader, card.Greek)
			for i = #copies, 1, -1 do
				table.insert(reader.Injected, 1, copies[i])
			end
			pending += #copies
		elseif card.Type == "Multicast" then
			pending += card.Draw
			node.Spread += card.Spread or 0
			node.Formation = card.Formation or node.Formation -- cercle / arrière : la dernière formation lue l'emporte
		else -- Projectile / Trigger
			if budget.Projectiles >= Limits.MaxProjectilesPerCast then
				truncate(budget, "MaxProjectilesPerCast")
				break
			end
			budget.Projectiles += 1

			local wantedCopies = math.max(1, math.floor(state.Divide)) * (card.Copies or 1)
			local snapshot = table.clone(state)
			snapshot.Stacks = table.clone(state.Stacks)
			local shot: Shot = {
				Card = card,
				State = snapshot,
				Trigger = card.Trigger or state.AddTrigger,
				Payload = nil,
				Copies = 1,
			}
			shot.State.DamageMult *= state.DivideDamage
			-- les éclats de Fragmentation comptent dans le budget comme de vrais projectiles
			local frags = fragmentsOf(shot)
			if frags > 0 then
				local room = math.max(0, Limits.MaxProjectilesPerCast - budget.Projectiles)
				if frags > room then
					shot.State.Fragments = room
					truncate(budget, "MaxProjectilesPerCast")
				end
				budget.Projectiles += fragmentsOf(shot)
			end
			-- les modificateurs one-shot sont consommés par CE projectile
			state.AddTrigger = nil
			state.Divide = 1
			state.DivideDamage = 1

			if shot.Trigger then
				if depth + 1 > Limits.MaxDepth then
					truncate(budget, "MaxDepth") -- récursion bornée : part sans charge
				else
					shot.Payload = buildNode(reader, budget, shot.Trigger.Draw, depth + 1)
				end
			end

			-- copies supplémentaires, dans la limite du budget (chaque copie emporte sa charge)
			if wantedCopies > 1 then
				local per = 1 + fragmentsOf(shot) + (if shot.Payload then Planner.Count(shot.Payload) else 0)
				local room = math.max(0, Limits.MaxProjectilesPerCast - budget.Projectiles)
				local extra = math.min(wantedCopies - 1, room // per)
				if extra < wantedCopies - 1 then
					truncate(budget, "MaxProjectilesPerCast")
				end
				shot.Copies = 1 + extra
				budget.Projectiles += extra * per
				node.Spread += extra * 4 -- les copies s'écartent légèrement
			end
			table.insert(node.Shots, shot)
		end
	end
	return node
end

export type Plan = {
	Root: CastNode,
	Mana: number,
	CastDelay: number,
	Recharge: number,
	NextCursor: number,
	ReachedEnd: boolean,
	Empty: boolean,
	FirstElement: string?,
	Truncated: boolean,
	Reason: string?,
	Iterations: number,
	Projectiles: number,
	Used: { [number]: boolean }, -- slots lus pendant ce clic
	Start: number, -- slot de départ
}

-- DÉLAI DE MANA : plus un tir coûte cher, plus la baguette met de temps à s'en remettre.
-- +0,0015 s par point de mana au-delà de 30, PLAFONNÉ à +0,3 s (s'ajoute au délai propre des cartes, déjà lourd
-- pour Gigantisme & co) : boule de feu 30 -> 0 ; 92 -> +0,09 s ; 125 -> +0,14 s ; 250+ -> +0,3 s.
-- (v1 : 0,004/pt dès 15 sans plafond -> jusqu'à 1,6-1,9 s d'attente, jugé beaucoup trop long)
Planner.MANA_DELAY_FREE = 30
Planner.MANA_DELAY_PER_POINT = 0.0015
Planner.MANA_DELAY_MAX = 0.3
function Planner.ManaDelay(mana: number): number
	return math.min(Planner.MANA_DELAY_MAX, math.max(0, (mana or 0) - Planner.MANA_DELAY_FREE) * Planner.MANA_DELAY_PER_POINT)
end

function Planner.Plan(deck: { string }, wand: Config.WandStats, cursor: number): Plan
	local budget: Budget = { Iterations = 0, Projectiles = 0, Mana = 0, CastDelay = 0, Recharge = 0, Truncated = false, Reason = nil }
	local size = #deck
	local start = math.clamp(math.floor(tonumber(cursor) or 1), 1, math.max(size, 1))
	local reader: Reader = { Deck = deck, Size = size, Cursor = start, Used = {}, Wrapped = false, Injected = {} }

	local root = buildNode(reader, budget, math.max(1, wand.SpellsPerCast), 0)
	-- Traînée élémentaire : chaque tir connaît le nombre total de projectiles du clic (durée raccourcie selon la charge)
	local castCount = math.max(1, Planner.Count(root))
	local function markCount(node)
		for _, shot in node.Shots do
			shot.State.CastCount = castCount
			if shot.Payload then
				markCount(shot.Payload)
			end
		end
	end
	markCount(root)
	local reachedEnd = reader.Wrapped or not hasCardFrom(reader)
	local first = root.Shots[1]
	local manaDelay = if budget.Projectiles > 0 then Planner.ManaDelay(budget.Mana - (budget.SpeedMana or 0)) else 0
	return {
		Root = root,
		Mana = budget.Mana, -- peut être négatif (Ajout de mana) : le serveur ne facture jamais moins que 0
		CastDelay = math.max(0.03, (wand.CastDelay + budget.CastDelay + manaDelay) * (budget.DelayMult or 1)),
		ManaDelay = manaDelay, -- part du délai due au coût en mana (aperçu)
		Recharge = math.max(0.05, (wand.RechargeTime + budget.Recharge) * (budget.DelayMult or 1)),
		NextCursor = if reachedEnd then 1 else reader.Cursor,
		ReachedEnd = reachedEnd,
		Empty = budget.Projectiles == 0,
		FirstElement = first and (first.State.Element or first.Card.Element) or nil,
		FirstCard = first and first.Card.Id or nil,
		Truncated = budget.Truncated,
		Reason = budget.Reason,
		Iterations = budget.Iterations,
		Projectiles = budget.Projectiles,
		Capped = budget.Capped or 0, -- modificateurs au-delà du cumul max (aperçu)
		CastMode = budget.CastMode or "Click", -- "Click" | "Hold"
		Used = reader.Used,
		Start = start,
	}
end

-- Coût réellement facturé (jamais négatif ; un tir sans projectile est gratuit).
function Planner.Cost(plan: Plan): number
	return if plan.Empty then 0 else math.max(0, plan.Mana)
end

function Planner.Delay(plan: Plan): number
	return if plan.ReachedEnd then math.max(plan.CastDelay, plan.Recharge) else plan.CastDelay
end

-- ── Stats finales d'un tir (carte + modificateurs + baguette), toutes bornées ───────────────────────────
export type ResolvedStats = {
	CardId: string, Element: string, Damage: number, Speed: number, Lifetime: number, Size: number,
	Radius: number, Gravity: number, Bounces: number, Pierce: number, Homing: number,
	Trajectory: string, Trigger: any?,
	Instant: boolean, Range: number, Chain: number, Knockback: number, Fragments: number,
	Aura: any?, Zone: any?, Self: boolean, OnEnd: string?, ZoneScale: number,
	FxScale: number, DurationMult: number, Growth: any?, Mana: number,
}

function Planner.Resolve(shot: Shot, wand: Config.WandStats): ResolvedStats
	local p = shot.Card.Proj
	local s = shot.State
	-- Traînée élémentaire : -8 % de durée, puis -3 % par projectile en plus dans le clic (max -35 %)
	local tfMult = if (s.Stacks.TRAIL_FIRE or 0) > 0 and shot.Card.Family ~= "Self" and shot.Card.Family ~= "Trap" then 1 - math.min(0.35, 0.08 + 0.03 * ((s.CastCount or 1) - 1)) else 1
	local stats = {
		CardId = shot.Card.Id,
		Element = s.Element or shot.Card.Element or "Arcane",
		Damage = math.clamp((p.Damage + s.DamageAdd) * s.DamageMult, 0, 999),
		Speed = math.clamp(p.Speed * s.SpeedMult * wand.SpeedMult, 4, 600),
		Lifetime = math.clamp(p.Lifetime * s.LifetimeMult * tfMult, 0.05, 10),
		-- orbe plafonné (le Gigantisme agrandit les effets via FxScale / ZoneScale / Radius, pas l'orbe)
		Size = math.clamp(p.Size * s.SizeMult, 0.2, math.max(p.Size, Limits.MaxProjectileSize)),
		Radius = math.clamp(p.Radius * s.RadiusMult + s.RadiusAdd, 0, 60),
		Gravity = math.clamp(p.Gravity + s.GravityAdd, -2, 4),
		Bounces = math.clamp(p.Bounces + s.BouncesAdd, 0, 12),
		Pierce = math.clamp(p.Pierce + s.PierceAdd, 0, 12),
		-- un projectile ne devient PAS plus chercheur en cumulant la carte (le cumul ne sert qu'aux procéduraux)
		Homing = math.clamp(s.Homing, 0, 18), -- CUMULABLE : x2 / x3 = virage plus serré + détection plus large (user)
		Trajectory = s.Trajectory or p.Trajectory,
		-- rayon de la spirale autour de l'axe : 1,4 puis +1,2 par exemplaire cumulé (1,4 / 2,6 / 3,8)
		SpiralRadius = 1.4 + 1.2 * math.clamp((s.SpiralAdd or 0) - 1, 0, 2),
		Spiral = (s.SpiralAdd or 0) > 0, -- Spirale présente (sorts procéduraux : hélice commune)
		Trigger = shot.Trigger,
		Instant = p.Instant,
		-- portée : rayons = vitesse x RangeMult ; procéduraux (distance d'ancrage) = vitesse seulement (Rebond / Boomerang n'y touchent plus)
		Range = math.clamp(if p.Growth then p.Range else p.Range * s.SpeedMult * (if p.Instant then s.RangeMult else 1), 0, 200), -- (procédural : portée FIXE, Accélération = pousse plus vite)
		Chain = math.clamp(p.Chain, 0, 6),
		Knockback = math.clamp(p.Knockback + s.Knockback, 0, 150),
		Fragments = fragmentsOf(shot),
		Aura = p.Aura,
		Zone = p.Zone,
		Self = p.Self,
		OnEnd = p.OnEnd,
		-- Gigantisme agrandit aussi les zones (trou noir, gaz, mur, branches...) et TOUS les effets visuels
		ZoneScale = math.clamp(s.SizeMult, 0.5, Limits.MaxScale),
		-- effets visuels et sorts PROCÉDURAUX : plafond plus haut (cumuls expérimentaux)
		FxScale = math.clamp(s.SizeMult, 0.5, Limits.MaxProcScale),
		ProcScale = math.clamp(s.SizeMult, 0.5, Limits.MaxProcScale),
		-- Prolongation : durée des zones / murs / branches
		DurationMult = math.clamp(s.DurationMult * tfMult, 0.25, 4),
		TrailShorten = 1 - tfMult, -- aperçu : part de durée retirée par la Traînée
		Growth = p.Growth,
		Phase = s.Phase == true, -- lu UNIQUEMENT par les sorts procéduraux
		-- "Self" | "Enemy" (sorts procéduraux uniquement) ; réactions spéciales : ModReactions de la carte
		Cage = s.Cage,
		Trap = p.Trap,
		GrowTime = math.clamp(s.GrowTimeMult, 1, 5), -- Élongation : pousse plus longue
		-- sorts PROCÉDURAUX : nombre d'ennemis différents visés = exemplaires cumulés de la carte
		HomingTargets = math.clamp(s.Stacks.HOMING or 0, 0, 3),
		CageTargets = math.clamp(s.Stacks.CAGE or 0, 0, 3),
		-- ORBITE cumulée : rayon 5 puis +3,5 studs par exemplaire, plafond 15 (user) ; s'applique aussi à la cage de Ramure
		OrbitRadius = math.min(5 + 3.5 * math.max((s.Stacks.ORBIT or 0) - 1, 0), 15),
		-- part des dégâts d'explosion RENDUE AU LANCEUR (propriété de nerf réutilisable : card.SelfDamage) (user)
		SelfDamage = shot.Card.SelfDamage or 0,
		ArmsAdd = math.clamp(s.ArmsAdd, 0, 9),
		ForkAdd = math.clamp(s.ForkAdd, 0, 0.2),
		-- Élongation ralentit (x0,85) ; chaque carte VITESSE accélère la pousse (x1,3, même portée)
		GrowSpeed = math.clamp(s.GrowSpeedMult * 1.3 ^ (s.Stacks.SPEED_PLUS or 0), 0.4, 2.5),
		Mana = shot.Card.Mana, -- remboursé si le sort échoue (branche sans surface)
		-- modificateurs PORTÉS par ce tir (id -> exemplaires) : leurs accroches (card.Hooks) tournent sur ce tir,
		-- quel que soit son moteur (projectile, rayon, procédural) -> phase 1.6
		ModStacks = table.clone(s.Stacks),
	}
	-- ACCROCHE ModReactions : la carte réagit à un modificateur précis posé avant elle
	-- (ex. Ramure + Orbite = cage autour du lanceur). Défini dans WandShared/Spells/<ID>.
	local reactions = shot.Card.ModReactions
	if reactions then
		for modId, react in reactions do
			local n = s.Stacks[modId]
			if n and n > 0 then
				react(stats, n)
			end
		end
	end
	return stats
end

return Planner

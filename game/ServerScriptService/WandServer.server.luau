--[[
	WandServer (Script principal)
	Point d'entrée serveur : câble les RemoteEvents, la validation et le moteur de sorts.

	Flux d'un tir :
	  Client --Cast(aimPoint)--> Serveur
	    1. limite de débit (anti-spam)            -> PlayerWands.LastCastReq
	    2. validation du point visé               -> Validator.IsValidAim
	    3. personnage vivant + recharge terminée  -> Validator.IsReady
	    4. PLAN du tir (pur, budget anti-crash)   -> SpellEngine.Plan
	    5. coût mana                              -> Validator.HasMana
	    6. EXÉCUTION (projectiles serveur)        -> SpellEngine.Execute
	    7. mise à jour curseur / délais / attributs répliqués
	  Client --SetDeck(ids)--> Serveur : Validator.SanitizeDeck puis DeckSync renvoie le deck officiel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("WandShared")
local Config = require(Shared.Config)
local Validator = require(Shared.Validator)
local Remotes = Shared.Remotes

local FXBus = require(script.FXBus)
local PlayerWands = require(script.PlayerWands)
local ProjectileService = require(script.ProjectileService)
local SpellEngine = require(script.SpellEngine)
local ZoneService = require(script.ZoneService)
local GrowthService = require(script.GrowthService)
local Dummies = require(script.Dummies)
local MatterService = require(script.MatterService)

local Limits = Config.Limits
local Incantation = require(Shared.Incantation)
local Combat = require(script.Combat)

FXBus.Init(Remotes.SpellFX)
MatterService.Init(require(script.Combat), FXBus) -- matière, feu qui se propage, cratères
local MovementService = require(script.MovementService)
MovementService.Init(require(script.Combat), FXBus) -- course / dash
local MoveAPI = require(script.MoveAPI)
MoveAPI.Init(require(script.Combat), FXBus, MovementService) -- propulser / céleste / tirer / téléporter / échanger
ProjectileService.Init()
ZoneService.Init()
GrowthService.Init(ProjectileService)
-- un sort procédural qui échoue (aucune surface visée) rend le mana de sa carte
GrowthService.OnRefund = function(player: Player, amount: number)
	local st = PlayerWands.Get(player)
	if st then
		st.Mana = math.min(st.Wand.ManaMax, st.Mana + amount)
		PlayerWands.Sync(player)
	end
end
ZoneService.OnRefund = GrowthService.OnRefund -- piège posé dans le vide : carte remboursée
SpellEngine.Bind(ProjectileService)
PlayerWands.Init()
Dummies.Start()

-- ── Joueurs ───────────────────────────────────────────────────────────────────
local function onPlayerAdded(player: Player)
	local st = PlayerWands.Add(player)
	Remotes.DeckSync:FireClient(player, st.Deck, st.Wand)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end
local endHold -- (défini plus bas)
Players.PlayerRemoving:Connect(function(player)
	local st = PlayerWands.Get(player)
	if st and st.Hold then
		endHold(player, st)
	end
	if st and st.Incant then
		st.Incant = nil
	end
	PlayerWands.Remove(player)
	ProjectileService.ClearOwner(player)
	ZoneService.ClearOwner(player)
	GrowthService.ClearOwner(player)
end)

-- ── RÉGLAGES DES EFFETS (caméra / halo / écran) : sauvegardés par joueur (DataStore), lus par le client ──
do
	local HttpService = game:GetService("HttpService")
	local okStore, store = pcall(function()
		return game:GetService("DataStoreService"):GetDataStore("WandFXSettings_v1")
	end)
	local remote = Instance.new("RemoteEvent")
	remote.Name = "WandSettings"
	remote.Parent = ReplicatedStorage
	local pending: { [Player]: any } = {}
	local function clean(t: any)
		if type(t) ~= "table" then
			return nil
		end
		local out = {}
		for _, k in { "Quality", "Shake", "Bloom", "Screen" } do
			local v = t[k]
			out[k] = if type(v) == "number" and v == v then math.clamp(v, 0, 1.5) else 1
		end
		return out
	end
	local function save(player: Player)
		local t = pending[player]
		pending[player] = nil
		if t and okStore then
			pcall(function()
				store:SetAsync("u" .. player.UserId, t)
			end)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		if not okStore then
			return
		end
		local ok, t = pcall(function()
			return store:GetAsync("u" .. player.UserId)
		end)
		t = ok and clean(t)
		if t then
			player:SetAttribute("FXSettings", HttpService:JSONEncode(t))
		end
	end)
	remote.OnServerEvent:Connect(function(player: Player, raw: any)
		local t = clean(raw)
		if not t then
			return
		end
		player:SetAttribute("FXSettings", HttpService:JSONEncode(t))
		local first = pending[player] == nil
		pending[player] = t
		if first then
			task.delay(6, save, player) -- regroupe les clics : une écriture au plus toutes les 6 s
		end
	end)
	Players.PlayerRemoving:Connect(save)
end

-- ── Banc de test (Studio uniquement) : les handlers des remotes sont aussi appelables côté serveur ──
-- (ServerStorage.WandTest:Invoke("Cast", player, aim, mode)) pour piloter plusieurs joueurs à la fois.
local TEST_HANDLERS: { [string]: (...any) -> () } = {}
local function bindRemote(remote: RemoteEvent, name: string, f: (...any) -> ())
	remote.OnServerEvent:Connect(f)
	TEST_HANDLERS[name] = f
end

-- ── SetDeck : le client propose un deck, le serveur nettoie et fait autorité ─────────────────
local function applyDeck(player: Player, raw: any)
	local st = PlayerWands.Get(player)
	if not st then
		return
	end
	local deck, err = Validator.SanitizeDeck(raw, st.Wand.Capacity, st.Inventory)
	if not deck then
		warn(("[Wand] deck rejeté pour %s : %s"):format(player.Name, tostring(err)))
		Remotes.DeckSync:FireClient(player, st.Deck, st.Wand) -- resynchronise le client
		return
	end
	st.Deck = deck
	st.Cursor = 1
	-- Modifier sa baguette impose une recharge (empêche d'annuler un cooldown en ré-équipant).
	local now = workspace:GetServerTimeNow()
	if st.ReadyAt < now + st.Wand.RechargeTime then
		st.CastStartedAt = now
		st.ReadyAt = now + st.Wand.RechargeTime
		st.Recharging = true
	end
	PlayerWands.Sync(player)
	Remotes.DeckSync:FireClient(player, deck, st.Wand)
end

bindRemote(Remotes.SetDeck, "SetDeck", function(player: Player, raw: any)
	local st = PlayerWands.Get(player)
	if not st then
		return
	end
	-- Limite de débit SANS perte : on garde la dernière demande et on l'applique dès que possible.
	st.PendingDeck = raw
	if st.DeckScheduled then
		return
	end
	st.DeckScheduled = true
	local wait = math.max(0, Limits.SetDeckInterval - (os.clock() - st.LastSetDeck))
	task.delay(wait, function()
		st.DeckScheduled = false
		st.LastSetDeck = os.clock()
		if PlayerWands.Get(player) == st then
			applyDeck(player, st.PendingDeck)
		end
		st.PendingDeck = nil
	end)
end)

-- ── Cast ────────────────────────────────────────────────────────────────────────
local function castWand(player: Player, st, root: BasePart, aim: Vector3, now: number)
	local plan = SpellEngine.Plan(st.Deck, st.Wand, st.Cursor)
	if plan.Truncated then
		warn(("[Wand] tir de %s tronqué par le garde-fou (%s) : %d pioches, %d projectiles")
			:format(player.Name, tostring(plan.Reason), plan.Iterations, plan.Projectiles))
	end

	-- coût facturé : jamais négatif (Ajout de mana), gratuit si aucun projectile n'est produit
	local cost = SpellEngine.Cost(plan)
	if not Validator.HasMana(st.Mana, cost) then
		Remotes.SpellFX:FireClient(player, { { k = "NoMana", c = plan.Mana } })
		st.ReadyAt = now + 0.2
		st.CastStartedAt = now
		PlayerWands.Sync(player)
		return
	end
	st.Mana -= cost

	-- L'origine est TOUJOURS calculée par le serveur ; le client ne fournit qu'une direction (point visé).
	local head = root.Position + Vector3.new(0, 1.5, 0)
	local dir = aim - head
	dir = if dir.Magnitude > 1 then dir.Unit else root.CFrame.LookVector
	local origin = head + dir * 2.5

	if not plan.Empty then
		SpellEngine.Execute(plan, origin, dir, player, st.Wand, aim)
		-- u = tireur : son client a déjà joué son et flash de départ (prédiction), il ignore ce message
		FXBus.Push({ k = "Cast", p = origin, d = dir, e = plan.FirstElement, c = plan.FirstCard, u = player.UserId })
	else
		-- le deck ne produit RIEN (que des modificateurs...) : effet "Faux" autour du joueur.
		-- Deck totalement vide : rien ne se passe.
		for _, id in st.Deck do
			if id ~= "" then
				FXBus.Push({ k = "Fizzle", p = root.Position, u = player.UserId })
				break
			end
		end
	end

	st.Cursor = plan.NextCursor
	local delay = SpellEngine.Delay(plan)
	st.CastStartedAt = now
	st.ReadyAt = now + math.max(0.05, delay)
	st.Recharging = plan.ReachedEnd
	PlayerWands.Sync(player)
end

-- ── MAINTIEN (carte "Maintien") ───────────────────────────────────────────────────────────────────────────
-- Départ : coût complet du tir ; les projectiles partent UNE fois (comme un clic) ; les sorts procéduraux sont
-- mis de côté et poussent à chaque tick là où le joueur vise. Chaque tick coûte HOLD_TICK_COST x le coût du
-- tir, sans régénération. Fin (relâchement, mana vide, mort, HOLD_MAX) : recharge + curseur avancé.
local HOLD_TICK = 0.12
local HOLD_TICK_COST = 0.3
local HOLD_MAX = 12
local HOLD_BEAM_DAMAGE = 0.4 -- rayon maintenu : chaque tick inflige 40 % des dégâts d'un tir (~3,3 tirs/s)
local holdBeamId = 0

local function originFor(root: BasePart, aim: Vector3): (Vector3, Vector3)
	local head = root.Position + Vector3.new(0, 1.5, 0)
	local dir = aim - head
	dir = if dir.Magnitude > 1 then dir.Unit else root.CFrame.LookVector
	return head + dir * 2.5, dir
end

endHold = function(player: Player, st)
	local h = st.Hold
	if not h then
		return
	end
	st.Hold = nil
	for i, stats in h.Shots do
		local state = h.States[i]
		if stats.Growth then
			GrowthService.EndHold(state)
		elseif stats.Zone then
			ZoneService.EndPath(state)
		end
	end
	-- tous les faisceaux continus (y compris ceux des charges) s'éteignent en fondu
	for _, tick in h.Beams do
		FXBus.Push({ k = "HoldBeamEnd", g = tick.HoldId, p = h.Aim })
	end
	-- le sort est considéré comme lancé à la FIN du maintien (même 0,1 s)
	local now = workspace:GetServerTimeNow()
	st.Cursor = h.Plan.NextCursor
	st.CastStartedAt = now
	st.ReadyAt = now + math.max(0.05, SpellEngine.Delay(h.Plan))
	st.Recharging = h.Plan.ReachedEnd
	player:SetAttribute("Holding", false)
	PlayerWands.Sync(player)
end

-- Un tick de FAISCEAU CONTINU, puis sa charge (déclencheur) depuis son point d'arrivée :
--   rayon dans la charge -> lui aussi un faisceau continu (clé stable = même faisceau d'un tick à l'autre) ;
--   autre sort dans la charge -> lancé normalement, mais seulement tous les HOLD_PAYLOAD_EVERY ticks.
local HOLD_PAYLOAD_EVERY = 3
local function holdBeam(player: Player, st, h, key: string, stats, payload, origin: Vector3, dir: Vector3, reach: number?, depth: number)
	local tick = h.Beams[key]
	if not tick then
		tick = table.clone(stats)
		tick.Damage = stats.Damage * HOLD_BEAM_DAMAGE
		tick.HoldTick = true
		tick.Trigger = nil -- la charge est gérée ici, pas par le tir instantané
		holdBeamId += 1
		tick.HoldId = holdBeamId
		h.Beams[key] = tick
	end
	local endPos, endNormal = ProjectileService.FireInstant(player, tick, origin, dir, nil, depth, st.Wand, reach)
	if not (payload and endPos) or depth >= Config.Limits.MaxDepth then
		return
	end
	-- même départ que la charge d'un rayon normal : rebond sur la surface touchée
	local from = if endNormal then endPos + endNormal * 0.6 else endPos
	local d = if endNormal then ProjectileService.Reflect(dir, endNormal) else dir
	for i, shot in payload.Shots do
		local s = SpellEngine.Resolve(shot, st.Wand)
		if s.Instant and not s.Self then
			holdBeam(player, st, h, key .. "/" .. i, s, shot.Payload, from, d, nil, depth + 1)
		elseif h.TickN % HOLD_PAYLOAD_EVERY == 0 then
			for _ = 1, shot.Copies do
				ProjectileService.Spawn(player, s, from, d, shot.Payload, depth + 1, st.Wand)
			end
		end
	end
end

local function startHold(player: Player, st, root: BasePart, aim: Vector3, now: number, plan)
	local cost = SpellEngine.Cost(plan)
	if not Validator.HasMana(st.Mana, cost) then
		Remotes.SpellFX:FireClient(player, { { k = "NoMana", c = plan.Mana } })
		st.ReadyAt = now + 0.2
		PlayerWands.Sync(player)
		return
	end
	st.Mana -= cost
	local origin, dir = originFor(root, aim)
	ProjectileService.Collect = {}
	local ok, err = pcall(SpellEngine.Execute, plan, origin, dir, player, st.Wand, aim)
	local shots = ProjectileService.Collect
	ProjectileService.Collect = nil
	if not ok then
		warn("[Wand] erreur au départ du maintien :", err)
	end
	if not plan.Empty then
		FXBus.Push({ k = "Cast", p = origin, d = dir, e = plan.FirstElement, c = plan.FirstCard, u = player.UserId })
	end
	st.Hold = {
		Plan = plan, Shots = shots, States = {}, Aim = aim, Acc = HOLD_TICK, Start = now, Beams = {}, TickN = 0,
		TickCost = math.max(2, cost * HOLD_TICK_COST),
	}
	st.ReadyAt = now + HOLD_MAX + 1 -- aucun autre tir pendant le maintien
	player:SetAttribute("Holding", true)
	PlayerWands.Sync(player)
	if #shots == 0 then
		endHold(player, st) -- aucun sort procédural : se comporte exactement comme un clic
	end
end

RunService.Heartbeat:Connect(function(dt)
	for _, player in Players:GetPlayers() do
		local st = PlayerWands.Get(player)
		local h = st and st.Hold
		if not h then
			continue
		end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (hum and root and hum.Health > 0) or workspace:GetServerTimeNow() - h.Start > HOLD_MAX then
			endHold(player, st)
			continue
		end
		h.Acc += dt
		while st.Hold == h and h.Acc >= HOLD_TICK do
			h.Acc -= HOLD_TICK
			if st.Mana < h.TickCost then
				Remotes.SpellFX:FireClient(player, { { k = "NoMana", c = h.TickCost } })
				endHold(player, st)
				break
			end
			st.Mana -= h.TickCost
			h.TickN += 1
			local origin, dir = originFor(root, h.Aim)
			local reach = (h.Aim - origin).Magnitude + 1
			for i, stats in h.Shots do
				local ok, res = pcall(function()
					if stats.Growth then
						return GrowthService.HoldTick(h.States[i], stats, origin, dir, player, reach)
					elseif stats.Instant then
						-- rayon continu (et sa charge, elle aussi continue) vers la visée actuelle
						holdBeam(player, st, h, tostring(i), stats, stats.HoldPayload, origin, dir, reach, 0)
						return true
					end
					return ZoneService.PathTick(h.States[i], stats, origin, dir, player, reach)
				end)
				if ok then
					h.States[i] = res
				else
					warn("[Wand] erreur de maintien :", res)
				end
			end
		end
	end
end)

-- ── INCANTATION (étape 3 des fondations) ─────────────────────────────────────────────────────────────────
-- Deck trop cher pour la barre PLEINE + baguette > Moyenne : clic maintenu = incantation. Les cercles (un par tir du
-- premier niveau) se chargent un par un ; relâcher = seuls les cercles TERMINÉS partent et on ne paie que leur part ;
-- un coup reçu, un gel ou un étourdissement casse le cercle EN COURS (il recommence) ; mort = tout est perdu.
-- Pendant l'incantation : déplacement -50 %, pas de course ni de dash (attribut Humanoid "Incanting").
-- Attributs joueur répliqués : IncantDur, IncantN, IncantDone, IncantStart (UI / cercles côté client).
local INCANT_SLOW = 0.5
local INCANT_BREAK_DAMAGE = 1 -- tout dégât reçu casse le cercle en cours

local function setIncantAttrs(player: Player, inc)
	player:SetAttribute("IncantN", inc and inc.N or nil)
	player:SetAttribute("IncantDur", inc and inc.Dur or nil)
	player:SetAttribute("IncantDone", inc and inc.Done or nil)
	player:SetAttribute("IncantStart", inc and inc.SegStart or nil)
	if not inc then
		player:SetAttribute("IncantAim", nil)
	end
end

local function stopIncant(player: Player, st, fire: boolean, reason: string?)
	local inc = st.Incant
	if not inc then
		return
	end
	st.Incant = nil
	if inc.HpConn then
		inc.HpConn:Disconnect()
	end
	local hum = inc.Hum
	if hum and hum.Parent then
		hum:SetAttribute("Incanting", nil)
		hum:SetAttribute("IncantMult", nil)
		Combat.RefreshMove(hum)
	end
	setIncantAttrs(player, nil)
	local now = workspace:GetServerTimeNow()
	local done = if fire then inc.Done else 0
	-- nombre de tirs du PREMIER niveau entièrement chargés (le tir + toutes les charges de son déclencheur)
	local rootsDone = 0
	if done > 0 and inc.Flat then
		local lastRoot = inc.Flat[#inc.Flat].Root
		for r = 1, lastRoot do
			local complete = true
			for k, f in inc.Flat do
				if f.Root == r and k > done then
					complete = false
					break
				end
			end
			if complete then
				rootsDone = r
			else
				break
			end
		end
	end
	local root = hum and hum.Parent and hum.Parent:FindFirstChild("HumanoidRootPart")
	if done >= inc.N then
		rootsDone = #inc.Plan.Root.Shots -- incantation complète : tout le deck part (même au-delà de 12 cercles)
	end
	if done > 0 and rootsDone == 0 then
		done = 0 -- aucun tir complet (ex. déclencheur chargé mais pas sa charge) : rien ne part
	end
	if done > 0 and root and hum.Health > 0 then
		-- seuls les cercles terminés : plan réduit aux `done` premiers tirs
		local plan = inc.Plan
		local partial = table.clone(plan)
		partial.Root = table.clone(plan.Root)
		partial.Root.Shots = table.move(plan.Root.Shots, 1, rootsDone, 1, {})
		local fullTotal = 0
		for _, sh in plan.Root.Shots do
			fullTotal += sh.Copies
		end
		partial.Root.FormationTotal = fullTotal -- les tirs gardent leur place dans la formation complète
		local share = done / inc.N
		st.Mana = math.max(0, st.Mana - inc.Cost * share) -- on ne paie que la part des cercles lancés (le reste vient de l'environnement)
		local origin, dir = originFor(root, inc.Aim)
		SpellEngine.Execute(partial, origin, dir, player, st.Wand, inc.Aim)
		FXBus.Push({ k = "Cast", p = origin, d = dir, e = plan.FirstElement, c = plan.FirstCard })
		FXBus.Push({ k = "IncantEnd", p = origin, u = player.UserId, n = done, r = "Release" })
		st.Cursor = plan.NextCursor
		local delay = SpellEngine.Delay(plan)
		st.CastStartedAt = now
		st.ReadyAt = now + math.max(0.05, delay)
		st.Recharging = plan.ReachedEnd
	else
		FXBus.Push({ k = "IncantEnd", p = root and root.Position or Vector3.zero, u = player.UserId, n = 0, r = reason or "Cancel" })
		st.ReadyAt = now + 0.35
		st.CastStartedAt = now
	end
	PlayerWands.Sync(player)
end

local function startIncant(player: Player, st, hum: Humanoid, aim: Vector3, plan, verdict): boolean
	local flat = Incantation.Flatten(plan)
	if #flat == 0 then
		flat = { { Shot = plan.Root.Shots[1], Root = 1 } }
	end
	local n = #flat
	-- poids de chaque cercle = coût du sort + coût de ses modificateurs -> durée au prorata
	local Catalog = require(Shared.SpellCatalog)
	local weights, total = {}, 0
	for i = 1, n do
		local shot = flat[i].Shot
		local wgt = 10
		if shot then
			wgt = math.max(shot.Card.Mana or 0, 5)
			for id, count in shot.State.Stacks do
				local m = Catalog.Get(id)
				if m and (m.Mana or 0) > 0 then
					wgt += m.Mana * count
				end
			end
		end
		weights[i] = wgt
		total += wgt
	end
	local segs = {}
	for i = 1, n do
		segs[i] = verdict.Duration * weights[i] / total
	end
	local inc = {
		Segs = segs, Frac = table.create(n, 0), Flat = flat,
		Plan = plan, Cost = SpellEngine.Cost(plan), Aim = aim, Hum = hum,
		N = n, Dur = verdict.Duration, Seg = verdict.Duration / n, Done = 0,
		SegStart = workspace:GetServerTimeNow(), LastHp = hum.Health,
	}
	st.Incant = inc
	hum:SetAttribute("Incanting", true)
	hum:SetAttribute("IncantMult", INCANT_SLOW)
	Combat.RefreshMove(hum)
	-- coup reçu : le cercle EN COURS se brise et recommence (les cercles terminés restent)
	inc.HpConn = hum.HealthChanged:Connect(function(hp)
		if st.Incant ~= inc then
			return
		end
		if hp <= 0 then
			stopIncant(player, st, false, "Death")
			return
		end
		if inc.LastHp - hp >= INCANT_BREAK_DAMAGE then
			inc.SegStart = workspace:GetServerTimeNow()
			FXBus.Push({ k = "IncantBreak", p = hum.Parent and hum.Parent:GetPivot().Position or Vector3.zero, u = player.UserId, n = inc.Done })
			setIncantAttrs(player, inc)
		end
		inc.LastHp = hp
	end)
	setIncantAttrs(player, inc)
	player:SetAttribute("IncantAim", aim)
	-- description des cercles pour TOUS les clients (ils ne connaissent pas le deck du lanceur) :
	-- élément + rang de chaque tir du premier niveau, formation, modificateurs (pour les runes, étape 6)
	-- angle de formation de chaque cercle = celui du 1er exemplaire de SON tir du premier niveau (même calcul que le moteur)
	local rootTotal, firstIdx, acc = 0, {}, 0
	for r, sh in plan.Root.Shots do
		firstIdx[r] = acc + 1
		acc += sh.Copies
	end
	rootTotal = acc
	local depthOf = {}
	local circles = {}
	for i = 1, n do
		inc.Frac[i] = segs[i] / verdict.Duration
		local shot = flat[i].Shot
		local mods = {}
		if shot then
			for id, count in shot.State.Stacks do
				if count > 0 then
					table.insert(mods, { id, count }) -- rune + nombre d'empilements (points)
				end
			end
		end
		-- TAILLE du cercle = rang x ampleur (Gigantisme) x puissance (dégâts + rayon d'effet), bornée
		local scale = 1
		if shot then
			local okR, stats = pcall(SpellEngine.Resolve or function() return nil end, shot, st.Wand)
			if not okR or not stats then
				okR, stats = pcall(require(Shared.SpellPlanner).Resolve, shot, st.Wand)
			end
			if okR and stats then
				local fx = math.clamp(stats.FxScale or 1, 0.5, 8)
				local power = ((stats.Damage or 0) + (stats.Radius or 0) * 2) / 20
				-- Gigantisme grossit NETTEMENT le cercle (user) : exposant 0,6, jusqu'à x4,5
				scale = math.clamp(fx ^ 0.78 * math.clamp(power ^ 0.25, 0.75, 1.6), 0.7, 7) -- (user : encore trop petits)
			end
		end
		circles[i] = {
			e = shot and (shot.State.Element or shot.Card.Element) or "Neutral",
			r = shot and shot.Card.Rank or "Moyen",
			f = shot and shot.Card.Family or nil, -- famille (Beam = son de cercle propre aux rayons)
			m = mods,
			s = math.floor(scale * 100 + 0.5) / 100,
			d = math.floor(inc.Frac[i] * 1000 + 0.5) / 1000, -- part de la durée totale pour CE cercle
			a = (firstIdx[flat[i].Root] - 1) / math.max(rootTotal, 1), -- fraction de tour (formation cercle)
			o = (function() -- rang du cercle parmi ceux du même tir (charges : un peu plus loin dans le même axe)
				local rr = flat[i].Root
				depthOf[rr] = (depthOf[rr] or 0) + 1
				return depthOf[rr] - 1
			end)(),
		}
	end
	-- PLACEMENT (user) : si le PREMIER sort du deck est procédural (Ramure...), les cercles sont AUTOUR du joueur
	-- (1er au sol, les suivants au-dessus de lui) ; sinon (projectile / déclencheur en tête) : devant la baguette.
	local first = flat[1] and flat[1].Shot
	local mode = if first and first.Card.Family == "Procedural" then "Around" else "Aim"
	FXBus.Push({ k = "IncantStart", p = hum.Parent:GetPivot().Position, u = player.UserId, n = n, t = inc.Dur, c = circles, f = plan.Root.Formation, m = mode })
	return true
end

RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		local st = PlayerWands.Get(player)
		local inc = st and st.Incant
		if inc then
			local hum = inc.Hum
			if not (hum and hum.Parent and hum.Health > 0) then
				stopIncant(player, st, false, "Death")
			elseif Combat.MoveLocked(hum) or hum:GetAttribute("Ragdoll") == true then
				-- gel / étourdissement / projection : le cercle en cours ne progresse pas (il recommence ensuite)
				if now - inc.SegStart > 0.05 then
					inc.SegStart = now
					setIncantAttrs(player, inc)
				end
			elseif now - inc.SegStart >= (inc.Segs[inc.Done + 1] or inc.Seg) then
				inc.Done += 1
				inc.SegStart = now
				FXBus.Push({ k = "IncantCircle", p = hum.Parent:GetPivot().Position, u = player.UserId, i = inc.Done, n = inc.N })
				if inc.Done >= inc.N then
					stopIncant(player, st, true) -- tous les cercles terminés : le deck part tout seul
				else
					setIncantAttrs(player, inc)
				end
			end
		end
	end
end)

bindRemote(Remotes.Cast, "Cast", function(player: Player, aim: any, mode: any)
	if mode ~= "aim" and mode ~= "end" then
		local ch = player.Character
		local h = ch and ch:FindFirstChildOfClass("Humanoid")
		if h and h:GetAttribute("Ragdoll") == true then
			return -- en ragdoll (propulsion céleste) : pas de sort
		end
		MovementService.OnCast(player) -- lancer un sort arrête la course
	end
	local st = PlayerWands.Get(player)
	if not st then
		return
	end
	-- messages de MAINTIEN en cours (hors limite de débit : ils ne lancent rien par eux-mêmes)
	if st.Hold then
		if mode == "aim" and Validator.IsValidAim(aim) then
			st.Hold.Aim = aim
		elseif mode == "end" then
			endHold(player, st)
		end
		return
	end
	if st.Incant then
		if mode == "aim" and Validator.IsValidAim(aim) then
			st.Incant.Aim = aim
			player:SetAttribute("IncantAim", aim)
		elseif mode == "end" then
			stopIncant(player, st, true)
		end
		return
	end
	if mode == "aim" or mode == "end" then
		return
	end
	local clock = os.clock()
	if clock - st.LastCastReq < Limits.CastRequestInterval then
		return -- spam : ignoré silencieusement
	end
	st.LastCastReq = clock

	if not Validator.IsValidAim(aim) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and humanoid.Health > 0) then
		return
	end

	local now = workspace:GetServerTimeNow()
	if not Validator.IsReady(st.ReadyAt, now) then
		return
	end

	-- le serveur décide lui-même du mode : un tir n'est maintenu que si SON plan contient "Maintien"
	if mode == "hold" then
		local plan = SpellEngine.Plan(st.Deck, st.Wand, st.Cursor)
		if plan.CastMode == "Hold" then
			local ok, err = pcall(startHold, player, st, root, aim, now, plan)
			if not ok then
				warn("[Wand] erreur de maintien :", err)
				st.Hold = nil
				st.ReadyAt = now + 0.5
			end
			return
		end
		-- deck trop cher pour la barre PLEINE : incantation (si la baguette et le mana actuel le permettent)
		local cost = SpellEngine.Cost(plan)
		if cost > st.Wand.ManaMax and not plan.Empty then
			local verdict = Incantation.Check(st.Wand, cost, st.Mana)
			if verdict.Ok then
				local ok, err = pcall(startIncant, player, st, humanoid, aim, plan, verdict)
				if not ok then
					warn("[Wand] erreur d'incantation :", err)
					st.Incant = nil
					st.ReadyAt = now + 0.5
				end
				return
			end
			Remotes.SpellFX:FireClient(player, { { k = "NoMana", c = plan.Mana, why = verdict.Reason } })
			st.ReadyAt = now + 0.3
			PlayerWands.Sync(player)
			return
		end
	end
	-- pcall : une erreur de logique dans un sort ne doit jamais casser le handler pour tout le serveur.
	local ok, err = pcall(castWand, player, st, root, aim, now)
	if not ok then
		warn("[Wand] erreur pendant le tir :", err)
		st.ReadyAt = now + 0.5
	end
end)


-- ── BANC DE TEST DE PERFORMANCE (Studio uniquement, inactif en jeu publié) ─────────────────────────
if game:GetService("RunService"):IsStudio() then
	local perf: { [string]: any } = {}
	local re = Instance.new("RemoteEvent")
	re.Name = "WandPerf" -- les clients y envoient leurs mesures quand workspace.WandPerfOn est vrai
	re.Parent = ReplicatedStorage
	re.OnServerEvent:Connect(function(player: Player, stats: any)
		if type(stats) == "table" then
			stats.At = os.clock()
			perf[player.Name] = stats
		end
	end)
	-- CONTRAT DE SORT : table de couverture vérifiée à chaque lancement dans Studio (incohérences en avertissement)
	task.defer(function()
		local tools = game:GetService("ServerStorage"):FindFirstChild("WandTools")
		local ok, rows, issues = pcall(function()
			return require(tools).Coverage()
		end)
		if not ok then
			warn("[WandCoverage] vérification impossible :", rows)
		elseif #issues == 0 then
			print("[WandCoverage] OK — tous les modificateurs font ce que l'interface annonce")
		else
			warn(("[WandCoverage] %d incohérence(s) entre l'interface et le moteur :\n  %s"):format(#issues, table.concat(issues, "\n  ")))
		end
	end)
	local bf = Instance.new("BindableFunction")
	bf.Name = "WandTest"
	-- BANC DE CHARGE « 6 joueurs » (Studio) : ServerStorage.BotBench:Invoke(player, deck, origin, aim)
	-- exécute un tir COMPLET (plan + moteur + effets diffusés à tous) depuis n'importe quelle position, comme
	-- s'il venait d'un autre joueur ; `player` sert seulement de propriétaire (pas de mana, pas de délai).
	local bot = Instance.new("BindableFunction")
	bot.Name = "BotBench"
	bot.OnInvoke = function(player: Player, deck: { string }, origin: Vector3, aim: Vector3)
		local st = PlayerWands.Get(player)
		assert(st, "joueur sans baguette")
		local plan = SpellEngine.Plan(deck, st.Wand, 1)
		local dir = aim - origin
		dir = if dir.Magnitude > 1 then dir.Unit else Vector3.new(0, 0, -1)
		if not plan.Empty then
			SpellEngine.Execute(plan, origin, dir, player, st.Wand, aim)
			FXBus.Push({ k = "Cast", p = origin, d = dir, e = plan.FirstElement, c = plan.FirstCard, u = 0 })
		end
		return SpellEngine.Delay(plan)
	end
	bot.Parent = game:GetService("ServerStorage")
	-- banc de test en MATRICE (chaque sort × infusions / modificateurs) : voir WandServer.TestBench
	local TestBench = require(script.TestBench)
	TestBench.Init({
		PlayerWands = PlayerWands, FXBus = FXBus, Zone = ZoneService, Growth = GrowthService, Projectiles = ProjectileService,
		Cast = function(player: Player, aim: Vector3)
			local st = PlayerWands.Get(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			assert(st and root, "joueur sans baguette / personnage")
			castWand(player, st, root, aim, workspace:GetServerTimeNow())
		end,
		-- MAINTIEN piloté par le banc : démarre comme un clic maintenu, balaie la visée (sweep), relâche après `duration`
		Hold = function(player: Player, aim: Vector3, duration: number, sweep: Vector3?)
			local st = PlayerWands.Get(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			assert(st and root, "joueur sans baguette / personnage")
			local now = workspace:GetServerTimeNow()
			local plan = SpellEngine.Plan(st.Deck, st.Wand, st.Cursor)
			local info = { Mode = plan.CastMode, Cost = SpellEngine.Cost(plan), ManaBefore = st.Mana, Ticks = 0, Shots = 0 }
			if plan.CastMode ~= "Hold" then
				castWand(player, st, root, aim, now)
				return info
			end
			startHold(player, st, root, aim, now, plan)
			local h = st.Hold
			info.Started = h ~= nil
			info.Shots = h and #h.Shots or 0
			local t0 = os.clock()
			while st.Hold == h and h and os.clock() - t0 < duration do
				if sweep then
					h.Aim = aim + sweep * math.sin((os.clock() - t0) * 2.5)
				end
				info.Ticks = h.TickN
				task.wait()
			end
			info.EndedEarly = st.Hold ~= h -- fin avant la durée (mana épuisée, mort...)
			if st.Hold == h and h then
				endHold(player, st)
			end
			local after = workspace:GetServerTimeNow()
			info.HoldLeft = st.Hold ~= nil
			info.AttrLeft = player:GetAttribute("Holding") == true
			info.ReadyIn = st.ReadyAt - after
			info.ManaAfter = st.Mana
			info.Held = os.clock() - t0
			return info
		end,
	})
	bf.OnInvoke = function(action: string, player: Player?, a: any, b: any)
		if action == "Matrix" then
			return TestBench.Run(player, a)
		elseif action == "PerfBench" then
			return TestBench.RunPerf(player, a, function() return perf end)
		end
		if action == "Perf" then
			return perf
		elseif action == "ClearPerf" then
			table.clear(perf)
			return true
		end
		local f = TEST_HANDLERS[action]
		if f and player then
			f(player, a, b)
			return true
		end
		return false
	end
	bf.Parent = game:GetService("ServerStorage")
end

-- ── MORT : tous les sorts actifs du joueur s'arrêtent + RAGDOLL (user 2026-11-23) ─────────────────────
do
	local function ragdoll(char: Model)
		for _, m in char:GetDescendants() do
			if m:IsA("Motor6D") and m.Part0 and m.Part1 and m.Name ~= "RootJoint" and m.Name ~= "Root" then
				local a0 = Instance.new("Attachment")
				a0.Name = "RagA0"
				a0.CFrame = m.C0
				a0.Parent = m.Part0
				local a1 = Instance.new("Attachment")
				a1.Name = "RagA1"
				a1.CFrame = m.C1
				a1.Parent = m.Part1
				local bs = Instance.new("BallSocketConstraint")
				bs.Attachment0, bs.Attachment1 = a0, a1
				bs.LimitsEnabled = true
				bs.TwistLimitsEnabled = true
				local neck = m.Name == "Neck"
				bs.UpperAngle = if neck then 35 else 75
				bs.TwistLowerAngle, bs.TwistUpperAngle = if neck then -30 else -60, if neck then 30 else 60
				bs.MaxFrictionTorque = 6 -- amortit : pas de membres qui tournent en boucle
				bs.Parent = m.Part0
				m.Enabled = false
			end
		end
		-- COLLISIONS (bug corrigé) : avant, TOUTES les pièces (chapeaux, cheveux, accessoires) devenaient solides
		-- et se cognaient entre elles. Maintenant : seuls les MEMBRES touchent le décor, jamais entre eux ;
		-- accessoires sans collision ni masse ; la racine ne touche rien.
		for _, p in char:GetDescendants() do
			if p:IsA("BasePart") then
				local limb = p.Parent == char and p.Name ~= "HumanoidRootPart"
				p.CollisionGroup = "Ragdoll"
				p.CanCollide = limb
				p.CanTouch = false
				if not limb then
					p.Massless = true
				end
			end
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			root.CanCollide = false
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.PlatformStand = true -- l'humanoïde n'essaie plus de se relever
		end
		-- physique du corps simulée par le SERVEUR : même chute pour tous, le client ne la perturbe plus
		if root then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end
		-- petite poussée pour que le corps tombe au lieu de rester figé debout
		local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
		if torso then
			torso:ApplyImpulse(torso.CFrame.LookVector * -torso.AssemblyMass * 6)
		end
	end
	do
		local PS = game:GetService("PhysicsService")
		pcall(function()
			if not PS:IsCollisionGroupRegistered("Ragdoll") then
				PS:RegisterCollisionGroup("Ragdoll")
			end
			PS:CollisionGroupSetCollidable("Ragdoll", "Ragdoll", false) -- les membres ne se cognent pas entre eux
		end)
	end

	local function onDeath(player: Player, char: Model)
		local st = PlayerWands.Get(player)
		if st then
			if st.Hold then
				pcall(endHold, player, st)
			end
			if st.Incant then
				pcall(stopIncant, player, st, false, "Death")
			end
		end
		pcall(ProjectileService.ClearOwner, player)
		pcall(ZoneService.ClearOwner, player)
		pcall(GrowthService.ClearOwner, player)
		pcall(ragdoll, char)
	end

	local function onChar(player: Player, char: Model)
		local hum = char:WaitForChild("Humanoid", 10)
		if not hum then
			return
		end
		hum.BreakJointsOnDeath = false -- sinon le corps se démonte avant le ragdoll
		hum.Died:Connect(function()
			onDeath(player, char)
		end)
	end

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(c)
			onChar(player, c)
		end)
		if player.Character then
			task.spawn(onChar, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

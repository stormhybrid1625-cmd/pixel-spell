--[[
	WandServer/Combat
	Dégâts, explosions, effets d'élément et recherche de cible (homing).
	  Feu    : brûlure (4 ticks de 2 dégâts, 0.5 s) — rafraîchie, jamais cumulée.
	  Glace  : ralentissement 50 % pendant 1.5 s — la vitesse d'origine est mémorisée en attribut.
	  Chaos  : multiplicateur de dégâts aléatoire x0.4 – x2.2.
	  Foudre : choc, immobilise 0.35 s.
	  Toxique: poison (4 ticks de 2 dégâts, 0.5 s).
	  Acier  : saignement (5 ticks de 1 dégât, 0.5 s).
	  Arcane : pas d'effet secondaire.
	Chaque message de dégâts porte son TYPE (t = Burn / Poison / Bleed pour les dégâts sur la durée) :
	le client choisit le son et l'affichage en conséquence.
	Poussée (Combat.Push) : les mannequins (physique serveur) sont poussés directement ; les joueurs
	possèdent leur personnage côté client, donc on leur envoie un message "Push" qu'ils appliquent eux-mêmes.
]]

local Players = game:GetService("Players")
local FXBus = require(script.Parent.FXBus)
-- matière & environnement : les souffles abîment aussi le décor (pas de cycle : MatterService ne requiert pas Combat)
local Matter = require(script.Parent.MatterService)

local Combat = {}
local rng = Random.new()

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.MaxParts = 200

function Combat.Init(projectileFolder: Folder)
	overlap.FilterDescendantsInstances = { projectileFolder }
end

-- Remonte d'une partie touchée jusqu'au Humanoid de son modèle (accessoires inclus).
function Combat.HumanoidFrom(inst: Instance): (Humanoid?, Model?)
	local model = inst:FindFirstAncestorOfClass("Model")
	while model do
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum then
			return hum, model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, nil
end

local function isOwnerOf(owner: Player?, model: Instance): boolean
	return owner ~= nil and owner.Character == model
end

local function rootOf(hum: Humanoid): BasePart?
	return hum.RootPart or (hum.Parent and hum.Parent:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

-- dotKind : nil = coup direct ; "Burn" / "Poison" / "Bleed" = tick de dégâts sur la durée
local function rawDamage(hum: Humanoid, amount: number, element: string, pos: Vector3?, dotKind: string?)
	if amount <= 0 or hum.Health <= 0 then
		return
	end
	hum:TakeDamage(amount)
	local root = rootOf(hum)
	FXBus.Push({ k = "Dmg", p = pos or (root and root.Position) or Vector3.zero, a = amount, e = element, t = dotKind })
end

-- ══ EFFETS D'ÉLÉMENT SUR LES CIBLES (pilotés par les DONNÉES) ═══════════════════════════════════════════
-- Chaque élément déclare son effet dans WandShared/Elements/<Élément>.Status ; ce moteur ne connaît que les GENRES :
--   Dot   : dégâts sur la durée qui se CUMULENT (Damage x niveaux par Tick, MaxStacks, Duration rafraîchie),
--           Attr = état visible client, Vulnerable = +x % de dégâts subis, PausedBy = marque qui suspend les ticks
--   Chill : ralenti (SlowFactor, Duration) ; BuildHits coups en BuildWindow s -> BLOCAGE (LockTime, LockAttr : gel /
--           enracinement), puis immunité LockImmune ; LockTimeMultIf = { [élément actif] = x }
--   Shock : immobilise Stun s (au plus toutes les StunCooldown s), Attr visible Show s ; Chain = saut vers d'autres cibles
-- Les RÉACTIONS (WandShared/Reactions) passent avant l'effet normal du coup.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Elements = require(ReplicatedStorage.WandShared.Elements)
local Reactions = require(ReplicatedStorage.WandShared.Reactions)

local states: { [Humanoid]: any } = {}
local function stateOf(hum: Humanoid)
	local st = states[hum]
	if not st then
		st = { Marks = {}, Slows = {}, Hits = {}, LockImmune = {}, StunReady = 0 }
		states[hum] = st
		hum.Destroying:Once(function()
			states[hum] = nil
		end)
		hum.Died:Once(function()
			-- mort pendant un blocage : on LIBÈRE (sinon un mannequin réutilisé resterait fixé pour toujours)
			if st.Pinned and st.Pinned.Parent then
				st.Pinned.Anchored = false
			end
			states[hum] = nil
		end)
	end
	return st
end

-- VITESSE : toutes les sources de ralenti/blocage actives, la plus forte l'emporte ; recalcul à chaque changement
local function applyMove(hum: Humanoid)
	local st = states[hum]
	if not st or not hum.Parent then
		return
	end
	if hum:GetAttribute("BaseWalkSpeed") == nil then
		hum:SetAttribute("BaseWalkSpeed", hum.WalkSpeed)
		hum:SetAttribute("BaseJump", if hum.UseJumpPower then hum.JumpPower else hum.JumpHeight)
	end
	local now = os.clock()
	local factor, noJump = 1, false
	for key, sl in st.Slows do
		if sl.Until > now then
			factor = math.min(factor, sl.Factor)
			noJump = noJump or sl.NoJump
		else
			st.Slows[key] = nil
		end
	end
	hum.WalkSpeed = hum:GetAttribute("BaseWalkSpeed") * factor * (hum:GetAttribute("MoveMult") or 1) * (hum:GetAttribute("IncantMult") or 1) -- MoveMult : course / glissade (MovementService)
	local bj = hum:GetAttribute("BaseJump")
	if hum.UseJumpPower then
		hum.JumpPower = if noJump then 0 else bj
	else
		hum.JumpHeight = if noJump then 0 else bj
	end
end
local function setSlow(hum: Humanoid, key: string, factor: number, duration: number, noJump: boolean?)
	local st = stateOf(hum)
	local untilT = os.clock() + duration
	local cur = st.Slows[key]
	if not cur or cur.Until < untilT or cur.Factor > factor then
		st.Slows[key] = { Factor = factor, Until = math.max(untilT, cur and cur.Until or 0), NoJump = noJump }
	end
	applyMove(hum)
	task.delay(duration + 0.02, applyMove, hum)
end
local function clearSlow(hum: Humanoid, key: string)
	local st = states[hum]
	if st and st.Slows[key] then
		st.Slows[key] = nil
		applyMove(hum)
	end
end

-- MARQUES (« empoisonné », « en feu », « gelé »...) : lues par les réactions et la vulnérabilité
local function markActive(hum: Humanoid, key: string): any
	local st = states[hum]
	local m = st and st.Marks[key]
	if m and m.Until > os.clock() then
		return m
	end
	return nil
end
Combat.MarkActive = markActive
-- recalcule la vitesse (ralentis x multiplicateur de déplacement) : appelé par MovementService
function Combat.RefreshMove(hum: Humanoid)
	stateOf(hum)
	applyMove(hum)
end
-- vrai si le joueur ne peut pas bouger (gel, étourdi...) : bloque esquive / glissade
function Combat.MoveLocked(hum: Humanoid): boolean
	local st = states[hum]
	if not st then return false end
	local now = os.clock()
	for _, sl in st.Slows do
		if sl.Until > now and sl.Factor <= 0.05 then return true end
	end
	return false
end

local function endMark(hum: Humanoid, key: string)
	local st = states[hum]
	local m = st and st.Marks[key]
	if not m then
		return
	end
	st.Marks[key] = nil
	if m.Attr then
		hum:SetAttribute(m.Attr, nil)
	end
	if m.SlowKey then
		clearSlow(hum, m.SlowKey)
		-- libéré seulement si AUCUN autre blocage n'est encore actif (gel + racines en même temps)
		local stillLocked = false
		for _, other in st.Marks do
			if other.SlowKey and other.Until > os.clock() then
				stillLocked = true
			end
		end
		if st.Pinned and not stillLocked then
			if st.Pinned.Parent then
				st.Pinned.Anchored = false
			end
			st.Pinned = nil
		end
	end
end

-- tic de ZONE en cours (flaque, feu au sol, aura...) : voir Combat.ZoneDamage
local zoneTick = false

-- Dot : dégâts sur la durée, CUMULÉS (coups directs). Une ZONE n'empile pas : elle pose / entretient 1 niveau,
-- et ne prolonge pas des niveaux montés par des coups directs (sinon rester dans le feu = brûlure max permanente)
local function applyDot(hum: Humanoid, element: string, S, durMult: number, extraStacks: number?)
	local st = stateOf(hum)
	local now = os.clock()
	local m = markActive(hum, element)
	local add = 1 + (extraStacks or 0)
	if m and zoneTick then
		if m.Stacks <= 1 then
			m.Until = now + S.Duration * durMult
		end
		return
	end
	if zoneTick then
		add = 1
	end
	if m then
		m.Stacks = math.min(S.MaxStacks or 1, m.Stacks + add)
		m.Until = now + S.Duration * durMult
		return
	end
	m = { Stacks = math.min(S.MaxStacks or 1, add), Until = now + S.Duration * durMult, Attr = S.Attr, Vulnerable = S.Vulnerable }
	st.Marks[element] = m
	if S.Attr then
		hum:SetAttribute(S.Attr, true)
	end
	task.spawn(function()
		while hum.Parent and hum.Health > 0 and st.Marks[element] == m and m.Until > os.clock() do
			task.wait(S.Tick or 0.5)
			if st.Marks[element] ~= m then
				break
			end
			if S.PausedBy and markActive(hum, S.PausedBy) then
				m.Until += S.Tick or 0.5 -- suspendu (ex. poison gelé) : le temps ne s'écoule pas
			elseif hum.Parent and hum.Health > 0 then
				local root = rootOf(hum)
				rawDamage(hum, (S.Damage or 1) * m.Stacks, element, root and root.Position + Vector3.new(0, 2, 0), S.DotType)
			end
		end
		if st.Marks[element] == m then
			st.Marks[element] = nil
			if S.Attr and hum.Parent then
				hum:SetAttribute(S.Attr, nil)
			end
		end
	end)
end

-- Chill : ralenti qui s'accumule jusqu'au BLOCAGE (gel, enracinement)
local function applyChill(hum: Humanoid, element: string, S, durMult: number)
	local st = stateOf(hum)
	local now = os.clock()
	setSlow(hum, element, S.SlowFactor, S.Duration * durMult)
	st.Marks[element] = { Stacks = 1, Until = now + S.Duration * durMult }
	if not S.BuildHits or not S.LockAttr then
		return
	end
	if markActive(hum, S.LockAttr) or (st.LockImmune[S.LockAttr] or 0) > now then
		return -- déjà bloqué, ou immunisé juste après un blocage (pas de blocage en boucle)
	end
	local hits = st.Hits[element] or {}
	st.Hits[element] = hits
	table.insert(hits, now)
	while hits[1] and now - hits[1] > (S.BuildWindow or 3) do
		table.remove(hits, 1)
	end
	if #hits >= S.BuildHits then
		table.clear(hits)
		local t = S.LockTime * durMult -- Prolongation allonge aussi le BLOCAGE (gel, enracinement)
		for other, mult in S.LockTimeMultIf or {} do
			if markActive(hum, other) then
				t *= mult
			end
		end
		st.Marks[S.LockAttr] = { Stacks = 1, Until = now + t, Attr = S.LockAttr, SlowKey = S.LockAttr }
		hum:SetAttribute(S.LockAttr, true)
		hum:SetAttribute("LockFor", math.floor(t * 100) / 100) -- durée du dernier blocage (lecture banc / debug)
		setSlow(hum, S.LockAttr, 0, t, true)
		-- PRISONNIER : bloquer la marche ne suffit pas (on pourrait le pousser) -> le personnage est FIXÉ sur place
		local pin = rootOf(hum)
		if pin and not pin.Anchored and not st.Pinned then -- (déjà fixé à l'origine : on n'y touche pas)
			pin.AssemblyLinearVelocity = Vector3.zero
			pin.Anchored = true
			st.Pinned = pin
		end
		st.LockImmune[S.LockAttr] = now + t + (S.LockImmune or 0)
		local root = rootOf(hum)
		FXBus.Push({ k = "Impact", p = root and root.Position or Vector3.zero, n = Vector3.yAxis, e = element, r = 0, s = 1.4 })
		task.delay(t, function()
			local m = st.Marks[S.LockAttr]
			if m and m.Until <= os.clock() + 0.01 then
				endMark(hum, S.LockAttr)
			end
		end)
	end
end

-- Shock : immobilisation brève (anti-blocage) + état visible
local function applyShock(hum: Humanoid, element: string, S, durMult: number)
	local st = stateOf(hum)
	local now = os.clock()
	if now >= st.StunReady then
		st.StunReady = now + (S.StunCooldown or 0)
		setSlow(hum, "Stun", 0, S.Stun or 0.35, true)
	end
	st.Marks[element] = { Stacks = 1, Until = now + (S.Show or 0.9) * durMult }
	if S.Attr then
		local token = (hum:GetAttribute("ShockToken") or 0) + 1
		hum:SetAttribute("ShockToken", token)
		hum:SetAttribute(S.Attr, true)
		task.delay((S.Show or 0.9) * durMult, function()
			if hum.Parent and hum:GetAttribute("ShockToken") == token then
				hum:SetAttribute(S.Attr, nil)
			end
		end)
	end
end

local KIND = { Dot = applyDot, Chill = applyChill, Shock = applyShock }

-- texte flottant (nom de la réaction) au-dessus de la cible
local function label(hum: Humanoid, text: string, element: string)
	local root = rootOf(hum)
	FXBus.Push({ k = "React", p = (root and root.Position or Vector3.zero) + Vector3.new(0, 3.5, 0), t = text, e = element })
end

-- RÉACTIONS : avant l'effet normal du coup ; renvoie true si une réaction a « consommé » le coup
local function runReactions(hum: Humanoid, element: string, amount: number, owner: Player?, pos: Vector3?): boolean
	local consumed = false
	for _, rx in Reactions.Targets do
		if rx.Hit == element and markActive(hum, rx.On) then
			local root = rootOf(hum)
			local at = root and root.Position or pos or Vector3.zero
			local r = {
				Hum = hum, Pos = at, Owner = owner, Amount = amount,
				Stacks = function(key) local m = markActive(hum, key) return m and m.Stacks or 0 end,
				Consume = function(key) endMark(hum, key) end,
				Explode = function(radius, dmg, el) Combat.Explode(at, radius, dmg, owner, el or element) end,
				DamageAround = function(radius, dmg, el) Combat.DamageInRadius(at, radius, dmg, owner, el or element) end,
				Damage = function(dmg, el) rawDamage(hum, math.floor(dmg + 0.5), el or element, at + Vector3.new(0, 2.5, 0)) end,
				AddStacks = function(el, n)
					local def = Elements[el]
					if def and def.Status and def.Status.Kind == "Dot" then
						applyDot(hum, el, def.Status, 1, n)
					end
				end,
				FX = function(msg) msg.p = msg.p or at FXBus.Push(msg) end,
				Visual = function(name, scale) FXBus.Push({ k = "ReactFX", n = name, p = at, s = scale or 1 }) end,
				Label = function(text) label(hum, text, element) end,
			}
			local ok, res = pcall(rx.Run, r)
			if not ok then
				warn("[Wand] réaction " .. tostring(rx.Name) .. " en erreur :", res)
			elseif res == true then
				consumed = true
			end
		end
	end
	return consumed
end

-- applique l'effet de l'élément (selon son genre déclaré) ; extraStacks : niveaux en plus (réactions)
-- MALUS DE RÉGÉNÉRATION (Status.Regen = { Hp = x, Mana = x, After = s }) : écrits sur l'humanoid,
-- lus par la régénération de vie (StarterCharacterScripts.Health) et de mana (PlayerWands). Le plus fort l'emporte,
-- la fin la plus tardive l'emporte. Les SOINS ne sont jamais affectés.
local function applyRegen(hum: Humanoid, S, durMult: number)
	local R = S.Regen
	if not R then
		return
	end
	local now = workspace:GetServerTimeNow()
	local untilT = now + (S.Duration or S.Stun or 0) * durMult + (R.After or 0)
	for _, key in { "Hp", "Mana" } do
		local mult = R[key]
		if mult then
			local attrM, attrU = "Regen" .. key .. "Mult", "Regen" .. key .. "Until"
			local active = (hum:GetAttribute(attrU) or 0) > now
			local curM = if active then (hum:GetAttribute(attrM) or 1) else 1
			hum:SetAttribute(attrM, math.min(curM, mult))
			hum:SetAttribute(attrU, math.max(if active then hum:GetAttribute(attrU) else 0, untilT))
		end
	end
end

-- multiplicateur actuel de régénération naturelle (1 = normal, 0 = bloquée)
function Combat.RegenMult(hum: Humanoid?, key: string): number
	if not hum then
		return 1
	end
	if (hum:GetAttribute("Regen" .. key .. "Until") or 0) <= workspace:GetServerTimeNow() then
		return 1
	end
	return hum:GetAttribute("Regen" .. key .. "Mult") or 1
end

-- ÉTAT DU CORPS (Status.Body) : attribut répliqué "Body<Élément>" = heure serveur de fin ; lu par le client
-- (VFXManager, Visuals.Body) pour des effets purement décoratifs sur le personnage
local function applyBody(hum: Humanoid, element: string, S, durMult: number)
	if not S.Body then
		return
	end
	local untilT = workspace:GetServerTimeNow() + (S.Duration or S.Stun or 0) * durMult + (S.Regen and S.Regen.After or 0)
	local attr = "Body" .. element
	hum:SetAttribute(attr, math.max(hum:GetAttribute(attr) or 0, untilT))
end

-- un coup d'un élément ARRÊTE les états du corps qui le déclarent (Status.BodyClearedBy : le feu réchauffe)
local function clearBodies(hum: Humanoid, element: string)
	for name, def in Elements do
		local S = type(def) == "table" and def.Status
		if S and S.BodyClearedBy and S.BodyClearedBy[element] and hum:GetAttribute("Body" .. name) then
			hum:SetAttribute("Body" .. name, nil)
		end
	end
end

local function applyStatus(hum: Humanoid, element: string, durMult: number)
	local def = Elements[element]
	local S = def and def.Status
	local fn = S and KIND[S.Kind]
	if fn then
		fn(hum, element, S, durMult)
		applyRegen(hum, S, durMult)
		applyBody(hum, element, S, durMult)
	end
end

-- VULNÉRABILITÉ : une marque active peut augmenter les dégâts subis (poison : +10 %)
local function vulnerability(hum: Humanoid): number
	local st = states[hum]
	if not st then
		return 1
	end
	local mult = 1
	local now = os.clock()
	for _, m in st.Marks do
		if m.Vulnerable and m.Until > now then
			mult += m.Vulnerable
		end
	end
	return mult
end

-- Pousse un personnage (vitesse ajoutée, studs/s). Bornée pour éviter les envols absurdes.
function Combat.Push(hum: Humanoid, velocity: Vector3, knock: boolean?)
	local root = rootOf(hum)
	if not root or velocity.Magnitude < 1 then
		return
	end
	if knock then -- RECUL (modificateur) : son de projection sur la cible, entendu par tous
		FXBus.Push({ k = "Knock", p = root.Position, s = math.floor(velocity.Magnitude) })
	end
	if velocity.Magnitude > 150 then
		velocity = velocity.Unit * 150
	end
	local player = Players:GetPlayerFromCharacter(hum.Parent)
	if player then
		FXBus.Push({ k = "Push", u = player.UserId, v = velocity })
	else
		root.AssemblyLinearVelocity += velocity
	end
end

-- Dégâts directs. Le lanceur ne se blesse pas lui-même ; un ForceField protège.
-- durMult : Prolongation -> brûlure / poison / saignement durent plus longtemps
-- direct = coup PORTÉ par un sort (projectile, rayon) : seul un coup direct déclenche le SAUT de la foudre
function Combat.Damage(hum: Humanoid, amount: number, owner: Player?, element: string, pos: Vector3?, durMult: number?, direct: boolean?)
	local model = hum.Parent
	if not model or hum.Health <= 0 or isOwnerOf(owner, model) then
		return
	end
	if model:FindFirstChildOfClass("ForceField") then
		return
	end
	local mult = if element == "Chaos" then rng:NextNumber(0.4, 2.2) else 1
	mult *= vulnerability(hum)
	rawDamage(hum, math.floor(amount * mult + 0.5), element, pos)
	local dm = math.clamp(durMult or 1, 1, 4)
	if hum.Health <= 0 then
		return
	end
	clearBodies(hum, element)
	-- 1) réactions avec les marques déjà présentes  2) effet normal de l'élément
	if not runReactions(hum, element, amount * mult, owner, pos) then
		applyStatus(hum, element, dm)
	end
	-- 3) SAUT (foudre) : vers les cibles proches, depuis un coup direct seulement (pas de réaction en chaîne infinie)
	local def = Elements[element]
	local chain = direct and def and def.Status and def.Status.Chain
	if chain then
		local from = rootOf(hum)
		if from then
			local done = { [hum] = true }
			local cur, curPos = hum, from.Position
			for _ = 1, chain.Count or 1 do
				local best, bestD = nil, chain.Range or 8
				for _, h in Combat.HumanoidsInRadius(curPos, chain.Range or 8, owner) do
					local r = not done[h] and rootOf(h)
					if r and (r.Position - curPos).Magnitude < bestD then
						best, bestD = h, (r.Position - curPos).Magnitude
					end
				end
				if not best then
					break
				end
				done[best] = true
				local to = rootOf(best).Position
				FXBus.Push({ k = "Beam", p = curPos, d = to, e = element, w = 0.4, c = "LIGHTNING", j = 1 })
				Combat.Damage(best, amount * (chain.Mult or 0.6), owner, element, to, durMult, false)
				-- l'arc PROPAGE certains états (arc toxique : le poison de la cible saute avec l'éclair)
				for _, spread in chain.Spreads or {} do
					local sdef = Elements[spread]
					if markActive(cur, spread) and sdef and sdef.Status then
						applyStatus(best, spread, 1)
					end
				end
				cur, curPos = best, to
			end
		end
	end
end

-- Dégâts à tous les personnages dans un rayon (auras, zones). Retourne le nombre de cibles.
function Combat.DamageInRadius(pos: Vector3, radius: number, damage: number, owner: Player?, element: string, push: Vector3?, durMult: number?): number
	local seen: { [Humanoid]: boolean } = {}
	local count = 0
	for _, part in workspace:GetPartBoundsInRadius(pos, radius, overlap) do
		local hum = Combat.HumanoidFrom(part)
		if hum and not seen[hum] and hum.Health > 0 and not isOwnerOf(owner, hum.Parent) then
			seen[hum] = true
			count += 1
			local root = rootOf(hum)
			Combat.Damage(hum, damage, owner, element, root and root.Position + Vector3.new(0, 2.5, 0), durMult)
			if push then
				Combat.Push(hum, push)
			end
		end
	end
	-- zones / auras : la matière du rayon subit aussi (gaz qui flétrit l'herbe, feu qui allume...) sans cratère
	-- (silencieux : une aura qui tique en continu ne doit pas faire de bruits d'impact / de casse)
	Matter.Blast(pos, radius, damage * 0.5, element, owner, { NoCarve = true, Silent = true })
	return count
end

-- Dégâts d'un TIC DE ZONE : mêmes effets qu'un coup, mais les statuts cumulables ne s'empilent pas (voir applyDot)
function Combat.ZoneDamage(...)
	zoneTick = true
	local ok, err = pcall(Combat.Damage, ...)
	zoneTick = false
	if not ok then
		error(err, 2)
	end
end

function Combat.ZoneDamageInRadius(...): number
	zoneTick = true
	local ok, res = pcall(Combat.DamageInRadius, ...)
	zoneTick = false
	if not ok then
		error(res, 2)
	end
	return res
end

-- Liste des humanoids vivants (hors lanceur) dans un rayon.
function Combat.HumanoidsInRadius(pos: Vector3, radius: number, owner: Player?): { Humanoid }
	local list, seen = {}, {}
	for _, part in workspace:GetPartBoundsInRadius(pos, radius, overlap) do
		local hum = Combat.HumanoidFrom(part)
		if hum and not seen[hum] and hum.Health > 0 and not isOwnerOf(owner, hum.Parent) then
			seen[hum] = true
			table.insert(list, hum)
		end
	end
	return list
end

Combat.RootOf = rootOf
Combat.IsOwnerOf = isOwnerOf

-- Explosion : dégâts décroissants avec la distance (100 % au centre -> 40 % au bord).
function Combat.Explode(pos: Vector3, radius: number, damage: number, owner: Player?, element: string, knock: number?, durMult: number?, selfMult: number?)
	if radius <= 0 then
		return
	end
	local blast = knock or radius * 4 -- souffle : toute explosion repousse
	local seen: { [Humanoid]: boolean } = {}
	for _, part in workspace:GetPartBoundsInRadius(pos, radius, overlap) do
		local hum = Combat.HumanoidFrom(part)
		if hum and not seen[hum] then
			seen[hum] = true
			local root = rootOf(hum)
			local dist = root and (root.Position - pos).Magnitude or 0
			local falloff = 1 - 0.6 * math.clamp(dist / radius, 0, 1)
			Combat.Damage(hum, damage * falloff, owner, element, root and root.Position + Vector3.new(0, 2.5, 0), durMult)
			local own = isOwnerOf(owner, hum.Parent)
			-- DÉGÂTS AU LANCEUR (card.SelfDamage, ex. bombe 50 %) : dégâts bruts + souffle, sans effet d'élément
			if own and (selfMult or 0) > 0 and hum.Health > 0 and not hum.Parent:FindFirstChildOfClass("ForceField") then
				rawDamage(hum, math.floor(damage * falloff * selfMult + 0.5), element, root and root.Position + Vector3.new(0, 2.5, 0))
			end
			if root and blast > 0 and (not own or (selfMult or 0) > 0) then
				local away = root.Position - pos
				away = if away.Magnitude > 0.1 then away.Unit else Vector3.yAxis
				Combat.Push(hum, (away + Vector3.new(0, 0.6, 0)).Unit * blast * falloff, knock ~= nil)
			end
		end
	end
	-- le décor encaisse aussi : matière abîmée / cassée, feu, extinction, cratère dans la pierre
	Matter.Blast(pos, radius, damage, element, owner, { Knock = knock })
end

-- Cible la plus proche pour le homing (joueurs adverses + mannequins).
function Combat.FindTarget(pos: Vector3, range: number, owner: Player?): BasePart?
	local best, bestDist = nil, range
	local function consider(model: Instance?)
		if not model or isOwnerOf(owner, model) then
			return
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		local root = hum and rootOf(hum)
		if hum and root and hum.Health > 0 then
			local d = (root.Position - pos).Magnitude
			if d < bestDist then
				best, bestDist = root, d
			end
		end
	end
	for _, p in Players:GetPlayers() do
		consider(p.Character)
	end
	local dummies = workspace:FindFirstChild("WandDummies")
	if dummies then
		for _, m in dummies:GetChildren() do
			consider(m)
		end
	end
	return best
end

return Combat

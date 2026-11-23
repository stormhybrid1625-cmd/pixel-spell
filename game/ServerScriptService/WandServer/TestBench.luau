--[[
	WandServer/TestBench — BANC DE TEST EN MATRICE (Studio uniquement)

	ServerStorage.WandTest:Invoke("Matrix", player, opts) tire automatiquement :
	  chaque SORT × chaque INFUSION (aucune + 5)        -> opts.Infusions (défaut true)
	  chaque SORT × chaque MODIFICATEUR (sans infusion)  -> opts.Mods = true
	sur une ou plusieurs CIBLES : "dummy" (mannequin), "ground" (sol devant lui), "wall" (mur du fond).
	Pour chaque combinaison : dégâts infligés, messages FX émis, zones créées, erreurs serveur ET client,
	voix volées, sons introuvables, pire image client. Rapport complet dans ServerStorage.WandTestReport
	(StringValue) + résumé des combinaisons suspectes dans la sortie.

	opts : { Decks = { {Deck={...}, Label="..."} }?, Cards = {"FIREBALL", ...}?, Targets = {"dummy","ground","wall"}?, Wait = 1.0?, Mods = bool?, Infusions = bool? }

	MODE MAINTIEN (opts.Hold = true) : chaque deck est précédé de « Maintien », le clic est TENU opts.HoldTime s
	(défaut 1.5) en balayant la visée (opts.Sweep, défaut 4 studs). Sans opts.Cards : les sorts qui se maintiennent
	(rayons, procéduraux, mur de glace) + une boule de feu (doit se comporter comme un clic).
	Vérifie en plus : ticks effectués, mana consommée, maintien bien terminé (état + attribut Holding),
	faisceau éteint (HoldBeamEnd), AUCUN tir de faisceau après le relâchement, délai de reprise raisonnable.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Catalog = require(ReplicatedStorage.WandShared.SpellCatalog)

local TestBench = {}
local deps
local current = nil -- enregistrement de la combinaison en cours
local clientReports: { [number]: any } = {}

local INFUSIONS = { "", "INFUSE_FIRE", "INFUSE_ICE", "INFUSE_LIGHTNING", "INFUSE_TOXIC", "INFUSE_NATURE" }
-- cartes qui ne se testent pas d'un simple clic
local SKIP = { CAST_HOLD = true }

function TestBench.Init(d)
	deps = d
	-- compteur des messages FX (Impact, Dmg, Zone...) émis pendant la combinaison
	local push = deps.FXBus.Push
	deps.FXBus.Push = function(msg, ...)
		if current and type(msg) == "table" and msg.k then
			current.Fx[msg.k] = (current.Fx[msg.k] or 0) + 1
		end
		return push(msg, ...)
	end
	LogService.MessageOut:Connect(function(text, kind)
		if not current then
			return
		end
		if kind == Enum.MessageType.MessageError or (kind == Enum.MessageType.MessageWarning and text:find("Wand")) then
			-- côté serveur seulement (les erreurs client arrivent par le rapport client)
			if not text:find("Players%.") and not text:find("StarterPlayer") then
				table.insert(current.SrvErr, text:sub(1, 200))
			end
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		if current and dt > current.HbMax then
			current.HbMax = dt
		end
	end)
	local rep = Instance.new("RemoteEvent")
	rep.Name = "WandTestReport"
	rep.Parent = ReplicatedStorage
	rep.OnServerEvent:Connect(function(_, mark, data)
		if type(mark) == "number" and type(data) == "table" then
			clientReports[mark] = data
		end
	end)
end

local function dummies()
	local list = {}
	local f = workspace:FindFirstChild("WandDummies")
	for _, m in (f and f:GetChildren() or {}) do
		local h = m:FindFirstChildOfClass("Humanoid")
		if h then
			table.insert(list, h)
		end
	end
	return list
end

local homePivots = {}

local function resetDummyPositions()

	-- les mannequins sont poussés (recul, trou noir...) : on les remet à leur place d'origine avant chaque mesure

	for _, h in dummies() do

		local m = h.Parent

		if m then

			homePivots[m] = homePivots[m] or m:GetPivot()

			m:PivotTo(homePivots[m])

			for _, p in m:GetDescendants() do

				if p:IsA("BasePart") then

					p.AssemblyLinearVelocity = Vector3.zero

					p.AssemblyAngularVelocity = Vector3.zero

				end

			end

		end

	end

end


local function healDummies()

	resetDummyPositions()
	-- un mannequin mort réapparaît : on attend qu'ils soient tous vivants (max 6 s) avant de mesurer
	local t0 = os.clock()
	repeat
		local allAlive = true
		for _, h in dummies() do
			if h.Health > 0 then
				h.Health = h.MaxHealth
			else
				allAlive = false
			end
		end
		if allAlive then
			return
		end
		task.wait(0.2)
	until os.clock() - t0 > 6
end

-- temps d'attente adapté au sort : durée de vie du projectile (mèche de bombe...) + marge, borné
local function waitFor(deck: { string }, base: number): number
	local id = deck[#deck]
	local c = Catalog.Get(id)
	local life = c and c.Proj and c.Proj.Lifetime or 0
	return math.clamp(math.max(base, life + 0.7), base, 4)
end

local function dummyDamage(): number
	local d = 0
	for _, h in dummies() do
		d += h.MaxHealth - math.max(0, h.Health)
	end
	return d
end

-- scène : joueur posé à 16 studs du premier mannequin, cibles calculées une fois
local function setupScene(player: Player)
	local hums = dummies()
	local dummy = hums[1] and hums[1].Parent
	assert(dummy, "aucun mannequin dans workspace.WandDummies")
	local dp = dummy:GetPivot().Position
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	assert(root, "personnage introuvable")
	local stand = dp + Vector3.new(0, 0, -16)
	root.CFrame = CFrame.lookAt(stand, Vector3.new(dp.X, stand.Y, dp.Z))
	root.AssemblyLinearVelocity = Vector3.zero
	task.wait(0.3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, workspace:FindFirstChild("WandDummies") }
	local g = workspace:Raycast(dp + Vector3.new(0, 4, -7), Vector3.new(0, -40, 0), params)
	local wall
	for a = -60, 60, 10 do
		local dir = (CFrame.Angles(0, math.rad(a), 0) * root.CFrame).LookVector
		local hit = workspace:Raycast(root.Position, dir * 120, params)
		if hit and math.abs(hit.Normal.Y) < 0.3 and hit.Distance > 20 then
			wall = hit.Position
			break
		end
	end
	return {
		dummy = dp,
		ground = if g then g.Position else dp + Vector3.new(0, -3, -7),
		wall = wall,
	}
end

local function cardType(id: string): string?
	local c = Catalog.Get(id)
	return c and c.Type
end

local function runCombo(player: Player, deck: { string }, aim: Vector3, waitT: number, label: string, mark: number, hold: any?)
	deps.Zone.ClearOwner(player)
	deps.Growth.ClearOwner(player)
	healDummies()
	local st = deps.PlayerWands.Get(player)
	st.Hold = nil
	st.Deck = deck
	st.Cursor = 1
	st.Mana = st.Wand.ManaMax
	st.ReadyAt = 0
	st.Recharging = false
	task.wait(0.05)
	local markers = workspace:FindFirstChild("WandZoneMarkers")
	current = { Label = label, Fx = {}, SrvErr = {}, HbMax = 0, Zones = 0, Mark = mark }
	local zoneConn = markers and markers.ChildAdded:Connect(function()
		if current then
			current.Zones += 1
		end
	end)
	workspace:SetAttribute("WandTestMark", mark)
	if hold then
		local ok, info = pcall(deps.Hold, player, aim, hold.Time, hold.Sweep)
		if not ok then
			table.insert(current.SrvErr, "HOLD: " .. tostring(info))
			info = {}
		end
		current.Hold = info
		-- après le relâchement : plus AUCUN tir de faisceau maintenu ne doit partir
		-- (HoldBeam = tick du rayon MAINTENU ; les « Beam » ordinaires, ex. arcs d'un arbre foudre, sont normaux)
		local beamsAtEnd = current.Fx.HoldBeam or 0
		task.wait(0.4)
		current.BeamsAfter = (current.Fx.HoldBeam or 0) - beamsAtEnd
		task.wait(math.max(0, waitT - 0.4))
	else
		local ok, err = pcall(deps.Cast, player, aim)
		if not ok then
			table.insert(current.SrvErr, "CAST: " .. tostring(err))
		end
		task.wait(waitFor(deck, waitT))
	end
	local rec = current
	rec.Dmg = math.floor(dummyDamage() + 0.5)
	current = nil
	if zoneConn then
		zoneConn:Disconnect()
	end
	return rec
end

local function fxString(fx): string
	local keys = {}
	for k in fx do
		table.insert(keys, k)
	end
	table.sort(keys)
	local out = {}
	for _, k in keys do
		table.insert(out, k .. fx[k])
	end
	return table.concat(out, ",")
end

function TestBench.Run(player: Player?, opts: any?)
	opts = opts or {}
	player = player or Players:GetPlayers()[1]
	assert(player, "aucun joueur")
	local scene = setupScene(player)
	local waitT = opts.Wait or 1.0
	local targets = opts.Targets or { "dummy" }
	local hold = if opts.Hold then { Time = opts.HoldTime or 1.5, Sweep = Vector3.new(opts.Sweep or 4, 0, 0) } else nil
	-- sorts à tester : tout ce qui se lance (projectiles + déclencheurs posés), sauf exclusions
	local cards = opts.Cards
	if not cards and opts.Decks then
		cards = {} -- decks précis seulement
	end
	if not cards and hold then
		cards = {}
		for _, cid in Catalog.Order do
			local c = Catalog.ById[cid]
			local p = c.Proj
			if p and (p.Growth or (p.Instant and not p.Self) or (p.Zone and p.Zone.Kind == "IceWall")) then
				table.insert(cards, c.Id)
			end
		end
		table.insert(cards, "FIREBALL") -- témoin : ne se maintient pas, doit partir comme un clic
	elseif not cards then
		cards = {}
		for _, cid in Catalog.Order do
			local c = Catalog.ById[cid]
			if (c.Type == "Projectile" or c.Type == "Trigger") and not SKIP[c.Id] then
				table.insert(cards, c.Id)
			end
		end
	end
	local combos = {}
	for _, id in cards do
		local t = cardType(id)
		if t == "Projectile" or t == "Trigger" then
			if opts.Infusions ~= false then
				for _, inf in INFUSIONS do
					table.insert(combos, { Deck = if inf == "" then { id } else { inf, id }, Label = id .. (if inf == "" then "" else "+" .. inf:sub(8)) })
				end
			end
			if opts.Mods then
				-- tir de RÉFÉRENCE (sans modificateur) pour repérer les modificateurs sans effet
				if opts.Infusions == false then
					table.insert(combos, { Deck = { id }, Label = id })
				end
				for _, cid in Catalog.Order do
					local c = Catalog.ById[cid]
					if c.Type == "Modifier" and not c.Id:find("^INFUSE_") and not SKIP[c.Id] then
						table.insert(combos, { Deck = { c.Id, id }, Label = id .. "+" .. c.Id, Mod = true, Base = id })
					end
				end
			end
		end
	end
	-- DECKS PRÉCIS : opts.Decks = { { Deck = {...}, Label = "..." }, ... }
	for _, d in opts.Decks or {} do
		table.insert(combos, { Deck = d.Deck, Label = d.Label or table.concat(d.Deck, "+") })
	end
	clientReports = {}
	local results = {}
	local mark = 0
	local t0 = os.clock()
	for _, combo in combos do
		for _, tg in targets do
			local aim = scene[tg]
			if tg == "dummy" then
				local h = dummies()[1]
				local m = h and h.Parent
				if m then
					aim = m:GetPivot().Position
				end
			end
			if aim then
				mark += 1
				local deck = combo.Deck
				if hold then
					deck = table.clone(deck)
					table.insert(deck, 1, "CAST_HOLD")
				end
				local rec = runCombo(player, deck, aim, waitT, (if hold then "MAINTIEN " else "") .. combo.Label .. " @" .. tg, mark, hold)
				rec.Target = tg
				rec.Combo = combo
				table.insert(results, rec)
			end
		end
	end
	-- dernier rapport client
	mark += 1
	workspace:SetAttribute("WandTestMark", mark)
	task.wait(0.6)
	workspace:SetAttribute("WandTestMark", nil)
	deps.Zone.ClearOwner(player)
	deps.Growth.ClearOwner(player)
	healDummies()

	-- signature de base (sans modificateur) pour repérer les modificateurs SANS EFFET
	local baseSig = {}
	for _, r in results do
		if not r.Combo.Mod and #r.Combo.Deck == 1 then
			baseSig[r.Combo.Deck[1] .. r.Target] = fxString(r.Fx) .. "|" .. r.Dmg .. "|" .. r.Zones
		end
	end
	local lines, flagged = {}, {}
	local nErr, nSteal, nMissing = 0, 0, 0
	for _, r in results do
		local cr = clientReports[r.Mark] or {}
		local flags = {}
		local cliErr = cr.Err or {}
		if #r.SrvErr > 0 then
			table.insert(flags, "ERR_SERVEUR")
			nErr += 1
		end
		if #cliErr > 0 then
			table.insert(flags, "ERR_CLIENT")
			nErr += 1
		end
		if (cr.Steals or 0) > 0 then
			table.insert(flags, "VOIX_VOLEES")
			nSteal += 1
		end
		if cr.Missing and cr.Missing ~= "" then
			table.insert(flags, "SON_MANQUANT")
			nMissing += 1
		end
		if next(r.Fx) == nil then
			table.insert(flags, "AUCUN_FX")
		end
		if r.HbMax > 0.05 then
			table.insert(flags, ("PIC_SERVEUR_%dms"):format(r.HbMax * 1000))
		end
		if (cr.MaxMs or 0) > 60 then
			table.insert(flags, ("PIC_CLIENT_%dms"):format(cr.MaxMs))
		end
		if r.Combo.Mod and baseSig[r.Combo.Base .. r.Target] == fxString(r.Fx) .. "|" .. r.Dmg .. "|" .. r.Zones then
			table.insert(flags, "MODIF_SANS_EFFET?")
		end
		-- contrôles propres au MAINTIEN
		local holdTxt = ""
		local hi = r.Hold
		if hi then
			if hi.Mode == "Hold" then
				local spent = (hi.ManaBefore or 0) - (hi.ManaAfter or 0)
				holdTxt = (" maintien=%d ticks/%.1fs tirs=%d mana=%d"):format(hi.Ticks or 0, hi.Held or 0, hi.Shots or 0, spent)
				if hi.Shots and hi.Shots > 0 and (hi.Ticks or 0) == 0 then
					table.insert(flags, "MAINTIEN_SANS_TICK")
				end
				if hi.HoldLeft or hi.AttrLeft then
					table.insert(flags, "MAINTIEN_PAS_TERMINE")
				end
				if (r.BeamsAfter or 0) > 0 then
					table.insert(flags, ("FAISCEAU_APRES_RELACHE_%d"):format(r.BeamsAfter))
				end
				if (r.Fx.HoldBeam or 0) > 0 and (r.Fx.HoldBeamEnd or 0) == 0 then
					table.insert(flags, "FAISCEAU_NON_ETEINT")
				end
				if hi.Shots and hi.Shots > 0 and spent <= (hi.Cost or 0) then
					table.insert(flags, "MANA_TICK_NON_PAYEE")
				end
				if (hi.ReadyIn or 0) > 5 then
					table.insert(flags, ("REPRISE_TROP_LONGUE_%.1fs"):format(hi.ReadyIn))
				end
				if hi.EndedEarly then
					holdTxt ..= " (arrêté avant la fin)"
				end
			else
				holdTxt = " (pas de maintien : tir normal)"
			end
		end
		local line = ("%-40s dmg=%-4d zones=%d fx=[%s]%s hb=%dms cli=%dms%s%s%s"):format(
			r.Label, r.Dmg, r.Zones, fxString(r.Fx), holdTxt, r.HbMax * 1000, cr.MaxMs or -1,
			if cr.Missing and cr.Missing ~= "" then " manquants=" .. cr.Missing else "",
			if #flags > 0 then "  <<" .. table.concat(flags, " ") .. ">>" else "",
			if #r.SrvErr + #cliErr > 0 then "\n      " .. table.concat(r.SrvErr, "\n      ") .. table.concat(cliErr, "\n      ") else "")
		table.insert(lines, line)
		if #flags > 0 then
			table.insert(flagged, line)
		end
	end
	local header = ("MATRICE : %d tirs en %.0f s — %d avec erreurs, %d avec voix volées, %d avec sons manquants, %d signalés")
		:format(#results, os.clock() - t0, nErr, nSteal, nMissing, #flagged)
	local sv = ServerStorage:FindFirstChild("WandTestReport") or Instance.new("StringValue")
	sv.Name = "WandTestReport"
	sv.Value = header .. "\n" .. table.concat(lines, "\n")
	sv.Parent = ServerStorage
	print("[WandTest] " .. header)
	for _, l in flagged do
		print("[WandTest] " .. l)
	end
	return header
end

-- ══ BANC DE PERFORMANCE (phase 1.4) ══════════════════════════════════════════════════════
-- ServerStorage.WandTest:Invoke("PerfBench", player, { Seconds = 8?, Scenarios = {...}? })
-- Chaque SCÉNARIO = un deck lourd tiré en CONTINU (dès que la baguette est prête) pendant Seconds, mana infinie.
-- Mesure par scénario : serveur (temps d'image moyen / pire), client (FPS moyen, 95e centile, pire image, étincelles,
-- objets d'effets, lumières), charge du jeu (projectiles, arbres, zones, cellules de feu).
-- Puis 4 s de repos : FUITES = instances / mémoire qui ne redescendent pas au niveau de départ.
-- SEUILS (signalés) : serveur moyen > 4 ms ou pire > 50 ms ; client 95e centile > 33 ms (< 30 FPS) ; fuite > 3 %.
local PERF_SCENARIOS = {
	{ Name = "Feu en triple", Deck = { "TRIPLE", "INFUSE_FIRE", "FIREBALL", "FIREBALL", "FIREBALL" }, Target = "ground" },
	{ Name = "Bombes en éventail", Deck = { "SCATTER", "BOMB", "BOMB", "BOMB", "BOMB" }, Target = "ground" },
	{ Name = "Gigantisme III + boule de feu", Deck = { "SIZE_PLUS_3", "FIREBALL" }, Target = "ground" },
	{ Name = "Éclats explosifs", Deck = { "FRAGMENT", "EXPLOSIVE", "DIVIDE_4", "SPARK_BOLT" }, Target = "dummy" },
	{ Name = "Ramure foudre + mèche", Deck = { "ADD_EXPIRE", "INFUSE_LIGHTNING", "BRANCH", "INFUSE_FIRE", "SPARK_BOLT" }, Target = "ground" },
	{ Name = "Rayon tellurique toxique", Deck = { "INFUSE_TOXIC", "TERRA_BEAM" }, Target = "ground" },
	{ Name = "Éclair maintenu", Deck = { "CAST_HOLD", "LIGHTNING" }, Target = "dummy", Hold = true },
	{ Name = "Ramure maintenue feu", Deck = { "CAST_HOLD", "INFUSE_FIRE", "BRANCH" }, Target = "ground", Hold = true },
	{ Name = "Oméga (tout le deck)", Deck = { "OMEGA", "FIREBALL", "BOMB", "LASER", "INFUSE_ICE", "SPARK_BURST" }, Target = "dummy" },
}
TestBench.PerfScenarios = PERF_SCENARIOS

function TestBench.RunPerf(player: Player?, opts: any?, getPerf: () -> any)
	opts = opts or {}
	player = player or Players:GetPlayers()[1]
	assert(player, "aucun joueur")
	local Matter = require(script.Parent.MatterService)
	local scene = setupScene(player)
	local seconds = opts.Seconds or 8
	local scenarios = opts.Scenarios or PERF_SCENARIOS
	local st = deps.PlayerWands.Get(player)
	local savedDeck = st.Deck
	local markers = workspace:FindFirstChild("WandZoneMarkers")

	local function clientSnapshot(): any
		local p = getPerf()[player.Name]
		return p and table.clone(p) or nil
	end
	local function settle(t: number)
		deps.Zone.ClearOwner(player)
		deps.Growth.ClearOwner(player)
		task.wait(t)
	end

	workspace:SetAttribute("WandPerfOn", true)
	settle(3)
	local base = clientSnapshot()
	local baseSrv = game:GetService("Stats").InstanceCount
	local lines, flagged = {}, {}
	local t0 = os.clock()
	for _, sc in scenarios do
		local aim = scene[sc.Target or "dummy"] or scene.dummy
		st.Deck = table.clone(sc.Deck)
		st.Cursor = 1
		st.Hold = nil
		st.ReadyAt = 0
		-- TRAVAIL du serveur par image (Stats.HeartbeatTimeMs), pas l'intervalle entre images
		local Stats = game:GetService("Stats")
		local hb, hbMax, frames = 0, 0, 0
		local peak = { Proj = 0, Trees = 0, Zones = 0, Fire = 0 }
		local conn = RunService.Heartbeat:Connect(function(dt)
			local work = (Stats.HeartbeatTimeMs or 0) / 1000
			hb += work
			frames += 1
			if dt > hbMax then
				hbMax = dt -- pire INTERVALLE : un vrai blocage du serveur s'y voit
			end
			peak.Proj = math.max(peak.Proj, deps.Projectiles.LiveCount())
			peak.Trees = math.max(peak.Trees, deps.Growth.Count())
			peak.Zones = math.max(peak.Zones, markers and #markers:GetChildren() or 0)
			peak.Fire = math.max(peak.Fire, Matter.BurningCount())
		end)
		local cli = { Fps = {}, P95 = 0, Max = 0, Sparks = 0, Fx = 0, Lights = 0 }
		local casts, errs = 0, 0
		local start = os.clock()
		local lastSample = 0
		while os.clock() - start < seconds do
			st.Mana = st.Wand.ManaMax -- mana infinie : on mesure la charge, pas l'économie
			healDummies()
			if sc.Hold then
				local ok = pcall(deps.Hold, player, aim, math.min(2.5, seconds - (os.clock() - start)), Vector3.new(4, 0, 0))
				casts += 1
				errs += if ok then 0 else 1
				st.ReadyAt = 0
			elseif workspace:GetServerTimeNow() >= st.ReadyAt then
				local ok = pcall(deps.Cast, player, aim + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3)))
				casts += 1
				errs += if ok then 0 else 1
			end
			-- un relevé client par seconde
			local p = getPerf()[player.Name]
			if p and p.At ~= lastSample then
				lastSample = p.At
				table.insert(cli.Fps, p.Fps)
				cli.P95 = math.max(cli.P95, p.P95Ms or 0)
				cli.Max = math.max(cli.Max, p.MaxMs or 0)
				cli.Sparks = math.max(cli.Sparks, p.Sparks or 0)
				cli.Fx = math.max(cli.Fx, p.Fx or 0)
				cli.Lights = math.max(cli.Lights, p.Lights or 0)
			end
			task.wait(0.05)
		end
		conn:Disconnect()
		local fpsAvg = 0
		for _, f in cli.Fps do
			fpsAvg += f / #cli.Fps
		end
		local srvAvg = if frames > 0 then hb / frames * 1000 else 0
		-- temps d'image serveur : Heartbeat mesure l'intervalle (~16,7 ms) ; le TRAVAIL du jeu = au-delà de 16,7 ms
		local flags = {}
		if srvAvg > 4 then
			table.insert(flags, ("SERVEUR_LENT_%.0fms"):format(srvAvg))
		end
		if hbMax * 1000 > 50 then
			table.insert(flags, ("PIC_SERVEUR_%.0fms"):format(hbMax * 1000))
		end
		if cli.P95 > 33 then
			table.insert(flags, ("CLIENT_SOUS_30FPS_p95=%.0fms"):format(cli.P95))
		end
		if errs > 0 then
			table.insert(flags, "ERREURS_" .. errs)
		end
		local line = ("%-30s tirs=%-3d | serveur travail moy %.2fms, pire image %.0fms | client %.0f FPS, p95 %.0fms, pire %.0fms | étincelles %d, effets %d, lumières %d | projectiles %d, arbres %d, zones %d, feu %d%s")
			:format(sc.Name, casts, srvAvg, hbMax * 1000, fpsAvg, cli.P95, cli.Max, cli.Sparks, cli.Fx, cli.Lights, peak.Proj, peak.Trees, peak.Zones, peak.Fire,
				if #flags > 0 then "  <<" .. table.concat(flags, " ") .. ">>" else "")
		table.insert(lines, line)
		if #flags > 0 then
			table.insert(flagged, line)
		end
		settle(1.5)
	end
	-- FUITES : après 4 s de repos, tout doit revenir au niveau de départ
	settle(4)
	local after = clientSnapshot()
	local afterSrv = game:GetService("Stats").InstanceCount
	workspace:SetAttribute("WandPerfOn", nil)
	st.Deck = savedDeck
	st.Cursor = 1
	local leak = {}
	local srvGrow = (afterSrv - baseSrv) / math.max(1, baseSrv)
	if srvGrow > 0.03 then
		table.insert(leak, ("FUITE_SERVEUR +%d instances (+%.1f %%)"):format(afterSrv - baseSrv, srvGrow * 100))
	end
	if base and after then
		local ci = ((after.Instances or 0) - (base.Instances or 0)) / math.max(1, base.Instances or 1)
		if ci > 0.03 then
			table.insert(leak, ("FUITE_CLIENT +%d instances (+%.1f %%)"):format((after.Instances or 0) - (base.Instances or 0), ci * 100))
		end
		if (after.Fx or 0) > (base.Fx or 0) + 20 then
			table.insert(leak, ("EFFETS_RESTANTS %d"):format(after.Fx))
		end
	end
	local memLine = if base and after then ("mémoire client %.0f -> %.0f Mo, instances client %d -> %d, serveur %d -> %d"):format(
		base.MemMb or 0, after.MemMb or 0, base.Instances or 0, after.Instances or 0, baseSrv, afterSrv) else "(pas de mesures client)"
	local header = ("PERFORMANCE : %d scénarios x %ds en %.0f s — %d signalés, %s"):format(
		#scenarios, seconds, os.clock() - t0, #flagged, if #leak > 0 then table.concat(leak, ", ") else "aucune fuite")
	local sv = ServerStorage:FindFirstChild("WandPerfReport") or Instance.new("StringValue")
	sv.Name = "WandPerfReport"
	sv.Value = header .. "\n" .. memLine .. "\n" .. table.concat(lines, "\n")
	sv.Parent = ServerStorage
	print("[WandPerf] " .. header)
	for _, l in flagged do
		print("[WandPerf] " .. l)
	end
	return header
end

return TestBench

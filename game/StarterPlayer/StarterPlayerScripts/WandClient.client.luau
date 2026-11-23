--[[
	WandClient (LocalScript principal)
	Le client est une VUE + une TÉLÉCOMMANDE :
	  • il affiche la baguette et le grimoire (WandUI) et propose un deck au serveur (SetDeck) ;
	  • il envoie uniquement le point visé quand on tire (Cast) ;
	  • il dessine les VFX à partir de ce que le serveur réplique (VFXManager).
	Aucune décision de gameplay n'est prise ici.

	Contrôles : clic gauche maintenu = tirer | E = ouvrir/fermer le grimoire | L = ambiance sombre on/off
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("WandShared")
local Remotes = Shared:WaitForChild("Remotes")

local WandUI = require(script:WaitForChild("WandUI"))
local IncantFX = require(script:WaitForChild("IncantFX"))
local VFX = require(script:WaitForChild("VFXManager"))
local Ambience = require(script:WaitForChild("Ambience"))
local SoundFX = require(script:WaitForChild("SoundFX"))
local CameraFX = require(script:WaitForChild("CameraFX"))
local ScreenFX = require(script:WaitForChild("ScreenFX"))
local SettingsUI = require(script:WaitForChild("SettingsUI"))
local Slippery = require(script:WaitForChild("Slippery"))
local Planner = require(Shared:WaitForChild("SpellPlanner"))
local Catalog = require(Shared:WaitForChild("SpellCatalog"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ── Envoi du deck (regroupé : une seule requête pour plusieurs déplacements rapides) ────────
local pendingDeck: { string }? = nil
local sendScheduled = false

local function sendDeck(deck: { string })
	pendingDeck = deck
	if sendScheduled then
		return
	end
	sendScheduled = true
	task.delay(0.15, function()
		sendScheduled = false
		if pendingDeck then
			Remotes.SetDeck:FireServer(pendingDeck)
			pendingDeck = nil
		end
	end)
end

SoundFX.Init()
WandUI.Init({ OnDeckChanged = sendDeck })
VFX.Init() -- initialise aussi LightPool et Sparks
Ambience.Init(false) -- démarre en LUMINEUX (user 2026-11-23) ; touche L = ambiance sombre
CameraFX.Init() -- secousses / recul / halo des explosions (réglages : FXSettings)
ScreenFX.Init() -- vignettes texturées par élément + teinte
SettingsUI.Init() -- bouton REGLAGES (touche O)
Slippery.Init() -- la glace et le givre font déraper le personnage
require(script:WaitForChild("MovementController")).Init() -- course (Shift) / dash (Q)
require(script:WaitForChild("Footsteps")).Init() -- bruits de pas + poussière en courant (tous les joueurs proches)
if RunService:IsStudio() then
	task.defer(function()
		pcall(function()
			require(script:WaitForChild("ConsistencyCheck")).Run() -- contrôle de cohérence (sortie : [WandCheck])
		end)
	end)
end

Remotes.DeckSync.OnClientEvent:Connect(function(deck, wand)
	if pendingDeck then
		return -- une modification locale plus récente est en route : on attend la prochaine synchro
	end
	WandUI.SetDeck(deck, wand)
end)

-- Poussée (explosions, recul, trou noir) : le serveur ne peut pas déplacer directement un personnage
-- dont la physique appartient au client ; il envoie la vitesse à ajouter, bornée ici aussi.
local function applyPush(msg)
	if msg.u ~= player.UserId or typeof(msg.v) ~= "Vector3" then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local v = msg.v
		if v.Magnitude > 150 then
			v = v.Unit * 150
		end
		root.AssemblyLinearVelocity += v
	end
end

-- Budget de création d'effets : les visuels qui arrivent ensemble (6 impacts dans la même image)
-- sont étalés sur les images suivantes (2,5 ms max par image, jamais plus de 0,2 s de retard).
-- Les sons / caméra restent immédiats.
local vfxQueue = {}
local VFX_BUDGET = 0.0025
local VFX_MAX_LAG = 0.2
game:GetService("RunService").Heartbeat:Connect(function()
	local n = #vfxQueue
	if n == 0 then
		return
	end
	local t0 = os.clock()
	local done = 0
	for i = 1, n do
		local e = vfxQueue[i]
		if i > 1 and os.clock() - t0 > VFX_BUDGET and t0 - e.t < VFX_MAX_LAG then
			break
		end
		local ok, err = pcall(VFX.Handle, e.m)
		if not ok then
			warn("VFX", err)
		end
		done = i
	end
	if done == n then
		table.clear(vfxQueue)
	else
		vfxQueue = table.move(vfxQueue, done + 1, n, 1, {})
	end
end)

Remotes.SpellFX.OnClientEvent:Connect(function(batch)
	if type(batch) ~= "table" then
		return
	end
	for _, msg in batch do
		if type(msg) == "table" then
			if msg.k == "Cast" and msg.u == player.UserId then
				continue -- notre propre tir : son et flash déjà joués au clic (prédiction)
			end
			if msg.k == "NoMana" then
				WandUI.FlashNoMana()
			elseif msg.k == "Push" then
				applyPush(msg)
			else
				table.insert(vfxQueue, { m = msg, t = os.clock() })
			end
			IncantFX.Handle(msg) -- cercles d'incantation (immédiat, hors budget VFX)
			SoundFX.Handle(msg) -- chaque événement a aussi son son (randomisé, limité)
			CameraFX.Handle(msg)
			ScreenFX.Handle(msg)
		end
	end
end)

-- ── Visée ─────────────────────────────────────────────────────────────────────────────
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local function getAimPoint(): Vector3
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local ignore = { VFX.Folder() }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local proj = workspace:FindFirstChild("WandProjectiles")
	if proj then
		table.insert(ignore, proj)
	end
	aimParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, aimParams)
	return if hit then hit.Position else ray.Origin + ray.Direction * 1000
end

-- ── Prédiction du tir ──────────────────────────────────────────────────────────────────────────
-- Le son de départ, le sifflement et le flash jouent à l'instant du clic, avec le MÊME planificateur
-- que le serveur (aucun aller-retour réseau). Le serveur reste seul juge : s'il refuse, rien d'autre
-- ne se passe (pas de projectile). On ne prédit pas un tir que le mana ne permet pas.
local lastCastElement: string? = nil
local function predictCast(aim: Vector3)
	local deck, wand = WandUI.GetDeck()
	local ok, plan = pcall(Planner.Plan, deck, wand, player:GetAttribute("WandCursor") or 1)
	if not ok or plan.Empty or (player:GetAttribute("Mana") or 0) < Planner.Cost(plan) then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local head = root.Position + Vector3.new(0, 1.5, 0) -- même calcul d'origine que le serveur
	local dir = aim - head
	dir = if dir.Magnitude > 1 then dir.Unit else root.CFrame.LookVector
	local origin = head + dir * 2.5
	local card = Catalog.ById[plan.FirstCard or ""]
	local proj = card and card.Proj
	VFX.Cast(origin, dir, plan.FirstElement)
	SoundFX.PredictCast(plan.FirstCard, plan.FirstElement, origin, proj and proj.Speed or 100, proj ~= nil and (proj.Instant or proj.Self))
	-- recul doux du tir (aucune rotation : la visée ne bouge pas), selon le coût du sort
	CameraFX.Recoil(math.clamp(Planner.Cost(plan) / 60, 0.08, 1), plan.FirstElement)
	ScreenFX.Pulse(math.clamp(Planner.Cost(plan) / 100, 0.12, 0.5)) -- bref voile noir sur les bords au tir
	lastCastElement = plan.FirstElement
end

-- ── Tir (clic maintenu = tir automatique au rythme de la baguette) ───────────────────────
local firing = false
local lastSend = 0
-- MAINTIEN : si le prochain tir contient la carte "Maintien", le clic démarre un lancement maintenu ;
-- on envoie ensuite la visée ~12 fois/s, puis "end" au relâchement.
local holding = false
local lastAim = 0

local Incantation = require(ReplicatedStorage:WaitForChild("WandShared"):WaitForChild("Incantation"))
local function nextCastMode(): string
	local deck, wand = WandUI.GetDeck()
	local ok, plan = pcall(Planner.Plan, deck, wand, player:GetAttribute("WandCursor") or 1)
	if not ok then
		return "Click"
	end
	if plan.CastMode == "Hold" then
		return "Hold"
	end
	-- deck plus cher que la barre PLEINE : incantation (même règle que le serveur)
	local cost = Planner.Cost(plan)
	if wand and cost > (wand.ManaMax or math.huge) and not plan.Empty then
		local v = Incantation.Check(wand, cost, player:GetAttribute("Mana") or 0)
		if v.Ok then
			return "Incant"
		end
	end
	return "Click"
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not gameProcessed and not WandUI.IsOpen() and not WandUI.IsPointerOverUI() then
			firing = true
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = false
		if holding then
			holding = false
			Remotes.Cast:FireServer(getAimPoint(), "end")
		end
	end
end)

RunService.RenderStepped:Connect(function()
	-- vibration continue pendant un lancement MAINTENU (signature de l'élément du sort)
	CameraFX.Hold(if holding then 0.16 else 0, lastCastElement)
	if holding then
		if os.clock() - lastAim >= 0.08 then
			lastAim = os.clock()
			Remotes.Cast:FireServer(getAimPoint(), "aim")
		end
		return
	end
	if not firing or WandUI.IsOpen() then
		return
	end
	local ready = player:GetAttribute("CastReadyAt") or 0
	-- petite avance (30 ms) pour compenser la latence ; le serveur revérifie de toute façon
	if workspace:GetServerTimeNow() + 0.03 < ready then
		return
	end
	if os.clock() - lastSend < 0.05 then
		return
	end
	lastSend = os.clock()
	local aim = getAimPoint()
	local mode = nextCastMode()
	if mode == "Incant" then
		holding = true -- même canal que le maintien : visée ~12/s puis "end" au relâchement
		lastAim = os.clock()
		Remotes.Cast:FireServer(aim, "hold")
		return
	end
	predictCast(aim)
	if mode == "Hold" then
		holding = true
		lastAim = os.clock()
		Remotes.Cast:FireServer(aim, "hold")
	else
		Remotes.Cast:FireServer(aim)
	end
end)


-- ── BANC DE TEST EN MATRICE (Studio uniquement) : rapport client par combinaison (workspace.WandTestMark) ──
if RunService:IsStudio() then
	task.spawn(function()
		local rep = ReplicatedStorage:WaitForChild("WandTestReport", 20)
		if not rep then
			return
		end
		local LogService = game:GetService("LogService")
		local SoundService = game:GetService("SoundService")
		local cur = { Err = {}, Max = 0 }
		local mark = workspace:GetAttribute("WandTestMark")
		local steals0 = SoundService:GetAttribute("WandSFXSteals") or 0
		LogService.MessageOut:Connect(function(text, kind)
			if workspace:GetAttribute("WandTestMark") and (kind == Enum.MessageType.MessageError or (kind == Enum.MessageType.MessageWarning and text:find("Wand")))
				and not text:find("ServerScriptService") and not text:find("%[WandTest%]") then
				table.insert(cur.Err, text:sub(1, 200))
			end
		end)
		RunService.RenderStepped:Connect(function(dt)
			if dt > cur.Max then
				cur.Max = dt
			end
		end)
		workspace:GetAttributeChangedSignal("WandTestMark"):Connect(function()
			local st = SoundService:GetAttribute("WandSFXSteals") or 0
			if mark then
				rep:FireServer(mark, { Err = cur.Err, MaxMs = cur.Max * 1000, Steals = st - steals0, Missing = SoundService:GetAttribute("WandSFXMissing") or "" })
			end
			SoundService:SetAttribute("WandSFXMissing", "")
			steals0 = st
			cur = { Err = {}, Max = 0 }
			mark = workspace:GetAttribute("WandTestMark")
		end)
	end)
end

-- ── MESURES DE PERFORMANCE (Studio uniquement) : envoyées au serveur quand workspace.WandPerfOn ─────
if RunService:IsStudio() then
	task.spawn(function()
		local perfRemote = ReplicatedStorage:WaitForChild("WandPerf", 20)
		if not perfRemote then
			return
		end
		local Stats = game:GetService("Stats")
		local frames = {}
		RunService.RenderStepped:Connect(function(dt)
			if #frames < 600 then
				table.insert(frames, dt)
			end
		end)
		while true do
			task.wait(1)
			if workspace:GetAttribute("WandPerfOn") and #frames > 0 then
				local sorted = table.clone(frames)
				table.sort(sorted)
				local sum = 0
				for _, d in sorted do
					sum += d
				end
				local n = #sorted
				local function stat(name)
					local ok, v = pcall(function()
						return (Stats :: any)[name]
					end)
					return if ok then v else -1
				end
				perfRemote:FireServer({
					Fps = n / sum,
					AvgMs = sum / n * 1000,
					P95Ms = sorted[math.max(1, math.floor(n * 0.95))] * 1000,
					MaxMs = sorted[n] * 1000,
					MemMb = Stats:GetTotalMemoryUsageMb(),
					RecvKbps = stat("DataReceiveKbps"),
					Instances = stat("InstanceCount"),
					Parts = #workspace.Terrain:GetChildren(),
					-- coût des EFFETS côté joueur (banc de performance 1.4)
					Sparks = (function() local ok, n = pcall(function() return require(script:WaitForChild("Sparks")).Count() end) return if ok then n else -1 end)(), -- étincelles ACTIVES (pas la réserve)
					Fx = (function() local f = workspace:FindFirstChild("WandFX_Local") return f and #f:GetDescendants() or 0 end)(),
					Lights = (function() local f = workspace:FindFirstChild("WandLights_Local") local n = 0 if f then for _, d in f:GetDescendants() do if d:IsA("Light") and d.Enabled and d.Brightness > 0 then n += 1 end end end return n end)(),
				})
			end
			table.clear(frames)
		end
	end)
end

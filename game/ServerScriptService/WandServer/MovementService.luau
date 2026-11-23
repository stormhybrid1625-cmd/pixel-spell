-- MovementService — validates base movement (course / dash) and publishes the state.
-- Physics run on the owning client (it owns its character); the server checks cooldowns / locks,
-- sets the speed multiplier and replicates the state for animations + FX on every client:
--   Humanoid attributes: MoveState ("" | "Sprint" | "Dash"), MoveDir (Vector3), MoveMult (number)
-- Rules: casting stops the sprint; frozen / stunned (Combat.MoveLocked) or incanting (attr "Incanting")
-- blocks the dash.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("WandShared")
local Cfg = require(Shared.MoveConfig)

local MovementService = {}
local Combat, FXBus
local states: { [Player]: any } = {}
local TOL = 0.15 -- latency tolerance on cooldowns

local function humOf(player: Player): (Humanoid?, BasePart?)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then return nil, nil end
	return hum, root :: BasePart
end

local function stOf(player: Player)
	local s = states[player]
	if not s then
		s = { SprintHeld = false, DashReady = 0, Token = 0 }
		states[player] = s
	end
	return s
end

local function flat(v: any): Vector3?
	if typeof(v) ~= "Vector3" or v ~= v then return nil end
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 0.05 or f.Magnitude > 1e4 then return nil end
	return f.Unit
end

local function setState(player: Player, hum: Humanoid, state: string, dir: Vector3?)
	local s = stOf(player)
	s.Token += 1
	hum:SetAttribute("MoveState", state)
	if dir then hum:SetAttribute("MoveDir", dir) end
	hum:SetAttribute("MoveMult", if state == "Sprint" then Cfg.SprintMult else 1)
	Combat.RefreshMove(hum)
	return s.Token
end

-- back to sprint (if still held) or idle once a timed state ends, unless something else happened since
local function endTimed(player: Player, token: number)
	local s = states[player]
	local hum = humOf(player)
	if not s or not hum or s.Token ~= token then return end
	setState(player, hum, if s.SprintHeld then "Sprint" else "")
end

local function blocked(hum: Humanoid): boolean
	return Combat.MoveLocked(hum) or hum:GetAttribute("Incanting") == true or hum:GetAttribute("Ragdoll") == true
end

local function onMove(player: Player, action: any, arg: any)
	local hum, root = humOf(player)
	if not hum or not root then return end
	local s = stOf(player)
	local state = hum:GetAttribute("MoveState") or ""
	local now = os.clock()
	if action == "GetUp" then -- propulsion céleste : le client a vu son atterrissage (MoveAPI valide)
		if MovementService.GetUpHook then MovementService.GetUpHook(player) end
		return
	end
	if action == "Sprint" then
		s.SprintHeld = arg == true and hum:GetAttribute("Ragdoll") ~= true
		if state == "" or state == "Sprint" then
			setState(player, hum, if s.SprintHeld then "Sprint" else "")
		end
	elseif action == "Dash" then
		local dir = flat(arg)
		if not dir or now < s.DashReady - TOL or blocked(hum) then return end
		s.DashReady = now + Cfg.DashCooldown
		local token = setState(player, hum, "Dash", dir)
		FXBus.Push({ k = "Dash", p = root.Position, d = dir, u = player.UserId })
		task.delay(Cfg.DashTime, endTimed, player, token)
	end
end

-- a spell moved this player (MoveAPI): any sprint / dash is cancelled (Shift has to be pressed again)
function MovementService.Interrupt(player: Player)
	local s = states[player]
	local hum = humOf(player)
	if not s or not hum then return end
	s.SprintHeld = false
	if (hum:GetAttribute("MoveState") or "") ~= "" then setState(player, hum, "") end
end

-- casting a spell stops the sprint (the client has to press Shift again)
function MovementService.OnCast(player: Player)
	local s = states[player]
	local hum = humOf(player)
	if not s or not hum or hum:GetAttribute("MoveState") ~= "Sprint" then return end
	s.SprintHeld = false
	setState(player, hum, "")
end

function MovementService.Init(combat, fxbus)
	Combat, FXBus = combat, fxbus
	Shared.Remotes.Move.OnServerEvent:Connect(onMove)
	MovementService.Test = onMove -- banc de test serveur
	local function reset(player: Player)
		states[player] = nil
	end
	Players.PlayerRemoving:Connect(reset)
	Players.PlayerAdded:Connect(function(p) p.CharacterAdded:Connect(function() reset(p) end) end)
	for _, p in Players:GetPlayers() do p.CharacterAdded:Connect(function() reset(p) end) end
end

return MovementService

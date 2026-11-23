-- MoveAPI — shared movement API for spells (Kickback, Grappin, Échange, Lévitation, runic spells...).
--   MoveAPI.Kick(hum, dir, power)         KICKBACK & attacks: power < Cfg.CelestialSpeed -> ground recoil,
--                                         above -> propulsion céleste (both scale with power)
--   MoveAPI.Propel(hum, velocity)         RECUL AU SOL: violently pushed, stays on the ground, braces on
--                                         its legs and skids to a stop over Cfg.SkidTime (horizontal only)
--   MoveAPI.Celestial(hum, velocity)      ragdoll + launch; gets up Cfg.GetUpDelay s after landing
--   MoveAPI.Teleport(hum, pos) -> bool    safe teleport (never inside a wall: searches up to 6 studs up)
--   MoveAPI.Swap(humA, humB) -> bool      swaps two characters' positions
-- Players own their character physics: the server builds the ragdoll joints (so EVERY client sees it),
-- the owning client applies the velocity / Physics state; the server detects the landing and decides
-- when to get up (single authority). Dummies (no player) are fully simulated here.
-- Humanoid attribute "Ragdoll" = true while ragdolled (blocks casting, dash, sprint).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("WandShared")
local Cfg = require(Shared.MoveConfig)

local MoveAPI = {}
local Combat, FXBus, MovementService
local rng = Random.new()
local SOCKET_LIMITS = { Neck = 35, ["Right Shoulder"] = 85, ["Left Shoulder"] = 85, ["Right Hip"] = 60, ["Left Hip"] = 60 }
local LIMBS = { "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }

local function partsOf(hum: Humanoid): (Model?, BasePart?, BasePart?)
	local ch = hum.Parent
	if not ch or not ch:IsA("Model") then return nil, nil, nil end
	-- R6 "Torso", R15 "UpperTorso"
	return ch, ch:FindFirstChild("HumanoidRootPart") :: BasePart?, (ch:FindFirstChild("Torso") or ch:FindFirstChild("UpperTorso")) :: BasePart?
end

local function interrupt(hum: Humanoid)
	local pl = Players:GetPlayerFromCharacter(hum.Parent)
	if pl and MovementService and MovementService.Interrupt then MovementService.Interrupt(pl) end
end

-- ── ragdoll joints (server: replicates to every client) ────────────────────
-- the joint that ties the root part to the body stays rigid (otherwise the root drifts away)
local ROOT_JOINTS = { RootJoint = true, Root = true }

-- works for R6 (Motor6D), classic R15 (Motor6D) and physics rigs (AnimationConstraint + BallSocket)
local function buildRagdoll(ch: Model, hum: Humanoid, torso: BasePart)
	hum.RequiresNeck = false -- disabling the Neck joint must not kill the humanoid
	local r6 = ch:FindFirstChild("Torso") ~= nil
	for _, m in ch:GetDescendants() do
		if m:IsA("AnimationConstraint") and m.Enabled and not ROOT_JOINTS[m.Name] then
			-- physics rig: the body is already held by BallSocketConstraints -> just stop animating it
			m.Enabled = false
			m:SetAttribute("RagOff", true)
		elseif m:IsA("Motor6D") and m.Enabled and not ROOT_JOINTS[m.Name] and m.Part0 and m.Part1 then
			local limit = SOCKET_LIMITS[m.Name] or 60
			local a0 = Instance.new("Attachment")
			a0.Name = "RagA0"
			a0.CFrame = m.C0
			a0.Parent = m.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagA1"
			a1.CFrame = m.C1
			a1.Parent = m.Part1
			local bs = Instance.new("BallSocketConstraint")
			bs.Name = "RagSocket"
			bs.Attachment0, bs.Attachment1 = a0, a1
			bs.LimitsEnabled = true
			bs.UpperAngle = limit
			bs.TwistLimitsEnabled = true
			bs.TwistLowerAngle, bs.TwistUpperAngle = -40, 40
			bs.Parent = torso
			m.Enabled = false
			m:SetAttribute("RagOff", true)
		end
	end
	-- R6 limbs don't collide on a Humanoid: invisible colliders so the body really hits the ground
	for _, n in (if r6 then LIMBS else {}) do
		local limb = ch:FindFirstChild(n)
		if limb and limb:IsA("BasePart") then
			local c = Instance.new("Part")
			c.Name = "RagCollider"
			c.Size = limb.Size * Vector3.new(0.75, 0.8, 0.75)
			c.Transparency = 1
			c.Massless = true
			c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = true, false, false, false
			c.CFrame = limb.CFrame
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = c, limb
			w.Parent = c
			c.Parent = limb
		end
	end
	-- limbs are now separate assemblies: give their physics to the owning player (else the server
	-- simulates them, they stay on the ground and hold the body down)
	local pl = Players:GetPlayerFromCharacter(ch)
	for _, d in ch:GetDescendants() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function() d:SetNetworkOwner(pl) end) -- pl == nil -> server (dummies)
		end
	end
	hum:SetAttribute("Ragdoll", true)
end

local function removeRagdoll(ch: Model, hum: Humanoid, torso: BasePart?)
	for _, d in ch:GetDescendants() do
		if d.Name == "RagSocket" or d.Name == "RagA0" or d.Name == "RagA1" or d.Name == "RagCollider" then d:Destroy() end
	end
	for _, m in ch:GetDescendants() do
		if (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) and m:GetAttribute("RagOff") then
			m.Enabled = true
			m:SetAttribute("RagOff", nil)
		end
	end
	hum.RequiresNeck = true
	hum:SetAttribute("Ragdoll", nil)
end

local tokens: { [Humanoid]: number } = {}
local launchedAt: { [Humanoid]: number } = {}

local function getUp(hum: Humanoid)
	local ch, root, torso = partsOf(hum)
	tokens[hum] = nil
	launchedAt[hum] = nil
	if not ch or not hum.Parent then return end
	removeRagdoll(ch, hum, torso)
	if hum.Health > 0 then
		local player = Players:GetPlayerFromCharacter(ch)
		if player then
			FXBus.Push({ k = "GetUp", u = player.UserId, p = if root then root.Position else nil })
		else
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

-- the owning client saw its own landing (no network lag) and asks to get up after GetUpDelay
function MoveAPI.RequestGetUp(player: Player)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum or hum:GetAttribute("Ragdoll") ~= true or not tokens[hum] then return end
	if os.clock() - (launchedAt[hum] or 0) < 0.35 + Cfg.GetUpDelay then return end -- can't skip the flight
	getUp(hum)
end

-- ── PROPULSION CÉLESTE ─────────────────────────────────────────────────────
function MoveAPI.Celestial(hum: Humanoid, velocity: Vector3)
	local ch, root, torso = partsOf(hum)
	if not ch or not root or not torso or hum.Health <= 0 then return end
	if velocity.Magnitude > 160 then velocity = velocity.Unit * 160 end
	interrupt(hum)
	if hum:GetAttribute("Ragdoll") ~= true then buildRagdoll(ch, hum, torso) end
	tokens[hum] = (tokens[hum] or 0) + 1
	launchedAt[hum] = os.clock()
	local token = tokens[hum]
	local spin = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.4, 0.4), rng:NextNumber(-1, 1)) * 6
	local player = Players:GetPlayerFromCharacter(ch)
	FXBus.Push({ k = "Launch", p = root.Position, s = math.floor(velocity.Magnitude) })
	if player then
		FXBus.Push({ k = "Celestial", u = player.UserId, v = velocity, w = spin, p = root.Position })
	else
		hum:ChangeState(Enum.HumanoidStateType.Physics)
		for _, part in ch:GetDescendants() do
			if part:IsA("BasePart") and not part.Anchored then part.AssemblyLinearVelocity = velocity end
		end
		root.AssemblyAngularVelocity = spin
	end
	-- server decides when to get up: GetUpDelay s after touching the ground (or the safety timeout)
	task.spawn(function()
		local ray = RaycastParams.new()
		ray.FilterType = Enum.RaycastFilterType.Exclude
		ray.FilterDescendantsInstances = { ch }
		local t0 = os.clock()
		local landedAt: number? = nil
		local wasLanded = false
		task.wait(0.25) -- leave the ground first
		while tokens[hum] == token do
			if not hum.Parent or hum.Health <= 0 or not torso.Parent then break end
			local now = os.clock()
			-- the GetUpDelay count starts at the FIRST impact; small bounces / rolls don't reset it,
			-- only a real second flight (torso > 6 studs above the ground) does
			local hit = workspace:Raycast(torso.Position, Vector3.new(0, -3.2, 0), ray)
			if hit then
				if not landedAt then
					landedAt = now
					if not wasLanded then
						FXBus.Push({ k = "Land", p = hit.Position, s = math.floor(velocity.Magnitude) })
						wasLanded = true
					end
				end
			elseif landedAt and not workspace:Raycast(torso.Position, Vector3.new(0, -6, 0), ray) then
				landedAt = nil -- launched again (high in the air): wait for the next impact
			end
			-- players: their client asks to get up exactly GetUpDelay after its own landing; this is the
			-- fallback (server sees positions late) -> a bit more margin
			local delay = if player then Cfg.GetUpDelay + 0.6 else Cfg.GetUpDelay
			if (landedAt and now - landedAt >= delay) or now - t0 >= Cfg.RagdollMaxTime then break end
			RunService.Heartbeat:Wait()
		end
		if tokens[hum] ~= token then return end -- a newer launch took over (or the client already got up)
		getUp(hum)
	end)
end

-- RECUL AU SOL : horizontal skid that decelerates linearly to 0 over SkidTime (client-driven for players)
function MoveAPI.Propel(hum: Humanoid, velocity: Vector3)
	local ch, root = partsOf(hum)
	if not ch or not root or hum.Health <= 0 or hum:GetAttribute("Ragdoll") then return end
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude < 1 then return end
	if flat.Magnitude > Cfg.SkidMax then flat = flat.Unit * Cfg.SkidMax end
	interrupt(hum)
	local dir = flat.Unit
	hum:SetAttribute("SkidDir", dir)
	hum:SetAttribute("Skid", os.clock()) -- poses / footsteps read it (value changes = new skid)
	local token = (hum:GetAttribute("SkidToken") or 0) + 1
	hum:SetAttribute("SkidToken", token)
	FXBus.Push({ k = "Skid", p = root.Position, d = dir, s = math.floor(flat.Magnitude), u = (function()
		local pl = Players:GetPlayerFromCharacter(ch)
		return pl and pl.UserId
	end)() })
	local player = Players:GetPlayerFromCharacter(ch)
	if not player then
		task.spawn(function()
			local t0 = os.clock()
			while root.Parent and os.clock() - t0 < Cfg.SkidTime do
				local k = 1 - (os.clock() - t0) / Cfg.SkidTime
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(flat.X * k, v.Y, flat.Z * k)
				RunService.Heartbeat:Wait()
			end
		end)
	end
	task.delay(Cfg.SkidTime, function()
		if hum.Parent and hum:GetAttribute("SkidToken") == token then
			hum:SetAttribute("Skid", nil)
		end
	end)
end

-- KICKBACK & propelling attacks: one entry point, the power picks (and scales) the propulsion
--   power < CelestialSpeed : ground recoil, speed = power        (e.g. 20 -> ~6 studs, 60 -> ~18 studs)
--   power >= CelestialSpeed: propulsion céleste, flies higher and further with power
function MoveAPI.Kick(hum: Humanoid, dir: Vector3, power: number)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	if power < Cfg.CelestialSpeed then
		MoveAPI.Propel(hum, flat * power)
	else
		local k = math.clamp((power - Cfg.CelestialSpeed) / 80, 0, 1) -- 0 at the threshold, 1 at +80
		local up = 70 + 60 * k -- ~12 to ~43 studs high
		local out = power * (0.38 + 0.12 * k) -- distance grows with power but stays readable
		MoveAPI.Celestial(hum, flat * out + Vector3.new(0, up, 0))
	end
end

-- free spot for a character standing at `pos` (root height): searches upwards, never inside a wall
local function freeSpot(pos: Vector3, ignore: { Instance }): Vector3?
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	for up = 0, 6, 1 do
		local p = pos + Vector3.new(0, up, 0)
		local hits = workspace:GetPartBoundsInBox(CFrame.new(p), Vector3.new(1.8, 4.6, 1.2), params)
		local blocked = false
		for _, h in hits do
			if h.CanCollide and not h:IsA("Terrain") then blocked = true break end
		end
		-- parts only: also check the TERRAIN voxels (hills, cliffs) around the body
		if not blocked then
			local lo = p - Vector3.new(1, 2.5, 1)
			local hi = p + Vector3.new(1, 2.5, 1)
			local region = Region3.new(lo, hi):ExpandToGrid(4)
			local ok, mats, occ = pcall(function() return workspace.Terrain:ReadVoxels(region, 4) end)
			if ok then
				local size = mats.Size
				for x = 1, size.X do
					for y = 1, size.Y do
						for z = 1, size.Z do
							local m = mats[x][y][z]
							if m ~= Enum.Material.Air and m ~= Enum.Material.Water and occ[x][y][z] > 0.35 then
								blocked = true
							end
						end
					end
				end
			end
		end
		if not blocked then return p end
	end
	return nil
end

function MoveAPI.Teleport(hum: Humanoid, pos: Vector3): boolean
	local ch, root = partsOf(hum)
	if not ch or not root or hum.Health <= 0 then return false end
	local spot = freeSpot(pos, { ch })
	if not spot then return false end
	interrupt(hum)
	local _, yaw = root.CFrame:ToOrientation()
	ch:PivotTo(CFrame.new(spot) * CFrame.Angles(0, yaw, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

function MoveAPI.Swap(a: Humanoid, b: Humanoid): boolean
	local ca, ra = partsOf(a)
	local cb, rb = partsOf(b)
	if not ca or not cb or not ra or not rb or a.Health <= 0 or b.Health <= 0 then return false end
	interrupt(a)
	interrupt(b)
	local fa, fb = ra.CFrame, rb.CFrame
	ca:PivotTo(fb)
	cb:PivotTo(fa)
	ra.AssemblyLinearVelocity, rb.AssemblyLinearVelocity = Vector3.zero, Vector3.zero
	return true
end

function MoveAPI.Init(combat, fxbus, movementService)
	Combat, FXBus, MovementService = combat, fxbus, movementService
	MovementService.GetUpHook = MoveAPI.RequestGetUp
	-- Studio test hook: ServerStorage.MoveTest:Invoke(op, ...) (op = Kick / Propel / Celestial / Teleport / Swap)
	if RunService:IsStudio() then
		local bf = game:GetService("ServerStorage"):FindFirstChild("MoveTest") or Instance.new("BindableFunction")
		bf.Name = "MoveTest"
		bf.OnInvoke = function(op: string, ...)
			return (MoveAPI :: any)[op](...)
		end
		bf.Parent = game:GetService("ServerStorage")
		-- STUDIO TESTER (StarterPlayerScripts.MoveAPITester): keys 1-5 call the API on the tester himself
		local rem = Shared.Remotes:FindFirstChild("MoveAPITest") or Instance.new("RemoteEvent")
		rem.Name = "MoveAPITest"
		rem.Parent = Shared.Remotes
		rem.OnServerEvent:Connect(function(player: Player, op: any, aim: any, aim2: any)
			local ch = player.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hum or not root or typeof(aim) ~= "Vector3" then return end
			local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
			local fwd = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
			local msg = ""
			-- recoil goes AWAY from the aimed point (as if the aimed point hit you)
			if op == "Kick" then
				local power = tonumber(aim2) or 40
				MoveAPI.Kick(hum, -fwd, power)
				msg = string.format("Kick puissance %d -> %s", power, if power < Cfg.CelestialSpeed then "recul au sol" else "propulsion céleste")
			elseif op == "Teleport" then
				local ok = MoveAPI.Teleport(hum, aim + Vector3.new(0, 3, 0))
				msg = if ok then "Téléportation : OK" else "Téléportation REFUSÉE (point bloqué)"
			elseif op == "Swap" then
				local best, bestD = nil, 40
				for _, h in workspace:GetDescendants() do
					if h:IsA("Humanoid") and h ~= hum and h.Health > 0 then
						local r = h.Parent and h.Parent:FindFirstChild("HumanoidRootPart")
						if r and (r.Position - aim).Magnitude < bestD then best, bestD = h, (r.Position - aim).Magnitude end
					end
				end
				if best then
					local ok = MoveAPI.Swap(hum, best)
					msg = if ok then "Échange avec " .. best.Parent.Name else "Échange impossible"
				else
					msg = "Échange : vise un mannequin ou un joueur (40 studs max autour du point visé)"
				end
			end
			rem:FireClient(player, msg)
		end)
	end
end

return MoveAPI

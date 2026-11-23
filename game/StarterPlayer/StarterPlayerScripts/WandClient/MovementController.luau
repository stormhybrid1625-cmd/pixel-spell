-- MovementController — base movement on the client: course (Shift) and dash (Q).
-- Physics are applied locally (the client owns its character); the server (MovementService) validates
-- cooldowns / locks and replicates the state: Humanoid attrs MoveState / MoveDir / MoveMult.
-- Also drives the PROCEDURAL movement poses of every nearby R6 character (Motor6D.Transform, after
-- the Animator) — lean when sprinting, swept body on dash. Tuning: WandShared.MoveConfig.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("WandShared")
local Cfg = require(Shared:WaitForChild("MoveConfig"))
local Remote = Shared:WaitForChild("Remotes"):WaitForChild("Move")

local MovementController = {}
local player = Players.LocalPlayer

-- ══ 1. LOCAL INPUT + PHYSICS ══════════════════════════════════════════
local shiftHeld, sentSprint, suppressed = false, false, false
local dashReady = 0
local drive: LinearVelocity? = nil
local driveToken = 0

local function charParts(): (Humanoid?, BasePart?)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then return nil, nil end
	return hum, root :: BasePart
end

local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.05 then f.Unit else nil
end

local function wishDir(hum: Humanoid, root: BasePart): Vector3
	return flat(hum.MoveDirection) or flat(workspace.CurrentCamera.CFrame.LookVector) or flat(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
end

local function stopDrive()
	driveToken += 1
	if drive then drive:Destroy() drive = nil end
end

-- constant horizontal velocity for `time` s (vertical left free: gravity / jumps still work)
local function startDrive(root: BasePart, velocity: Vector3, time: number)
	stopDrive()
	local att = root:FindFirstChild("RootAttachment") :: Attachment?
	if not att then return end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "MoveDrive"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(4e4, 0, 4e4)
	lv.VectorVelocity = velocity
	lv.Parent = root
	drive = lv
	driveToken += 1
	local token = driveToken
	task.delay(time, function()
		if token == driveToken then stopDrive() end
	end)
end

local function canAct(hum: Humanoid): boolean
	return hum.WalkSpeed > 0.5 and hum:GetAttribute("Incanting") ~= true and hum:GetAttribute("Ragdoll") ~= true
end

-- ══ SCREEN FX (our own character only) ══════════════════════════════
local Lighting = game:GetService("Lighting")
local CameraFX = require(script.Parent:WaitForChild("CameraFX"))
local blur: BlurEffect? = nil
local blurToken = 0
-- blur that eases to `size` over `t` s (never a flash: soft, short)
local function blurTo(size: number, t: number)
	if not blur or not blur.Parent then
		blur = Instance.new("BlurEffect")
		blur.Name = "MoveBlur"
		blur.Size = 0
		blur.Parent = Lighting
	end
	blurToken += 1
	local token, from, t0 = blurToken, blur.Size, os.clock()
	task.spawn(function()
		while token == blurToken and blur do
			local k = math.clamp((os.clock() - t0) / math.max(t, 0.01), 0, 1)
			blur.Size = from + (size - from) * k
			if k >= 1 then break end
			RunService.RenderStepped:Wait()
		end
	end)
end
local fovToken = 0
local function fovKick(add: number, rise: number, fall: number)
	local cam = workspace.CurrentCamera
	if not cam then return end
	fovToken += 1
	local token = fovToken
	local base = cam:GetAttribute("BaseFOV") or cam.FieldOfView
	cam:SetAttribute("BaseFOV", base)
	task.spawn(function()
		local t = 0
		while token == fovToken and t < rise + fall do
			t += RunService.RenderStepped:Wait()
			local k = if t < rise then t / rise else 1 - (t - rise) / fall
			cam.FieldOfView = base + add * math.clamp(k, 0, 1)
		end
		if token == fovToken then cam.FieldOfView = base cam:SetAttribute("BaseFOV", nil) end
	end)
end
-- DASH speed lines: thin pale streaks rushing from the screen edges towards the centre (pixel style)
local linesGui: ScreenGui? = nil
local function speedLines(duration: number)
	if not linesGui or not linesGui.Parent then
		linesGui = Instance.new("ScreenGui")
		linesGui.Name = "DashLines"
		linesGui.IgnoreGuiInset = true
		linesGui.ResetOnSpawn = false
		linesGui.DisplayOrder = 2
		linesGui.Parent = player:WaitForChild("PlayerGui")
	end
	local gui = linesGui :: ScreenGui
	local rng = Random.new()
	for i = 1, 26 do
		local ang = rng:NextNumber(0, math.pi * 2)
		local dirx, diry = math.cos(ang), math.sin(ang)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromHex("e8f0ff")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(rng:NextInteger(60, 160), 2)
		f.Rotation = math.deg(ang)
		f.BackgroundTransparency = 1
		f.Parent = gui
		local r0, r1 = rng:NextNumber(0.62, 0.75), rng:NextNumber(0.42, 0.55)
		local delay = rng:NextNumber(0, duration * 0.4)
		local life = rng:NextNumber(0.14, 0.22)
		task.delay(delay, function()
			local t = 0
			while t < life do
				t += RunService.RenderStepped:Wait()
				local k = t / life
				local r = r0 + (r1 - r0) * k
				f.Position = UDim2.fromScale(0.5 + dirx * r * 0.62, 0.5 + diry * r)
				f.BackgroundTransparency = 0.45 + 0.55 * math.abs(k * 2 - 1) -- fades in then out
			end
			f:Destroy()
		end)
	end
end

-- ══ MoveAPI messages for OUR character (server builds the ragdoll joints, we own the physics) ══
-- ══ FLIGHT: wind on every ragdolled body (heard by everyone) + speed FOV for our own flight ══
local WIND_ENABLED = false
local WIND_ID = "rbxassetid://9125742262" -- PSE Plasma Trails Constant Airy Whooshing Windy (33 s, continu)
local winds: { [Model]: Sound } = {}
local flightFov = { Active = false, Base = 70, Cur = 0, Punch = 0 }
local function stepFlight(dt: number)
	-- wind follows every ragdolled character nearby; louder / higher with speed
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local torso = ch and (ch:FindFirstChild("Torso") or ch:FindFirstChild("UpperTorso")) :: BasePart?
		-- (user 2026-11-22) plus de son de VENT pendant la propulsion céleste : seul l'impact au sol reste
		local on = WIND_ENABLED and hum ~= nil and torso ~= nil and hum:GetAttribute("Ragdoll") == true
		local w = ch and winds[ch]
		if on and torso then
			if not w then
				w = Instance.new("Sound")
				w.Name = "FlightWind"
				w.SoundId = WIND_ID
				w.Looped = true
				w.Volume = 0
				w.RollOffMinDistance = 12
				w.RollOffMaxDistance = 140
				w.TimePosition = math.random() * 20
				local grp = game:GetService("SoundService"):FindFirstChild("WandSFX")
				if grp then w.SoundGroup = grp :: SoundGroup end
				w.Parent = torso
				w:Play()
				winds[ch :: Model] = w
			end
			local sp = torso.AssemblyLinearVelocity.Magnitude
			local target = math.clamp(0.35 + sp / 60, 0.35, 1.6)
			w.Volume += (target - w.Volume) * math.min(1, dt * 8)
			w.PlaybackSpeed = math.clamp(0.85 + sp / 220, 0.85, 1.4)
		elseif w then
			w.Volume -= dt * 4 -- fades out after landing
			if w.Volume <= 0.02 then
				w:Destroy()
				winds[ch :: Model] = nil
			end
		end
	end
	for ch, w in winds do
		if not ch.Parent or not w.Parent then
			if w.Parent then w:Destroy() end
			winds[ch] = nil
		end
	end
	-- our own flight: FOV widens with speed, squeezes on impact (Punch) then settles back
	local cam = workspace.CurrentCamera
	if cam and (flightFov.Active or math.abs(flightFov.Cur) > 0.05 or math.abs(flightFov.Punch) > 0.05) then
		local _, root = charParts()
		local sp = if root and flightFov.Active then root.AssemblyLinearVelocity.Magnitude else 0
		local want = if flightFov.Active then math.min(sp * 0.16, 24) else 0
		flightFov.Cur += (want - flightFov.Cur) * math.min(1, dt * 5)
		flightFov.Punch += (0 - flightFov.Punch) * math.min(1, dt * 6)
		cam.FieldOfView = flightFov.Base + flightFov.Cur + flightFov.Punch
		if not flightFov.Active and math.abs(flightFov.Cur) <= 0.05 and math.abs(flightFov.Punch) <= 0.05 then
			cam.FieldOfView = flightFov.Base
		end
	end
end

local function onMoveMsg(msg: { [string]: any })
	if msg.u ~= player.UserId then return end
	local hum, root = charParts()
	if not hum or not root then return end
	if msg.k == "Skid" and typeof(msg.d) == "Vector3" then
		-- RECUL AU SOL: pushed back, stays on the ground, skids to a stop (linear deceleration)
		local speed = math.clamp(tonumber(msg.s) or 30, 1, Cfg.SkidMax)
		local dir = Vector3.new(msg.d.X, 0, msg.d.Z).Unit
		stopDrive()
		local att = root:FindFirstChild("RootAttachment") :: Attachment?
		if not att then return end
		local lv = Instance.new("LinearVelocity")
		lv.Name = "MoveDrive"
		lv.Attachment0 = att
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		lv.MaxAxesForce = Vector3.new(5e4, 0, 5e4)
		lv.VectorVelocity = dir * speed
		lv.Parent = root
		drive = lv
		driveToken += 1
		local token = driveToken
		CameraFX.Shake(math.clamp(speed / 140, 0.12, 0.45))
		task.spawn(function()
			local t0 = os.clock()
			while token == driveToken and lv.Parent do
				local k = (os.clock() - t0) / Cfg.SkidTime
				if k >= 1 then break end
				lv.VectorVelocity = dir * speed * (1 - k)
				RunService.Heartbeat:Wait()
			end
			if token == driveToken then stopDrive() end
		end)
		return
	end
	if msg.k == "Celestial" and typeof(msg.v) == "Vector3" then
		stopDrive()
		-- screen: FOV follows the flight speed (stepFlight) + soft blur for the whole flight
		local cam = workspace.CurrentCamera
		if cam and not flightFov.Active and math.abs(flightFov.Cur) < 0.05 then flightFov.Base = cam.FieldOfView end
		flightFov.Active = true
		blurTo(5, 0.25)
		hum:ChangeState(Enum.HumanoidStateType.Physics) -- limp body until the server says get up
		-- every body part gets the launch velocity (ragdolled limbs are separate assemblies: launching only
		-- the root, they'd stay behind and brake the body)
		for _, part in (player.Character :: Model):GetDescendants() do
			if part:IsA("BasePart") and not part.Anchored then part.AssemblyLinearVelocity = msg.v end
		end
		if typeof(msg.w) == "Vector3" then root.AssemblyAngularVelocity = msg.w end
		-- our own landing detection (no network lag): ask to get up GetUpDelay after the first impact
		local ch = player.Character :: Model
		local torso = ch:FindFirstChild("Torso") :: BasePart?
		if torso then
			local token = (hum:GetAttribute("CelestialToken") or 0) + 1
			hum:SetAttribute("CelestialToken", token)
			task.spawn(function()
				local ray = RaycastParams.new()
				ray.FilterType = Enum.RaycastFilterType.Exclude
				ray.FilterDescendantsInstances = { ch }
				task.wait(0.25)
				local landedAt: number? = nil
				local t0 = os.clock()
				while hum.Parent and hum.Health > 0 and hum:GetAttribute("CelestialToken") == token and os.clock() - t0 < Cfg.RagdollMaxTime do
					local now = os.clock()
					if workspace:Raycast(torso.Position, Vector3.new(0, -3.2, 0), ray) then
						if not landedAt then
							-- impact: FOV squeezed hard + short blur pulse that settles (shake = Land FX)
							flightFov.Active = false
							flightFov.Punch = -9
							blurTo(9, 0.05)
							task.delay(0.08, function() blurTo(2, 0.4) end)
						end
						landedAt = landedAt or now
					elseif landedAt and not workspace:Raycast(torso.Position, Vector3.new(0, -6, 0), ray) then
						landedAt = nil
					end
					if landedAt and now - landedAt >= Cfg.GetUpDelay then
						Remote:FireServer("GetUp")
						return
					end
					RunService.Heartbeat:Wait()
				end
			end)
		end
	elseif msg.k == "GetUp" then
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		flightFov.Active = false
		blurTo(0, 0.35)
	end
end

local function tryDash()
	local hum, root = charParts()
	if not hum or not root or os.clock() < dashReady or not canAct(hum) then return end
	local dir = wishDir(hum, root)
	dashReady = os.clock() + Cfg.DashCooldown
	Remote:FireServer("Dash", dir)
	startDrive(root, dir * (Cfg.DashDistance / Cfg.DashTime), Cfg.DashTime)
	speedLines(Cfg.DashTime)
	CameraFX.Shake(0.1)
end

-- ══ ANIMATIONS de marche / course (personnage local : le serveur les réplique aux autres) ══
local runTrack: AnimationTrack? = nil
local function setupAnims(ch: Model, hum: Humanoid)
	runTrack = nil
	-- la marche par défaut du script Animate est remplacée (Animate se reconfigure quand l'id change)
	local animate = ch:WaitForChild("Animate", 5)
	if animate then
		for _, set in { "walk", "run" } do
			local v = animate:FindFirstChild(set)
			local a = v and v:FindFirstChildOfClass("Animation")
			if a and a.AnimationId ~= Cfg.WalkAnimId then
				-- swap the Animation object: Animate reconfigures on ChildAdded (a bare id change is not always seen)
				local n = a:Clone()
				n.AnimationId = Cfg.WalkAnimId
				a:Destroy()
				n.Parent = v
			end
		end
	end
	local animator = hum:WaitForChild("Animator", 5) :: Animator?
	if not animator then return end
	local anim = Instance.new("Animation")
	anim.AnimationId = Cfg.RunAnimId
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Movement
		track.Looped = true
		runTrack = track
	end
end

local function stepAnims()
	local hum, root = charParts()
	if not hum or not root or hum.Health <= 0 then return end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local dashing = hum:GetAttribute("MoveState") == "Dash"
	local running = hum:GetAttribute("MoveState") == "Sprint" and speed > 4 and hum.FloorMaterial ~= Enum.Material.Air
	if runTrack then
		if running then
			if not runTrack.IsPlaying then runTrack:Play(0.18) end
			runTrack:AdjustSpeed(math.clamp(speed / Cfg.RunAnimRef, 0.5, 1.6))
		elseif runTrack.IsPlaying then
			runTrack:Stop(if dashing then 0.05 else 0.22)
		end
	end
	-- marche : la vitesse de lecture suit la vitesse réelle (Animate ne la règle qu'aux changements d'état) ;
	-- pendant le DASH la marche est éteinte (poids ~0) : seule la pose de dash reste, les jambes ne pédalent pas
	for _, t in hum.Animator:GetPlayingAnimationTracks() do
		if t.Animation and t.Animation.AnimationId == Cfg.WalkAnimId then
			local w = if dashing then 0.001 else 1
			if math.abs(t.WeightTarget - w) > 0.01 then t:AdjustWeight(w, if dashing then 0.05 else 0.15) end
			if dashing then
				-- Animate règle la marche sur la vitesse réelle (~60 studs/s en dash = jambes x4) et Roblox
				-- renormalise les poids : on FIGE la marche, la pose de dash fait le reste
				t:AdjustSpeed(0)
			elseif speed > 0.5 then
				t:AdjustSpeed(math.clamp(speed / Cfg.WalkAnimRef, 0.3, 1.6))
			end
		end
	end
end

local function hookCharacter(ch: Model)
	stopDrive()
	sentSprint, suppressed = false, false
	local hum = ch:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then return end
	task.spawn(setupAnims, ch, hum)
	hum.Died:Connect(function()
		stopDrive()
		-- RAGDOLL : plus aucune animation (marche / course / Animate) sur le corps mort
		local animate = ch:FindFirstChild("Animate")
		if animate and animate:IsA("LocalScript") then
			animate.Disabled = true
		end
		if runTrack then
			runTrack:Stop(0)
			runTrack = nil
		end
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then
			for _, t in animator:GetPlayingAnimationTracks() do
				t:Stop(0)
			end
		end
	end)
	-- the server cleared our sprint (we cast a spell): stay walking until Shift is pressed again
	hum:GetAttributeChangedSignal("MoveState"):Connect(function()
		if hum:GetAttribute("MoveState") == "" and sentSprint and shiftHeld then
			sentSprint, suppressed = false, true
		end
	end)
end

-- ══ 2. PROCEDURAL POSES (all nearby R6 characters) ═══════════════════
-- R6 joint frames: RootJoint / Neck Angles(+a) = lean / nod FORWARD, Angles(0,+r,0) = roll LEFT,
-- translation Z- = lower the body. Shoulders / hips swing about Z: right +Z = forward, left -Z = forward.
local JOINTS = { "RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }
local KEYS = { "Lean", "Roll", "Drop", "Nod", "RArm", "LArm", "RLeg", "LLeg" }
local recs: { [Model]: any } = {}

local function smooth01(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- dashT = seconds since this character's dash started (nil when not dashing)
local function targetsFor(hum: Humanoid, root: BasePart, dashT: number?): { [string]: number }
	local t = { Lean = 0, Roll = 0, Drop = 0, Nod = 0, RArm = 0, LArm = 0, RLeg = 0, LLeg = 0 }
	local state = hum:GetAttribute("MoveState")
	-- (la course a sa vraie animation : plus de pose procédurale pour elle)
	local skidAt = hum:GetAttribute("Skid")
	local skidDir = hum:GetAttribute("SkidDir")
	if type(skidAt) == "number" and typeof(skidDir) == "Vector3" and state ~= "Dash" then
		-- RECUL AU SOL: leans INTO the push (towards where the hit came from), legs braced wide,
		-- arms forward for balance; the pose relaxes as the skid slows down
		local e = 1 - math.clamp((os.clock() - skidAt) / Cfg.SkidTime, 0, 1)
		local k = e ^ 0.6
		local towards = -skidDir -- the push comes from there
		local fwd = towards:Dot(root.CFrame.LookVector)
		local right = towards:Dot(root.CFrame.RightVector)
		t.Lean = 0.38 * fwd * k
		t.Roll = -0.32 * right * k
		t.Drop = 0.35 * k -- knees bent: body lower
		t.Nod = 0.1 * k
		t.RLeg, t.LLeg = 0.45 * k, -0.35 * k -- one leg forward, the other braced behind
		t.RArm, t.LArm = 0.55 * k, 0.4 * k -- arms forward for balance
		return t
	end
	if state == "Dash" then
		-- ANIMATED dash, driven by time (p = 0..1 over the dash): arms throw forward for the push, then
		-- sweep far back and flutter in the wind; one big scissor stride; body leans in then starts to recover
		local tt = dashT or 0
		local p = math.clamp(tt / Cfg.DashTime, 0, 1)
		local push = smooth01(p / 0.6) -- 0 -> 1 over the first 60 % (unhurried sweep)
		local rec = smooth01((p - 0.65) / 0.35) -- recovery over the last 35 %
		local flutter = math.sin(tt * 20) * 0.06 * push * (1 - rec)
		local arms = 0.25 + (-0.85 - 0.25) * push -- +0.25 (slightly forward) -> -0.85 (back, not too far)
		arms += (-0.35 - arms) * rec -- back towards a running carriage at the end
		t.RArm = arms + flutter
		t.LArm = arms - flutter * 1.3 + 0.08 * push -- slightly out of phase: never perfectly symmetric
		local stride = math.sin(math.min(p / 0.9, 1) * math.pi) -- one big step, open then close (slower)
		t.RLeg = -0.2 - 0.6 * stride + 0.3 * rec
		t.LLeg = 0.1 + 0.5 * stride - 0.15 * rec
		local d = hum:GetAttribute("MoveDir")
		if typeof(d) == "Vector3" then
			local fwd = d:Dot(root.CFrame.LookVector)
			local right = d:Dot(root.CFrame.RightVector)
			local lean = (0.25 + 0.4 * push) * (1 - 0.45 * rec) -- leans in, starts to straighten at the end
			t.Lean = lean * fwd
			t.Roll = -0.5 * right * (1 - 0.5 * rec) + math.sin(tt * 12) * 0.03 * push
			t.Nod = -0.3 * fwd * push
		end
	end
	return t
end

local function offsets(c: { [string]: number }): { [string]: CFrame }
	return {
		RootJoint = CFrame.new(0, 0, -c.Drop) * CFrame.Angles(c.Lean, c.Roll, 0),
		Neck = CFrame.Angles(c.Nod, 0, 0),
		["Right Shoulder"] = CFrame.Angles(0, 0, c.RArm),
		["Left Shoulder"] = CFrame.Angles(0, 0, -c.LArm),
		["Right Hip"] = CFrame.Angles(0, 0, c.RLeg),
		["Left Hip"] = CFrame.Angles(0, 0, -c.LLeg),
	}
end

local function recFor(ch: Model): any
	local r = recs[ch]
	if r then return r end
	local torso = ch:FindFirstChild("Torso")
	local root = ch:FindFirstChild("HumanoidRootPart")
	if not torso or not root then return nil end
	local motors = {}
	for _, name in JOINTS do
		local m = (if name == "RootJoint" then root else torso):FindFirstChild(name)
		if m and m:IsA("Motor6D") then motors[name] = m end
	end
	if not motors.RootJoint then return nil end -- not R6
	r = { Motors = motors, Cur = {}, Written = {}, Off = {} }
	for _, k in KEYS do r.Cur[k] = 0 end
	recs[ch] = r
	ch.Destroying:Connect(function() recs[ch] = nil end)
	return r
end

local function stepPoses(dt: number)
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local k = math.min(1, dt * 14)
	local n = 0
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or not root then continue end
		local far = (root.Position - camPos).Magnitude > Cfg.AnimRange or n >= Cfg.AnimMax
		local r = recFor(ch)
		if not r or hum:GetAttribute("Ragdoll") == true then continue end -- ragdoll: physics only
		local dashing = hum:GetAttribute("MoveState") == "Dash"
		local skidding = type(hum:GetAttribute("Skid")) == "number"
		if (dashing or skidding) and not r.DashStart then r.DashStart = os.clock() r.Snap = nil elseif not dashing and not skidding then r.DashStart = nil end
		local tgt = if far or hum.Health <= 0 then nil else targetsFor(hum, root, if r.DashStart then os.clock() - r.DashStart else nil)
		-- the dash pose snaps in (~0.03 s) instead of easing, otherwise the limbs visibly swing through
		local kk = if hum:GetAttribute("MoveState") == "Dash" then math.min(1, dt * 18) else k
		local active = false
		for _, key in KEYS do
			local goal = if tgt then tgt[key] else 0
			r.Cur[key] += (goal - r.Cur[key]) * kk
			if math.abs(r.Cur[key]) > 1e-3 then active = true end
		end
		if not active and not r.Live then continue end
		r.Live = active
		n += 1
		local offs = offsets(r.Cur)
		-- DASH: this script is the ONLY thing animating the body. Whatever the Animator / Animate wrote this
		-- frame (walk tracks, legacy motor angles at x4 speed...) is discarded: neutral base + dash pose.
		local exclusive = tgt ~= nil and (hum:GetAttribute("MoveState") == "Dash" or type(hum:GetAttribute("Skid")) == "number")
		for name, m in r.Motors do
			if not m.Parent then continue end
			local base = m.Transform
			-- if the Animator didn't rewrite this joint since our last frame, strip our previous offset first
			if r.Written[name] and base == r.Written[name] then
				base = base * r.Off[name]:Inverse()
			end
			if exclusive then
				-- fade out a SNAPSHOT of the pose taken when the dash started (the live animation is itself
				-- changing as the run stops -> fading from it jitters) over 0.12 s instead of snapping
				r.Snap = r.Snap or {}
				if not r.Snap[name] then r.Snap[name] = base end
				local a = math.clamp((os.clock() - (r.DashStart or 0)) / 0.12, 0, 1)
				base = if a >= 1 then CFrame.identity else r.Snap[name]:Lerp(CFrame.identity, smooth01(a))
				if m.CurrentAngle ~= 0 or m.DesiredAngle ~= 0 then -- legacy motor swing (Animate R6)
					m.DesiredAngle = 0
					m.CurrentAngle = 0
				end
			end
			local w = base * offs[name]
			m.Transform = w
			r.Written[name], r.Off[name] = w, offs[name]
		end
	end
end

-- ══ 3. INIT ══════════════════════════════════════════════════════════
function MovementController.Init()
	UIS.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Cfg.Keys.Sprint then
			shiftHeld, suppressed = true, false
		elseif input.KeyCode == Cfg.Keys.Dash then
			tryDash()
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.KeyCode == Cfg.Keys.Sprint then shiftHeld = false end
	end)
	RunService.Heartbeat:Connect(function()
		local hum = charParts()
		local want = hum ~= nil and shiftHeld and not suppressed and hum.MoveDirection.Magnitude > 0.1 and hum:GetAttribute("Ragdoll") ~= true
		if want ~= sentSprint then
			sentSprint = want
			Remote:FireServer("Sprint", want)
		end
		local ok, err = pcall(stepAnims)
		if not ok then warn("[Movement] anims :", err) end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(stepFlight, dt)
		if not ok then warn("[Movement] vol :", err) end
	end)
	RunService.Stepped:Connect(function(_, dt)
		local ok, err = pcall(stepPoses, dt)
		if not ok then warn("[Movement] poses :", err) end
	end)
	Shared:WaitForChild("Remotes"):WaitForChild("SpellFX").OnClientEvent:Connect(function(batch)
		if type(batch) ~= "table" then return end
		for _, msg in batch do
			if type(msg) == "table" and (msg.k == "Celestial" or msg.k == "GetUp" or msg.k == "Skid") then
				local ok, err = pcall(onMoveMsg, msg)
				if not ok then warn("[Movement] MoveAPI :", err) end
			end
		end
	end)
	if player.Character then task.spawn(hookCharacter, player.Character) end
	player.CharacterAdded:Connect(hookCharacter)
end

return MovementController

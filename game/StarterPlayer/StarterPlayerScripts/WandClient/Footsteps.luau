-- Footsteps — footstep sounds + running dust for every nearby R6 character.
-- A step is detected from the real foot motion (bottom of each leg relative to the root), with ADAPTIVE
-- thresholds per leg: each leg keeps its foot heights of the last 1.5 s (> one walk cycle) and uses
-- their exact min / max (walk lifts the foot ~0.5 stud, run ~2 studs; adapts within 1.5 s). Hysteresis: the foot must rise above 60 % of its range (armed) before coming back
-- under 25 % (= touches the ground) -> exactly one step per foot plant, no jitter double-steps. Works for any
-- animation and any playback speed, for all players (their animations replicate to us).
-- Running adds kicked-up dust coloured like the ground under the foot. Tuning: WandShared.MoveConfig.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("WandShared")
local Cfg = require(Shared:WaitForChild("MoveConfig"))
local SoundFX = require(script.Parent:WaitForChild("SoundFX"))
local Sparks = require(script.Parent:WaitForChild("Sparks"))

local Footsteps = {}
local rng = Random.new()
local recs: { [Model]: any } = {}
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude
ray.IgnoreWater = true

local GRASS = { [Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true }
-- soft ground -> dirt steps ; everything else -> hard (concrete) steps
local SOFT = { [Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true, [Enum.Material.Ground] = true,
	[Enum.Material.Sand] = true, [Enum.Material.Mud] = true, [Enum.Material.Snow] = true, [Enum.Material.Fabric] = true }
local GREY = Color3.fromHex("6e665d")
local LEAF = { Color3.fromHex("5f8a3a"), Color3.fromHex("4b7030"), Color3.fromHex("7aa24a") }

-- dust colour = the ground's colour, warmed towards earth and clearly DARKER than the ground so it
-- reads against it (light floors -> mid-grey-brown dust, dark floors -> slightly lighter); never glows
local EARTH = Color3.fromHex("7a6a58")
local function dustColors(c: Color3): { Color3 }
	local base = c:Lerp(EARTH, 0.5)
	local h, s, v = base:ToHSV()
	local tv = if v > 0.45 then v * 0.62 else math.min(v * 1.35, 0.5)
	return {
		Color3.fromHSV(h, math.min(s * 1.1, 0.45), math.clamp(tv, 0.2, 0.55)),
		Color3.fromHSV(h, math.min(s * 1.0, 0.4), math.clamp(tv * 0.82, 0.16, 0.48)),
		Color3.fromHSV(h, math.min(s * 1.2, 0.5), math.clamp(tv * 1.15, 0.24, 0.6)),
	}
end

local function runDust(foot: Vector3, vel: Vector3, ground: RaycastResult, speed: number)
	local back = if vel.Magnitude > 0.1 then -Vector3.new(vel.X, 0, vel.Z).Unit else Vector3.zero
	local cols = dustColors(ground.Instance.Color)
	local k = math.clamp(speed / 24, 0.6, 1.3)
	local at = ground.Position + Vector3.new(0, 0.15, 0)
	-- bouffée basse qui traîne derrière le pied
	local side = Vector3.new(-back.Z, 0, back.X)
	for _ = 1, 6 do
		Sparks.Emit(at + back * rng:NextNumber(0, 0.6) + side * rng:NextNumber(-0.5, 0.5),
			back * rng:NextNumber(1.8, 4) * k + side * rng:NextNumber(-1.4, 1.4) + Vector3.new(0, rng:NextNumber(0.9, 2), 0),
			{ Puff = true, Colors = cols, Gravity = -0.03, Drag = 3, Life = NumberRange.new(0.5, 0.85),
				Size = rng:NextNumber(0.5, 0.72) * k, Grow = 2.5, Fade0 = 0.46 })
	end
	-- grains projetés vers l'arrière et vers le haut, qui retombent
	for _ = 1, 6 do
		Sparks.Emit(at, back * rng:NextNumber(3, 7) * k + Vector3.new(0, rng:NextNumber(2.5, 5), 0) + rng:NextUnitVector() * 1.2,
			{ Colors = cols, Gravity = 1, Drag = 1.2, Life = NumberRange.new(0.25, 0.45), Size = 0.08, Matte = true })
	end
	if GRASS[ground.Material] then -- brins d'herbe arrachés
		for _ = 1, 3 do
			Sparks.Emit(at, back * rng:NextNumber(2, 5) + Vector3.new(0, rng:NextNumber(2, 4), 0) + rng:NextUnitVector(),
				{ Colors = LEAF, Gravity = 0.7, Drag = 2, Life = NumberRange.new(0.3, 0.55), Size = 0.09, Matte = true })
		end
	end
end

local function recFor(ch: Model): any
	local r = recs[ch]
	if r then return r end
	local root = ch:FindFirstChild("HumanoidRootPart")
	local rl, ll = ch:FindFirstChild("Right Leg"), ch:FindFirstChild("Left Leg")
	if not root or not rl or not ll then return nil end
	-- the default Roblox footstep LOOP ("Running", plastic steps at its own tempo) would play on top of
	-- ours, out of sync with our animations -> muted for every character (we handle steps ourselves)
	local function mute(s: Instance)
		if s:IsA("Sound") and s.Name == "Running" then s.Volume = 0 end
	end
	for _, s in root:GetChildren() do mute(s) end
	root.ChildAdded:Connect(mute)
	r = { Root = root, Legs = { { Part = rl, Buf = {}, I = 0, Acc = 0, Armed = false, Last = 0 }, { Part = ll, Buf = {}, I = 0, Acc = 0, Armed = false, Last = 0 } } }
	recs[ch] = r
	ch.Destroying:Connect(function() recs[ch] = nil end)
	return r
end

-- plays one footstep (sound + run dust) for character `ch` at its foot `legPart`
local function footstep(ch: Model, hum: Humanoid, legPart: BasePart, vel: Vector3, speed: number, running: boolean)
	local foot = legPart.CFrame:PointToWorldSpace(Vector3.new(0, -1, 0))
	ray.FilterDescendantsInstances = { ch }
	local ground = workspace:Raycast(foot + Vector3.new(0, 1, 0), Vector3.new(0, -2.5, 0), ray)
	local at = if ground then ground.Position else foot
	local soft = ground ~= nil and SOFT[ground.Material] == true
	SoundFX.Play(if soft then (if running then "Step.RunSoft" else "Step.WalkSoft") else (if running then "Step.Run" else "Step.Walk"), at)
	if ground and GRASS[ground.Material] then SoundFX.Play("Step.Grass", at) end
	if running and ground then runDust(foot, vel, ground, speed) end
end

-- known walk / run animation playing on this character -> its phase (0..1) and step markers
local function knownPhase(hum: Humanoid): (number?, { number }?, boolean, AnimationTrack?)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return nil, nil, false, nil end
	local walk, run
	for _, t in animator:GetPlayingAnimationTracks() do
		local id = t.Animation and t.Animation.AnimationId
		if id == Cfg.RunAnimId and t.WeightCurrent > 0.5 then run = t
		elseif id == Cfg.WalkAnimId then walk = t end
	end
	local t = run or walk
	if not t or t.Length <= 0 then return nil, nil, false, nil end
	return (t.TimePosition / t.Length) % 1, if run then Cfg.RunSteps else Cfg.WalkSteps, run ~= nil, t
end

local function step(dt: number)
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local now = os.clock()
	local n = 0
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or hum.RigType ~= Enum.HumanoidRigType.R6 then continue end
		local r = recFor(ch)
		if not r or (r.Root.Position - camPos).Magnitude > Cfg.StepRange then continue end
		n += 1
		if n > Cfg.AnimMax then break end
		local vel = r.Root.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local grounded = hum.FloorMaterial ~= Enum.Material.Air
		local state = hum:GetAttribute("MoveState")
		if type(hum:GetAttribute("Skid")) == "number" or hum:GetAttribute("Ragdoll") == true then continue end
		-- 1) known animation: step exactly when its phase crosses a foot-contact marker (regular rhythm)
		local phase, marks, isRun, track = knownPhase(hum)
		if phase and marks then
			local prev = if r.Track == track then r.Phase else nil
			r.Track, r.Phase = track, phase
			if prev and grounded and speed > 2 and state ~= "Dash" then
				for i, m in marks do
					-- crossed m between prev and phase (handles the wrap 0.98 -> 0.02)
					local crossed = if prev <= phase then (prev < m and m <= phase) else (prev < m or m <= phase)
					if crossed then
						footstep(ch, hum, r.Legs[if i == 1 then (if isRun then 1 else 2) else (if isRun then 2 else 1)].Part, vel, speed, isRun and speed > 16)
					end
				end
			end
			continue
		end
		r.Track = nil
		-- 2) unknown animation: fall back on the foot-height detector
		for _, leg in r.Legs do
			local foot = leg.Part.CFrame:PointToWorldSpace(Vector3.new(0, -1, 0))
			local h = r.Root.CFrame:PointToObjectSpace(foot).Y -- ~-3 when the foot is on the ground
			-- adaptive range: extremes follow the foot instantly, then slowly relax towards it
			-- sliding window: one sample every 1/30 s, 45 samples = 1.5 s
			leg.Acc += dt
			if leg.Acc >= 1 / 30 then
				leg.Acc = 0
				leg.I = leg.I % 45 + 1
				leg.Buf[leg.I] = h
			end
			local lo, hi = h, h
			for _, v in leg.Buf do
				if v < lo then lo = v end
				if v > hi then hi = v end
			end
			leg.Lo, leg.Hi = lo, hi
			local range = hi - lo
			if range > 0.15 and h > leg.Lo + range * 0.6 then leg.Armed = true end
			if leg.Armed and range > 0.15 and h < leg.Lo + range * 0.25 then
				leg.Armed = false
			if grounded and speed > 2 and state ~= "Dash" and now - leg.Last > 0.12 then
				leg.Last = now
				footstep(ch, hum, leg.Part, vel, speed, state == "Sprint" and speed > 16)
			end
			end
		end
	end
end

function Footsteps.Init()
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then warn("[Footsteps]", err) end
	end)
end

return Footsteps

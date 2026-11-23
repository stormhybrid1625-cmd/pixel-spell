--!strict
-- MagicCircle — client-side pixel magic circles (Pixel Spell)
-- Textures + sample points are generated offline (scratchpad/circles/gen.js -> CircleData).
-- API:
--   local c = MagicCircle.new({ Element = "Fire", Anchor = rootPart | CFrame = cf, Size = 9, Kind = "Superieur" })
--   c:SetProgress(p)   -- 0..1, drives convergence + layer reveal (stages: core 0-.3, star .3-.65, rune ring .65-1)
--   c:Release()        -- collapse inward then cleanup (spell fires)
--   c:Break()          -- scatter outward then cleanup (interrupted)
--   c:Destroy()        -- instant cleanup
--   MagicCircle.ActiveCount()
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Data = require(script.CircleData)

local MagicCircle = {}
MagicCircle.__index = MagicCircle

local ASSETS = {
	Superieur = { A = "rbxassetid://105061294898171", B = "rbxassetid://83615273010401", C = "rbxassetid://139400212034441" },
	Sigil = {
		Neutral = "rbxassetid://103719598013696", Fire = "rbxassetid://71559551813532", Ice = "rbxassetid://89329696142362",
		Lightning = "rbxassetid://101263785736362", Nature = "rbxassetid://116059596490295", Toxic = "rbxassetid://93075919985112",
		Arcane = "rbxassetid://73408266912604", Chaos = "rbxassetid://118073851253165", Steel = "rbxassetid://132198901850170",
	},
}
MagicCircle.Assets = ASSETS

local CANVAS = 516
local HALF = CANVAS / 2
local SIGIL_FRAC = 41 / 129 -- sigil texture size relative to the circle
local MAX_ACTIVE = 12
local LOD_DIST = 150
-- stage windows per layer (progress 0..1)
local STAGES = { Sig = { 0, 0.3 }, C = { 0, 0.3 }, B = { 0.3, 0.65 }, A = { 0.65, 1 } }
local SPIN = { A = 7, B = -11, C = 0, Sig = 0 } -- deg/s at progress 0 (x up to 3 with progress)

local active: { any } = {}
local folder: Folder? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function hex(h: string): Color3 return Color3.fromHex(h) end
local function smooth(t: number): number t = math.clamp(t, 0, 1) return t * t * (3 - 2 * t) end
local function stageT(p: number, s: { number }): number return math.clamp((p - s[1]) / (s[2] - s[1]), 0, 1) end

local function getFolder(): Folder
	if folder and folder.Parent then return folder end
	local f = workspace:FindFirstChild("ClientMagicCircles") :: Folder?
	if not f then
		local nf = Instance.new("Folder")
		nf.Name = "ClientMagicCircles"
		nf.Parent = workspace
		f = nf
	end
	folder = f
	return f :: Folder
end

local function groundCF(pos: Vector3, ignore: { Instance }): CFrame
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -14, 0), rayParams)
	local y = if hit then hit.Position.Y else pos.Y - 3
	return CFrame.new(pos.X, y + 0.06, pos.Z)
end

local function newLayer(parent: Instance, name: string, image: string, color: Color3, sizeFrac: number, z: number)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(sizeFrac, sizeFrac)
	holder.ZIndex = z
	local img = Instance.new("ImageLabel")
	img.Name = "Img"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = image
	img.ImageColor3 = color
	img.ImageTransparency = 1
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.ZIndex = z
	img.Parent = holder
	holder.Parent = parent
	return holder, img
end

function MagicCircle.ActiveCount(): number return #active end

function MagicCircle.new(opts: { [string]: any })
	-- cap: drop the oldest circle beyond MAX_ACTIVE
	if #active >= MAX_ACTIVE then
		local old = table.remove(active, 1)
		if old then old:Destroy() end
	end
	local self = setmetatable({}, MagicCircle)
	local el = opts.Element or "Neutral"
	if not Data.Palette[el] then el = "Neutral" end
	local pal = Data.Palette[el]
	self.Element = el
	self.Core, self.Mid, self.Edge = hex(pal[1]), hex(pal[2]), hex(pal[3])
	self.Size = opts.Size or 9
	self.Anchor = opts.Anchor
	self.Kind = opts.Kind or "Superieur"
	self.Progress = 0
	self.Done = false
	self.Dead = false
	self.Particles = {}
	self.Spawned = { A = 0, B = 0, C = 0, Sig = 0 }
	self.Angle = { A = math.random() * 360, B = math.random() * 360, C = 0, Sig = 0 }
	self.Ignore = {}
	if self.Anchor and self.Anchor.Parent then table.insert(self.Ignore, self.Anchor.Parent) end
	table.insert(self.Ignore, getFolder())

	local part = Instance.new("Part")
	part.Name = "MagicCircle_" .. el
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(self.Size, 0.05, self.Size)
	part.CFrame = if self.Anchor then groundCF(self.Anchor.Position, self.Ignore) else (opts.CFrame or CFrame.new())
	self.Part = part

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(CANVAS, CANVAS)
	gui.LightInfluence = 0
	gui.Brightness = 1.25
	gui.MaxDistance = 400
	gui.ClipsDescendants = true
	gui.ZOffset = 1
	gui.Parent = part
	self.Gui = gui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	self.Root = root

	local tex = ASSETS[self.Kind] or ASSETS.Superieur
	self.Layers = {}
	self.Layers.A = { newLayer(root, "A", tex.A, self.Mid, 1, 2) }
	self.Layers.B = { newLayer(root, "B", tex.B, self.Mid:Lerp(self.Core, 0.45), 1, 3) }
	self.Layers.C = { newLayer(root, "C", tex.C, self.Mid, 1, 2) }
	self.Layers.Sig = { newLayer(root, "Sig", ASSETS.Sigil[el], self.Core:Lerp(self.Mid, 0.25), SIGIL_FRAC, 4) }

	part.Parent = getFolder()
	table.insert(active, self)
	return self
end

-- one converging pixel; target in layer-normalized coords (-1..1, y down)
function MagicCircle:_spawn(layer: string, pt: { number })
	local holder = self.Layers[layer][1]
	local lv = pt[3]
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	local px = if lv == 1 then 6 else 5
	f.Size = UDim2.fromOffset(px, px)
	f.BackgroundColor3 = if lv == 1 then self.Core elseif lv == 2 then self.Mid else self.Edge:Lerp(self.Mid, 0.5)
	f.ZIndex = 6
	-- start: random point on the disc, biased outward, so pixels "fly in" from everywhere
	local a = math.random() * math.pi * 2
	local r = 0.55 + math.random() * 0.45
	local sx, sy = math.cos(a) * r, math.sin(a) * r
	if layer == "Sig" then sx, sy = sx / SIGIL_FRAC * 0.9, sy / SIGIL_FRAC * 0.9 end
	f.Position = UDim2.fromScale(0.5 + sx / 2, 0.5 + sy / 2)
	f.Parent = holder
	table.insert(self.Particles, {
		F = f, SX = sx, SY = sy, TX = pt[1], TY = pt[2], T = 0,
		Dur = 0.45 + math.random() * 0.35, Swirl = (math.random() - 0.5) * 1.4, Fade = -1,
	})
end

function MagicCircle:SetProgress(p: number)
	if self.Dead then return end
	self.Progress = math.clamp(p, 0, 1)
end

function MagicCircle:_far(): boolean
	local cam = workspace.CurrentCamera
	return cam ~= nil and (cam.CFrame.Position - self.Part.Position).Magnitude > LOD_DIST
end

function MagicCircle:_step(dt: number)
	if self.Dead then return end
	local p = self.Progress
	if self.Anchor then
		if not self.Anchor.Parent then self:Break() return end
		self.Part.CFrame = groundCF(self.Anchor.Position, self.Ignore)
	end
	local far = self:_far()
	-- reveal + spawn per layer
	for name, s in STAGES do
		local t = stageT(p, s)
		local holder, img = self.Layers[name][1], self.Layers[name][2]
		-- texture fades in behind the incoming pixels (slight lag so pixels read first)
		img.ImageTransparency = 1 - smooth((t - 0.15) / 0.85) * (if self.Done then 1 else 0.92)
		local pts = if name == "Sig" then Data.Sigils[self.Element] else Data.Layers[name]
		local want = math.floor(t * #pts)
		if far then self.Spawned[name] = want end
		while self.Spawned[name] < want do
			self.Spawned[name] += 1
			self:_spawn(name, pts[self.Spawned[name]])
		end
		-- rotation speeds up with progress; small kick once complete
		local mult = 1 + 2 * p + (if self.Done then 1.5 else 0)
		self.Angle[name] = (self.Angle[name] + SPIN[name] * mult * dt) % 360
		holder.Rotation = self.Angle[name]
	end
	if p >= 1 and not self.Done then
		self.Done = true
		self.PulseT = 0
	end
	if self.PulseT then
		self.PulseT += dt
		local k = math.clamp(self.PulseT / 0.45, 0, 1)
		self.Gui.Brightness = 1.25 + 0.45 * math.sin(k * math.pi) -- soft pulse, no flash
		if k >= 1 then self.PulseT = nil end
	end
	self:_stepParticles(dt)
end

function MagicCircle:_stepParticles(dt: number)
	for i = #self.Particles, 1, -1 do
		local q = self.Particles[i]
		q.T += dt
		if q.Out then
			local k = q.T / q.Dur
			q.F.Position = UDim2.fromScale(0.5 + (q.SX + q.VX * k) / 2, 0.5 + (q.SY + q.VY * k) / 2)
			q.F.BackgroundTransparency = k
			if k >= 1 then q.F:Destroy() table.remove(self.Particles, i) end
		else
			local k = math.clamp(q.T / q.Dur, 0, 1)
			local e = 1 - (1 - k) ^ 3
			local sw = q.Swirl * (1 - e) -- curved approach
			local x = q.SX + (q.TX - q.SX) * e
			local y = q.SY + (q.TY - q.SY) * e
			x, y = x * math.cos(sw) - y * math.sin(sw), x * math.sin(sw) + y * math.cos(sw)
			q.F.Position = UDim2.fromScale(0.5 + x / 2, 0.5 + y / 2)
			if k >= 1 then
				-- landed: fade into the texture
				q.Fade = if q.Fade < 0 then 0 else q.Fade + dt
				q.F.BackgroundTransparency = math.clamp(q.Fade / 0.35, 0, 1)
				if q.Fade >= 0.35 then q.F:Destroy() table.remove(self.Particles, i) end
			end
		end
	end
end

local function cleanup(self)
	self.Dead = true
	local i = table.find(active, self)
	if i then table.remove(active, i) end
	if self.Part then self.Part:Destroy() end
	self.Particles = {}
end

function MagicCircle:Destroy()
	if self.Dead then return end
	cleanup(self)
end

-- spell fires: everything collapses into the centre
function MagicCircle:Release()
	if self.Dead or self.Ending then return end
	self.Ending = "Release"
	self.EndT = 0
end

-- interrupted: pixels scatter outward, texture snaps off
function MagicCircle:Break()
	if self.Dead or self.Ending then return end
	self.Ending = "Break"
	self.EndT = 0
	if not self:_far() then
		for name in STAGES do
			local pts = if name == "Sig" then Data.Sigils[self.Element] else Data.Layers[name]
			local n = math.floor(stageT(self.Progress, STAGES[name]) * #pts)
			for k = 1, n, 3 do
				local pt = pts[k]
				local f = Instance.new("Frame")
				f.BorderSizePixel = 0
				f.AnchorPoint = Vector2.new(0.5, 0.5)
				f.Size = UDim2.fromOffset(5, 5)
				f.BackgroundColor3 = if pt[3] == 1 then self.Core else self.Mid
				f.ZIndex = 6
				f.Position = UDim2.fromScale(0.5 + pt[1] / 2, 0.5 + pt[2] / 2)
				f.Parent = self.Layers[name][1]
				local d = math.sqrt(pt[1] ^ 2 + pt[2] ^ 2) + 0.05
				local sp = 0.25 + math.random() * 0.35
				table.insert(self.Particles, { F = f, Out = true, SX = pt[1], SY = pt[2],
					VX = pt[1] / d * sp + (math.random() - 0.5) * 0.15, VY = pt[2] / d * sp + (math.random() - 0.5) * 0.15,
					T = 0, Dur = 0.45 + math.random() * 0.3 })
			end
		end
	end
end

function MagicCircle:_stepEnd(dt: number): boolean
	self.EndT += dt
	if self.Ending == "Release" then
		local k = math.clamp(self.EndT / 0.32, 0, 1)
		local e = k * k
		self.Root.Size = UDim2.fromScale(1 - 0.85 * e, 1 - 0.85 * e)
		self.Root.Rotation = 140 * e
		for _, L in self.Layers do L[2].ImageTransparency = math.max(L[2].ImageTransparency, e) end
		for _, q in self.Particles do q.F.BackgroundTransparency = math.max(q.F.BackgroundTransparency, e) end
		return k >= 1
	else
		local k = math.clamp(self.EndT / 0.12, 0, 1)
		for _, L in self.Layers do L[2].ImageTransparency = math.max(L[2].ImageTransparency, k) end
		self:_stepParticles(dt)
		return k >= 1 and #self.Particles == 0
	end
end

RunService.RenderStepped:Connect(function(dt)
	for i = #active, 1, -1 do
		local c = active[i]
		if c.Ending then
			if c:_stepEnd(dt) then cleanup(c) end
		else
			local ok, err = pcall(c._step, c, dt)
			if not ok then
				warn("[MagicCircle] step error:", err)
				cleanup(c)
			end
		end
	end
end)

return MagicCircle

-- MagicCircle — client-side pixel magic circles (Pixel Spell)
-- Textures + sample points are generated offline (scratchpad/circles/gen.js -> CircleData).
-- API:
--   local c = MagicCircle.new({ Element = "Fire", Anchor = rootPart | CFrame = cf, Size = 9, Kind = "Superieur" })
--   Point mode (cast origin): MagicCircle.new({ Element, Origin = function() return pos, dir end, Size })
--     -> vertical circle centred on pos, facing dir (updated every frame, e.g. wand Muzzle + aim)
--   c:SetProgress(p)   -- 0..1, drives convergence + layer reveal (stages: core 0-.3, star .3-.65, rune ring .65-1)
--   c:Release()        -- collapse inward then cleanup (spell fires)
--   c:Break()          -- scatter outward then cleanup (interrupted)
--   c:Destroy()        -- instant cleanup
--   MagicCircle.ActiveCount()
local RunService = game:GetService("RunService")

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

-- RUNES DE MODIFICATEURS (étape 6) : une rune par modificateur, gravée en anneau ; points = nombre d'empilements
local RUNE_ATLAS = "rbxassetid://76370146539199"
local RUNE_CELL = {DAMAGE_PLUS={0,0},EXPLOSIVE={100,0},DETONATE={200,0},KNOCKBACK={300,0},HEAVY={400,0},SIZE_PLUS={500,0},SIZE_PLUS_2={0,100},SIZE_PLUS_3={100,100},SPEED_PLUS={200,100},QUICK={300,100},RECHARGE_DOWN={400,100},DURATION_PLUS={500,100},DURATION_ZERO={0,200},SPIRAL={100,200},WAVE={200,200},ORBIT={300,200},BOOMERANG={400,200},HOMING={500,200},BOUNCE={0,300},PIERCE={100,300},IGNORE_OBSTACLES={200,300},DIVIDE_2={300,300},DIVIDE_3={400,300},DIVIDE_4={500,300},FRAGMENT={0,400},ADD_TRIGGER={100,400},ADD_TIMER={200,400},ADD_EXPIRE={300,400},CAST_HOLD={400,400},ADD_MANA={500,400},TRAIL_FIRE={0,500},BRANCH_PLUS={100,500},CAGE={200,500}}
MagicCircle.RuneCells = RUNE_CELL
local RUNE_RING = 0.71 -- rayon (fraction du demi-cercle) de l'anneau de runes
local RUNE_STAGE = { 0.3, 0.75 } -- les runes se gravent une à une pendant cette part de la progression

local CANVAS = 516
local SIGIL_FRAC = 41 / 129
local MAX_ACTIVE = 12
local LOD_DIST = 150
local STAGES = { Sig = { 0, 0.3 }, C = { 0, 0.3 }, B = { 0.3, 0.65 }, A = { 0.65, 1 } }
local SPIN = { A = 7, B = -11, C = 0, Sig = 0 }

local active = {}
local folder = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function smooth(t) t = math.clamp(t, 0, 1) return t * t * (3 - 2 * t) end
local function stageT(p, s) return math.clamp((p - s[1]) / (s[2] - s[1]), 0, 1) end

local function getFolder()
	if folder and folder.Parent then return folder end
	local f = workspace:FindFirstChild("ClientMagicCircles")
	if not f then
		f = Instance.new("Folder")
		f.Name = "ClientMagicCircles"
		f.Parent = workspace
	end
	folder = f
	return f
end

-- uneven ground: sample centre + 4 points and sit on the highest so no step hides part of the circle
local PROBE = { Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }
local function groundCF(pos, ignore, yaw, radius)
	rayParams.FilterDescendantsInstances = ignore
	local y = nil
	for _, o in PROBE do
		local hit = workspace:Raycast(pos + o * (radius or 0) * 0.45 + Vector3.new(0, 1, 0), Vector3.new(0, -14, 0), rayParams)
		if hit and (y == nil or hit.Position.Y > y) then y = hit.Position.Y end
	end
	y = y or pos.Y - 3
	return CFrame.new(pos.X, y + 0.06, pos.Z) * CFrame.Angles(0, yaw or 0, 0)
end

local function newLayer(parent, name, image, color, sizeFrac, z)
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
	return { holder, img }
end

function MagicCircle.ActiveCount() return #active end

function MagicCircle.new(opts)
	if #active >= MAX_ACTIVE then
		local old = table.remove(active, 1)
		if old then old:Destroy() end
	end
	local self = setmetatable({}, MagicCircle)
	local el = opts.Element or "Neutral"
	if not Data.Palette[el] then el = "Neutral" end
	local pal = Data.Palette[el]
	self.Element = el
	self.Core, self.Mid, self.Edge = Color3.fromHex(pal[1]), Color3.fromHex(pal[2]), Color3.fromHex(pal[3])
	self.Size = opts.Size or 9
	self.Anchor = opts.Anchor
	self.Origin = opts.Origin
	self.Kind = opts.Kind or "Superieur"
	self.Progress = 0
	self.Done = false
	self.Dead = false
	self.Particles = {}
	self.Spawned = { A = 0, B = 0, C = 0, Sig = 0 }
	self.Angle = { A = math.random() * 360, B = math.random() * 360, C = 0, Sig = 0 }
	self.Ignore = { getFolder() }
	if self.Anchor and self.Anchor.Parent then
		table.insert(self.Ignore, self.Anchor.Parent)
		self.Hum = self.Anchor.Parent:FindFirstChildOfClass("Humanoid")
	end

	local part = Instance.new("Part")
	part.Name = "MagicCircle_" .. el
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(self.Size, 0.05, self.Size)
	-- sigil "up" faces the caster's forward (fixed at creation so turning doesn't spin the circle)
	if self.Anchor then
		local lv = self.Anchor.CFrame.LookVector
		self.Yaw = math.atan2(lv.Z, -lv.X) -- texture "up" is the part's -X
	end
	part.CFrame = if self.Origin then MagicCircle._pointCF(self.Origin()) elseif self.Anchor then groundCF(self.Anchor.Position, self.Ignore, self.Yaw, self.Size / 2) else (opts.CFrame or CFrame.new())
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
	self.Layers = {
		A = newLayer(root, "A", tex.A, self.Mid, 1, 2),
		B = newLayer(root, "B", tex.B, self.Mid:Lerp(self.Core, 0.45), 1, 3),
		C = newLayer(root, "C", tex.C, self.Mid, 1, 2),
		Sig = newLayer(root, "Sig", ASSETS.Sigil[el], self.Core:Lerp(self.Mid, 0.25), SIGIL_FRAC, 4),
	}

	-- anneau de runes
	self.Runes = {}
	local list = {}
	for _, r in opts.Runes or {} do
		local id, n = r, 1
		if typeof(r) == "table" then id, n = r[1], tonumber(r[2]) or 1 end
		if RUNE_CELL[id] then table.insert(list, { id, math.clamp(n, 1, 6) }) end
	end
	if #list > 0 then
		local rp = Instance.new("Part")
		rp.Name = "Runes"
		rp.Anchored, rp.CanCollide, rp.CanQuery, rp.CanTouch, rp.CastShadow = true, false, false, false, false
		rp.Transparency = 1
		rp.Size = part.Size
		rp.CFrame = part.CFrame * CFrame.new(0, self:_runeLift(), 0)
		rp.Parent = part
		self.RunePart = rp
		local rg = Instance.new("SurfaceGui")
		rg.Face = gui.Face
		rg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		rg.CanvasSize = gui.CanvasSize
		rg.LightInfluence = 0
		rg.Brightness = 1.6
		rg.MaxDistance = gui.MaxDistance
		rg.Parent = rp
		self.RuneGui = rg
		local runeRoot = Instance.new("Frame")
		runeRoot.BackgroundTransparency = 1
		runeRoot.AnchorPoint = Vector2.new(0.5, 0.5)
		runeRoot.Position = UDim2.fromScale(0.5, 0.5)
		runeRoot.Size = UDim2.fromScale(1, 1)
		runeRoot.Parent = rg
		self.RuneRoot = runeRoot
		local ring = Instance.new("Frame")
		ring.Name = "R"
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(1, 1)
		ring.ZIndex = 5
		ring.Parent = runeRoot
		self.RuneRing = ring
		local cnt = #list
		local rs = math.clamp(1.6 / cnt, 0.15, 0.22) -- taille d'une rune (fraction du canevas)
		for k, r in list do
			local ang = -math.pi / 2 + (k - 1) / cnt * math.pi * 2
			local cx, cy = 0.5 + math.cos(ang) * RUNE_RING / 2, 0.5 + math.sin(ang) * RUNE_RING / 2
			local holder = Instance.new("Frame")
			holder.BackgroundTransparency = 1
			holder.AnchorPoint = Vector2.new(0.5, 0.5)
			holder.Position = UDim2.fromScale(cx, cy)
			holder.Size = UDim2.fromScale(rs, rs)
			holder.Rotation = math.deg(ang) + 90 -- le haut de la rune regarde vers l'extérieur
			holder.ZIndex = 5
			holder.Parent = ring
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Size = UDim2.fromScale(1, 1)
			img.Image = RUNE_ATLAS
			img.ImageRectOffset = Vector2.new(RUNE_CELL[r[1]][1], RUNE_CELL[r[1]][2])
			img.ImageRectSize = Vector2.new(100, 100)
			img.ImageColor3 = self.Core:Lerp(self.Mid, 0.2)
			img.ImageTransparency = 1
			img.ResampleMode = Enum.ResamplerMode.Pixelated
			img.ZIndex = 5
			img.Parent = holder
			-- ombre sombre décalée : la rune reste lisible sur n'importe quel cercle (glace claire, etc.)
			local sh = img:Clone()
			sh.Name = "Shadow"
			sh.ImageColor3 = self.Edge:Lerp(Color3.new(0, 0, 0), 0.75)
			sh.Position = UDim2.fromScale(0.05, 0.06)
			sh.ZIndex = 4
			sh.Parent = holder
			local dots = {}
			if r[2] >= 2 then
				for d = 1, r[2] do
					local f = Instance.new("Frame")
					f.BorderSizePixel = 0
					f.AnchorPoint = Vector2.new(0.5, 0.5)
					f.Size = UDim2.fromScale(0.09, 0.09)
					f.Position = UDim2.fromScale(0.5 + (d - (r[2] + 1) / 2) * 0.17, 1.02)
					f.BackgroundColor3 = self.Core
					f.BackgroundTransparency = 1
					f.ZIndex = 5
					f.Parent = holder
					table.insert(dots, f)
				end
			end
			table.insert(self.Runes, { Img = img, Shadow = sh, Dots = dots, Holder = holder, T0 = (k - 1) / cnt, T1 = k / cnt, Lit = false })
		end
	end

	part.Parent = getFolder()
	table.insert(active, self)
	return self
end

function MagicCircle:_spawn(layer, pt)
	local holder = self.Layers[layer][1]
	local lv = pt[3]
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	local px = if lv == 1 then 10 else 8
	f.Size = UDim2.fromOffset(px, px)
	f.BackgroundColor3 = if lv == 1 then self.Core elseif lv == 2 then self.Mid else self.Edge:Lerp(self.Mid, 0.5)
	f.ZIndex = 6
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

-- hauteur des runes au-dessus du cercle (proportionnelle à sa taille, légère)
function MagicCircle:_runeLift()
	return math.clamp(self.Size * 0.06, 0.35, 1.6)
end

function MagicCircle:SetProgress(p)
	if self.Dead then return end
	self.Progress = math.clamp(p, 0, 1)
end

-- vertical circle at pos, its face (Top) looking along dir; texture "up" kept towards world up
function MagicCircle._pointCF(pos, dir)
	dir = if dir and dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 0, -1)
	local up = if math.abs(dir.Y) > 0.98 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	-- columns: X = -up (texture up is part -X), Y = dir (Top face normal), Z = X cross Y
	local x = -(up - dir * up:Dot(dir)).Unit
	local z = x:Cross(dir)
	return CFrame.fromMatrix(pos, x, dir, z)
end

function MagicCircle:_far()
	local cam = workspace.CurrentCamera
	return cam ~= nil and (cam.CFrame.Position - self.Part.Position).Magnitude > LOD_DIST
end

function MagicCircle:_step(dt)
	if self.Dead then return end
	local p = self.Progress
	if self.Origin then
		local ok, pos, dir = pcall(self.Origin)
		if not ok or not pos then self:Break() return end
		self.Part.CFrame = MagicCircle._pointCF(pos, dir)
		-- a SurfaceGui is one-sided: show it on the face turned towards the camera (caster sees it from behind)
		local cam = workspace.CurrentCamera
		if cam then
			local front = (cam.CFrame.Position - pos):Dot(self.Part.CFrame.UpVector) >= 0
			local face = if front then Enum.NormalId.Top else Enum.NormalId.Bottom
			if self.Gui.Face ~= face then self.Gui.Face = face end
		end
	elseif self.Anchor then
		-- caster gone or dead: the circle breaks
		if not self.Anchor.Parent or (self.Hum and self.Hum.Health <= 0) then self:Break() return end
		self.Part.CFrame = groundCF(self.Anchor.Position, self.Ignore, self.Yaw, self.Size / 2)
	end
	local far = self:_far()
	for name, s in STAGES do
		local t = stageT(p, s)
		local holder, img = self.Layers[name][1], self.Layers[name][2]
		img.ImageTransparency = 1 - smooth((t - 0.15) / 0.85) * (if self.Done then 1 else 0.92)
		local pts = if name == "Sig" then Data.Sigils[self.Element] else Data.Layers[name]
		local want = math.floor(t * #pts)
		if far then self.Spawned[name] = want end
		while self.Spawned[name] < want do
			self.Spawned[name] += 1
			self:_spawn(name, pts[self.Spawned[name]])
		end
		local mult = 1 + 2 * p + (if self.Done then 1.5 else 0)
		self.Angle[name] = (self.Angle[name] + SPIN[name] * mult * dt) % 360
		holder.Rotation = self.Angle[name]
	end
	-- runes : gravées une à une (fondu + léger rebond), tournent avec l'anneau extérieur
	if self.RunePart then
		local lift = self:_runeLift() * (0.6 + 0.4 * smooth(p)) + math.sin(os.clock() * 2.2) * 0.06
		local face = self.Gui.Face
		self.RunePart.CFrame = self.Part.CFrame * CFrame.new(0, if face == Enum.NormalId.Bottom then -lift else lift, 0)
		if self.RuneGui.Face ~= face then self.RuneGui.Face = face end
		self.RuneGui.Brightness = self.Gui.Brightness + 0.15
		if self.Root then self.RuneRoot.Size = self.Root.Size self.RuneRoot.Rotation = self.Root.Rotation end
	end
	if self.RuneRing then
		self.RuneRing.Rotation = self.Angle.A
		local rt = stageT(p, RUNE_STAGE)
		for _, r in self.Runes do
			local k = math.clamp((rt - r.T0) / math.max(r.T1 - r.T0, 1e-3), 0, 1)
			local tr = 1 - smooth(k) * 0.92
			if self.Done then tr = 0 end
			r.Img.ImageTransparency = tr
			r.Shadow.ImageTransparency = 0.25 + 0.75 * tr
			for _, d in r.Dots do d.BackgroundTransparency = tr end
			if k > 0 and not r.Lit then
				r.Lit = true
				r.PopT = 0
			end
			if r.PopT then
				r.PopT += dt
				local b = math.clamp(r.PopT / 0.35, 0, 1)
				local sc = 1 + 0.35 * math.sin(b * math.pi)
				r.Holder.Size = UDim2.fromScale(r.Holder.Size.X.Scale / (r.Sc or 1) * sc, r.Holder.Size.Y.Scale / (r.Sc or 1) * sc)
				r.Sc = sc
				if b >= 1 then r.PopT = nil end
			end
		end
	end
	if p >= 1 and not self.Done then
		self.Done = true
		self.PulseT = 0
		-- ONDE : copie de l'anneau extérieur qui s'agrandit et s'efface (cercle terminé)
		local src = self.Layers and self.Layers.A and self.Layers.A[2]
		if src and src:IsA("ImageLabel") and self.Root then
			local wave = src:Clone()
			wave.Name = "DoneWave"
			wave.AnchorPoint = Vector2.new(0.5, 0.5)
			wave.Position = UDim2.fromScale(0.5, 0.5)
			wave.Size = UDim2.fromScale(1, 1)
			wave.ImageTransparency = 0.35
			wave.ZIndex = 0
			wave.Parent = self.Root
			self.Wave = wave
		end
	end
	if self.PulseT then
		self.PulseT += dt
		local k = math.clamp(self.PulseT / 0.6, 0, 1)
		local bump = math.sin(k * math.pi)
		self.Gui.Brightness = 1.25 + 0.6 * bump -- flash léger (pas de saturation)
		if self.Root and not self.Ending then
			self.Root.Size = UDim2.fromScale(1 + 0.08 * bump, 1 + 0.08 * bump) -- petit gonflement
		end
		if self.Wave then
			-- l'onde part du cœur et file jusqu'au bord (le SurfaceGui coupe ce qui dépasse le cercle)
			local s = 0.35 + 0.65 * (1 - (1 - k) ^ 2)
			self.Wave.Size = UDim2.fromScale(s, s)
			self.Wave.ImageTransparency = 0.2 + 0.8 * k
		end
		if k >= 1 then
			self.PulseT = nil
			if self.Root and not self.Ending then
				self.Root.Size = UDim2.fromScale(1, 1)
			end
			if self.Wave then
				self.Wave:Destroy()
				self.Wave = nil
			end
		end
	end
	self:_stepParticles(dt)
end

function MagicCircle:_stepParticles(dt)
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
			local sw = q.Swirl * (1 - e)
			local x = q.SX + (q.TX - q.SX) * e
			local y = q.SY + (q.TY - q.SY) * e
			x, y = x * math.cos(sw) - y * math.sin(sw), x * math.sin(sw) + y * math.cos(sw)
			q.F.Position = UDim2.fromScale(0.5 + x / 2, 0.5 + y / 2)
			if k >= 1 then
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

function MagicCircle:Release()
	if self.Dead or self.Ending then return end
	self.Ending = "Release"
	self.EndT = 0
end

function MagicCircle:Break()
	if self.Dead or self.Ending then return end
	self.Ending = "Break"
	self.EndT = 0
	if not self:_far() then
		for name, s in STAGES do
			local pts = if name == "Sig" then Data.Sigils[self.Element] else Data.Layers[name]
			local n = math.floor(stageT(self.Progress, s) * #pts)
			for k = 1, n, 3 do
				local pt = pts[k]
				local f = Instance.new("Frame")
				f.BorderSizePixel = 0
				f.AnchorPoint = Vector2.new(0.5, 0.5)
				f.Size = UDim2.fromOffset(8, 8)
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

function MagicCircle:_stepEnd(dt)
	self.EndT += dt
	if self.Ending == "Release" then
		-- (user : disparition moins brusque) fondu LONG : 1,1 s, rotation et rétrécissement doux
		local k = math.clamp(self.EndT / 1.1, 0, 1)
		local shrink = 1 - (1 - k) ^ 2 -- décélère en fin de course
		local fade = k ^ 1.6 -- reste bien visible au début, s'efface progressivement
		self.Root.Size = UDim2.fromScale(1 - 0.55 * shrink, 1 - 0.55 * shrink)
		self.Root.Rotation = 120 * shrink
		if self.RuneRoot then self.RuneRoot.Size = self.Root.Size self.RuneRoot.Rotation = self.Root.Rotation end
		for _, L in self.Layers do L[2].ImageTransparency = math.max(L[2].ImageTransparency, fade) end
		for _, r in self.Runes or {} do
			r.Img.ImageTransparency = math.max(r.Img.ImageTransparency, fade)
			r.Shadow.ImageTransparency = math.max(r.Shadow.ImageTransparency, fade)
			for _, d in r.Dots do d.BackgroundTransparency = math.max(d.BackgroundTransparency, fade) end
		end
		for _, q in self.Particles do q.F.BackgroundTransparency = math.max(q.F.BackgroundTransparency, fade) end
		return k >= 1
	else
		local k = math.clamp(self.EndT / 0.6, 0, 1) -- cercle BRISÉ : 0,6 s (était 0,12)
		for _, L in self.Layers do L[2].ImageTransparency = math.max(L[2].ImageTransparency, k) end
		for _, r in self.Runes or {} do
			r.Img.ImageTransparency = math.max(r.Img.ImageTransparency, k)
			r.Shadow.ImageTransparency = math.max(r.Shadow.ImageTransparency, k)
			for _, d in r.Dots do d.BackgroundTransparency = math.max(d.BackgroundTransparency, k) end
		end
		self:_stepParticles(dt)
		return k >= 1 and #self.Particles == 0
	end
end

RunService.RenderStepped:Connect(function(dt)
	for i = #active, 1, -1 do
		local c = active[i]
		if c then
			if c.Ending then
				local ok, done = pcall(c._stepEnd, c, dt)
				if not ok or done then
					if not ok then warn("[MagicCircle] end error:", done) end
					cleanup(c)
				end
			else
				local ok, err = pcall(c._step, c, dt)
				if not ok then
					warn("[MagicCircle] step error:", err)
					cleanup(c)
				end
			end
		end
	end
end)

return MagicCircle
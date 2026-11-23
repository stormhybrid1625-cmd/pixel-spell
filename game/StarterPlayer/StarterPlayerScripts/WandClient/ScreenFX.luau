--[[
	WandClient/ScreenFX — COULEURS ET BORDS D'ÉCRAN liés aux SORTS / ÉLÉMENTS (jamais de flash)

	• VIGNETTES TEXTURÉES pixel art par élément (PixelSpell/tools/gen_vignettes.js), centre transparent :
	  givre (glace) · flammes (feu, animées) · arcs (foudre, animés) · bave (toxique) · ronces (nature).
	  Définies dans WandShared/Elements/<Élément>.Screen (Images, Fps, Creep, Rest, Opacity, Tint...).
	• Teinte douce de l'écran (ColorCorrection séparée de l'ambiance) : Screen.Tint / Saturation / Contrast.
	• Déclencheurs : ÉTAT du joueur lié à une infusion (en feu, gelé, électrocuté, empoisonné, entravé),
	  être DEBOUT dans une zone au sol (effet plus léger), EXPLOSION proche (souffle : bords assombris),
	  mana vide (voile gris-bleu). Aucun effet de coup générique, aucun effet de vie basse.
	• Tout monte en douceur et retombe lentement ; le CENTRE de l'écran reste toujours dégagé.
	• Réglage : FXSettings Screen (0 / 0,5 / 1).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FXSettings = require(script.Parent:WaitForChild("FXSettings"))
local Elements = require(ReplicatedStorage:WaitForChild("WandShared"):WaitForChild("Elements"))

local ScreenFX = {}
local player = Players.LocalPlayer
local rng = Random.new()
local gui: ScreenGui
local cc: ColorCorrectionEffect
local PX = 8 -- taille d'un « pixel » d'écran (recalculée selon la résolution)
local W, H = 1280, 720
local layers = {} -- [nom] = { Root, Weight, Target, Update(dt, w), Built }
local blastUntil, manaUntil = 0, 0
local punch = 0 -- grosse explosion : contraste + couleurs ternies un instant (jamais de flash)
local pulse = 0 -- VIGNETTE NOIRE : impulsion (tir, projectile qui frôle, explosion), retombe seule
local flyAcc = 0

local function hex(s) return Color3.fromHex(s) end

local function block(parent, x, y, w, h, color)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.Parent = parent
	return f
end

local function newRoot(name)
	local r = Instance.new("Frame")
	r.Name = name
	r.BackgroundTransparency = 1
	r.Size = UDim2.fromScale(1, 1)
	r.Visible = false
	r.Parent = gui
	return r
end

-- ── MOTIFS ───────────────────────────────────────────────────────────────────────────────────────────
local BUILD = {}

-- VIGNETTE TEXTURÉE d'un élément (WandShared/Elements/<Élément>.Screen) : image pixel art plein écran
-- (PixelSpell/tools/gen_vignettes.js), centre transparent. Elle S'INSINUE depuis les bords : agrandie hors
-- de l'écran quand l'effet est faible, elle se resserre vers son cadre quand il monte. Images = 1 ou 2
-- (alternées à Fps pour animer : feu, foudre) ; sinon elle « respire » doucement.
local function textureLayer(L, sc)
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(0.5, 0.5)
	img.Size = UDim2.fromScale(1, 1)
	img.ScaleType = Enum.ScaleType.Stretch
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.Image = sc.Images[1]
	img.ImageTransparency = 1
	img.Parent = L.Root
	L.Frame, L.Acc = 1, 0
	L.Update = function(dt, w)
		if #sc.Images > 1 then
			L.Acc += dt
			if L.Acc >= 1 / (sc.Fps or 8) then
				L.Acc = 0
				L.Frame = L.Frame % #sc.Images + 1
				img.Image = sc.Images[L.Frame]
			end
		end
		local breathe = 1 + math.sin(os.clock() * (sc.Breathe or 1.6)) * 0.008
		local creep = 1 + (1 - w) * (sc.Creep or 0.22) -- hors écran à faible intensité
		local rest = sc.Rest or 1 -- échelle de repos à pleine intensité (> 1 = la vignette mange moins l'écran)
		img.Size = UDim2.fromScale(creep * breathe * rest, creep * breathe * rest)
		img.ImageTransparency = 1 - math.clamp(w, 0, 1) * (sc.Opacity or 0.9)
	end
end

-- vignette pixel en paliers (souffle d'explosion, mana vide) : 4 bandes de plus en plus transparentes
local function stepVignette(L, color)
	L.Bands = {}
	for b = 0, 3 do
		local o = b * PX
		for _, rect in { { 0, o, W, PX }, { 0, H - o - PX, W, PX }, { o, 0, PX, H }, { W - o - PX, 0, PX, H } } do
			local f = block(L.Root, rect[1], rect[2], rect[3], rect[4], color)
			table.insert(L.Bands, { F = f, K = 1 - b / 4 })
		end
	end
	L.Update = function(dt, w)
		for _, b in L.Bands do
			b.F.BackgroundTransparency = 1 - 0.75 * w * b.K
		end
	end
end
BUILD.Blast = function(L) stepVignette(L, hex("07060c")) end
BUILD.Mana = function(L) stepVignette(L, hex("3a4a6a")) end

local function layer(name)
	local L = layers[name]
	if L then
		return L
	end
	L = { Weight = 0, Target = 0 }
	L.Root = newRoot(name)
	local elId = name:match("^El_(.+)$")
	if elId then
		textureLayer(L, Elements[elId].Screen)
	else
		BUILD[name](L)
	end
	layers[name] = L
	return L
end

local function rebuild()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	W, H = math.max(320, vp.X), math.max(240, vp.Y)
	PX = math.max(6, math.floor(H / 95))
	for name, L in layers do
		L.Root:Destroy()
		layers[name] = nil
	end
end

-- ── TEINTE ───────────────────────────────────────────────────────────────────────────────────────────
local tintW: { [string]: number } = {}

local function edgeFor(el: string?)
	local def = el and Elements[el]
	return def and def.Screen
end

-- cible de chaque élément (0..1) d'après l'état du joueur et son environnement
local function elementTargets(): { [string]: number }
	local out = {}
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hum.Health > 0 then
		for _, def in Elements.All() do
			local sc = def.Screen
			if sc and sc.Status and hum:GetAttribute(sc.Status) then
				out[def.Id] = 1
			end
		end
		local slowUntil = hum:GetAttribute("ElemSlowUntil")
		local slowEl = hum:GetAttribute("SlowElem")
		if type(slowUntil) == "number" and slowUntil > workspace:GetServerTimeNow() and type(slowEl) == "string" then
			out[slowEl] = 1
		end
	end
	-- tout près d'une RAMURE INFUSÉE (feu, glace, foudre, toxique...) : vignette légère de son élément
	if root then
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character }
		params.MaxParts = 40
		for _, part in workspace:GetPartBoundsInRadius(root.Position, 5, params) do
			local el = part:GetAttribute("GrowElement")
			if type(el) == "string" and el ~= "Nature" then
				out[el] = math.max(out[el] or 0, 0.55)
			end
		end
	end
	-- debout dans une zone au sol : effet plus léger
	local markers = workspace:FindFirstChild("WandZoneMarkers")
	if root and markers then
		for _, m in markers:GetChildren() do
			if m.Name == "Patch" then
				local el = m:GetAttribute("Element")
				local r = m:GetAttribute("Radius") or 4
				local d = root.Position - m.Position
				if type(el) == "string" and Vector2.new(d.X, d.Z).Magnitude < r and math.abs(d.Y) < 5 then
					out[el] = math.max(out[el] or 0, 0.4)
				end
			end
		end
	end
	return out
end

local scanAcc = 0
local targets = {}
local function step(dt: number)
	local mul = FXSettings.Get("Screen")
	scanAcc += dt
	if scanAcc > 0.15 then
		scanAcc = 0
		targets = elementTargets()
	end
	-- bords par élément
	local wanted = {}
	for el, t in targets do
		local sc = edgeFor(el)
		if sc and sc.Images then
			wanted["El_" .. el] = math.max(wanted["El_" .. el] or 0, t)
		end
	end
	local now = os.clock()
	-- VIGNETTE NOIRE : impulsions + présence continue (en feu / dans le feu, rayon maintenu)
	pulse = math.max(0, pulse - dt * 1.5)
	local sustained = 0
	if (targets.Fire or 0) > 0 then
		sustained = math.max(sustained, 0.35 * targets.Fire) -- chaleur étouffante
	end
	if player:GetAttribute("Holding") then
		sustained = math.max(sustained, 0.25) -- concentration du maintien
	end
	-- projectile ENNEMI qui frôle le joueur
	flyAcc += dt
	if flyAcc > 0.05 then
		flyAcc = 0
		local folder = workspace:FindFirstChild("WandProjectiles")
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if folder and root then
			for _, p in folder:GetChildren() do
				if p:IsA("BasePart") and p:GetAttribute("Owner") ~= player.UserId then
					local d = (p.Position - root.Position).Magnitude
					if d < 9 then
						pulse = math.max(pulse, 0.6 * (1 - d / 9))
					end
				end
			end
		end
	end
	wanted.Blast = math.max(if now < blastUntil then 1 else 0, pulse, sustained)
	wanted.Mana = if now < manaUntil then 0.7 else 0
	local names = {}
	for name in BUILD do
		names[name] = true
	end
	for name in wanted do
		names[name] = true
	end
	for name in layers do
		names[name] = true
	end
	for name in names do
		local tgt = (wanted[name] or 0) * mul
		local L = layers[name]
		if tgt > 0.01 and not L then
			L = layer(name)
		end
		if L then
			-- monte vite, retombe lentement (jamais brutal)
			local speed = if tgt > L.Weight then 5 else 1.6
			if name == "Blast" then
				speed = if tgt > L.Weight then 14 else 2.2
			end
			L.Weight += (tgt - L.Weight) * math.min(1, dt * speed)
			if L.Weight < 0.01 and tgt <= 0.01 then
				L.Weight = 0
				L.Root.Visible = false
			else
				L.Root.Visible = true
				L.Update(dt, L.Weight)
			end
		end
	end
	-- teinte
	local tint, sat, con = Color3.new(1, 1, 1), 0, 0
	for _, def in Elements.All() do
		local sc = def.Screen
		if sc then
			local tgt = (targets[def.Id] or 0) * mul
			local w = tintW[def.Id] or 0
			w += (tgt - w) * math.min(1, dt * (if tgt > w then 4 else 1.4))
			tintW[def.Id] = w
			if w > 0.001 then
				if sc.Tint then
					tint = tint:Lerp(sc.Tint, w * 0.6)
				end
				sat += (sc.Saturation or 0) * w
				con += (sc.Contrast or 0) * w
			end
		end
	end
	punch = math.max(0, punch - dt * 1.4)
	cc.TintColor = tint
	cc.Saturation = sat - 0.35 * punch * mul
	cc.Contrast = con + 0.3 * punch * mul
end

function ScreenFX.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "WandScreenFX"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = -10 -- sous l'interface du jeu
	gui.Parent = player:WaitForChild("PlayerGui")
	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "WandScreenTint" -- séparée de l'étalonnage d'ambiance
	cc.Parent = Lighting
	rebuild()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(rebuild)
	end
	RunService.RenderStepped:Connect(step)
end

-- impulsion de VIGNETTE NOIRE (0..1) : tir, explosion, projectile qui frôle...
function ScreenFX.Pulse(amount: number)
	pulse = math.max(pulse, math.clamp(amount, 0, 1))
end

-- messages FX
function ScreenFX.Handle(msg: { [string]: any })
	local kind = msg.k
	if kind == "Impact" then
		local r = tonumber(msg.r) or 0
		local p = if typeof(msg.p) == "Vector3" then msg.p else nil
		local cam = workspace.CurrentCamera
		if r > 0 and p and cam then
			-- souffle : les bords s'assombrissent, d'autant plus que l'explosion est proche et grosse
			-- VIGNETTE NOIRE (user 2026-11-23 : plus forte, de plus loin pour les grosses explosions)
			local range = 25 + r * 6
			local d = (cam.CFrame.Position - p).Magnitude
			if d < range then
				local k = (1 - d / range) ^ 0.6
				local z = math.clamp(tonumber(msg.z) or 1, 0.5, 5)
				ScreenFX.Pulse(math.min(1, k * math.clamp(0.6 + r / 15, 0.6, 1) * 1.8))
				-- grosse explosion : le voile TIENT un instant avant de retomber
				local hold = math.clamp((r - 8) / 30, 0, 1) * k
				if hold > 0 then
					blastUntil = math.max(blastUntil, os.clock() + 0.1 + hold * 0.6)
				end
				local big = (r * math.sqrt(z) - 6) / 10
				if big > 0 then
					punch = math.max(punch, math.min(1, big * k * 1.3))
				end
			end
		end
	elseif kind == "NoMana" then
		manaUntil = os.clock() + 0.45
	end
end

return ScreenFX

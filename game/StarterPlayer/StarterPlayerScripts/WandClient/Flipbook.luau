--[[
	WandClient/Flipbook — Sprites pixel art animés

	Les planches (Config.Sprites) sont des bandes horizontales de N images carrées.
	On les affiche dans un ImageLabel avec ResampleMode = Pixelated (aucun lissage = pixels nets),
	en changeant ImageRectOffset image par image. UN SEUL RenderStepped anime tous les sprites.

	  Flipbook.Billboard(adornee, sprite, studs, opts) -> BillboardGui face à la caméra
	  Flipbook.Ground(pos, sprite, studs, opts, parent) -> Part plate au sol avec SurfaceGui (vu de dessus)
	  opts : Brightness (>1 = déclenche le Bloom), Transparency, AlwaysOnTop, Rotation, Fps
	Un sprite non bouclant (Loop = false) se cache tout seul à la dernière image.

	PERFORMANCES (6 joueurs, traînées de zones) :
	  • animation à 30 Hz (les planches tournent à 5-16 images/s : inutile de les mettre à jour à 240 Hz)
	  • BUDGET : au plus MAX_LOOPING sprites BOUCLANTS animés en même temps ; au-delà, un nouveau sprite
	    bouclant reste figé sur une image au hasard (visuellement identique de loin, coût nul)
	  • la face arrière des sprites au sol partage l'animation de la face avant (une seule entrée)
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("WandShared"):WaitForChild("Config"))

local Flipbook = {}

local MAX_LOOPING = 140

local FXSettings = require(script.Parent:WaitForChild("FXSettings"))
local function applyQuality() -- réglage Qualité des effets (Bas / Moyen / Haut)
	MAX_LOOPING = math.floor(140 * FXSettings.QualityK())
end
applyQuality()
FXSettings.OnChanged(applyQuality)
local TICK = 1 / 30

type Anim = { Label: ImageLabel, Mirror: ImageLabel?, Sprite: any, Start: number, Frame: number, Fps: number }
local active: { Anim } = {}
local looping = 0
local clock = 0
local acc = 0
local rng = Random.new()

local function newLabel(parent: Instance, sp: any, opts: any): ImageLabel
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = sp.Id
	img.ImageRectSize = Vector2.new(sp.Size, sp.Size)
	img.ImageRectOffset = Vector2.zero
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.ImageTransparency = opts.Transparency or 0
	img.Rotation = opts.Rotation or 0
	img.Parent = parent
	return img
end

-- registers an animation (or freezes it on a random frame when the looping budget is full)
local function animate(img: ImageLabel, sp: any, opts: any, mirror: ImageLabel?)
	if sp.Loop and looping >= MAX_LOOPING then
		local f = rng:NextInteger(0, sp.Frames - 1)
		img.ImageRectOffset = Vector2.new(f * sp.Size, 0)
		if mirror then mirror.ImageRectOffset = img.ImageRectOffset end
		return
	end
	if sp.Loop then looping += 1 end
	table.insert(active, { Label = img, Mirror = mirror, Sprite = sp, Start = clock, Frame = 0, Fps = opts.Fps or sp.Fps })
end

function Flipbook.Image(parent: Instance, spriteName: string, opts: any?): ImageLabel?
	local sp = Config.Sprites[spriteName]
	if not sp then
		warn("[Wand] sprite inconnu :", spriteName)
		return nil
	end
	opts = opts or {}
	local img = newLabel(parent, sp, opts)
	animate(img, sp, opts)
	return img
end

function Flipbook.Billboard(adornee: BasePart, spriteName: string, studs: number, opts: any?): (BillboardGui, ImageLabel?)
	opts = opts or {}
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(studs, studs)
	bb.LightInfluence = 0
	bb.Brightness = opts.Brightness or 1
	bb.AlwaysOnTop = opts.AlwaysOnTop or false
	bb.Adornee = adornee
	bb.Parent = adornee
	return bb, Flipbook.Image(bb, spriteName, opts)
end

function Flipbook.Ground(pos: Vector3, spriteName: string, studs: number, opts: any?, parent: Instance): (Part, ImageLabel?)
	opts = opts or {}
	local sp = Config.Sprites[spriteName]
	local p = Instance.new("Part")
	p.Name = "GroundSprite"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(studs, 0.05, studs)
	p.CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0))
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.LightInfluence = 0
	sg.Brightness = opts.Brightness or 1
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 16
	sg.Parent = p
	if not sp then
		p.Parent = parent
		return p, nil
	end
	-- SurfaceGui is one-sided: mirror on the Bottom face so the sprite is also seen from below / behind;
	-- the mirror shares the front face's animation entry (no extra cost)
	local back = sg:Clone()
	back.Face = Enum.NormalId.Bottom
	back.Parent = p
	local img = newLabel(sg, sp, opts)
	local mirror = newLabel(back, sp, opts)
	animate(img, sp, opts, mirror)
	p.Parent = parent -- parented once, fully built (one replication / render update)
	return p, img
end

local function update(dt: number)
	clock += dt
	acc += dt
	if acc < TICK then return end
	acc = 0
	for i = #active, 1, -1 do
		local a = active[i]
		local sp = a.Sprite
		if not a.Label.Parent then
			if sp.Loop then looping -= 1 end
			active[i] = active[#active]
			active[#active] = nil
			continue
		end
		local f = math.floor((clock - a.Start) * a.Fps)
		if sp.Loop then
			f %= sp.Frames
		elseif f >= sp.Frames then
			a.Label.Visible = false -- animation terminée
			if a.Mirror then a.Mirror.Visible = false end
			active[i] = active[#active]
			active[#active] = nil
			continue
		end
		if f ~= a.Frame then
			a.Frame = f
			local off = Vector2.new(f * sp.Size, 0)
			a.Label.ImageRectOffset = off
			if a.Mirror then a.Mirror.ImageRectOffset = off end
		end
	end
end

function Flipbook.Count(): (number, number)
	return #active, looping
end

function Flipbook.Init()
	RunService.RenderStepped:Connect(update)
end

return Flipbook

--[[
	WandClient/LightPool
	Gestionnaire de lumières dynamiques avec BUDGET.

	Problème : 80 projectiles + 30 explosions = 110 PointLight -> les FPS s'effondrent.
	Solution : les effets ne créent jamais de PointLight eux-mêmes, ils font des DEMANDES.
	Chaque frame, on note toutes les demandes (luminosité x portée, divisé par la distance à la caméra)
	et seules les MAX_LIGHTS meilleures reçoivent une vraie lumière, prise dans un pool réutilisé.

	Types de demandes :
	  LightPool.Attach(part, color, range, brightness, flicker) -> handle (suit une Part ; handle:Release())
	  LightPool.Flash(pos, color, range, brightness, duration, steps?) -> flash fixe qui décroît PAR PALIERS
	  flicker (0..1) = scintillement (bruit de Perlin), donne la vie aux flammes et aux étincelles.
]]

local RunService = game:GetService("RunService")

local LightPool = {}

local MAX_LIGHTS = 28
local DEFAULT_STEPS = { 1, 0.55, 0.25 } -- décroissance en paliers (look rétro, pas de fondu)

type Request = {
	Part: BasePart?,
	Pos: Vector3,
	Color: Color3,
	Range: number,
	Brightness: number,
	Flicker: number,
	Life: number?, -- nil = persistante (Attach)
	Age: number,
	Steps: { number },
	Seed: number,
	Dead: boolean,
	Score: number,
	FadeAt: number?, -- Release(fade) : âge auquel l'extinction douce a commencé
	FadeDur: number?,
}

local requests: { Request } = {}
local slots: { { Part: Part, Light: PointLight } } = {}
local folder: Folder
local clock = 0

local function newSlot()
	local p = Instance.new("Part")
	p.Name = "Light"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.1
	local l = Instance.new("PointLight")
	l.Shadows = false
	l.Enabled = false
	l.Parent = p
	p.Parent = folder
	return { Part = p, Light = l }
end

local function add(req: Request): Request
	table.insert(requests, req)
	return req
end

function LightPool.Attach(part: BasePart, color: Color3, range: number, brightness: number, flicker: number?)
	local req = add({
		Part = part, Pos = part.Position, Color = color, Range = range, Brightness = brightness,
		Flicker = flicker or 0, Life = nil, Age = 0, Steps = DEFAULT_STEPS, Seed = math.random() * 100,
		Dead = false, Score = 0,
	})
	return {
		-- extinction DOUCE par défaut (0.35 s) : une lumière ne disparaît jamais d'un coup
		Release = function(fade: number?)
			fade = fade or 0.35
			if fade <= 0 then
				req.Dead = true
			elseif not req.FadeAt then
				req.Part = nil -- reste à sa dernière position
				req.FadeAt = req.Age
				req.FadeDur = fade
			end
		end,
		Set = function(_, newColor: Color3?, newBrightness: number?)
			req.Color = newColor or req.Color
			req.Brightness = newBrightness or req.Brightness
		end,
	}
end

function LightPool.Flash(pos: Vector3, color: Color3, range: number, brightness: number, duration: number, steps: { number }?, flicker: number?)
	add({
		Part = nil, Pos = pos, Color = color, Range = range, Brightness = brightness,
		Flicker = flicker or 0, Life = duration, Age = 0, Steps = steps or DEFAULT_STEPS, Seed = math.random() * 100,
		Dead = false, Score = 0,
	})
end

local function currentBrightness(req: Request): number
	local b = req.Brightness
	if req.Life then
		local n = #req.Steps
		local index = math.clamp(math.floor(req.Age / req.Life * n) + 1, 1, n)
		b *= req.Steps[index]
	end
	if req.Flicker > 0 then
		b *= 1 + req.Flicker * math.noise(clock * 9, req.Seed)
	end
	if req.FadeAt then
		local k = 1 - (req.Age - req.FadeAt) / (req.FadeDur or 0.35)
		b *= math.clamp(k, 0, 1) ^ 2
	end
	return math.max(0, b)
end

local function update(dt: number)
	clock += dt
	local camPos = workspace.CurrentCamera.CFrame.Position

	-- 1) vieillissement + nettoyage (suppression par échange, O(1))
	local i = 1
	while i <= #requests do
		local req = requests[i]
		req.Age += dt
		local part = req.Part
		if part then
			if part.Parent then
				req.Pos = part.Position
			else
				req.Dead = true
			end
		end
		if req.Dead or (req.Life and req.Age >= req.Life) or (req.FadeAt and req.Age - req.FadeAt >= (req.FadeDur or 0.35)) then
			requests[i] = requests[#requests]
			requests[#requests] = nil
		else
			req.Score = req.Brightness * req.Range / (1 + (req.Pos - camPos).Magnitude / 40)
			i += 1
		end
	end

	-- 2) les meilleures demandes reçoivent une vraie lumière
	if #requests > MAX_LIGHTS then
		table.sort(requests, function(a, b)
			return a.Score > b.Score
		end)
	end
	for s = 1, MAX_LIGHTS do
		local req = requests[s]
		local slot = slots[s]
		if req then
			if not slot then
				slot = newSlot()
				slots[s] = slot
			end
			slot.Part.CFrame = CFrame.new(req.Pos)
			slot.Light.Color = req.Color
			slot.Light.Range = math.min(req.Range, 60)
			slot.Light.Brightness = currentBrightness(req)
			slot.Light.Enabled = true
		elseif slot then
			slot.Light.Enabled = false
		end
	end
end

function LightPool.Count(): number
	return #requests
end

function LightPool.Init()
	folder = Instance.new("Folder")
	folder.Name = "WandLights_Local"
	folder.Parent = workspace
	RunService.RenderStepped:Connect(update)
end

return LightPool

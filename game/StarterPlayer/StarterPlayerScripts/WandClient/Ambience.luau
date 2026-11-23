--[[
	WandClient/Ambience
	Ambiance sombre "façon Noita" : le monde est dans le noir, les SORTS sont la source de lumière.

	• 100 % LOCAL : les réglages de Lighting sont modifiés côté client uniquement, et TOUTES les valeurs
	  d'origine sont mémorisées puis restaurées à la désactivation. Le Lighting de la place n'est jamais touché.
	• Les effets de post-traitement existants (Bloom, SunRays, DepthOfField, ColorCorrection) sont coupés
	  et remplacés par les nôtres : un Bloom à seuil haut qui ne fait briller que les cœurs très chauds
	  (Neon, LightEmission 1), pas les surfaces éclairées.
	• Touche L = activer / désactiver. Ambience.Glow() donne aux VFX un facteur d'intensité adapté.
]]

local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local Ambience = {}

local PRESET = {
	ClockTime = 0,
	Brightness = 0.1,
	Ambient = Color3.fromRGB(10, 9, 16),
	OutdoorAmbient = Color3.fromRGB(16, 14, 26),
	EnvironmentDiffuseScale = 0.1,
	EnvironmentSpecularScale = 0.4,
	ExposureCompensation = 0.3,
	FogColor = Color3.fromRGB(6, 5, 10),
	FogStart = 80,
	FogEnd = 500,
}

local active = false
local saved: { { Instance | string | any } } = {} -- { instance, propriété, valeur d'origine }
local ours: { Instance } = {}
local changed = Instance.new("BindableEvent")
Ambience.Changed = changed.Event

local function set(inst: Instance, prop: string, value: any)
	local target: any = inst
	table.insert(saved, { inst, prop, target[prop] })
	target[prop] = value
end

local function enable()
	for prop, value in PRESET do
		set(Lighting, prop, value)
	end
	for _, fx in Lighting:GetChildren() do
		if fx:IsA("PostEffect") then
			set(fx, "Enabled", false)
		elseif fx:IsA("Atmosphere") then
			set(fx, "Density", 0.3)
			set(fx, "Haze", 0)
			set(fx, "Glare", 0)
			set(fx, "Color", Color3.fromRGB(12, 10, 20))
			set(fx, "Decay", Color3.fromRGB(4, 3, 8))
		elseif fx:IsA("Sky") then
			set(fx, "CelestialBodiesShown", false) -- pas de lune qui éclaire la scène
			set(fx, "MoonAngularSize", 0) -- certains ciels personnalisés l'affichent quand même
			set(fx, "SunAngularSize", 0)
			set(fx, "StarCount", 600)
		end
	end

	-- Bloom à seuil haut : seuls les éléments très lumineux (cœurs de sorts, étincelles Neon) brillent.
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "WandBloom"
	bloom.Threshold = 1.1
	bloom.Intensity = 1.1
	bloom.Size = 22
	bloom.Parent = Lighting
	-- léger contraste / saturation pour des couleurs franches dans le noir
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "WandGrade"
	cc.Contrast = 0.12
	cc.Saturation = 0.2
	cc.Parent = Lighting
	ours = { bloom, cc }
end

local function disable()
	for _, inst in ours do
		inst:Destroy()
	end
	ours = {}
	-- restauration dans l'ordre inverse
	for i = #saved, 1, -1 do
		local entry = saved[i]
		local target: any = entry[1]
		if target.Parent then
			target[entry[2]] = entry[3]
		end
	end
	saved = {}
end

function Ambience.Set(on: boolean)
	if on == active then
		return
	end
	active = on
	if on then
		enable()
	else
		disable()
	end
	changed:Fire(on)
end

function Ambience.IsDark(): boolean
	return active
end

-- Facteur d'intensité des VFX : en plein jour on calme la lumière émise (sinon tout vire au blanc).
function Ambience.Glow(): number
	return if active then 1 else 0.45
end

function Ambience.Init(startDark: boolean?)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.L then
			Ambience.Set(not active)
		end
	end)
	if startDark ~= false then
		Ambience.Set(true)
	end
end

return Ambience

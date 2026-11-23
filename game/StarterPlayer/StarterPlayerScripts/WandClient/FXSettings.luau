--[[
	WandClient/FXSettings — RÉGLAGES DES EFFETS (par joueur, sauvegardés côté serveur)
	  Shake  : secousses / recul de la caméra       (0 | 0.5 | 1 | 1.5)
	  Bloom  : halo lumineux des explosions proches (0 | 0.5 | 1)
	  Screen : couleurs et bords d'écran            (0 | 0.5 | 1)
	Lecture : FXSettings.Get("Shake") ; écriture : FXSettings.Set("Shake", 0.5) (sauvegarde différée).
]]
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FXSettings = {}
FXSettings.Options = {
	{ Key = "Quality", Label = "Qualite effets", Steps = { 0.5, 1, 1.5 }, Names = { "Bas", "Moyen", "Haut" } },
	{ Key = "Shake", Label = "Secousse camera", Steps = { 0, 0.5, 1, 1.5 } },
	{ Key = "Bloom", Label = "Halo explosions", Steps = { 0, 0.5, 1 } },
	{ Key = "Screen", Label = "Effets d'ecran", Steps = { 0, 0.5, 1 } },
}
local UIS = game:GetService("UserInputService")
-- appareil tactile sans clavier (téléphone / tablette) : qualité Basse par défaut
local values = { Quality = if UIS.TouchEnabled and not UIS.KeyboardEnabled then 0.5 else 1, Shake = 1, Bloom = 1, Screen = 1 }
local listeners = {}
local player = Players.LocalPlayer

local function load()
	local raw = player:GetAttribute("FXSettings")
	if type(raw) == "string" then
		local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(t) == "table" then
			for k in values do
				if type(t[k]) == "number" then
					values[k] = math.clamp(t[k], 0, 1.5)
				end
			end
		end
	end
end
load()
player:GetAttributeChangedSignal("FXSettings"):Connect(load)

function FXSettings.Get(key: string): number
	return values[key] or 1
end

local saveScheduled = false
function FXSettings.Set(key: string, v: number)
	if values[key] == nil then
		return
	end
	values[key] = math.clamp(v, 0, 1.5)
	for _, f in listeners do
		task.spawn(f, key, values[key])
	end
	if not saveScheduled then
		saveScheduled = true
		task.delay(0.5, function()
			saveScheduled = false
			local remote = ReplicatedStorage:FindFirstChild("WandSettings")
			if remote then
				remote:FireServer(values)
			end
		end)
	end
end

-- multiplicateur des plafonds d'effets : Bas 0,5 / Moyen 1 / Haut 1,2
function FXSettings.QualityK(): number
	local q = values.Quality or 1
	return if q < 0.75 then 0.5 elseif q > 1.25 then 1.2 else 1
end

function FXSettings.OnChanged(f)
	table.insert(listeners, f)
end

return FXSettings

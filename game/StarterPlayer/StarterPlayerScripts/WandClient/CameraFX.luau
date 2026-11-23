--[[
	WandClient/CameraFX — EFFETS DE CAMÉRA DES SORTS (secousse, recul, vibration, halo)

	• Secousse à « traumatisme » : chaque événement ajoute du traumatisme (cumulable, plafonné à 1) ;
	  l'amplitude vaut traumatisme² et suit un bruit FLUIDE (math.noise), puis retombe seule.
	  Rotation légère + petit déplacement, appliqués APRÈS la caméra Roblox (rien ne s'accumule).
	• Chaque ÉLÉMENT a sa signature (WandShared/Elements/<Élément>.Camera) : fréquence, amplitude, retombée.
	• Distance : forte près de soi, nulle au-delà de la portée ; les tirs des AUTRES secouent moins.
	• Halo (bloom) COURT pour les explosions proches : monte en 0,06 s, retombe en ~0,35 s (pas de flash).
	• Réglages : FXSettings Shake / Bloom.
]]
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FXSettings = require(script.Parent:WaitForChild("FXSettings"))
local Elements = require(ReplicatedStorage:WaitForChild("WandShared"):WaitForChild("Elements"))

local CameraFX = {}
local player = Players.LocalPlayer
local DEFAULT_PROFILE = { Freq = 12, Rot = 0.8, Pos = 0.2, Decay = 1.8 }
local MAX_ROT = math.rad(3) -- jamais plus de 3° : la visée reste précise
local MAX_POS = 0.45
local decayMul = 1 -- (< 1 : grosse explosion -> la secousse dure plus longtemps)

local trauma = 0
local profile = DEFAULT_PROFILE
local holdLevel, holdTarget = 0, 0
local recoil = 0 -- recul (tangage vers le haut), ressort
local seed = math.random() * 100
local bloom: BloomEffect? = nil
local bloomTween: Tween? = nil

local function profileOf(element: string?)
	local def = element and Elements[element]
	return (def and def.Camera) or DEFAULT_PROFILE
end

-- secousse brute (0..1)
function CameraFX.Shake(amount: number, element: string?)
	local mul = FXSettings.Get("Shake")
	if mul <= 0 or amount <= 0 then
		return
	end
	local p = profileOf(element)
	amount *= mul * (p.Amp or 1)
	-- la signature suit l'événement le plus fort du moment
	if amount >= trauma * 0.5 then
		profile = p
	end
	trauma = math.min(1, trauma + amount)
end

-- secousse depuis un point du monde : forte près de la caméra, nulle au-delà de `range`
function CameraFX.ShakeAt(pos: Vector3, amount: number, range: number, element: string?, isOwn: boolean?)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local d = (cam.CFrame.Position - pos).Magnitude
	if d >= range then
		return
	end
	local k = 1 - d / range
	CameraFX.Shake(amount * k * (if isOwn == false then 0.6 else 1), element)
end

-- recul du tir (tangage vers le haut qui revient)
-- RECUL DU TIR, doux et SANS ROTATION (la visée ne bouge pas) :
--   « kick » = la caméra recule un instant le long de son axe de visée puis revient (dolly pur) ;
--   + micro-tremblement en translation, signature de l'élément. amount 0..1 (selon le coût du sort).
local kick, kickVel = 0, 0
local boom, boomVel = 0, 0 -- grosse explosion : la caméra plonge puis rebondit (translation verticale)
function CameraFX.Boom(strength: number)
	local mul = FXSettings.Get("Shake")
	if mul > 0 and strength > 0 then
		boomVel -= math.min(strength, 1.5) * 9 * mul
	end
end
function CameraFX.Recoil(amount: number, element: string?)
	local mul = FXSettings.Get("Shake")
	if mul <= 0 or amount <= 0 then
		return
	end
	kickVel += math.min(amount, 1) * 6 * mul -- impulsion vers l'arrière (studs/s)
	CameraFX.Shake(math.min(amount, 1) * 0.14, element)
end

-- vibration continue (rayon maintenu...) : niveau visé, 0 = arrêt
function CameraFX.Hold(level: number, element: string?)
	holdTarget = 0 -- (désactivé : le joueur ne veut aucun tremblement pendant un rayon maintenu ; vignette noire à la place)
	if level > 0 then
		profile = profileOf(element)
	end
end

-- halo court des explosions proches (strength 0..1)
function CameraFX.Bloom(strength: number)
	local mul = FXSettings.Get("Bloom")
	if not bloom or mul <= 0 or strength <= 0 then
		return
	end
	local peak = math.min(1.6, bloom.Intensity + 1.5 * strength * mul) -- plafonné : un halo, jamais un écran blanc
	if bloomTween then
		bloomTween:Cancel()
	end
	bloom.Intensity = peak
	bloom.Size = 36 + 20 * strength
	bloomTween = TweenService:Create(bloom, TweenInfo.new(0.35 + 0.45 * strength, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Intensity = 0 })
	bloomTween:Play()
end

local function apply(dt: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	holdLevel += (holdTarget * FXSettings.Get("Shake") - holdLevel) * math.min(1, dt * 6)
	local amp = trauma ^ 1.5 + holdLevel * holdLevel
	-- AUCUNE ROTATION : la caméra donne la direction de VISÉE ; seul un léger DÉPLACEMENT (translation)
	-- est appliqué, il ne change pas la direction du curseur (demande du joueur : la visée ne doit jamais bouger)
	if amp > 1e-4 then
		local t = os.clock() * (profile.Freq or 12)
		-- (user 2026-11-23 : secousses plus fortes) amplitude x2, jusqu'à ~1 stud pour une explosion colossale
		local pos = MAX_POS * (profile.Pos or 0.2) / 0.2 * amp * 1.05
		local px = math.noise(seed + 30, t) * pos
		local py = math.noise(seed + 40, t) * pos
		cam.CFrame = cam.CFrame * CFrame.new(px, py, 0)
	end
	-- kick (ressort amorti) : recule puis revient, uniquement le long de l'axe de visée
	if kickVel ~= 0 or kick ~= 0 then
		kickVel += (-kick * 220 - kickVel * 22) * dt
		kick += kickVel * dt
		if math.abs(kick) < 1e-4 and math.abs(kickVel) < 1e-3 then
			kick, kickVel = 0, 0
		end
		cam.CFrame = cam.CFrame * CFrame.new(0, 0, math.clamp(kick, -0.05, 0.45))
	end
	if boomVel ~= 0 or boom ~= 0 then
		boomVel += (-boom * 90 - boomVel * 9) * dt -- ressort lent et lourd
		boom += boomVel * dt
		if math.abs(boom) < 1e-4 and math.abs(boomVel) < 1e-3 then
			boom, boomVel = 0, 0
		end
		cam.CFrame = cam.CFrame * CFrame.new(0, math.clamp(boom, -0.9, 0.6), 0)
	end
	trauma = math.max(0, trauma - dt * (profile.Decay or 1.8) * decayMul)
	if trauma <= 0 then
		decayMul = 1
	end
end

function CameraFX.Init()
	bloom = Instance.new("BloomEffect")
	bloom.Name = "WandBlastBloom" -- séparé du bloom d'ambiance : ne touche jamais au sien
	bloom.Intensity = 0
	bloom.Threshold = 0.8 -- seuls les éléments vraiment lumineux brillent (pas tout l'écran)
	bloom.Size = 40
	bloom.Parent = Lighting
	RunService:BindToRenderStep("WandCameraFX", Enum.RenderPriority.Camera.Value + 1, apply)
end

-- messages FX (mêmes que sons / visuels)
function CameraFX.Handle(msg: { [string]: any })
	local p = if typeof(msg.p) == "Vector3" then msg.p else nil
	if not p then
		return
	end
	local kind = msg.k
	local element = if type(msg.e) == "string" then msg.e else nil
	-- MOUVEMENTS : propulsion céleste (départ / impact au sol) et recul au sol, ressentis autour
	if kind == "Launch" then
		CameraFX.ShakeAt(p, 0.4, 40)
		return
	elseif kind == "Land" then
		local s = tonumber(msg.s) or 100
		CameraFX.ShakeAt(p, math.clamp(s / 180, 0.35, 0.8), 50)
		return
	elseif kind == "Skid" then
		CameraFX.ShakeAt(p, math.clamp((tonumber(msg.s) or 30) / 180, 0.08, 0.35), 25)
		return
	end
	if kind == "Impact" then
		local r = tonumber(msg.r) or 0
		if r > 0 then
			local z = math.clamp(tonumber(msg.z) or 1, 0.5, 5)
			-- PORTÉE proportionnelle au rayon (r = 60 -> ~390 studs) ; décroissance douce (on sent les grosses de loin)
			local range = 25 + r * 6
			local cam0 = workspace.CurrentCamera
			local d0 = if cam0 then (cam0.CFrame.Position - p).Magnitude else 0
			if d0 < range then
				local fall = (1 - d0 / range) ^ 0.6
				CameraFX.Shake(math.clamp(0.4 + r * 0.035, 0.4, 1.4) * math.sqrt(z) * fall, element)
				-- grosse explosion : la secousse s'éternise (grondement), jusqu'à ~3x plus longue
				local big0 = math.clamp((r - 8) / 25, 0, 1)
				decayMul = math.min(decayMul, 1 - 0.65 * big0)
			end
			-- halo court si l'explosion est PROCHE
			local cam = workspace.CurrentCamera
			if cam then
				local d = (cam.CFrame.Position - p).Magnitude
				local near = r * 3 + 12
				if d < near then
					CameraFX.Bloom(math.clamp((1 - d / near) * (0.5 + r / 12) * math.sqrt(z), 0, 1.4))
				end
				-- GROSSE explosion (bombe, Gigantisme...) : coup de boutoir en plus
				local big = (r * math.sqrt(z) - 6) / 10
				if big > 0 and d < range then
					CameraFX.Boom(math.min(1.5, big) * (1 - d / range))
				end
			end
		end
	elseif kind == "Beam" and element == "Lightning" and not msg.h then
		CameraFX.ShakeAt(p, 0.22, 30, "Lightning")
	elseif kind == "GrowStart" then
		local z = math.clamp(tonumber(msg.z) or 1, 0.5, 8)
		if z >= 2 then
			CameraFX.ShakeAt(p, 0.1 * z, 25 + z * 5, "Nature") -- grosse croissance : grondement lourd
		end
	end
end

return CameraFX

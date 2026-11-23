--[[
	WandServer/Dummies
	Mannequins d'entraînement (R15 par défaut) pour tester dégâts, homing, perforation et explosions.
	Réapparaissent 3 s après leur mort. À supprimer / remplacer par tes ennemis plus tard.
]]

local Players = game:GetService("Players")

local Dummies = {}

local SPOTS = {
	Vector3.new(-16, 4, -38),
	Vector3.new(-5, 4, -46),
	Vector3.new(6, 4, -46),
	Vector3.new(17, 4, -38),
	Vector3.new(0, 4, -76),
}
local SKIN = Color3.fromHex("8a7fa3")
local TORSO = Color3.fromHex("4a3f63")

local folder: Folder

-- PERF : le corps R15 n'est construit QU'UNE FOIS (CreateHumanoidModelFromDescription est lent : il
-- assemble et charge tout le rig). Ensuite chaque réapparition = un simple Clone() du modèle de référence,
-- préparé pendant les 3 s d'attente : au moment du respawn il ne reste qu'à le poser dans le monde.
local template: Model? = nil

local function buildTemplate(): Model?
	if template then
		return template
	end
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = SKIN
		desc.LeftArmColor = SKIN
		desc.RightArmColor = SKIN
		desc.TorsoColor = TORSO
		desc.LeftLegColor = TORSO
		desc.RightLegColor = TORSO
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[Wand] mannequin impossible :", model)
		return nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.MaxHealth = 250
	hum.Health = 250
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	-- rangé DANS le DataModel : hors DataModel, le 1er clone posé dans le monde chargeait ses données
	-- d'un coup (pic de ~250 ms mesuré au 1er respawn) ; ici ce chargement se fait au démarrage
	-- ALLÉGEMENT : un mannequin immobile n'a pas besoin du script d'animation (un LocalScript ne tourne
	-- de toute façon pas hors d'un personnage joueur) ni du visage animé / des points de vêtements
	-- -> ~80 instances de moins à répliquer à chaque réapparition
	for _, d in model:GetDescendants() do
		if d:IsA("LocalScript") or d:IsA("FaceControls") or d:IsA("WrapTarget") then
			d:Destroy()
		end
	end
	model.Name = "MannequinTemplate"
	model.Parent = game:GetService("ServerStorage")
	template = model
	-- PRÉCHAUFFAGE : la 1re suppression d'un humanoïde dans la partie coûte ~240 ms au moteur (mesuré,
	-- côté serveur ET client). On la fait ici, pendant le chargement, sous la carte.
	local warm = model:Clone()
	warm:PivotTo(CFrame.new(0, -400, 0))
	warm.Parent = workspace
	task.delay(0.5, function()
		warm:Destroy()
	end)
	return model
end

local function spawnDummy(index: number, pos: Vector3, prepared: Model?)
	local model = prepared
	if not model then
		local t = buildTemplate()
		if not t then
			return
		end
		model = t:Clone()
	end
	model.Name = "Mannequin" .. index
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	model:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1)))
	model.Parent = folder
	hum.Died:Connect(function()
		-- le remplaçant est cloné TOUT DE SUITE (hors du monde), pendant que le corps tombe
		local nextModel = template and template:Clone()
		task.delay(3, function()
			model:Destroy()
			spawnDummy(index, pos, nextModel)
		end)
	end)
end

function Dummies.Start()
	folder = workspace:FindFirstChild("WandDummies") or Instance.new("Folder")
	folder.Name = "WandDummies"
	folder.Parent = workspace
	task.spawn(function()
		buildTemplate() -- une seule construction, puis 5 clones
		for i, pos in SPOTS do
			spawnDummy(i, pos)
		end
	end)
end

return Dummies

--[[
	WandClient/Slippery — LA GLACE ET LE GIVRE SONT GLISSANTS (personnage du joueur local)

	Sur une surface gelée, le personnage DÉRAPE : il garde son élan, accélère et freine lentement, tourne mal.
	Surfaces gelées :
	  • sol givré laissé par un sort de glace (marqueur de zone Patch d'élément Ice, posé au sol) ;
	  • murs / blocs de glace des sorts (workspace.WandIceWalls) ;
	  • toute matière de glace de la map (Enum.Material Ice / Glacier).
	La physique du personnage appartient au client : la glissade est donc calculée ici (aucun aller-retour).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Sparks = require(script.Parent:WaitForChild("Sparks"))
local SoundFX = require(script.Parent:WaitForChild("SoundFX"))
local Slippery = {}
local SHAVINGS = { Colors = { Color3.new(1, 1, 1), Color3.fromHex("d8f8ff"), Color3.fromHex("8fe3ff") }, Gravity = 1.2, Drag = 1.5, Bounce = 0.3, Life = NumberRange.new(0.25, 0.5), Size = 0.1 }
local scrape = nil -- boucle de crissement pendant la glissade
local fxAcc = 0
local player = Players.LocalPlayer
local GRIP = 1.15 -- vitesse à laquelle on rejoint la direction voulue sur la glace (bas = glisse beaucoup)
local FRICTION = 0.2 -- freinage naturel sans appui (par seconde)
local ICE_MATERIALS = { [Enum.Material.Ice] = true, [Enum.Material.Glacier] = true }

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local slide: Vector3? = nil -- vitesse horizontale conservée sur la glace
local onIce = false

local function standingOnIce(root: BasePart, hum: Humanoid): boolean
	local ignore = { player.Character }
	for _, name in { "WandFX_Local", "WandSparks_Local", "WandProjectiles", "WandZoneMarkers" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	params.FilterDescendantsInstances = ignore
	-- hauteur des jambes : HipHeight vaut 0 en R6 (jambes de 2) -> sinon le rayon s'arrêtait AVANT le sol
	local legs = if hum.RigType == Enum.HumanoidRigType.R6 then 2 else hum.HipHeight
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -(legs + root.Size.Y / 2 + 1.2), 0), params)
	if not hit then
		return false
	end
	if ICE_MATERIALS[hit.Material] then
		return true
	end
	local walls = workspace:FindFirstChild("WandIceWalls")
	if walls and hit.Instance:IsDescendantOf(walls) then
		return true
	end
	-- sol givré par un sort (zone Patch de glace, posée au sol)
	local markers = workspace:FindFirstChild("WandZoneMarkers")
	if markers then
		for _, m in markers:GetChildren() do
			if m.Name == "Patch" and m:GetAttribute("Element") == "Ice" then
				-- le givre couvre toutes les surfaces autour de l'impact (sol au pied d'un mur compris)
				local r = (m:GetAttribute("Radius") or 4) * 0.95
				-- traînée (TF) : petits morceaux espacés de ~3 studs -> rayon élargi pour que la LIGNE entière glisse
				if m:GetAttribute("Trail") then
					r = math.max(r, 2.6)
				end
				-- distance HORIZONTALE (le marqueur peut être un peu au-dessus du sol), hauteur tolérée à part
				local flat = Vector3.new(hit.Position.X - m.Position.X, 0, hit.Position.Z - m.Position.Z).Magnitude
				if flat < r and math.abs(hit.Position.Y - m.Position.Y) < 4 and hit.Normal.Y > 0.6 then
					return true
				end
			end
		end
	end
	return false
end

-- contrainte de vitesse HORIZONTALE (plan XZ) : sur la glace elle impose la vitesse de glissade au
-- contrôleur du Humanoid (qui sinon freine net) ; désactivée hors de la glace. Le saut / la chute restent libres.
local lv: LinearVelocity? = nil
local function constraintFor(root: BasePart): LinearVelocity
	if lv and lv.Parent and lv.Attachment0 and lv.Attachment0.Parent == root then
		return lv
	end
	local att = root:FindFirstChild("WandSlideAttachment") or Instance.new("Attachment")
	att.Name = "WandSlideAttachment"
	att.Parent = root
	local c = Instance.new("LinearVelocity")
	c.Name = "WandSlide"
	c.Attachment0 = att
	c.RelativeTo = Enum.ActuatorRelativeTo.World
	c.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	c.PrimaryTangentAxis = Vector3.xAxis
	c.SecondaryTangentAxis = Vector3.zAxis
	c.MaxForce = 60000
	c.Enabled = false
	c.Parent = root
	lv = c
	return c
end

local acc = 0
local function step(dt: number)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (hum and root and hum.Health > 0) then
		slide = nil
		return
	end
	acc += dt
	if acc >= 0.1 then -- détection 10 fois/s suffit
		acc = 0
		local grounded = hum.FloorMaterial ~= Enum.Material.Air
		onIce = grounded and standingOnIce(root, hum)
		player:SetAttribute("OnIce", onIce)
	end
	local c = constraintFor(root)
	if not onIce then
		slide = nil
		c.Enabled = false
		if scrape then
			scrape.Stop()
			scrape = nil
		end
		return
	end
	if not slide then
		local v = root.AssemblyLinearVelocity
		slide = Vector3.new(v.X, 0, v.Z) -- on garde l'élan avec lequel on arrive sur la glace
	end
	local want = hum.MoveDirection * hum.WalkSpeed
	if want.Magnitude > 0.1 then
		-- on rejoint la direction voulue LENTEMENT (dérapage, virages larges)
		slide += (want - slide) * math.min(1, dt * GRIP)
	else
		-- sans appui : on continue de glisser, freinage très faible
		slide *= math.max(0, 1 - dt * FRICTION)
	end
	if slide.Magnitude > hum.WalkSpeed * 1.9 then
		slide = slide.Unit * hum.WalkSpeed * 1.9
	end
	c.PlaneVelocity = Vector2.new(slide.X, slide.Z)
	c.Enabled = true
	-- RETOURS de la glissade : éclats de givre aux pieds + crissement de glace, selon la vitesse
	local speed = slide.Magnitude
	local feet = root.Position - Vector3.new(0, hum.HipHeight + root.Size.Y / 2 - 0.1, 0)
	if speed > 6 then
		fxAcc += dt * speed * 1.2
		while fxAcc >= 1 do
			fxAcc -= 1
			local back = -slide.Unit
			Sparks.Emit(feet + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.8,
				back * (speed * 0.15) + Vector3.new(0, 2 + math.random() * 2, 0), SHAVINGS)
		end
		if not scrape then
			scrape = SoundFX.PointLoop("Loop.FrostCrackle", feet)
		end
		if scrape then
			scrape.Move(feet)
		end
	elseif scrape then
		scrape.Stop()
		scrape = nil
	end
end

function Slippery.Init()
	RunService.Heartbeat:Connect(step)
end

return Slippery

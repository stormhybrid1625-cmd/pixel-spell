--[[
	WandServer/SpellEngine — Exécution serveur des tirs

	1. PLAN : délégué à WandShared.SpellPlanner (fonction pure, bornée par les garde-fous).
	   Le client utilise le même module pour son aperçu, mais le serveur recalcule TOUJOURS le sien.
	2. EXECUTE : instancie les projectiles du nœud racine. Les charges des triggers sont exécutées
	   plus tard par ProjectileService (impact / minuterie / expiration) via OnPayload.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("WandShared")
local Config = require(Shared.Config)
local Planner = require(Shared.SpellPlanner)

local Limits = Config.Limits

local SpellEngine = {}

SpellEngine.Plan = Planner.Plan
SpellEngine.Resolve = Planner.Resolve
SpellEngine.Cost = Planner.Cost
SpellEngine.Delay = Planner.Delay

local ProjectileService = nil
local rng = Random.new()

-- Direction dans un cône : éventail régulier quand il y a plusieurs tirs + légère variation aléatoire.
local function spreadDirection(dir: Vector3, spreadDeg: number, index: number, count: number): Vector3
	local yaw
	if count > 1 then
		yaw = (-0.5 + (index - 1) / (count - 1)) * spreadDeg + rng:NextNumber(-0.1, 0.1) * spreadDeg
	else
		yaw = rng:NextNumber(-0.5, 0.5) * spreadDeg
	end
	local pitch = rng:NextNumber(-0.5, 0.5) * spreadDeg * 0.3
	local up = if math.abs(dir.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	local cf = CFrame.lookAt(Vector3.zero, dir, up) * CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)
	return cf.LookVector
end

-- Formations : remplacent l'éventail classique.
--   Circle : tirs répartis sur 360° autour de l'axe vertical, à partir de la direction visée.
--   Behind : un tir sur deux part dans la direction opposée.
local function formationDirection(formation: string, dir: Vector3, index: number, count: number): Vector3?
	if formation == "Circle" then
		local angle = (index - 1) / math.max(count, 1) * math.pi * 2
		return (CFrame.Angles(0, angle, 0) * CFrame.lookAt(Vector3.zero, dir)).LookVector
	elseif formation == "Behind" then
		return if index % 2 == 0 then -dir else dir
	end
	return nil
end

-- Lance tous les tirs d'un nœud (racine OU charge de trigger). Les copies (Divide / Copies)
-- sont réparties dans l'éventail comme des tirs à part entière.
-- reach : distance jusqu'au point visé (racine seulement) ; les tirs instantanés vont au moins jusque-là.
function SpellEngine.ExecuteNode(node: Planner.CastNode, origin: Vector3, dir: Vector3, owner: Player?, wand: Config.WandStats, depth: number, reach: number?)
	if depth > Limits.MaxDepth + 1 then
		return -- double sécurité (le plan est déjà borné)
	end
	local total = 0
	for _, shot in node.Shots do
		total += shot.Copies
	end
	-- incantation relâchée tôt : chaque tir garde l'angle qu'il aurait eu dans la formation COMPLÈTE
	local formTotal = node.FormationTotal or total
	local index = 0
	for _, shot in node.Shots do
		local stats = Planner.Resolve(shot, wand)
		local spread = wand.SpreadDeg + node.Spread + shot.Card.Proj.Spread + shot.State.SpreadAdd
		for _ = 1, shot.Copies do
			index += 1
			local d = node.Formation and formationDirection(node.Formation, dir, index, formTotal)
			if (stats.Instant or stats.Trap) and total == 1 then
				-- tir instantané seul (rayon, éclair) : aucune dispersion, il part EXACTEMENT vers le curseur
				d = dir
			elseif d then
				d = spreadDirection(d, wand.SpreadDeg, 1, 1) -- légère dispersion naturelle
			else
				d = spreadDirection(dir, spread, index, total)
			end
			ProjectileService.Spawn(owner, stats, origin, d, shot.Payload, depth, wand, reach)
		end
	end
end

function SpellEngine.Execute(plan: Planner.Plan, origin: Vector3, dir: Vector3, owner: Player?, wand: Config.WandStats, aim: Vector3?)
	local reach = if aim then (aim - origin).Magnitude + 1 else nil
	SpellEngine.ExecuteNode(plan.Root, origin, dir, owner, wand, 0, reach)
end

-- Injection de dépendance (évite un require circulaire Engine <-> ProjectileService).
function SpellEngine.Bind(projectileService)
	ProjectileService = projectileService
	projectileService.OnPayload = function(payload, origin: Vector3, dir: Vector3, owner: Player?, wand, depth: number)
		SpellEngine.ExecuteNode(payload, origin, dir, owner, wand, depth)
	end
end

return SpellEngine

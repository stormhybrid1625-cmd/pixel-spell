-- MagicCirclePreview — STUDIO ONLY dev preview of magic circles (removed/ignored in live games)
-- K : 3 cercles empilés au point de départ du sort (devant toi, face à la visée)
-- J : formation cercle — 6 cercles autour de toi, chacun là où un tir partirait
-- (l'élément change à chaque appui)
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local MC = require(script.Parent:WaitForChild("WandClient"):WaitForChild("MagicCircle"))
local mouse = player:GetMouse()
local ELS = { "Fire", "Ice", "Lightning", "Nature", "Toxic", "Arcane", "Chaos", "Steel", "Neutral" }
local idx = 0
local busy = false

-- same rule as the server (WandServer.originFor) until wands get a Muzzle attachment
local function origin()
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local head = root.Position + Vector3.new(0, 1.5, 0)
	local dir = mouse.Hit.Position - head
	dir = if dir.Magnitude > 1 then dir.Unit else root.CFrame.LookVector
	return head + dir * 2.5, dir, head
end

local function run(circles)
	local t = 0
	while t < 3 do
		t += RunService.RenderStepped:Wait()
		for i, c in circles do c:SetProgress(math.clamp(t / 3 * #circles - (i - 1), 0, 1)) end -- one after another
	end
	task.wait(0.8)
	for _, c in circles do c:Release() end
end

UIS.InputBegan:Connect(function(input, gp)
	if gp or busy then return end
	if input.KeyCode ~= Enum.KeyCode.K and input.KeyCode ~= Enum.KeyCode.J then return end
	if not origin() then return end
	busy = true
	idx = idx % #ELS + 1
	local el = ELS[idx]
	local circles = {}
	if input.KeyCode == Enum.KeyCode.K then
		for i = 1, 3 do
			circles[i] = MC.new({ Element = el, Size = 3 + i * 0.9, Origin = function()
				local p, d = origin()
				if not p then return nil end
				return p + d * (i - 1) * 1.4, d
			end })
		end
	else
		for i = 1, 6 do
			circles[i] = MC.new({ Element = el, Size = 3.2, Origin = function()
				local _, d, head = origin()
				if not head then return nil end
				local flat = Vector3.new(d.X, 0, d.Z)
				flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
				local dd = CFrame.Angles(0, (i - 1) * math.pi / 3, 0):VectorToWorldSpace(flat)
				return head + dd * 3.3, dd
			end })
		end
	end
	task.spawn(function()
		local ok, err = pcall(run, circles)
		if not ok then warn("[MagicCirclePreview]", err) end
		busy = false
	end)
end)

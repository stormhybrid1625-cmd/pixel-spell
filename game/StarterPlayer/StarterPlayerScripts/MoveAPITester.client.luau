-- MoveAPITester — STUDIO ONLY: test the movement API on yourself (aim with the mouse).
--   1-4 Kick (as if the aimed point hit you): 30 / 60 = recul au sol, 100 / 160 = propulsion céleste
--   5 Téléporter au point visé (refusé dans un mur / le terrain)   6 Échanger avec la cible visée
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local rem = game:GetService("ReplicatedStorage"):WaitForChild("WandShared"):WaitForChild("Remotes"):WaitForChild("MoveAPITest", 30)
if not rem then return end
local mouse = player:GetMouse()

local OPS = {
	[Enum.KeyCode.One] = { "Kick", "1  Kick 30  (recul au sol)", 30 },
	[Enum.KeyCode.Two] = { "Kick", "2  Kick 60  (recul au sol, fort)", 60 },
	[Enum.KeyCode.Three] = { "Kick", "3  Kick 100 (propulsion céleste)", 100 },
	[Enum.KeyCode.Four] = { "Kick", "4  Kick 160 (céleste, maximum)", 160 },
	[Enum.KeyCode.Five] = { "Teleport", "5  Téléporter au point visé" },
	[Enum.KeyCode.Six] = { "Swap", "6  Échanger avec la cible visée" },
}

local gui = Instance.new("ScreenGui")
gui.Name = "MoveAPITester"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local panel = Instance.new("TextLabel")
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 12, 0.45, 0)
panel.Size = UDim2.fromOffset(320, 150)
panel.BackgroundColor3 = Color3.fromRGB(20, 18, 30)
panel.BackgroundTransparency = 0.15
panel.TextColor3 = Color3.fromRGB(230, 225, 245)
panel.Font = Enum.Font.Code
panel.TextSize = 14
panel.TextXAlignment = Enum.TextXAlignment.Left
panel.TextYAlignment = Enum.TextYAlignment.Top
local lines = { "TEST API DÉPLACEMENT (Studio)" }
for _, k in { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six } do
	table.insert(lines, OPS[k][2])
end
panel.Text = "  " .. table.concat(lines, "\n  ")
panel.Parent = gui
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 8)
pad.Parent = panel
local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0, 0)
toast.Position = UDim2.new(0, 12, 0.45, 82)
toast.Size = UDim2.fromOffset(300, 28)
toast.BackgroundTransparency = 1
toast.TextColor3 = Color3.fromRGB(255, 220, 130)
toast.Font = Enum.Font.Code
toast.TextSize = 14
toast.TextXAlignment = Enum.TextXAlignment.Left
toast.TextWrapped = true
toast.Text = ""
toast.Parent = gui

UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	local op = OPS[input.KeyCode]
	if op then rem:FireServer(op[1], mouse.Hit.Position, op[3]) end
end)
rem.OnClientEvent:Connect(function(msg)
	toast.Text = tostring(msg)
	local t = os.clock()
	task.delay(3, function() if os.clock() - t >= 2.9 then toast.Text = "" end end)
end)

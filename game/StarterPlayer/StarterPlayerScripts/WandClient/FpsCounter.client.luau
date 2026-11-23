--[[
	WandClient/FpsCounter — petit compteur d'images par seconde en haut à gauche (sous la barre Roblox).
	Moyenne sur 0,5 s ; couleur : vert >= 50, jaune >= 30, rouge en dessous.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local gui = Instance.new("ScreenGui")
gui.Name = "FpsCounter"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.IgnoreGuiInset = false -- sous la barre du haut de Roblox (ne recouvre pas ses boutons)

local label = Instance.new("TextLabel")
label.BackgroundColor3 = Color3.fromRGB(12, 10, 20)
label.BackgroundTransparency = 0.35
label.BorderSizePixel = 0
label.Position = UDim2.fromOffset(8, 6)
label.Size = UDim2.fromOffset(64, 18)
label.Font = Enum.Font.Code
label.TextSize = 14
label.TextColor3 = Color3.fromRGB(120, 255, 140)
label.Text = "-- FPS"
label.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 3)
corner.Parent = label
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local frames, acc = 0, 0
RunService.RenderStepped:Connect(function(dt)
	frames += 1
	acc += dt
	if acc >= 0.5 then
		local fps = math.floor(frames / acc + 0.5)
		frames, acc = 0, 0
		label.Text = fps .. " FPS"
		label.TextColor3 = if fps >= 50 then Color3.fromRGB(120, 255, 140)
			elseif fps >= 30 then Color3.fromRGB(255, 220, 90)
			else Color3.fromRGB(255, 90, 90)
	end
end)

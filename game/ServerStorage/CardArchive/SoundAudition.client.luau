-- SoundAudition — STUDIO ONLY : écoute des candidats de son de DASH (touches Z X C V B N M , .)
-- Volumes ÉGALISÉS (niveau mesuré au chargement). Maj + touche = version plus grave.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

local C = {
	{ Key = Enum.KeyCode.Z, Name = "Side Dash", Id = 136880713327520, Peak = 9234 },
	{ Key = Enum.KeyCode.X, Name = "Dash Wind Burst", Id = 119573908217733, Peak = 45914 },
	{ Key = Enum.KeyCode.C, Name = "Speed woosh (tissu)", Id = 79833203443837, Peak = 43862 },
	{ Key = Enum.KeyCode.V, Name = "Speed burst (tissu)", Id = 137322083927464, Peak = 44467 },
	{ Key = Enum.KeyCode.B, Name = "Dash 1", Id = 123389986399408, Peak = 35602 },
	{ Key = Enum.KeyCode.N, Name = "Woosh rapide / rafale", Id = 74818885604525, Peak = 39171 },
	{ Key = Enum.KeyCode.M, Name = "dash8", Id = 6128977275, Peak = 4401 },
	{ Key = Enum.KeyCode.Comma, Name = "dash sfx", Id = 133755966655233, Peak = 24513 },
	{ Key = Enum.KeyCode.Period, Name = "Passage rapide aérien (PSE)", Id = 9114374049, Peak = 16091 },
}

local gui = Instance.new("ScreenGui")
gui.Name = "SoundAudition"
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local lab = Instance.new("TextLabel")
lab.Size = UDim2.fromOffset(330, 40 + #C * 18)
lab.Position = UDim2.new(1, -342, 0, 110)
lab.BackgroundColor3 = Color3.fromRGB(20, 18, 28)
lab.BackgroundTransparency = 0.15
lab.TextColor3 = Color3.new(1, 1, 1)
lab.Font = Enum.Font.Code
lab.TextSize = 13
lab.TextXAlignment = Enum.TextXAlignment.Left
lab.TextYAlignment = Enum.TextYAlignment.Top
local lines = { "ÉCOUTE SON DE DASH (Studio)", "Maj + touche = plus grave" }
for _, c in C do
	table.insert(lines, ("%s  %s"):format(UIS:GetStringForKeyCode(c.Key), c.Name))
end
lab.Text = "  " .. table.concat(lines, "\n  ")
lab.Parent = gui

local current
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	for _, c in C do
		if input.KeyCode == c.Key then
			if current then current:Destroy() end
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. c.Id
			s.Volume = math.clamp(0.8 * 30000 / (c.Peak or 30000), 0.3, 3)
			s.PlaybackSpeed = if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then 0.8 else 1
			s.Parent = workspace.CurrentCamera
			s:Play()
			current = s
			task.delay(6, function() s:Destroy() end)
		end
	end
end)

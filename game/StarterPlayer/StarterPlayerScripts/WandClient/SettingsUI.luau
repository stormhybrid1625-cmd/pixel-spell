--[[
	WandClient/SettingsUI — PANNEAU DE RÉGLAGES (bouton « REGLAGES » en haut à droite, touche O)
	Une ligne par option de FXSettings (secousse caméra, halo des explosions, effets d'écran),
	chaque palier est un bouton ; le palier actif est surligné. Sauvegarde automatique (serveur).
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Theme = require(script.Parent:WaitForChild("Theme"))
local FXSettings = require(script.Parent:WaitForChild("FXSettings"))

local SettingsUI = {}
local C = Theme.C
local panel: Frame
local stepButtons = {}

local function pct(v: number): string
	return math.floor(v * 100 + 0.5) .. "%"
end

local function refresh()
	for key, list in stepButtons do
		local cur = FXSettings.Get(key)
		for _, b in list do
			local on = math.abs(b.Value - cur) < 1e-3
			b.Button.BackgroundColor3 = if on then C.Gold else C.BG3
			b.Button.TextColor3 = if on then C.BG0 else C.Text
		end
	end
end

local function makeButton(parent, text: string, size: UDim2, pos: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = C.BG3
	b.FontFace = Theme.Font
	b.TextSize = Theme.Small
	b.TextColor3 = C.Text
	b.Text = Theme.Txt(text)
	b.Size = size
	b.Position = pos
	b.Parent = parent
	Theme.Stroke(b, C.Line, 2)
	return b
end

function SettingsUI.Toggle(force: boolean?)
	panel.Visible = if force ~= nil then force else not panel.Visible
	refresh()
end

function SettingsUI.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WandSettingsGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- bouton d'ouverture
	local open = makeButton(gui, "Reglages", UDim2.fromOffset(110, 28), UDim2.new(1, -122, 0, 12))
	open.MouseButton1Click:Connect(function()
		SettingsUI.Toggle()
	end)

	local rowH, n = 46, #FXSettings.Options
	local root, body = Theme.Panel(gui, "Settings", UDim2.fromOffset(440, 74 + n * rowH), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel = root
	panel.Visible = false
	local title = Theme.Label(body, "Reglages des effets", Theme.Big, C.Gold, Enum.TextXAlignment.Left)
	title.Position = UDim2.fromOffset(16, 16)
	local close = makeButton(body, "X", UDim2.fromOffset(28, 28), UDim2.new(1, -40, 0, 10))
	close.MouseButton1Click:Connect(function()
		SettingsUI.Toggle(false)
	end)

	for i, opt in FXSettings.Options do
		local y = 52 + (i - 1) * rowH
		local lab = Theme.Label(body, opt.Label, Theme.Small, C.Text, Enum.TextXAlignment.Left)
		lab.Position = UDim2.fromOffset(16, y + 10)
		lab.Size = UDim2.fromOffset(170, Theme.Small)
		stepButtons[opt.Key] = {}
		for k, v in opt.Steps do
			local b = makeButton(body, if opt.Names then opt.Names[k] else pct(v), UDim2.fromOffset(52, 28), UDim2.fromOffset(186 + (k - 1) * 60, y))
			table.insert(stepButtons[opt.Key], { Button = b, Value = v })
			b.MouseButton1Click:Connect(function()
				FXSettings.Set(opt.Key, v)
				refresh()
			end)
		end
	end
	FXSettings.OnChanged(refresh)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.O then
			SettingsUI.Toggle()
		end
	end)
end

return SettingsUI

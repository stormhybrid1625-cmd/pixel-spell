--[[
	WandClient/Theme
	Charte pixel art + petites fabriques d'objets GUI.
	Règles : aplats uniquement (pas de UICorner, pas de UIGradient), bordures UIStroke 1-2 px
	en LineJoinMode.Miter (angles vifs), tailles et positions en pixels entiers, police Press Start 2P
	à 8 ou 16 px (multiples de sa grille native = texte net).
]]

local Theme = {}
local hex = Color3.fromHex

Theme.Font = Font.new("rbxasset://fonts/families/PressStart2P.json") -- titres / glyphes (pixel, sans accents)
-- Texte long (infobulles) : monospace net et lisible, garde les accents français.
Theme.Body = Font.new("rbxasset://fonts/families/BuilderMono.json", Enum.FontWeight.Bold)
Theme.Small = 8
Theme.Big = 16

Theme.C = {
	BG0 = hex("07060c"), -- ombre portée
	BG1 = hex("15111e"), -- fond de panneau
	BG2 = hex("1f192b"), -- fond de slot
	BG3 = hex("2b2339"), -- fond de carte
	Bevel = hex("2e2640"), -- liseré haut des panneaux
	Line = hex("3f3554"),
	LineHi = hex("8a78b8"),
	Gold = hex("f2c14e"),
	Text = hex("ece6f7"),
	Dim = hex("8a7fa3"),
	Mana = hex("3fa2ff"),
	ManaDark = hex("0f2742"),
	Delay = hex("c9c2d9"),
	Danger = hex("e0483f"),
}

Theme.TypeColor = {
	Projectile = hex("d65a4a"),
	Modifier = hex("4a8ad6"),
	Multicast = hex("d6b44a"),
	Trigger = hex("b65ad6"),
}
Theme.TypeLabel = {
	Projectile = "Projectile",
	Modifier = "Modificateur",
	Multicast = "Multicast",
	Trigger = "Déclencheur",
}
Theme.TriggerBadge = { Hit = "T", Timer = "M", Expire = "X", Trap = "P" }
Theme.TriggerLabel = { Hit = "à l'impact", Timer = "minuterie", Expire = "à expiration", Trap = "piège" }

-- La police pixel n'a pas d'accents : on les retire et on passe en MAJUSCULES (look rétro).
local ACCENTS = {
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["à"] = "a", ["â"] = "a", ["ç"] = "c",
	["î"] = "i", ["ï"] = "i", ["ô"] = "o", ["ù"] = "u", ["û"] = "u", ["É"] = "E", ["È"] = "E", ["À"] = "A",
	["Ç"] = "C", ["Î"] = "I", ["Ô"] = "O", ["’"] = "'",
}
function Theme.Txt(s: string): string
	local out = s:gsub(utf8.charpattern, function(ch)
		if #ch == 1 then
			return ch
		end
		return ACCENTS[ch] or "?"
	end)
	return string.upper(out)
end

function Theme.Stroke(parent: GuiObject, color: Color3, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Theme.Frame(parent: Instance?, name: string, size: UDim2, pos: UDim2?, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos or UDim2.new()
	f.BorderSizePixel = 0
	if color then
		f.BackgroundColor3 = color
	else
		f.BackgroundTransparency = 1
	end
	f.Parent = parent
	return f
end

function Theme.Label(parent: Instance?, text: string, size: number, color: Color3, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = Theme.Font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = Theme.Txt(text)
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Size = UDim2.new(1, 0, 0, size)
	l.Parent = parent
	return l
end

--[[
	Panneau rétro : ombre portée dure (décalage 4 px) + corps avec bordure 2 px + liseré haut.
	Retourne (racine, corps). Les enfants se placent dans `corps`.
]]
function Theme.Panel(parent: Instance, name: string, size: UDim2, pos: UDim2, anchor: Vector2?): (Frame, Frame)
	local root = Theme.Frame(parent, name, size, pos)
	root.AnchorPoint = anchor or Vector2.zero
	Theme.Frame(root, "Shadow", UDim2.fromScale(1, 1), UDim2.fromOffset(4, 4), Theme.C.BG0)
	local body = Theme.Frame(root, "Body", UDim2.fromScale(1, 1), UDim2.new(), Theme.C.BG1)
	body.Active = true -- absorbe les clics (pas de tir à travers l'UI)
	Theme.Stroke(body, Theme.C.Line, 2)
	Theme.Frame(body, "Bevel", UDim2.new(1, 0, 0, 2), UDim2.new(), Theme.C.Bevel)
	return root, body
end

return Theme

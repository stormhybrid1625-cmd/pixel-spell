--[[
	WandClient/WandUI
	Baguette (slots horizontaux, lus de gauche à droite) + Grimoire (toutes les cartes), en pixel art.

	Déplacement des cartes — une seule machine d'état pour deux styles d'interaction :
	  • GLISSER-DÉPOSER : appuyer sur une carte, déplacer (> 6 px), relâcher sur un slot.
	  • CLIC-CLIC       : cliquer une carte (elle reste "en main"), puis cliquer un slot.
	  Poser sur un slot occupé = échange. Poser sur le grimoire = retirer. Clic dans le vide / Échap = annuler.
	  Clic droit sur un slot = le vider.

	Le test de survol est géométrique (AbsolutePosition/Size). Attention : GetMouseLocation() est en
	coordonnées "viewport" (barre du haut Roblox INCLUSE) alors que AbsolutePosition ne l'inclut pas toujours.
	mousePos() convertit donc la souris dans l'espace du ScreenGui (voir plus bas).
	Le client n'est qu'une vue : chaque changement est PROPOSÉ au serveur (OnDeckChanged), qui renvoie le deck officiel.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("WandShared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("SpellCatalog"))
local Planner = require(Shared:WaitForChild("SpellPlanner")) -- même lecture de deck que le serveur (aperçu exact)
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundFX = require(script.Parent:WaitForChild("SoundFX"))
local C = Theme.C

local player = Players.LocalPlayer

local SLOT = 48 -- taille d'un slot (px)
local GAP = 4
local PAD = 10
local SLOTS_Y = 62 -- ordonnée de la rangée de slots dans la baguette
local DRAG_THRESHOLD = 6
local TIP_W = 360 -- largeur de l'infobulle (px)
local PREVIEW_W = 330 -- largeur du panneau "Prochain clic"
local PREVIEW_MAX_LINES = 18
local PLACEHOLDER = Config.Textures.Placeholder

type Held = { Id: string, From: "slot" | "lib", Index: number? }

local WandUI = {}

local ui: { [string]: any } = {}
local slotFrames: { Frame } = {}
local slotStrokes: { UIStroke } = {}
local slotMarks: { Frame } = {} -- marque dorée sous chaque slot lu par le prochain clic
local renderPreview: () -> () -- définie plus bas (après les utilitaires d'infobulle)
local previewCost = 0
local libCells: { [string]: Frame } = {}
local state = {
	Deck = {} :: { string },
	Wand = Config.DefaultWand,
	Open = false,
	Held = nil :: Held?,
	Press = nil :: { Pos: Vector2, Dragging: boolean }?,
	NoManaUntil = 0,
	TooltipId = nil :: string?,
}
local callbacks = { OnDeckChanged = function(_deck: { string }) end }

local GuiService = game:GetService("GuiService")

-- Souris dans le même repère que AbsolutePosition des slots / cartes.
-- GetMouseLocation() compte depuis le haut de la fenêtre (barre Roblox incluse), alors que
-- AbsolutePosition compte toujours depuis SOUS la barre (même avec IgnoreGuiInset) : on retire l'inset.
local function mousePos(): Vector2
	return UserInputService.GetMouseLocation(UserInputService) - GuiService:GetGuiInset()
end

-- ── Tuile de carte ────────────────────────────────────────────────────────────────────────
local function badgeFor(card): string?
	if card.Type == "Modifier" then
		return "+"
	elseif card.Type == "Trigger" then
		return Theme.TriggerBadge[card.Trigger.Kind]
	end
	return nil
end

local function makeTile(parent: GuiObject, id: string): Frame?
	local card, count = Catalog.ParseSlot(id) -- "ID" ou "ID*N" (modificateur empilé)
	if not card then
		return nil
	end
	local inner = SLOT - 8
	local tile = Theme.Frame(nil, "Tile", UDim2.fromOffset(inner, inner), UDim2.fromOffset(4, 4), C.BG3)
	Theme.Stroke(tile, Theme.TypeColor[card.Type], 2)

	local element = card.Element and Config.Elements[card.Element]
	if card.Icon ~= PLACEHOLDER and card.Icon ~= "" then
		-- icône 16 px agrandie d'un facteur ENTIER (pixels tous de la même taille), centrée dans la tuile
		local px = math.max(16, math.floor((inner - 4) / 16) * 16)
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(px, px)
		img.Position = UDim2.fromOffset(math.floor((inner - px) / 2), math.floor((inner - px) / 2))
		img.Image = card.Icon
		img.ResampleMode = Enum.ResamplerMode.Pixelated -- pas de lissage sur le pixel art
		img.Parent = tile
		if card.IconTag then
			local tag = Theme.Label(tile, card.IconTag, Theme.Small, C.Text, Enum.TextXAlignment.Left)
			tag.Size = UDim2.fromOffset(20, 8)
			tag.Position = UDim2.fromOffset(2, inner - 9)
			local st = Instance.new("UIStroke")
			st.Color = C.BG0
			st.Thickness = 1
			st.Parent = tag
		end
	else
		local glyph = Theme.Label(tile, card.Short, Theme.Big, element and element.Mid or C.Text, Enum.TextXAlignment.Center)
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.Position = UDim2.fromOffset(1, 1)
	end

	local badge = badgeFor(card)
	if badge then
		local b = Theme.Frame(tile, "Badge", UDim2.fromOffset(12, 12), UDim2.new(1, 0, 0, 0), Theme.TypeColor[card.Type])
		b.AnchorPoint = Vector2.new(1, 0)
		local bl = Theme.Label(b, badge, Theme.Small, C.BG0, Enum.TextXAlignment.Center)
		bl.Size = UDim2.fromScale(1, 1)
		bl.Position = UDim2.fromOffset(1, 1)
	end
	-- cumul sur le slot : pastille dorée "x2" / "x3" en bas à droite
	if count > 1 then
		local s = Theme.Frame(tile, "Stack", UDim2.fromOffset(18, 12), UDim2.new(1, 0, 1, 0), C.Gold)
		s.AnchorPoint = Vector2.new(1, 1)
		local sl = Theme.Label(s, "x" .. count, Theme.Small, C.BG0, Enum.TextXAlignment.Center)
		sl.Size = UDim2.fromScale(1, 1)
		sl.Position = UDim2.fromOffset(1, 1)
	end
	tile.Parent = parent
	return tile
end

-- ── Construction ──────────────────────────────────────────────────────────────────────────
local function bar(parent: GuiObject, name: string, y: number, height: number, back: Color3, fill: Color3, stroke: number)
	local frame = Theme.Frame(parent, name, UDim2.new(1, -PAD * 2, 0, height), UDim2.fromOffset(PAD, y), back)
	local s = Theme.Stroke(frame, C.Line, stroke)
	local f = Theme.Frame(frame, "Fill", UDim2.new(0, 0, 1, 0), UDim2.new(), fill)
	return frame, f, s
end

local function build()
	if ui.Gui then
		ui.Gui:Destroy()
	end
	table.clear(slotFrames)
	table.clear(slotStrokes)
	table.clear(slotMarks)
	table.clear(libCells)

	local gui = Instance.new("ScreenGui")
	gui.Name = "WandGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	ui.Gui = gui

	local cap = state.Wand.Capacity
	local width = PAD * 2 + cap * SLOT + (cap - 1) * GAP

	-- ─ Panneau baguette (bas de l'écran) ─
	local wandH = SLOTS_Y + SLOT + 10 + PAD
	local wandRoot, wandBody = Theme.Panel(gui, "Wand", UDim2.fromOffset(width, wandH), UDim2.new(0.5, 0, 1, -20), Vector2.new(0.5, 1))
	ui.WandRoot, ui.WandBody = wandRoot, wandBody

	local title = Theme.Label(wandBody, state.Wand.Name, Theme.Small, C.Text)
	title.Position = UDim2.fromOffset(PAD, PAD)
	title.Size = UDim2.new(1, -PAD * 2, 0, 8)
	local key = Theme.Label(wandBody, "[E] Grimoire", Theme.Small, C.Gold, Enum.TextXAlignment.Right)
	key.Position = UDim2.fromOffset(PAD, PAD)
	key.Size = UDim2.new(1, -PAD * 2, 0, 8)
	ui.KeyHint = key
	-- bouton VIDER : retire toutes les cartes de la baguette d'un coup (visible grimoire ouvert)
	local clearBtn = Theme.Frame(wandBody, "ClearDeck", UDim2.fromOffset(64, 14), UDim2.new(1, -PAD - 112 - 64, 0, PAD - 3), C.BG2)
	local clearStroke = Theme.Stroke(clearBtn, C.Danger, 1)
	local clearLabel = Theme.Label(clearBtn, "VIDER", Theme.Small, C.Danger, Enum.TextXAlignment.Center)
	clearLabel.Size = UDim2.fromScale(1, 1)
	clearLabel.Position = UDim2.fromOffset(1, 1)
	clearBtn.Visible = state.Open
	ui.ClearBtn, ui.ClearStroke = clearBtn, clearStroke
	-- bouton ANNULER (Ctrl+Z ; Ctrl+Y = rétablir), à gauche de Vider
	local undoBtn = Theme.Frame(wandBody, "UndoDeck", UDim2.fromOffset(64, 14), UDim2.new(1, -PAD - 112 - 64 - 6 - 64, 0, PAD - 3), C.BG2)
	local undoStroke = Theme.Stroke(undoBtn, C.Line, 1)
	local undoLabel = Theme.Label(undoBtn, "ANNULER", Theme.Small, C.Dim, Enum.TextXAlignment.Center)
	undoLabel.Size = UDim2.fromScale(1, 1)
	undoLabel.Position = UDim2.fromOffset(1, 1)
	undoBtn.Visible = state.Open
	ui.UndoBtn, ui.UndoStroke, ui.UndoLabel = undoBtn, undoStroke, undoLabel

	local manaBar, manaFill, manaStroke = bar(wandBody, "Mana", 24, 12, C.ManaDark, C.Mana, 2)
	ui.ManaBar, ui.ManaFill, ui.ManaStroke = manaBar, manaFill, manaStroke
	local manaText = Theme.Label(manaBar, "", Theme.Small, C.Text, Enum.TextXAlignment.Center)
	manaText.Size = UDim2.fromScale(1, 1)
	manaText.Position = UDim2.fromOffset(0, 1)
	manaText.ZIndex = 2
	ui.ManaText = manaText

	local rechBar, rechFill = bar(wandBody, "Recharge", 40, 4, C.BG0, C.Delay, 1)
	ui.RechargeBar, ui.RechargeFill = rechBar, rechFill

	local stats = Theme.Label(wandBody, "", Theme.Small, C.Dim)
	stats.Position = UDim2.fromOffset(PAD, 49)
	stats.Size = UDim2.new(1, -PAD * 2, 0, 8)
	ui.Stats = stats

	for i = 1, cap do
		local f = Theme.Frame(wandBody, "Slot" .. i, UDim2.fromOffset(SLOT, SLOT), UDim2.fromOffset(PAD + (i - 1) * (SLOT + GAP), SLOTS_Y), C.BG2)
		slotStrokes[i] = Theme.Stroke(f, C.Line, 2)
		slotFrames[i] = f
	end
	-- curseur de lecture : prochaine carte lue au prochain clic
	ui.Cursor = Theme.Frame(wandBody, "Cursor", UDim2.fromOffset(16, 4), UDim2.fromOffset(0, SLOTS_Y + SLOT + 4), C.Gold)
	ui.Cursor.Visible = false -- remplacé par les marques de slots lus (aperçu)
	for i = 1, cap do
		local mark = Theme.Frame(wandBody, "Mark" .. i, UDim2.fromOffset(SLOT - 8, 4), UDim2.fromOffset(PAD + (i - 1) * (SLOT + GAP) + 4, SLOTS_Y + SLOT + 4), C.Gold)
		mark.Visible = false
		slotMarks[i] = mark
	end

	-- ─ Aperçu "Prochain clic" (à côté de la baguette, hauteur automatique) ─
	local prev = Theme.Frame(gui, "Preview", UDim2.fromOffset(PREVIEW_W, 0), UDim2.new(), C.BG1)
	prev.AutomaticSize = Enum.AutomaticSize.Y
	prev.AnchorPoint = Vector2.new(0, 1)
	Theme.Stroke(prev, C.Line, 2)
	local ppad = Instance.new("UIPadding")
	ppad.PaddingTop, ppad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
	ppad.PaddingLeft, ppad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	ppad.Parent = prev
	local plist = Instance.new("UIListLayout")
	plist.Padding = UDim.new(0, 3)
	plist.SortOrder = Enum.SortOrder.LayoutOrder
	plist.Parent = prev
	ui.Preview = prev

	-- ─ Grimoire (au-dessus de la baguette, caché par défaut) ─
	-- grille dans un ScrollingFrame : au-delà de 5 rangées, on fait défiler (molette / barre dorée)
	local cols = cap
	local rows = math.ceil(#Catalog.Order / cols)
	local gridH = rows * SLOT + (rows - 1) * GAP + 2
	local visibleRows = math.min(rows, 5)
	local viewH = visibleRows * SLOT + (visibleRows - 1) * GAP + 2
	local SCROLL_W = 10
	local libW = width + SCROLL_W
	local libH = PAD + 8 + 8 + viewH + 8 + 8 + PAD
	local libRoot, libBody = Theme.Panel(gui, "Grimoire", UDim2.fromOffset(libW, libH), UDim2.new(0.5, 0, 1, -20 - wandH - 16), Vector2.new(0.5, 1))
	libRoot.Visible = state.Open
	ui.LibRoot, ui.LibBody = libRoot, libBody

	local libTitle = Theme.Label(libBody, "Grimoire", Theme.Small, C.Gold)
	libTitle.Position = UDim2.fromOffset(PAD, PAD)
	libTitle.Size = UDim2.new(1, -PAD * 2, 0, 8)
	local legend = Theme.Label(libBody, "", Theme.Small, C.Dim, Enum.TextXAlignment.Right)
	legend.RichText = true
	legend.Text = ("<font color='#%s'>PROJ</font> <font color='#%s'>MOD</font> <font color='#%s'>MULTI</font> <font color='#%s'>DECL</font>")
		:format(Theme.TypeColor.Projectile:ToHex(), Theme.TypeColor.Modifier:ToHex(), Theme.TypeColor.Multicast:ToHex(), Theme.TypeColor.Trigger:ToHex())
	legend.Position = UDim2.fromOffset(PAD, PAD)
	legend.Size = UDim2.new(1, -PAD * 2, 0, 8)

	local gridY = PAD + 16
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(PAD - 1, gridY - 1)
	scroll.Size = UDim2.fromOffset(width - PAD * 2 + 2 + SCROLL_W, viewH)
	scroll.CanvasSize = UDim2.fromOffset(0, gridH)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = C.Gold
	scroll.ScrollBarImageTransparency = 0
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.None
	scroll.ElasticBehavior = Enum.ElasticBehavior.Never
	scroll.ScrollingEnabled = rows > visibleRows
	scroll.Parent = libBody
	ui.LibScroll = scroll
	for index, id in Catalog.Order do
		local col = (index - 1) % cols
		local row = (index - 1) // cols
		local cell = Theme.Frame(scroll, id, UDim2.fromOffset(SLOT, SLOT), UDim2.fromOffset(1 + col * (SLOT + GAP), 1 + row * (SLOT + GAP)), C.BG2)
		Theme.Stroke(cell, C.Line, 1)
		makeTile(cell, id)
		libCells[id] = cell
	end
	local hint = Theme.Label(libBody, "Clic: placer  Clic droit: ajouter / retirer  Meme modif.: x2 x3", Theme.Small, C.Dim)
	hint.Position = UDim2.fromOffset(PAD, gridY + viewH + 8)
	hint.Size = UDim2.new(1, -PAD * 2, 0, 8)

	-- ─ Infobulle ─
	local tip = Theme.Frame(gui, "Tooltip", UDim2.fromOffset(TIP_W, 0), UDim2.new(), C.BG0)
	tip.AutomaticSize = Enum.AutomaticSize.Y
	tip.Visible = false
	tip.ZIndex = 20
	ui.TooltipStroke = Theme.Stroke(tip, C.LineHi, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.Parent = tip
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = tip
	ui.Tooltip = tip
	local tipScale = Instance.new("UIScale") -- infobulle un peu plus petite (user 2026-11-23)
	tipScale.Scale = 0.85
	tipScale.Parent = tip

	-- ─ Carte "en main" (suit la souris) ─
	local ghost = Theme.Frame(gui, "Ghost", UDim2.fromOffset(SLOT, SLOT), UDim2.new())
	ghost.ZIndex = 30
	ghost.Visible = false
	ui.Ghost = ghost

	-- Placement au pixel ENTIER : un AnchorPoint de 0.5 sur un écran de largeur impaire tombe sur un
	-- demi-pixel (texte et bordures flous). On recalcule donc la position à chaque redimensionnement.
	wandRoot.AnchorPoint = Vector2.zero
	libRoot.AnchorPoint = Vector2.zero
	local function layout()
		local screen = gui.AbsoluteSize
		local x = math.floor((screen.X - width) / 2)
		local wandY = math.floor(screen.Y - 20 - wandH)
		wandRoot.Position = UDim2.fromOffset(x, wandY)
		libRoot.Position = UDim2.fromOffset(x - SCROLL_W // 2, wandY - 16 - libH)
		-- aperçu à droite de la baguette, ou à gauche si l'écran est trop étroit
		local px = x + width + 16
		if px + PREVIEW_W > screen.X - 8 then
			px = math.max(8, x - 16 - PREVIEW_W)
		end
		prev.Position = UDim2.fromOffset(px, wandY + wandH)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	gui.Parent = player:WaitForChild("PlayerGui")
	layout()
end

-- ── Rendu ──────────────────────────────────────────────────────────────────────────────────
local function render()
	for i, f in slotFrames do
		local old = f:FindFirstChild("Tile")
		if old then
			old:Destroy()
		end
		local id = state.Deck[i]
		if id and id ~= "" then
			local tile = makeTile(f, id)
			-- modificateur SANS EFFET sur les sorts qu'il vise : marque rouge + carte assombrie
			if tile and Catalog.Useless(state.Deck, i) then
				local mark = Theme.Frame(tile, "NoEffect", UDim2.fromOffset(12, 12), UDim2.new(1, -13, 0, 1), C.Danger)
				mark.ZIndex = (tile.ZIndex or 1) + 5
				local x = Theme.Label(mark, "!", Theme.Small, C.Text, Enum.TextXAlignment.Center)
				x.Size = UDim2.fromScale(1, 1)
				x.Position = UDim2.fromOffset(1, 1)
				x.ZIndex = mark.ZIndex + 1
				local dim = Theme.Frame(tile, "Dim", UDim2.fromScale(1, 1), UDim2.new(), C.BG0)
				dim.BackgroundTransparency = 0.45
				dim.ZIndex = mark.ZIndex - 1
			end
		end
	end
	local ghost = ui.Ghost
	ghost:ClearAllChildren()
	if state.Held then
		local t = makeTile(ghost, state.Held.Id)
		if t then
			t.ZIndex = 30
		end
	end
	ghost.Visible = state.Held ~= nil
	local w = state.Wand
	ui.Stats.Text = Theme.Txt(("Délai %.2fs  Recharge %.2fs  Sorts/tir %d"):format(w.CastDelay, w.RechargeTime, w.SpellsPerCast))
	if renderPreview then
		renderPreview()
	end
end

-- ── Historique (Annuler / Rétablir) ── un instantané du deck AVANT chaque modification validée
local HISTORY_MAX = 40
local undoStack, redoStack = {}, {}
local lastDeck: { string }? = nil -- dernier deck validé (référence pour détecter un changement)

local function sameDeck(a, b)
	if not a or not b or #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function refreshUndoBtn()
	if ui.UndoLabel then
		ui.UndoLabel.TextColor3 = if #undoStack > 0 then C.Text else C.Dim
	end
end

local function commit(fromHistory: boolean?)
	if not fromHistory and lastDeck and not sameDeck(lastDeck, state.Deck) then
		table.insert(undoStack, lastDeck)
		if #undoStack > HISTORY_MAX then
			table.remove(undoStack, 1)
		end
		table.clear(redoStack) -- nouvelle action : l'avenir annulé est perdu
	end
	lastDeck = table.clone(state.Deck)
	refreshUndoBtn()
	render()
	callbacks.OnDeckChanged(table.clone(state.Deck))
end

-- ── Infobulle détaillée ────────────────────────────────────────────────────────────────────────
-- Chaque ligne = { kind, text } : "title" | "sub" | "text" | "head" | "row" | "rule" | "sep" | "cost"
local function num(n: number): string
	if n == math.floor(n) then
		return tostring(n)
	end
	return (("%.2f"):format(n):gsub("0+$", ""):gsub("%.", ","))
end

local function signed(n: number): string
	return (if n >= 0 then "+" else "") .. num(n)
end

local ELEMENT_EFFECT = {
	Fire = "Brûlure qui se cumule (3 niveaux) : 2 dégâts par niveau toutes les 0,5 s pendant 2 s (les zones au sol n'empilent pas)",
	Ice = "Ralentit de 45 % ; 3 coups en 3 s = GEL complet 1,2 s",
	Chaos = "Instable : dégâts aléatoires de x0,4 à x2,2",
	Arcane = "Pur : aucun effet secondaire",
	Steel = "Saignement : 1 dégât toutes les 0,5 s pendant 2,5 s",
	Lightning = "Choc : immobilise 0,35 s ; chaque coup SAUTE vers une cible proche (60 %)",
	Toxic = "Poison qui se cumule (5 niveaux, 4 s) ; la cible subit +10 % de dégâts",
	Nature = "Racines : ralentit de 70 % ; 3 coups en 3 s = ENRACINÉ 1 s",
	Neutral = "Neutre : aucun effet secondaire",
}

local ZONE_NAMES = {
	BlackHole = "trou noir", Gas = "nuage toxique", FireRing = "cercle de feu", Mine = "mine",
	Shield = "bouclier", Dispel = "annulation", IceWall = "mur de glace",
}

local TRAJECTORY = {
	Wave = "vague (zigzag latéral)", Spiral = "spirale autour de l'axe", Straight = "ligne droite",
	Orbit = "orbite autour du lanceur", Boomerang = "aller-retour vers le lanceur",
}

local MOD_TEXT: { [string]: (any) -> string } = {
	DamageAdd = function(v) return ("Dégâts %s"):format(signed(v)) end,
	DamageMult = function(v) return ("Dégâts x%s"):format(num(v)) end,
	SpeedMult = function(v) return ("Vitesse x%s"):format(num(v)) end,
	SizeMult = function(v) return ("Taille x%s (projectile, effets visuels, zones)"):format(num(v)) end,
	DurationMult = function(v) return ("Durée des zones, murs et branches x%s"):format(num(v)) end,
	RadiusMult = function(v) return ("Rayon d'explosion x%s"):format(num(v)) end,
	RadiusAdd = function(v) return ("Rayon d'explosion %s"):format(signed(v)) end,
	LifetimeMult = function(v) return ("Durée de vie x%s"):format(num(v)) end,
	GravityAdd = function(v) return ("Gravité %s (trajectoire en cloche)"):format(signed(v)) end,
	Homing = function(v) return ("Poursuit la cible la plus proche (force %s, portée 70)"):format(num(v)) end,
	BouncesAdd = function(v) return ("Rebonds %s sur les murs et le sol"):format(signed(v)) end,
	PierceAdd = function(v) return ("Traverse %s cible(s) de plus"):format(num(v)) end,
	SpreadAdd = function(v) return ("Dispersion %s°"):format(signed(v)) end,
	Element = function(v) return ("Devient élément %s"):format(Config.Elements[v] and Config.Elements[v].Label or v) end,
	Trajectory = function(v) return ("Trajectoire : %s"):format(TRAJECTORY[v] or v) end,
	SpiralAdd = function() return "Cumul : chaque exemplaire élargit la spirale (rayon 1,4 → 2,6 → 3,8)" end,
	AddTrigger = function(v) return ("Le prochain projectile devient un déclencheur %s"):format(Theme.TriggerLabel[v.Kind] or "") .. (if v.Kind == "Expire" then " (cumulable : +1 carte libérée par exemplaire, 3 max)" else "") end,
	Divide = function(v) return ("Le prochain projectile est lancé en %d copies"):format(v) end,
	DivideDamage = function(v) return ("Dégâts de chaque copie x%s"):format(num(v)) end,
	Fragments = function(v) return ("Éclate en %d fragments à sa disparition"):format(v) end,
	Knockback = function(v) return ("Repousse les cibles touchées (force %s)"):format(num(v)) end,
	Phase = function() return "Sorts PROCÉDURAUX : la matière traverse roches, murs et sol (aucun effet sur les projectiles)" end,
	CastMode = function(v) return if v == "Hold" then "Mode de lancement : MAINTIEN (garder le clic enfoncé)" else tostring(v) end,
	Cage = function(v) return if v == "Self" then "Sorts PROCÉDURAUX : se construit en cage autour de TOI (sans te toucher)" else "Sorts PROCÉDURAUX : encercle l'ennemi le plus proche en cage" end,
}
local MOD_ORDER = { "AddTrigger", "Divide", "DivideDamage", "Element", "DamageAdd", "DamageMult", "SpeedMult", "SizeMult", "RadiusMult", "RadiusAdd", "DurationMult", "LifetimeMult", "GravityAdd", "Homing", "BouncesAdd", "PierceAdd", "SpreadAdd", "Trajectory", "SpiralAdd", "Fragments", "Knockback", "Phase", "Cage", "CastMode" }

local TRIGGER_RULE = {
	Hit = "Au premier contact (ennemi, mur ou sol), lance %s du deck depuis le point d'impact.",
	Timer = "Après %s s de vol, lance %s depuis sa position, puis continue sa course.",
	Expire = "Quand il disparaît (impact ou fin de vie), lance %s depuis sa position.",
	Trap = "Quand un ennemi approche du piège, lance %s depuis le piège vers cet ennemi.",
}

local function nextCards(n: number): string
	return if n == 1 then "la carte suivante" else ("les %d cartes suivantes"):format(n)
end

local function row(label: string, value: string): { string }
	return { "row", ("<font color=\"#%s\">%s</font>  %s"):format(C.Dim:ToHex(), label, value) }
end

local function tooltipLines(card, slot: number?): { { string } }
	local lines = {}
	local sub = if card.Category == "Procedural" then (if card.Type == "Modifier" then "MODIFICATEUR PROCÉDURAL" else "PROCÉDURAL")
		elseif card.Category == "CastMode" then "MODE DE LANCEMENT"
		elseif card.Category == "Trap" then "PIÈGE ADAPTATIF"
		else Theme.TypeLabel[card.Type]
	if card.Family and card.Family ~= "Multicast" and card.Category ~= "Procedural" and card.Category ~= "Trap" then
		sub ..= "  ·  " .. string.upper(Catalog.FamilyLabel[card.Family] or card.Family)
	end
	if card.Rank then
		sub ..= "  ·  " .. string.upper(Catalog.RankLabel[card.Rank] or card.Rank)
	end
	if card.Element then
		sub ..= "  ·  " .. Config.Elements[card.Element].Label
	end
	table.insert(lines, { "title", card.Name })
	table.insert(lines, { "sub", sub })
	table.insert(lines, { "sep" })
	table.insert(lines, { "text", card.Desc })
	-- modificateur : familles sur lesquelles il agit + avertissement s'il ne sert à rien à cette place
	if card.Type == "Modifier" and card.AppliesTo then
		local names = {}
		for _, f in card.AppliesTo do
			table.insert(names, Catalog.FamilyLabel[f] or f)
		 end
		table.insert(lines, row("Agit sur   ", table.concat(names, ", ") .. " (et pièges)"))
		local useless = slot and Catalog.Useless(state.Deck, slot)
		if useless then
			local what = {}
			for _, s in useless do
				table.insert(what, s.Name .. " (" .. string.lower(Catalog.FamilyLabel[s.Family] or "?") .. ")")
			end
			table.insert(lines, { "rule", ("<font color=\"#%s\">SANS EFFET ICI : ne modifie pas %s.</font>"):format(C.Danger:ToHex(), table.concat(what, ", ")) })
		end
	end

	local p = card.Proj
	if p then
		table.insert(lines, { "head", "Statistiques" })
		table.insert(lines, row("Dégâts    ", num(p.Damage)))
		if p.Trap then
			table.insert(lines, row("Pose       ", "sur la surface visée (" .. num(p.Range) .. " studs max) ou au bout de son projectile porteur"))
			table.insert(lines, row("Piège      ", ("rayon %s, s'arme en %s s, dure %s s"):format(num(p.Trap.Radius), num(p.Trap.Arm), num(p.Trap.Duration))))
			table.insert(lines, { "rule", "Placé AVANT la mine : Dégâts+ = dégâts, Charge explosive = explosion, Infusion = élément (et couleur des paillettes), Gigantisme = rayon, Prolongation = durée, Recul = poussée. Le Maintien ne s'applique pas aux pièges." })
		elseif p.Growth then
			local g = p.Growth
			table.insert(lines, row("Cible      ", "surface solide visée (" .. num(p.Range) .. " studs max)"))
			table.insert(lines, row("Croissance ", ("%d bras, %s s de pousse, dure %s s"):format(g.Arms, num(g.Duration), num(g.Life))))
			table.insert(lines, row("Contact    ", ("%s dég. toutes les %s s"):format(num(g.Damage), num(g.Interval))))
			table.insert(lines, row("Détection  ", ("zone de %s studs au bout de chaque branche (avec Tête chercheuse)"):format(num(g.Sense or 9))))
			table.insert(lines, row("Taille     ", "Gigantisme allonge aussi la propagation (+12 % par palier de taille)"))
			table.insert(lines, { "rule", "Sans surface visée, le sort échoue et la carte est remboursée. Par défaut les troncs ne visent personne. Se modifie comme un sort normal : Tête chercheuse = chaque tronc vise l'ennemi le plus proche, Feu = troncs enflammés, Gigantisme = troncs colossaux, Prolongation = dure plus longtemps." })
		elseif p.Self then
			table.insert(lines, row("Cible      ", "toi-même (pas de projectile)"))
		elseif p.Instant then
			table.insert(lines, row("Portée     ", "instantanée, " .. num(p.Range) .. " studs"))
		else
			table.insert(lines, row("Vitesse    ", num(p.Speed) .. " studs/s"))
			table.insert(lines, row("Durée      ", num(p.Lifetime) .. " s  (portée ~" .. math.floor(p.Speed * p.Lifetime) .. " studs)"))
			table.insert(lines, row("Taille     ", num(p.Size)))
		end
		if p.Chain > 0 then
			table.insert(lines, row("Chaîne     ", p.Chain .. " sauts vers les cibles proches (x0,75)"))
		end
		if p.Aura then
			table.insert(lines, row("Aura       ", ("%s dég. toutes les %s s, rayon %s"):format(num(p.Aura.Damage), num(p.Aura.Interval or 0.2), num(p.Aura.Radius))))
		end
		if p.Zone then
			local z = p.Zone
			local size = if z.Kind == "IceWall" then ("%s x %s studs"):format(num(z.Width), num(z.Height)) else "rayon " .. num(z.Radius or 0)
			table.insert(lines, row("Zone       ", ("%s, %s, %s s"):format(ZONE_NAMES[z.Kind] or z.Kind, size, num(z.Duration or 0))))
		end
		if p.Knockback > 0 then
			table.insert(lines, row("Recul      ", "force " .. num(p.Knockback)))
		end
		if p.OnEnd == "Teleport" then
			table.insert(lines, row("Effet      ", "te téléporte à son point d'arrivée"))
		end
		if p.Radius > 0 then
			table.insert(lines, row("Explosion  ", "rayon " .. num(p.Radius) .. " (100 % au centre, 40 % au bord)"))
		end
		if p.Bounces > 0 then
			table.insert(lines, row("Rebonds    ", num(p.Bounces)))
		end
		if p.Pierce > 0 then
			table.insert(lines, row("Perforation", num(p.Pierce) .. " cible(s)"))
		end
		if p.Gravity ~= 0 then
			table.insert(lines, row("Gravité    ", num(p.Gravity)))
		end
		if card.Copies and card.Copies > 1 then
			table.insert(lines, row("Projectiles", card.Copies .. " en éventail"))
		end
		if card.Element then
			table.insert(lines, row("Élément    ", ELEMENT_EFFECT[card.Element] or ""))
		end
	end

	if card.Type == "Trigger" then
		local t = card.Trigger
		local rule = if t.Kind == "Timer"
			then TRIGGER_RULE.Timer:format(num(t.Delay or 0.3), nextCards(t.Draw))
			else TRIGGER_RULE[t.Kind]:format(nextCards(t.Draw))
		table.insert(lines, { "head", "Déclencheur " .. Theme.TriggerLabel[t.Kind] })
		table.insert(lines, { "rule", rule })
		table.insert(lines, { "rule", "Les cartes transportées repartent sans les modificateurs placés avant ce déclencheur." })
	elseif card.Type == "Modifier" then
		table.insert(lines, { "head", "Effets" })
		for _, key in MOD_ORDER do
			local v = card.Mod[key]
			if v ~= nil and MOD_TEXT[key] then
				table.insert(lines, { "row", "• " .. MOD_TEXT[key](v) })
			end
		end
		if card.Element then
			table.insert(lines, { "row", "• " .. (ELEMENT_EFFECT[card.Element] or "") })
		end
		if card.Mod.Element then
			table.insert(lines, { "row", "• Ne se cumule pas : une 2e infusion identique est sans effet" })
		elseif next(card.Mod) ~= nil then
			table.insert(lines, { "row", "• CUMULABLE (expérimental) : jusqu'à 3 exemplaires dans le même groupe, effets multipliés" })
		end
		if card.Mod.AddTrigger or card.Mod.Divide then
			table.insert(lines, { "rule", "Ne touche que le PROCHAIN projectile du groupe. Ne compte pas comme un tir : la baguette pioche une carte de plus." })
		elseif next(card.Mod) == nil then
			table.insert(lines, { "rule", "Agit sur la baguette (coût, délai ou recharge du tir). Ne compte pas comme un tir : la baguette pioche une carte de plus." })
		else
			table.insert(lines, { "rule", "S'applique à TOUS les sorts placés après lui dans le même groupe de tir. Ne compte pas comme un tir : la baguette pioche une carte de plus." })
		end
	elseif card.Greek then
		table.insert(lines, { "head", "Lettre grecque" })
		table.insert(lines, { "row", "• Les copies sont GRATUITES (pas de mana) et ne consomment aucun slot" })
		table.insert(lines, { "row", "• Elles agissent comme si les cartes étaient lues à cet endroit du deck" })
		table.insert(lines, { "rule", "Ne copie jamais une autre lettre grecque. Regarde l'aperçu « Prochain clic » pour voir exactement ce qui est copié." })
	elseif card.Type == "Multicast" then
		table.insert(lines, { "head", "Effets" })
		table.insert(lines, { "row", ("• Lance les %d cartes suivantes en même temps"):format(card.Draw) })
		if card.Formation == "Circle" then
			table.insert(lines, { "row", "• Disposition : cercle complet autour de toi" })
		elseif card.Formation == "Behind" then
			table.insert(lines, { "row", "• Disposition : un devant, un derrière" })
		else
			table.insert(lines, { "row", ("• Dispersion en éventail : %s°"):format(num(card.Spread or 0)) })
		end
		table.insert(lines, { "rule", "Les modificateurs placés AVANT ce multicast s'appliquent à tous les sorts lancés." })
	end

	table.insert(lines, { "sep" })
	local cost = if card.Mana < 0
		then ("<font color=\"#%s\">Rend %d mana</font>"):format(C.Mana:ToHex(), -card.Mana)
		else ("<font color=\"#%s\">Mana %d</font>"):format(C.Mana:ToHex(), card.Mana)
	if card.CastDelay ~= 0 then
		cost ..= ("   <font color=\"#%s\">Délai %s s</font>"):format(C.Delay:ToHex(), signed(card.CastDelay))
	end
	if card.Recharge ~= 0 then
		cost ..= ("   <font color=\"#%s\">Recharge %s s</font>"):format(C.Gold:ToHex(), signed(card.Recharge))
	end
	table.insert(lines, { "cost", cost })
	return lines
end

local function tipLabel(tip: Frame, order: number, text: string, font: Font, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = color
	l.RichText = true
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.new(1, 0, 0, size)
	l.LineHeight = 1.15
	l.LayoutOrder = order
	l.ZIndex = 21
	l.Text = text
	l.Parent = tip
	return l
end

-- ── Aperçu "Prochain clic" ─────────────────────────────────────────────────────────────────────────
-- Utilise SpellPlanner (le même code que le serveur) : ce qui est affiché est EXACTEMENT ce qui partira.
local REASON_TEXT = {
	MaxDepth = "trop de déclencheurs imbriqués",
	MaxProjectilesPerCast = "trop de projectiles pour un seul clic",
	MaxIterations = "trop de cartes lues",
}

-- Étiquettes courtes des modificateurs actifs sur un tir
local function shotTags(shot, st, card): string
	local s = shot.State
	local tags = {}
	local TRAJ_TAG = { Wave = "vague", Spiral = "spirale", Orbit = "orbite", Boomerang = "boomerang" }
	if TRAJ_TAG[st.Trajectory] then
		table.insert(tags, TRAJ_TAG[st.Trajectory])
	end
	if st.Instant then
		table.insert(tags, "instantané")
	end
	if st.Fragments > 0 then
		table.insert(tags, "+" .. st.Fragments .. " fragments")
	end
	if st.Knockback > 0 and (card.Proj.Knockback or 0) == 0 then
		table.insert(tags, "recul")
	end
	if st.Zone then
		table.insert(tags, ZONE_NAMES[st.Zone.Kind] or "zone")
	end
	if st.Growth then
		table.insert(tags, "croissance")
		if st.Phase then
			table.insert(tags, "ignore obstacles")
		end
		if st.Cage then
			table.insert(tags, if st.Cage == "Self" then "cage sur toi" else "cage ennemie")
		end
	end
	if s.DurationMult and s.DurationMult ~= 1 then
		table.insert(tags, "durée x" .. num(s.DurationMult))
	end
	if st.Homing > 0 then
		table.insert(tags, "chercheuse")
	end
	if s.SizeMult ~= 1 then
		table.insert(tags, "taille x" .. num(math.floor(s.SizeMult * 100 + 0.5) / 100))
	end
	if s.SpeedMult ~= 1 then
		table.insert(tags, "vit x" .. num(math.floor(s.SpeedMult * 100 + 0.5) / 100))
	end
	if s.BouncesAdd > 0 then
		table.insert(tags, "+" .. s.BouncesAdd .. " rebonds")
	end
	if s.PierceAdd > 0 then
		table.insert(tags, "+" .. s.PierceAdd .. " perfo")
	end
	if s.GravityAdd > 0 then
		table.insert(tags, "lesté")
	end
	if s.Element and s.Element ~= card.Element and Config.Elements[s.Element] then
		table.insert(tags, string.lower(Config.Elements[s.Element].Label))
	end
	return table.concat(tags, ", ")
end

-- ── AIDE AU DECK : aperçu AVANT / APRÈS une carte (aide 1) ─────────────────────────────────────────
-- Le joueur voit l'effet CONCRET d'une carte sur SON prochain clic (même code que le serveur : SpellPlanner).
local function planSummary(deck: { string })
	local wand = state.Wand
	local cursor = math.clamp(player:GetAttribute("WandCursor") or 1, 1, math.max(1, #deck))
	local ok, plan = pcall(Planner.Plan, deck, wand, cursor)
	if not ok or not plan then
		return nil
	end
	local sum = { Plan = plan, Damage = 0, Projectiles = plan.Projectiles or 0, Mana = Planner.Cost(plan), Delay = Planner.Delay(plan), First = nil }
	local function walk(node)
		for _, shot in node.Shots do
			local ok2, st = pcall(Planner.Resolve, shot, wand)
			if ok2 and st then
				sum.Damage += (if st.Aura then st.Aura.Damage else st.Damage) * shot.Copies
				sum.First = sum.First or st
			end
			if shot.Payload then
				walk(shot.Payload)
			end
		end
	end
	if not plan.Empty then
		walk(plan.Root)
	end
	return sum
end

-- deck de base pendant qu'une carte est en main (la carte prise dans un slot y est remise)
local function baseDeck(): { string }
	local d = table.clone(state.Deck)
	local h = state.Held
	if h and h.From == "slot" and h.Index and d[h.Index] == "" then
		d[h.Index] = h.Id
	end
	return d
end

-- deck simulé si la carte en main était posée sur le slot `key` (mêmes règles que place())
local function simulatePlace(key: number): { string }
	local held = state.Held
	local d = table.clone(state.Deck)
	local prev = d[key]
	local hc, hn = Catalog.ParseSlot(held.Id)
	local pc, pn = Catalog.ParseSlot(prev)
	if hc and pc and hc == pc and Catalog.CanStack(hc) then
		d[key] = Catalog.SlotEntry(hc.Id, math.min(hn + pn, Catalog.MaxStackOf(hc)))
	else
		d[key] = held.Id
		if held.From == "slot" and prev ~= "" and held.Index and d[held.Index] == "" then
			d[held.Index] = prev
		end
	end
	return d
end

-- deck simulé si la carte `id` était ajoutée JUSTE AVANT le prochain sort lu (décale vers le 1er slot libre)
local function insertAhead(id: string): { string }?
	local d = table.clone(state.Deck)
	local cur = planSummary(d)
	local start = (cur and cur.Plan.Start) or 1
	for j = start, #d do
		if d[j] == "" then
			for k = j, start + 1, -1 do
				d[k] = d[k - 1]
			end
			d[start] = id
			return d
		end
	end
	return nil
end

local function r2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

-- lignes « valeur avant → après » ; better = 1 (plus = mieux), -1 (moins = mieux), 0 (neutre)
local function diffLines(a, b): { string }
	local out = {}
	local function line(label: string, va: number, vb: number, better: number, unit: string?)
		va, vb = r2(va), r2(vb)
		if va == vb then
			return
		end
		local good = (vb - va) * better
		local col = if better == 0 then C.Gold elseif good > 0 then Color3.fromHex("7be07b") else C.Danger
		table.insert(out, ("<font color=\"#%s\">%s</font>  %s%s → <font color=\"#%s\">%s%s</font>"):format(
			C.Dim:ToHex(), label, num(va), unit or "", col:ToHex(), num(vb), unit or ""))
	end
	line("Dégâts", a.Damage, b.Damage, 1)
	line("Projectiles", a.Projectiles, b.Projectiles, 1)
	line("Mana", a.Mana, b.Mana, -1)
	line("Délai", a.Delay, b.Delay, -1, " s")
	local fa, fb = a.First, b.First
	if fa and fb and fa.CardId == fb.CardId then
		line("Vitesse", fa.Speed, fb.Speed, 1)
		line("Durée de vie", fa.Lifetime, fb.Lifetime, 1, " s")
		line("Taille", fa.FxScale, fb.FxScale, 1, "x")
		line("Explosion", fa.Radius, fb.Radius, 1)
		line("Durée zones", fa.DurationMult, fb.DurationMult, 1, "x")
		line("Rebonds", fa.Bounces, fb.Bounces, 1)
		line("Perforation", fa.Pierce, fb.Pierce, 1)
		line("Recul", fa.Knockback, fb.Knockback, 1)
		line("Fragments", fa.Fragments, fb.Fragments, 1)
		line("Gravité", fa.Gravity, fb.Gravity, 0)
		if fa.Homing ~= fb.Homing then
			table.insert(out, ("<font color=\"#%s\">Tête chercheuse</font>  %s"):format(C.Dim:ToHex(), if fb.Homing > 0 then "oui" else "non"))
		end
		if fa.Element ~= fb.Element and Config.Elements[fb.Element] then
			table.insert(out, ("<font color=\"#%s\">Élément</font>  %s → %s"):format(C.Dim:ToHex(),
				Config.Elements[fa.Element] and Config.Elements[fa.Element].Label or fa.Element, Config.Elements[fb.Element].Label))
		end
		if fa.Trajectory ~= fb.Trajectory then
			table.insert(out, ("<font color=\"#%s\">Trajectoire</font>  %s"):format(C.Dim:ToHex(), TRAJECTORY[fb.Trajectory] or fb.Trajectory))
		end
	elseif fb and (not fa or fa.CardId ~= fb.CardId) then
		local c = Catalog.Get(fb.CardId)
		table.insert(out, ("<font color=\"#%s\">Premier sort lancé</font>  %s"):format(C.Dim:ToHex(), c and c.Name or fb.CardId))
	end
	return out
end

-- ── CONSEILS (aide 5) : problèmes évidents du deck, jamais de « deck optimal » imposé ──────────────────
local function deckTips(deck: { string }, cost: number): { string }
	local tips = {}
	local manaMax = player:GetAttribute("ManaMax") or 0
	if manaMax > 0 and cost > manaMax then
		local wand = state.Wand or {}
		local tier = wand.Tier or "Moyenne"
		local Incant = require(game:GetService("ReplicatedStorage"):WaitForChild("WandShared"):WaitForChild("Incantation"))
		if tier == "Moyenne" then
			table.insert(tips, ("! Ce clic coûte %d mana, ta baguette n'en a que %d et ne peut pas incanter : il ne partira jamais. Retire des modificateurs coûteux."):format(cost, manaMax))
		elseif cost > manaMax * (wand.OverflowCap or 1.5) then
			table.insert(tips, ("! Ce clic coûte %d mana : trop même pour une incantation (cette baguette assimile au plus x%.1f ton mana, soit %d barre pleine)."):format(cost, wand.OverflowCap or 1.5, math.floor(manaMax * (wand.OverflowCap or 1.5))))
		else
			table.insert(tips, ("Incantation : ce clic coûte %d mana (> %d). Maintiens le clic pour charger les cercles ; il faut au moins %d mana pour commencer (%d avec cette baguette, qui assimile x%.1f ton mana actuel)."):format(cost, manaMax, math.ceil(manaMax * Incant.MIN_MANA_FRAC), math.max(math.ceil(manaMax * Incant.MIN_MANA_FRAC), math.ceil(cost / (wand.OverflowCap or 1.5))), wand.OverflowCap or 1.5))
		end
	elseif manaMax > 0 and cost > manaMax * 0.5 then
		table.insert(tips, ("Conseil : ce clic utilise %d %% de ta mana, tu ne pourras le lancer que %d fois d'affilée."):format(
			math.floor(cost / manaMax * 100 + 0.5), math.floor(manaMax / math.max(cost, 1))))
	end
	for i = 1, #deck do
		if #tips >= 3 then
			break
		end
		local c = Catalog.ParseSlot(deck[i])
		if c and c.Type == "Modifier" and Catalog.Useless(deck, i) then
			table.insert(tips, ("Conseil : %s (emplacement %d) n'agit pas sur le sort qui le suit. Survole-le pour savoir pourquoi."):format(c.Name, i))
		end
	end
	return tips
end

renderPreview = function()
	local prev = ui.Preview
	if not prev then
		return
	end
	for _, c in prev:GetChildren() do
		if c:IsA("TextLabel") or c.Name == "Sep" then
			c:Destroy()
		end
	end
	ui.PreviewCost = nil

	local wand = state.Wand
	-- carte en main au-dessus d'un slot : l'aperçu montre le tir SI elle était posée là (+ différences)
	local simulating = state.Held ~= nil and state.SimSlot ~= nil
	local deck = if simulating then simulatePlace(state.SimSlot) else state.Deck
	local cursor = math.clamp(player:GetAttribute("WandCursor") or 1, 1, math.max(1, #deck))
	local ok, plan = pcall(Planner.Plan, deck, wand, cursor)
	if not ok then
		return
	end

	-- marques sous les slots lus (doré plein = première carte lue)
	for i, mark in slotMarks do
		mark.Visible = plan.Used[i] == true
		mark.BackgroundTransparency = if i == plan.Start then 0 else 0.45
	end

	local order = 0
	local function add(text: string, font: Font, size: number, color: Color3): TextLabel
		order += 1
		return tipLabel(prev :: any, order, text, font, size, color)
	end
	local header = add(Theme.Txt(if simulating then "Prochain clic si posee ici" else "Prochain clic"), Theme.Font, Theme.Small, C.Gold)
	header.RichText = false

	local lines: { string } = {}
	local dim = C.Dim:ToHex()
	local function walk(node, depth: number)
		local indent = string.rep("   ", depth)
		local total = 0
		for _, s in node.Shots do
			total += s.Copies
		end
		if total > 1 then
			local layout = if node.Formation == "Circle" then "en cercle autour de toi"
				elseif node.Formation == "Behind" then "devant / derrière"
				else "éventail " .. num(wand.SpreadDeg + node.Spread) .. "°"
			table.insert(lines, ("%s<font color=\"#%s\">%d tirs simultanés, %s</font>")
				:format(indent, Theme.TypeColor.Multicast:ToHex(), total, layout))
		end
		for _, shot in node.Shots do
			local card = shot.Card
			local st = Planner.Resolve(shot, wand)
			local P = Config.Elements[st.Element] or Config.Elements.Arcane
			local tags = shotTags(shot, st, card)
			local copies = if shot.Copies > 1 then shot.Copies .. "x " else ""
			-- dégâts : directs, ou par tick pour une aura (scie) ; rien pour un sort purement utilitaire
			local dmgText
			if st.Aura then
				dmgText = ("%s dég / %s s"):format(num(st.Aura.Damage), num(st.Aura.Interval or 0.2))
			elseif st.Damage > 0 then
				dmgText = num(math.floor(st.Damage * 10 + 0.5) / 10) .. " dég"
			else
				dmgText = ""
			end
			local details = dmgText
			if tags ~= "" then
				details = if details ~= "" then details .. " · " .. tags else tags
			end
			table.insert(lines, ("%s• %s<font color=\"#%s\">%s</font>  <font color=\"#%s\">%s</font>"):format(
				indent, copies, P.Mid:ToHex(), card.Name, dim, details))
			if shot.Trigger then
				local t = shot.Trigger
				local when = if t.Kind == "Hit" then "à l'impact"
					elseif t.Kind == "Timer" then ("après %s s"):format(num(t.Delay or 0.35))
					elseif t.Kind == "Trap" then "quand un ennemi marche dessus"
					else "à expiration"
				table.insert(lines, ("%s   <font color=\"#%s\">└ %s, libère :</font>"):format(indent, Theme.TypeColor.Trigger:ToHex(), when))
				if shot.Payload and #shot.Payload.Shots > 0 then
					walk(shot.Payload, depth + 2)
				else
					table.insert(lines, ("%s      <font color=\"#%s\">(rien : plus de carte à lire)</font>"):format(indent, dim))
				end
			end
		end
	end

	if plan.Empty then
		table.insert(lines, ("<font color=\"#%s\">Aucun projectile : ce clic ne tire rien.</font>"):format(dim))
	else
		walk(plan.Root, 0)
	end
	if #lines > PREVIEW_MAX_LINES then
		local hidden = #lines - PREVIEW_MAX_LINES + 1
		for _ = 1, hidden do
			table.remove(lines)
		end
		table.insert(lines, ("<font color=\"#%s\">… et %d ligne(s) de plus</font>"):format(dim, hidden))
	end
	for _, line in lines do
		add(line, Theme.Body, 14, C.Text)
	end

	local sep = Theme.Frame(prev, "Sep", UDim2.new(1, 0, 0, 2), UDim2.new(), C.Line)
	order += 1
	sep.LayoutOrder = order

	previewCost = Planner.Cost(plan)
	local footer = ("Mana %d  ·  %d projectile(s)  ·  délai %s s%s"):format(
		previewCost, plan.Projectiles, num(math.floor(Planner.Delay(plan) * 100 + 0.5) / 100),
		if plan.ReachedEnd then " (recharge)" else "")
	local f = add(footer, Theme.Body, 14, C.Text)
	f.RichText = false
	ui.PreviewCost = f
	if (plan.ManaDelay or 0) >= 0.01 then
		add(("dont +%s s de délai dû au coût en mana"):format(num(math.floor(plan.ManaDelay * 100 + 0.5) / 100)), Theme.Body, 13, C.Delay)
	end
	if plan.CastMode == "Hold" then
		add(("MAINTIEN : puis %d mana toutes les 0,12 s tant que tu tiens le clic"):format(math.floor(math.max(2, previewCost * 0.3) + 0.5)), Theme.Body, 13, C.Gold)
	end
	if (plan.Capped or 0) > 0 then
		add(("! %d modificateur(s) au-delà du cumul max (3) : sans effet"):format(plan.Capped), Theme.Body, 13, C.Danger)
	end
	if plan.Truncated then
		add("! Coupé par le garde-fou : " .. (REASON_TEXT[plan.Reason] or tostring(plan.Reason)), Theme.Body, 13, C.Danger)
	end
	if simulating then
		local a, b = planSummary(baseDeck()), planSummary(deck)
		if a and b then
			local d = diffLines(a, b)
			add(Theme.Txt("Changements"), Theme.Font, Theme.Small, C.Gold).RichText = false
			if #d == 0 then
				table.insert(d, ("<font color=\"#%s\">Aucun changement sur ce clic</font>"):format(C.Dim:ToHex()))
			end
			for _, l in d do
				add(l, Theme.Body, 14, C.Text)
			end
		end
	end
	for _, t in deckTips(deck, previewCost) do
		add(t, Theme.Body, 13, if string.sub(t, 1, 1) == "!" then C.Danger else C.LineHi)
	end
end

local function showTooltip(id: string?, mouse: Vector2, slot: number?)
	local tip = ui.Tooltip
	if not id then
		tip.Visible = false
		state.TooltipId = nil
		return
	end
	local tipKey = id .. "#" .. tostring(slot) .. (if slot and Catalog.Useless(state.Deck, slot) then "!" else "")
		.. "|" .. table.concat(state.Deck, ",") .. "|" .. tostring(player:GetAttribute("WandCursor"))
	if state.TooltipId ~= tipKey then
		state.TooltipId = tipKey
		for _, c in tip:GetChildren() do
			if c:IsA("TextLabel") or c.Name == "Sep" then
				c:Destroy()
			end
		end
		local card = Catalog.ParseSlot(id)
		local typeColor = Theme.TypeColor[card.Type]
		ui.TooltipStroke.Color = typeColor
		local lines = tooltipLines(card, slot)
		-- carte du GRIMOIRE (modificateur) : son effet concret sur TON prochain clic
		if not slot and card.Type == "Modifier" then
			local sim = insertAhead(id)
			table.insert(lines, { "head", "Sur ton prochain clic" })
			if not sim then
				table.insert(lines, { "rule", "Baguette pleine : glisse la carte sur un emplacement pour voir son effet." })
			else
				local a, b = planSummary(state.Deck), planSummary(sim)
				local d = if a and b then diffLines(a, b) else {}
				if #d == 0 then
					table.insert(lines, { "rule", "Aucun changement visible sur ton prochain clic." })
				end
				for _, l in d do
					table.insert(lines, { "row", l })
				end
				table.insert(lines, { "rule", "(si tu la places juste avant ton prochain sort)" })
			end
		end
		for order, line in lines do
			local kind, text = line[1], line[2]
			if kind == "title" then
				local l = tipLabel(tip, order, Theme.Txt(text), Theme.Font, Theme.Big, typeColor)
				l.RichText = false
			elseif kind == "sub" then
				tipLabel(tip, order, text, Theme.Body, 15, C.Dim)
			elseif kind == "text" then
				tipLabel(tip, order, text, Theme.Body, 17, C.Text)
			elseif kind == "head" then
				local l = tipLabel(tip, order, "» " .. text, Theme.Body, 15, C.Gold)
				l.RichText = false
			elseif kind == "row" then
				tipLabel(tip, order, text, Theme.Body, 15, C.Text)
			elseif kind == "rule" then
				tipLabel(tip, order, text, Theme.Body, 14, C.LineHi)
			elseif kind == "cost" then
				tipLabel(tip, order, text, Theme.Body, 16, C.Text)
			elseif kind == "sep" then
				local s = Theme.Frame(tip, "Sep", UDim2.new(1, 0, 0, 2), UDim2.new(), C.Line)
				s.LayoutOrder = order
				s.ZIndex = 21
			end
		end
	end
	local screen = ui.Gui.AbsoluteSize
	local size = tip.AbsoluteSize
	local x = mouse.X + 18
	if x + size.X > screen.X - 8 then
		x = mouse.X - size.X - 18
	end
	local y = math.clamp(mouse.Y - size.Y - 12, 8, math.max(8, screen.Y - size.Y - 8))
	tip.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	tip.Visible = true
end

-- ── Hit-test ─────────────────────────────────────────────────────────────────────────────────
local function inside(g: GuiObject, p: Vector2): boolean
	local a, s = g.AbsolutePosition, g.AbsoluteSize
	return p.X >= a.X and p.Y >= a.Y and p.X < a.X + s.X and p.Y < a.Y + s.Y
end

-- Retourne ("slot", index) | ("lib", cardId) | ("libpanel") | ("wandpanel") | nil
local function targetAt(p: Vector2): (string?, any)
	if not ui.Gui then
		return nil, nil
	end
	for i, f in slotFrames do
		if inside(f, p) then
			return "slot", i
		end
	end
	if state.Open and ui.ClearBtn and inside(ui.ClearBtn, p) then
		return "clear", nil
	end
	if state.Open and ui.UndoBtn and inside(ui.UndoBtn, p) then
		return "undo", nil
	end
	if state.Open then
		for id, f in libCells do
			-- une carte cachée par le défilement garde des coordonnées : on exige aussi d'être DANS la zone visible
			if inside(f, p) and inside(ui.LibScroll, p) then
				return "lib", id
			end
		end
		if inside(ui.LibBody, p) then
			return "libpanel", nil
		end
	end
	if inside(ui.WandBody, p) then
		return "wandpanel", nil
	end
	return nil, nil
end

-- ── Machine d'état "carte en main" ───────────────────────────────────────────────────────────────
local function cancelHeld()
	local held = state.Held
	if not held then
		return
	end
	if held.From == "slot" and held.Index and state.Deck[held.Index] == "" then
		state.Deck[held.Index] = held.Id -- retour à sa place d'origine
	end
	state.Held = nil
	state.Press = nil
end

local function place(kind: string?, key: any)
	local held = state.Held
	if not held then
		return
	end
	if kind == "slot" then
		SoundFX.Play("Ui.Drop")
		local prev = state.Deck[key]
		-- MÊME modificateur déposé sur son slot : on EMPILE (max 3), le surplus retourne d'où il vient
		local hc, hn = Catalog.ParseSlot(held.Id)
		local pc, pn = Catalog.ParseSlot(prev)
		if hc and pc and hc == pc and Catalog.CanStack(hc) then
			local total = hn + pn
			local kept = math.min(total, Catalog.MaxStackOf(hc))
			state.Deck[key] = Catalog.SlotEntry(hc.Id, kept)
			local rest = total - kept
			if rest > 0 and held.From == "slot" and held.Index and state.Deck[held.Index] == "" then
				state.Deck[held.Index] = Catalog.SlotEntry(hc.Id, rest)
			end
			state.Held = nil
			state.Press = nil
			commit()
			return
		end
		state.Deck[key] = held.Id
		if held.From == "slot" and prev ~= "" and held.Index and state.Deck[held.Index] == "" then
			state.Deck[held.Index] = prev -- échange
		end
		-- (si la carte venait du grimoire, l'ancienne retourne simplement au grimoire)
		state.Held = nil
	elseif kind == "lib" or kind == "libpanel" then
		SoundFX.Play("Ui.Clear")
		state.Held = nil -- rangée dans le grimoire = retirée de la baguette
	elseif kind == nil then
		cancelHeld()
	else
		return -- bordure du panneau baguette : on garde la carte en main
	end
	state.Press = nil
	commit()
end

-- dir = -1 : annuler, +1 : rétablir
local function stepHistory(dir: number)
	if state.Held then
		cancelHeld()
	end
	local from, to = if dir < 0 then undoStack else redoStack, if dir < 0 then redoStack else undoStack
	local snap = table.remove(from)
	if not snap or #snap ~= state.Wand.Capacity then
		SoundFX.Play("NoMana") -- rien à annuler
		return
	end
	table.insert(to, table.clone(state.Deck))
	state.Deck = table.clone(snap)
	SoundFX.Play("Ui.Drop")
	commit(true)
end

local function onPress(p: Vector2)
	local kind, key = targetAt(p)
	if kind == "undo" then
		stepHistory(-1)
		return
	end
	if kind == "clear" then
		-- vide toute la baguette (et la carte en main, s'il y en a une)
		state.Held = nil
		state.Press = nil
		for i = 1, #state.Deck do
			state.Deck[i] = ""
		end
		SoundFX.Play("Ui.Clear")
		commit()
		return
	end
	if state.Held then
		place(kind, key)
		return
	end
	if kind == "slot" and state.Deck[key] ~= "" then
		state.Held = { Id = state.Deck[key], From = "slot", Index = key }
		state.Deck[key] = ""
	elseif kind == "lib" then
		state.Held = { Id = key, From = "lib" }
	else
		return
	end
	state.Press = { Pos = p, Dragging = false }
	SoundFX.Play("Ui.Pick")
	render()
end

local function onRelease(p: Vector2)
	local press = state.Press
	state.Press = nil
	if press and press.Dragging and state.Held then
		place(targetAt(p)) -- fin d'un glisser-déposer
	end
	-- sinon : simple clic -> la carte reste en main (mode clic-clic)
end

local function setOpen(open: boolean)
	if state.Open == open then
		return
	end
	state.Open = open
	if not open and state.Held then
		cancelHeld()
		commit()
	end
	ui.LibRoot.Visible = open
	if ui.ClearBtn then
		ui.ClearBtn.Visible = open
	end
	if ui.UndoBtn then
		ui.UndoBtn.Visible = open
	end
	SoundFX.Play(if open then "Ui.Open" else "Ui.Close")
	ui.KeyHint.Text = Theme.Txt(if open then "[E] Fermer" else "[E] Grimoire")
end

-- ── API publique ────────────────────────────────────────────────────────────────────────────
function WandUI.IsOpen(): boolean
	return state.Open
end

function WandUI.IsPointerOverUI(): boolean
	return (targetAt(mousePos())) ~= nil
end

-- Deck et baguette affichés (copie de travail locale) : sert à PRÉDIRE le tir au moment du clic.
function WandUI.GetDeck(): ({ string }, any)
	return state.Deck, state.Wand
end

function WandUI.FlashNoMana()
	state.NoManaUntil = os.clock() + 0.35
end

-- Deck officiel reçu du serveur.
function WandUI.SetDeck(deck: any, wand: any)
	if type(deck) ~= "table" then
		return
	end
	local capChanged = type(wand) == "table" and wand.Capacity ~= state.Wand.Capacity
	if type(wand) == "table" then
		state.Wand = wand
	end
	if state.Held then
		return -- ne pas écraser une manipulation en cours
	end
	local clean = table.create(state.Wand.Capacity, "")
	for i = 1, state.Wand.Capacity do
		local id = deck[i]
		local c, n = Catalog.ParseSlot(id)
		if c then
			clean[i] = Catalog.SlotEntry(c.Id, n)
		end
	end
	state.Deck = clean
	if capChanged then
		table.clear(undoStack) -- autre baguette : l'historique ne s'applique plus
		table.clear(redoStack)
	end
	lastDeck = table.clone(clean) -- deck officiel = nouvelle référence (pas une action du joueur)
	refreshUndoBtn()
	if capChanged then
		build()
	end
	render()
end

function WandUI.Init(cb)
	callbacks = cb
	state.Deck = table.create(state.Wand.Capacity, "")
	lastDeck = table.clone(state.Deck)
	build()
	render()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if UserInputService:GetFocusedTextBox() then
				return
			end
			if input.KeyCode == Enum.KeyCode.E then
				setOpen(not state.Open)
			elseif state.Open and (input.KeyCode == Enum.KeyCode.Z or input.KeyCode == Enum.KeyCode.Y)
				and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
				local redo = input.KeyCode == Enum.KeyCode.Y or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				stepHistory(if redo then 1 else -1)
			elseif input.KeyCode == Enum.KeyCode.Escape and state.Held then
				cancelHeld()
				commit()
			end
			return
		end
		if not state.Open then
			return -- édition seulement grimoire ouvert (sinon le clic gauche sert à tirer)
		end
		local p = mousePos()
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			onPress(p)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if state.Held then
				cancelHeld()
				commit()
			else
				local kind, key = targetAt(p)
				if kind == "slot" and state.Deck[key] ~= "" then
					-- slot empilé : le clic droit retire UN exemplaire
					local c, n = Catalog.ParseSlot(state.Deck[key])
					state.Deck[key] = if c and n > 1 then Catalog.SlotEntry(c.Id, n - 1) else ""
					SoundFX.Play("Ui.Clear")
					commit()
				elseif kind == "lib" then
					-- clic droit sur une carte du CATALOGUE : posée dans le PREMIER emplacement libre (en partant de la gauche)
					for i = 1, #state.Deck do
						if state.Deck[i] == "" then
							state.Deck[i] = key
							SoundFX.Play("Ui.Drop")
							commit()
							return
						end
					end
					SoundFX.Play("NoMana") -- baguette pleine : refus
				end
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and state.Open then
			onRelease(mousePos())
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not ui.Gui then
			return
		end
		local mouse = mousePos()

		-- glisser : seuil de déplacement
		local press = state.Press
		if press and not press.Dragging and (mouse - press.Pos).Magnitude > DRAG_THRESHOLD then
			press.Dragging = true
		end
		-- repère LOCAL du ScreenGui (pour positionner ses enfants directs : carte en main, infobulle)
		local localMouse = mouse - ui.Gui.AbsolutePosition
		if state.Held then
			ui.Ghost.Position = UDim2.fromOffset(math.floor(localMouse.X - SLOT / 2), math.floor(localMouse.Y - SLOT / 2))
		end

		-- mana (largeur arrondie au pixel)
		local mana = player:GetAttribute("Mana") or 0
		local manaMax = math.max(1, player:GetAttribute("ManaMax") or 1)
		local inner = ui.ManaBar.AbsoluteSize.X
		-- la barre GLISSE vers la valeur réelle (la dépense se voit, la régénération est fluide)
		state.ManaShown = (state.ManaShown or mana) + (mana - (state.ManaShown or mana)) * 0.25
		ui.ManaFill.Size = UDim2.new(0, math.floor(inner * math.clamp(state.ManaShown / manaMax, 0, 1)), 1, 0)
		-- régénération BLOQUÉE par une infusion (givre, foudre) : barre givrée + mention
		local blocked = player:GetAttribute("ManaBlocked") == true
		ui.ManaText.Text = if blocked then ("MANA %d/%d  ·  BLOQUÉ"):format(mana, manaMax) else ("MANA %d/%d"):format(mana, manaMax)
		ui.ManaFill.BackgroundColor3 = if blocked then Color3.fromRGB(70, 110, 140) else C.Mana
		ui.ManaStroke.Color = if os.clock() < state.NoManaUntil then C.Danger elseif blocked then Color3.fromRGB(150, 200, 230) else C.Line

		-- délai / recharge
		local now = workspace:GetServerTimeNow()
		local ready = player:GetAttribute("CastReadyAt") or 0
		local started = player:GetAttribute("CastStartedAt") or 0
		local ratio = if ready > started then math.clamp((now - started) / (ready - started), 0, 1) else 1
		ui.RechargeFill.Size = UDim2.new(0, math.floor(ui.RechargeBar.AbsoluteSize.X * ratio), 1, 0)
		ui.RechargeFill.BackgroundColor3 = if player:GetAttribute("Recharging") and ratio < 1 then C.Gold else C.Delay

		-- aperçu : recalculé quand le curseur de lecture avance (le deck, lui, déclenche render())
		local cursor = player:GetAttribute("WandCursor") or 1
		if cursor ~= state.LastCursor then
			state.LastCursor = cursor
			renderPreview()
		end
		if ui.PreviewCost then
			ui.PreviewCost.TextColor3 = if mana < previewCost then C.Danger else C.Text
		end

		-- survol
		local kind, key = targetAt(mouse)
		local simSlot = if state.Held and state.Open and kind == "slot" then key else nil
		if simSlot ~= state.SimSlot or (simSlot and state.SimHeld ~= state.Held) then
			state.SimSlot, state.SimHeld = simSlot, state.Held
			renderPreview()
		end
		if ui.ClearStroke then
			ui.ClearStroke.Thickness = if kind == "clear" then 2 else 1 -- survol du bouton Vider
		end
		if ui.UndoStroke then
			ui.UndoStroke.Thickness = if kind == "undo" then 2 else 1
		end
		-- survol d'une carte du grimoire : bordure claire + épaisse (on voit ce qu'on va prendre)
		local libHover = if kind == "lib" and not state.Held then libCells[key] else nil
		if ui.LibHover ~= libHover then
			if ui.LibHover then
				local s = ui.LibHover:FindFirstChildOfClass("UIStroke")
				if s then
					s.Color, s.Thickness = C.Line, 1
				end
			end
			if libHover then
				local s = libHover:FindFirstChildOfClass("UIStroke")
				if s then
					s.Color, s.Thickness = C.LineHi, 2
				end
			end
			ui.LibHover = libHover
		end
		for i, s in slotStrokes do
			if kind == "slot" and key == i and state.Open then
				s.Color = if state.Held then C.Gold else C.LineHi
			else
				s.Color = C.Line
			end
		end
		local hoverId, hoverSlot = nil, nil
		if not state.Held then
			if kind == "slot" and state.Deck[key] ~= "" then
				hoverId, hoverSlot = state.Deck[key], key
			elseif kind == "lib" then
				hoverId = key
			end
		end
		showTooltip(hoverId, localMouse, hoverSlot)
	end)
end

return WandUI

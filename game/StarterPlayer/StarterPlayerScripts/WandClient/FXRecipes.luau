--[[
	WandClient/FXRecipes
	Recettes visuelles = DONNÉES. Le VFXManager lit ces tables au lieu d'avoir un code par sort.
	Ajouter l'apparence d'une nouvelle carte = ajouter une entrée ici (aucun code à écrire tant que les
	briques existent). Les briques actuelles :
	  Impact : "Burst" (défaut) | "Firework"
	  Trail  : "Sparks" (défaut) | "Rocket"
	  Sprite : nom d'un sprite animé (Config.Sprites) affiché à la place du carré (SpriteSize en studs)
	  Core   : false = pas de cœur/halo carré (quand un sprite le remplace)
	  Blink  : cœur qui clignote (bombe, mine)
	  Beam   : "Lightning" | "Laser" pour les tirs instantanés
]]

local Elements = require(game:GetService("ReplicatedStorage"):WaitForChild("WandShared"):WaitForChild("Elements"))
local FXRecipes = {}

-- Valeurs par défaut de toute carte
local DEFAULT = {
	Trail = "Sparks",
	TrailSparks = 12, -- étincelles émises par seconde par le projectile
	Impact = "Burst",
	Flicker = 0.15, -- scintillement de la lumière du projectile (0..1)
	Light = 1, -- multiplicateur de lumière du projectile
}

-- Surcharges par carte (seules les clés qui changent)
-- recette visuelle PROPRE à une carte : champ FX de son module (WandShared/Spells/<ID>)
local CARDS = {
	ARC = { Beam = "Lightning" }, -- interne : arcs électriques d'un arbre de foudre (pas une carte)
}
do
	local Cat = require(game:GetService("ReplicatedStorage"):WaitForChild("WandShared"):WaitForChild("SpellCatalog"))
	for id, card in Cat.ById do
		if card.FX then
			CARDS[id] = card.FX
		end
	end
end

-- Comportement des étincelles selon l'élément
--   Gravity : chute (négatif = monte) | Drag : frottement de l'air | Bounce : restitution (0 = traverse)
--   Life : durée de vie | Speed : multiplicateur de vitesse d'éjection | Crackle : chance de "pop" secondaire
-- (défini dans WandShared/Elements/<Élément>.Sparks)
FXRecipes.ElementSparks = Elements.Field("Sparks")

-- Apparence des BRANCHES (sorts procéduraux) selon l'élément :
--   Bark = couleurs d'écorce (tirées au hasard par segment) ; Core = veine lumineuse (Neon) au cœur du segment ;
--   Leaf = couleurs de feuilles ; LeafChance ; Flame = flammes posées sur la branche ; Transparency.
--   L'écorce est AUTO-ÉCLAIRÉE (Neon) dans des tons sombres : le tronc reste lisible dans le noir sans éblouir.
-- Texture d'écorce pixel (tuilable 32 px, PixelSpell/tools/gen_sprites.js) posée en SurfaceGui NON ÉCLAIRÉ sur
-- les 4 faces longues de chaque segment ; Tint = teinte par élément.
FXRecipes.BarkTexture = "rbxassetid://103931292896980" -- plaques le long de l'axe X de l'image
FXRecipes.BarkTextureV = "rbxassetid://128300270808766" -- même texture tournée de 90° (faces Haut/Bas)
-- (défini dans WandShared/Elements/<Élément>.Branch)
FXRecipes.Branch = Elements.Field("Branch")

-- Palettes de feu d'artifice (paliers Core -> Mid -> Edge)
FXRecipes.FireworkPalettes = {
	{ Color3.fromHex("fff6c2"), Color3.fromHex("ffc53d"), Color3.fromHex("c4561a") }, -- or
	{ Color3.fromHex("ffe3f6"), Color3.fromHex("ff4fcf"), Color3.fromHex("7a1a6e") }, -- rose
	{ Color3.fromHex("e6fdff"), Color3.fromHex("4fe3ff"), Color3.fromHex("1a5f9e") }, -- cyan
	{ Color3.fromHex("efffd9"), Color3.fromHex("8aff4f"), Color3.fromHex("2d7a1a") }, -- vert
	{ Color3.fromHex("f1e3ff"), Color3.fromHex("a85cff"), Color3.fromHex("4a1f8a") }, -- violet
	{ Color3.fromHex("ffffff"), Color3.fromHex("ffffff"), Color3.fromHex("9aa6c4") }, -- argent
}

local cache = {}
function FXRecipes.Get(cardId: string?)
	local key = cardId or ""
	local r = cache[key]
	if not r then
		r = table.clone(DEFAULT)
		for k, v in CARDS[key] or {} do
			r[k] = v
		end
		cache[key] = r
	end
	return r
end

return FXRecipes

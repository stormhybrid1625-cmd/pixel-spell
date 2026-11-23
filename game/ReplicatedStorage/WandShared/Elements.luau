--[[
	WandShared/Elements — UN MODULE PAR ÉLÉMENT (tout ce qui le définit, au même endroit)

	Chaque enfant (Fire, Ice, Lightning, Toxic, Nature + éléments internes Arcane, Neutral, Steel, Chaos)
	renvoie une table :
	  Infusion : true si une carte d'infusion existe pour lui (les 5 éléments du joueur)
	  Palette  : couleurs / rotation / textures des particules (ex Config.Elements)
	  Sparks   : comportement des étincelles (ex FXRecipes.ElementSparks)
	  Branch   : apparence des branches procédurales (ex FXRecipes.Branch)
	  Affinity : multiplicateurs contre la MATIÈRE de chaque élément (ex MatterService.AFFINITY)
	  Status   : effet sur la CIBLE touchée (lu par Combat.Damage)
	  Sound    : noms d'événements sonores par phase (Profile), croissance (Grow), zone au sol (Patch)

	Lecteurs : Config, FXRecipes, MatterService, Combat, SoundFX. Pour modifier un élément : son seul module.
]]

local Elements = {}
local list = {}
for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") then
		local def = require(child)
		def.Id = child.Name
		Elements[child.Name] = def
		table.insert(list, def)
	end
end
table.sort(list, function(a, b)
	return a.Id < b.Id
end)

-- itérateur stable sur tous les éléments
function Elements.All()
	return list
end

-- les éléments qui ont une carte d'infusion (ceux du joueur)
function Elements.Infusions()
	local out = {}
	for _, def in list do
		if def.Infusion then
			table.insert(out, def)
		end
	end
	return out
end

-- table { [Id] = def[field] } pour les lecteurs qui veulent une vue par champ
function Elements.Field(field: string)
	local out = {}
	for _, def in list do
		if def[field] ~= nil then
			out[def.Id] = def[field]
		end
	end
	return out
end

-- COMPORTEMENT déclaré par un élément (Behavior) : Elements.Has("Fire", "PatchFalls") -> true
function Elements.Behavior(id: string?, key: string): any
	local def = id and Elements[id]
	return def and def.Behavior and def.Behavior[key]
end

return Elements

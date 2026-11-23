--[[
	WandClient/ConsistencyCheck — CONTRÔLE DE COHÉRENCE au démarrage (Studio uniquement)

	Vérifie, avant même de jouer, que tout ce qui est RÉFÉRENCÉ existe :
	  • cartes (WandShared/Spells|Modifiers) : sons propres (card.Sound) et sprites (card.FX.Sprite) ;
	  • éléments (WandShared/Elements) : sons de chaque phase (Profile, Grow, Patch) ;
	  • INFUSIONS (règle « sort complet ») : explosion propre (Explosion.<Élément>), Visuals (Impact + Patch),
	    Sounds, vignette d'écran (Screen.Images) et signature caméra (Camera) ;
	  • événements sonores : deux couches du même événement qui jouent le même fichier UNIQUE (son en phase).
	Résultat dans la sortie : « [WandCheck] OK » ou la liste des problèmes.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConsistencyCheck = {}

function ConsistencyCheck.Run(): (number, { string })
	local SoundFX = require(script.Parent:WaitForChild("SoundFX"))
	local D = SoundFX.Debug
	local Shared = ReplicatedStorage:WaitForChild("WandShared")
	local Catalog = require(Shared:WaitForChild("SpellCatalog"))
	local Elements = require(Shared:WaitForChild("Elements"))
	local Config = require(Shared:WaitForChild("Config"))
	local issues = {}
	local function bad(msg)
		table.insert(issues, msg)
	end
	local function sound(where: string, name: any)
		if name == false or name == nil then
			return
		end
		if type(name) ~= "string" then
			bad(where .. " : nom de son invalide")
		elseif not D.E[name] and not D.LOOP[name] then
			bad(where .. " : son « " .. name .. " » introuvable")
		end
	end
	-- cartes
	for _, id in Catalog.Order do
		local card = Catalog.ById[id]
		for phase, name in card.Sound or {} do
			sound("carte " .. id .. ".Sound." .. tostring(phase), name)
		end
		local fx = card.FX
		if fx and fx.Sprite and not Config.Sprites[fx.Sprite] then
			bad("carte " .. id .. ".FX.Sprite : sprite « " .. tostring(fx.Sprite) .. " » introuvable")
		end
		-- FAMILLES : tout sort déclare la sienne ; un modificateur ne vise que des familles connues
		if card.Type ~= "Modifier" and not Catalog.FamilyLabel[card.Family or ""] then
			bad("carte " .. id .. " : Family manquante ou inconnue (" .. tostring(card.Family) .. ")")
		end
		for _, f in card.AppliesTo or {} do
			if not Catalog.FamilyLabel[f] then
				bad("carte " .. id .. ".AppliesTo : famille inconnue « " .. tostring(f) .. " »")
			end
		end
	end
	-- fichiers : chaque boucle et chaque couche d'événement doit référencer des fichiers (Ids non vide)
	for nm, def in D.LOOP do
		if type(def.Ids) ~= "table" or #def.Ids == 0 then
			bad("boucle « " .. nm .. " » : aucun fichier (banque inexistante ?)")
		end
	end
	for nm, ev in D.E do
		for k, layer in ev.Layers or {} do
			if type(layer.Ids) ~= "table" or #layer.Ids == 0 then
				bad("événement « " .. nm .. " » couche " .. k .. " : aucun fichier (banque inexistante ?)")
			end
		end
	end
	-- éléments
	for _, def in Elements.All() do
		local where = "élément " .. def.Id
		local snd = def.Sound or {}
		for kind, spec in snd.Status or {} do -- sons des états sur les cibles
			for phase, nm in spec do
				sound(where .. ".Sound.Status." .. kind .. "." .. phase, nm)
			end
		end
		for phase, name in snd.Profile or {} do
			sound(where .. ".Profile." .. phase, name)
		end
		for phase, name in snd.Grow or {} do
			if type(name) == "string" then
				sound(where .. ".Grow." .. phase, name)
			end
		end
		for phase, name in snd.Patch or {} do
			if type(name) == "string" then
				sound(where .. ".Patch." .. phase, name)
			end
		end
		if def.Infusion then
			local mod = Shared.Elements:FindFirstChild(def.Id)
			if not D.E["Explosion." .. def.Id] and def.Id ~= "Fire" then
				bad(where .. " : pas d'explosion propre (Explosion." .. def.Id .. ")")
			end
			if not (mod and mod:FindFirstChild("Visuals")) then
				bad(where .. " : module Visuals manquant")
			else
				local ok, v = pcall(function()
					return require(mod.Visuals)({ Opts = {} })
				end)
				if ok and v then
					if not v.Impact then
						bad(where .. " : Visuals sans Impact")
					end
					if not v.Patch then
						bad(where .. " : Visuals sans Patch (zone au sol)")
					end
				end
			end
			if not (mod and mod:FindFirstChild("Sounds")) then
				bad(where .. " : module Sounds manquant")
			end
			if not (def.Screen and def.Screen.Images and #def.Screen.Images > 0) then
				bad(where .. " : pas de vignette d'écran (Screen.Images)")
			end
			if not def.Camera then
				bad(where .. " : pas de signature caméra (Camera)")
			end
			if not snd.Patch then
				bad(where .. " : pas de sons de zone au sol (Sound.Patch)")
			end
		end
	end
	-- même fichier UNIQUE joué deux fois dans le même événement (son « en phase »)
	for name, ev in D.E do
		local seen = {}
		for _, layer in ev.Layers or {} do
			local ids = layer.Ids or {}
			if #ids == 1 and not layer.Delay and not layer.Repeat then
				local key = tostring(ids[1])
				if seen[key] then
					bad("son " .. name .. " : deux couches jouent le même fichier unique " .. key .. " au même instant")
				end
				seen[key] = true
			end
		end
	end
	table.sort(issues)
	if #issues == 0 then
		print("[WandCheck] OK — cartes, éléments, infusions et sons cohérents")
	else
		warn(("[WandCheck] %d problème(s) :\n  "):format(#issues) .. table.concat(issues, "\n  "))
	end
	return #issues, issues
end

return ConsistencyCheck

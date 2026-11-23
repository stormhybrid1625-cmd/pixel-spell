--[[
	WandShared/Validator
	Fonctions de validation PURES (aucun état), utilisables des deux côtés :
	  - le client s'en sert pour pré-vérifier (confort d'UI) ;
	  - le serveur les ré-exécute TOUJOURS sur les données reçues : il ne fait jamais confiance au client.

	Règle d'or réseau : tout ce qui arrive par un RemoteEvent est de type `any`.
	On vérifie le type, la taille, les bornes, puis on RECONSTRUIT une donnée propre
	(on ne réutilise jamais la table envoyée par le client).
]]

local Shared = script.Parent
local Config = require(Shared.Config)
local Catalog = require(Shared.SpellCatalog)

local Limits = Config.Limits
local MAX_COORD = 1e5

local Validator = {}

local function isFiniteNumber(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

--[[
	Nettoie un deck envoyé par le client.
	  raw       : donnée brute reçue (any)
	  capacity  : nombre de slots de la baguette (côté serveur)
	  inventory : { [cardId] = quantité possédée } ; nil = tout est débloqué (mode test)
	Retourne un tableau dense de `capacity` chaînes ("" = slot vide), ou nil + raison.
]]
function Validator.SanitizeDeck(raw: any, capacity: number, inventory: { [string]: number }?): ({ string }?, string?)
	if type(raw) ~= "table" then
		return nil, "deck : table attendue"
	end

	-- Borne le nombre de clés : une table géante envoyée par un exploit est rejetée sans être parcourue entièrement.
	local keys = 0
	for _ in next, raw do
		keys += 1
		if keys > capacity + 8 then
			return nil, "deck : trop d'entrées"
		end
	end

	local clean = table.create(capacity, "")
	local used: { [string]: number } = {}
	for i = 1, capacity do
		local entry = rawget(raw, i)
		if type(entry) == "string" and #entry <= Limits.MaxCardIdLength then
			-- "ID" ou "ID*N" (cumul sur un slot, modificateurs seulement, N borné à 3)
			local card, n = Catalog.ParseSlot(entry)
			if card then
				local id = card.Id
				if inventory then
					local count = (used[id] or 0) + n
					if count <= (inventory[id] or 0) then
						used[id] = count
						clean[i] = Catalog.SlotEntry(id, n)
					end
				else
					clean[i] = Catalog.SlotEntry(id, n)
				end
			end
		end
		-- toute autre valeur (nil, nombre, id inconnu, chaîne trop longue...) devient un slot vide
	end
	return clean
end

-- Point visé envoyé par le client : Vector3 fini et dans des bornes raisonnables.
function Validator.IsValidAim(aim: any): boolean
	if typeof(aim) ~= "Vector3" then
		return false
	end
	return isFiniteNumber(aim.X) and isFiniteNumber(aim.Y) and isFiniteNumber(aim.Z)
		and math.abs(aim.X) < MAX_COORD and math.abs(aim.Y) < MAX_COORD and math.abs(aim.Z) < MAX_COORD
end

-- Temps de recharge : `readyAt` et `now` sont en temps serveur (workspace:GetServerTimeNow()).
function Validator.IsReady(readyAt: number, now: number): boolean
	return now >= readyAt
end

-- Coût en mana (le coût vient du PLAN calculé par le serveur, jamais du client).
function Validator.HasMana(mana: number, cost: number): boolean
	return isFiniteNumber(cost) and cost >= 0 and cost <= mana
end

return Validator

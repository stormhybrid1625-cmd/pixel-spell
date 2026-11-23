--[[
	WandShared/SpellCatalog
	Catalogue des cartes (pures données, aucune logique). Toutes les entrées sont gelées (table.freeze)
	pour qu'aucun module ne puisse les modifier par erreur pendant une exécution.

	Types de cartes :
	  Projectile : crée un projectile, consomme 1 pioche.
	  Trigger    : projectile qui transporte une CHARGE (les N cartes suivantes du deck),
	               libérée à l'impact (Hit), après un délai (Timer) ou à sa disparition (Expire).
	  Modifier   : modifie les projectiles qui le SUIVENT dans le même groupe de tir,
	               puis pioche une carte de plus (il ne compte pas comme un tir).
	  Multicast  : pioche N cartes supplémentaires, lancées simultanément en éventail.

	Icon : "rbxassetid://0" = pas d'icône -> l'UI affiche le glyphe Short (2 caractères).
]]

export type CardType = "Projectile" | "Trigger" | "Modifier" | "Multicast"

export type ProjStats = {
	Damage: number,
	Speed: number,
	Lifetime: number,
	Size: number,
	Radius: number, -- rayon d'explosion (0 = aucune)
	Gravity: number,
	Bounces: number,
	Pierce: number,
	Spread: number,
	Trajectory: string, -- "Straight" | "Wave" | "Spiral"
}

export type Card = {
	Id: string,
	Name: string,
	Short: string,
	Type: CardType,
	Element: string?,
	Mana: number,
	CastDelay: number,
	Recharge: number,
	Desc: string,
	Icon: string,
	Proj: ProjStats?,
	Trigger: { Kind: string, Draw: number, Delay: number? }?,
	Mod: { [string]: any }?,
	Draw: number?,
	Spread: number?,
}

local Catalog = {
	ById = {} :: { [string]: Card },
	Order = {} :: { string },
}

local function proj(t): ProjStats
	return table.freeze({
		Damage = t.Damage or 0,
		Speed = t.Speed or 100,
		Lifetime = t.Lifetime or 1,
		Size = t.Size or 0.6,
		Radius = t.Radius or 0,
		Gravity = t.Gravity or 0,
		Bounces = t.Bounces or 0,
		Pierce = t.Pierce or 0,
		Spread = t.Spread or 0,
		Trajectory = t.Trajectory or "Straight",
		-- mécaniques spéciales (2e vague)
		Instant = t.Instant or false, -- tir instantané (rayon / éclair) : portée = Range
		Range = t.Range or 0,
		Chain = t.Chain or 0, -- rebonds de cible en cible (éclair)
		Knockback = t.Knockback or 0, -- poussée sur les cibles touchées
		Aura = if t.Aura then table.freeze(t.Aura) else nil, -- dégâts périodiques autour du projectile (scie)
		Zone = if t.Zone then table.freeze(t.Zone) else nil, -- zone persistante créée à la fin du projectile
		Self = t.Self or false, -- pas de projectile : la zone apparaît sur le lanceur
		OnEnd = t.OnEnd, -- action spéciale à la fin ("Teleport")
		-- sort PROCÉDURAL : croissance (branches) depuis le point visé, sur une surface solide
		Growth = if t.Growth then table.freeze(t.Growth) else nil,
		-- sort de type PIÈGE : posé sur une surface, se déclenche quand un ennemi approche
		Trap = if t.Trap then table.freeze(t.Trap) else nil,
	})
end

-- Icônes : champ Icon / IconTag dans le module de la carte

local function add(card)
	assert(type(card.Id) == "string" and not Catalog.ById[card.Id], "Carte invalide ou en double")
	card.Icon = card.Icon or "rbxassetid://0"
		card.Mana = card.Mana or 0
	card.CastDelay = card.CastDelay or 0
	card.Recharge = card.Recharge or 0
	-- RANG (sorts seulement) : Moyen par défaut ; Superieur = impacte le champ de bataille ; Supreme = utilise le terrain
	if card.Type ~= "Modifier" and card.Family ~= "Multicast" then
		card.Rank = card.Rank or "Moyen"
	end
	if card.Type == "Projectile" or card.Type == "Trigger" then
		assert(card.Proj, card.Id .. " : Proj manquant")
	end
	-- SORTS MOYENS : taille de base +25 % (user 2026-11-23)
	if card.Rank == "Moyen" and card.Proj then
		local p = table.clone(card.Proj)
		p.Size *= 1.25
		card.Proj = table.freeze(p)
	end
	if card.Trigger then table.freeze(card.Trigger) end
	if card.Mod then table.freeze(card.Mod) end
	if card.AppliesTo then table.freeze(card.AppliesTo) end
	Catalog.ById[card.Id] = table.freeze(card)
	table.insert(Catalog.Order, card.Id)
end

-- ══ CHARGEMENT : une carte = un module (WandShared/Spells/<ID> et WandShared/Modifiers/<ID>) ══
-- Chaque module renvoie function(proj) -> carte. Order = position dans le grimoire.
do
	local defs = {}
	for _, folderName in { "Spells", "Modifiers" } do
		local folder = script.Parent:WaitForChild(folderName)
		for _, mod in folder:GetChildren() do
			if mod:IsA("ModuleScript") then
				local card = require(mod)(proj)
				assert(card.Id == mod.Name, "le module " .. mod.Name .. " doit avoir Id = \"" .. mod.Name .. "\"")
				table.insert(defs, card)
			end
		end
	end
	table.sort(defs, function(a, b)
		local oa, ob = a.Order or math.huge, b.Order or math.huge
		if oa ~= ob then
			return oa < ob
		end
		return a.Id < b.Id
	end)
	for _, card in defs do
		card.Order = nil
		add(card)
	end
end

function Catalog.Get(id: string): Card?
	return Catalog.ById[id]
end

-- ══ FAMILLES DE COMPORTEMENT ══
-- card.Family (sorts) : Projectile | Beam (rayon instantané) | Procedural (matière qui pousse) | Trap | Self | Multicast
-- card.AppliesTo (modificateurs) : familles sur lesquelles il a un effet ; absent = toutes.
Catalog.RankLabel = { Moyen = "Moyen", Superieur = "Supérieur", Supreme = "Suprême" }
Catalog.FamilyLabel = { Projectile = "Projectile", Beam = "Rayon", Procedural = "Procédural", Trap = "Piège", Self = "Sur soi", Multicast = "Multi-sort" }

-- le modificateur `mod` a-t-il un effet sur le sort `spell` ?
function Catalog.Affects(mod: Card, spell: Card): boolean
	local list = mod.AppliesTo
	if not list then
		return true
	end
	if spell.Family == "Trap" then
		return true -- le piège adaptatif transmet tout à ce qu'il déclenche
	end
	if spell.ModReactions and spell.ModReactions[mod.Id] then
		return true -- réaction spécifique déclarée par la carte (ex. Orbite sur Ramure = cage)
	end
	return table.find(list, spell.Family) ~= nil
end

-- sorts qu'un modificateur placé au slot i va modifier (lecture vers la droite : modificateurs ignorés,
-- un multi-sort étend le nombre de sorts concernés de Draw - 1)
function Catalog.TargetsOf(deck: { string }, i: number): { Card }
	local out, need = {}, 1
	for j = i + 1, #deck do
		local c = Catalog.ParseSlot(deck[j])
		if c then
			if c.Family == "Multicast" then
				need += math.max(0, (c.Draw or 1) - 1)
			elseif c.Type ~= "Modifier" then
				table.insert(out, c)
				if #out >= need then
					break
				end
			end
		end
	end
	return out
end

-- modificateur au slot i sans effet sur TOUS les sorts qu'il vise -> liste de ces sorts (sinon nil)
function Catalog.Useless(deck: { string }, i: number): { Card }?
	local mod = Catalog.ParseSlot(deck[i])
	if not mod or mod.Type ~= "Modifier" or not mod.AppliesTo then
		return nil
	end
	local targets = Catalog.TargetsOf(deck, i)
	if #targets == 0 then
		return nil
	end
	for _, s in targets do
		if Catalog.Affects(mod, s) then
			return nil
		end
	end
	return targets
end

-- ── CUMUL SUR UN MÊME SLOT ──
-- Un slot peut contenir jusqu'à 3 exemplaires du MÊME modificateur : entrée de deck "ID*2" / "ID*3".
-- Interdit pour les infusions (Element) et les modes de lancement (Maintien).
Catalog.MaxSlotStack = 3
-- cumul max d'UNE carte (card.MaxStack l'emporte : ex. Rapidité = 6)
function Catalog.MaxStackOf(card: Card?): number
	return (card and card.MaxStack) or Catalog.MaxSlotStack
end

function Catalog.CanStack(card: Card?): boolean
	return card ~= nil and card.Type == "Modifier" and card.Element == nil and card.Category ~= "CastMode"
end

-- entrée de deck -> (carte, nombre d'exemplaires)
function Catalog.ParseSlot(entry: any): (Card?, number)
	if type(entry) ~= "string" or entry == "" then
		return nil, 0
	end
	local id, n = string.match(entry, "^([%w_]+)%*(%d)$")
	if not id then
		return Catalog.ById[entry], 1
	end
	local card = Catalog.ById[id]
	if not Catalog.CanStack(card) then
		return card, 1
	end
	return card, math.clamp(tonumber(n) or 1, 1, Catalog.MaxStackOf(card))
end

function Catalog.SlotEntry(id: string, n: number?): string
	return if n and n > 1 then id .. "*" .. n else id
end

table.freeze(Catalog.Order)
return table.freeze(Catalog)

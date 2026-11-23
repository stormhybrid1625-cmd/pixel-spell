--[[
	WandServer/PlayerWands
	État serveur de chaque joueur : baguette, deck, curseur de lecture, mana, recharge.
	Le client n'a qu'une COPIE en lecture via des attributs du Player (répliqués automatiquement) :
	  Mana, ManaMax, CastReadyAt, CastStartedAt, Recharging, WandCursor
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.WandShared.Config)

export type WandState = {
	Wand: Config.WandStats,
	Deck: { string },
	Cursor: number,
	Mana: number,
	ReadyAt: number,
	CastStartedAt: number,
	Recharging: boolean,
	LastSetDeck: number,
	LastCastReq: number,
	PendingDeck: any,
	DeckScheduled: boolean,
	Inventory: { [string]: number }?, -- nil = tout débloqué (test)
}

local PlayerWands = {}

-- Combat chargé à la demande (évite une dépendance circulaire au chargement)
local combatMod
local function Combat()
	combatMod = combatMod or require(script.Parent.Combat)
	return combatMod
end
local states: { [Player]: WandState } = {}

function PlayerWands.Get(player: Player): WandState?
	return states[player]
end

function PlayerWands.Add(player: Player): WandState
	local wand = table.clone(Config.DefaultWand)
	local deck = table.create(wand.Capacity, "")
	for i, id in Config.DefaultDeck do
		if i <= wand.Capacity then
			deck[i] = id
		end
	end
	local st: WandState = {
		Wand = wand,
		Deck = deck,
		Cursor = 1,
		Mana = wand.ManaMax,
		ReadyAt = 0,
		CastStartedAt = 0,
		Recharging = false,
		LastSetDeck = 0,
		LastCastReq = 0,
		PendingDeck = nil,
		DeckScheduled = false,
		Inventory = nil,
	}
	states[player] = st
	PlayerWands.Sync(player)
	return st
end

function PlayerWands.Remove(player: Player)
	states[player] = nil
end

-- Pousse l'état vers les attributs répliqués (SetAttribute ne réplique que si la valeur change).
function PlayerWands.Sync(player: Player)
	local st = states[player]
	if not st then
		return
	end
	player:SetAttribute("ManaMax", st.Wand.ManaMax)
	player:SetAttribute("Mana", math.floor(st.Mana))
	player:SetAttribute("CastReadyAt", st.ReadyAt)
	player:SetAttribute("CastStartedAt", st.CastStartedAt)
	player:SetAttribute("Recharging", st.Recharging)
	player:SetAttribute("WandCursor", st.Cursor)
end

function PlayerWands.Init()
	-- Régénération du mana ; l'attribut n'est rafraîchi que 10 fois par seconde.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for player, st in states do
			-- toute baisse du mana = dépense : la régénération attend ManaRegenDelay s
			if st.PrevMana and st.Mana < st.PrevMana - 1e-3 then
				st.LastSpend = now
			end
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local mult = Combat().RegenMult(hum, "Mana") -- malus d'infusion (givre, foudre)
			local waiting = now - (st.LastSpend or 0) < (st.Wand.ManaRegenDelay or 0)
			if not st.Hold and not waiting and mult > 0 then -- pas de régénération pendant un lancement maintenu
				st.Mana = math.min(st.Wand.ManaMax, st.Mana + st.Wand.ManaRegen * mult * dt)
			end
			st.PrevMana = st.Mana
			st.ManaBlocked = mult <= 0
		end
		acc += dt
		if acc >= 0.1 then
			acc = 0
			for player, st in states do
				player:SetAttribute("Mana", math.floor(st.Mana))
				player:SetAttribute("ManaBlocked", st.ManaBlocked or nil)
			end
		end
	end)
end

return PlayerWands

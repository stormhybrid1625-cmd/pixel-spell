--[[
	WandServer/FXBus
	File d'attente des messages visuels serveur -> clients.
	Au lieu d'un FireAllClients par impact (des centaines par seconde avec des multicasts),
	on regroupe tous les messages d'une frame en UN SEUL envoi (batch) au Heartbeat.
	Format d'un message : { k = type, p = position, ... } (clés courtes = paquets légers).
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.WandShared.Config)

local FXBus = {}

local queue = {}
local remote: RemoteEvent

function FXBus.Init(r: RemoteEvent)
	remote = r
	RunService.Heartbeat:Connect(function()
		if #queue == 0 then
			return
		end
		local batch = queue
		queue = {}
		remote:FireAllClients(batch)
	end)
end

function FXBus.Push(msg)
	-- au-delà du plafond, les effets de la frame sont abandonnés (le gameplay, lui, continue)
	if #queue < Config.Limits.MaxFxPerFrame then
		table.insert(queue, msg)
	end
end

return FXBus

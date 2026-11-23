--[[
	WandClient/SoundAudit — MESURE AUTOMATIQUE DES SONS (Studio, en jeu côté client)

	require(WandClient.SoundAudit).Run() écoute TOUS les fichiers utilisés par SoundFX (banques P + identifiants
	écrits directement dans les couches), en PARALLÈLE et à volume nul, et mesure pour chacun :
	  • onset : début réel du son (premier instant > 8 % du pic) -> le blanc en tête à sauter (START_AT) ;
	  • tail  : fin réelle du son (dernier instant > 4 % du pic) ;
	  • peak / avg : niveau (prises très faibles = volume à compenser).
	Puis il croise avec chaque COUCHE d'événement (Start / Length / START_AT) et signale :
	  SILENCE_EN_TETE : la couche démarre dans le blanc et finit avant / juste après le vrai début du son ;
	  QUEUE_COUPEE    : coupe BRUSQUE (fondu < 0,15 s) sur un son encore fort (> 50 % du pic) ; les coupes avec un vrai fondu sont voulues.
	Retourne un rapport texte + une table de START_AT conseillés (onset > 0,05 s, absent de START_AT).
]]
local RunService = game:GetService("RunService")
local SoundAudit = {}

local function idsOf(list)
	local out = {}
	for _, v in list do
		local n = tonumber(v) or tonumber(tostring(v):match("%d+"))
		if n then
			table.insert(out, n)
		end
	end
	return out
end

-- mesure un lot de fichiers en parallèle ; renvoie [id] = { Len, Onset, Tail, Peak, Avg, Env = {{t, loud}} }
local function measureBatch(ids: { number }, maxDur: number)
	local sounds, res = {}, {}
	for _, id in ids do
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. id
		s.Volume = 0
		s.Parent = workspace
		sounds[id] = s
	end
	local t0 = os.clock()
	repeat
		local all = true
		for _, s in sounds do
			if not s.IsLoaded then
				all = false
			end
		end
		task.wait()
	until all or os.clock() - t0 > 8
	for id, s in sounds do
		res[id] = { Len = s.TimeLength, Env = {}, Peak = 0, Sum = 0, N = 0 }
		s:Play()
	end
	local start = os.clock()
	while os.clock() - start < maxDur do
		RunService.RenderStepped:Wait()
		for id, s in sounds do
			local r = res[id]
			if s.IsPlaying then
				local v = s.PlaybackLoudness
				table.insert(r.Env, { s.TimePosition, v })
				r.Peak = math.max(r.Peak, v)
				r.Sum += v
				r.N += 1
			end
		end
	end
	for id, s in sounds do
		s:Destroy()
		local r = res[id]
		r.Avg = if r.N > 0 then r.Sum / r.N else 0
		local on, tail = nil, 0
		for _, e in r.Env do
			if not on and e[2] > r.Peak * 0.08 then
				on = e[1]
			end
			if e[2] > r.Peak * 0.04 then
				tail = e[1]
			end
		end
		r.Onset = on or 0
		r.Tail = tail
	end
	return res
end

-- niveau (relatif au pic) à l'instant t du fichier
local function levelAt(r, t: number): number
	local best = 0
	for _, e in r.Env do
		if math.abs(e[1] - t) < 0.04 then
			best = math.max(best, e[2])
		end
	end
	return if r.Peak > 0 then best / r.Peak else 0
end

function SoundAudit.Run(opts)
	opts = opts or {}
	local SoundFX = require(script.Parent:WaitForChild("SoundFX"))
	local D = SoundFX.Debug
	assert(D, "SoundFX.Debug absent")
	-- tous les fichiers + toutes les couches qui les utilisent
	local all, uses = {}, {}
	local function addLayer(evName, layer)
		for _, id in idsOf(layer.Ids or {}) do
			all[id] = true
			uses[id] = uses[id] or {}
			table.insert(uses[id], { Ev = evName, L = layer })
		end
	end
	for name, ev in D.E do
		for _, layer in ev.Layers or {} do
			addLayer(name, layer)
		end
	end
	for name, def in D.LOOP do
		for _, id in idsOf(def.Ids or {}) do
			all[id] = true
		end
	end
	local list = {}
	for id in all do
		table.insert(list, id)
	end
	table.sort(list)
	-- mesure par lots de 24, 3,5 s chacun
	local res = {}
	for i = 1, #list, 24 do
		local batch = {}
		for k = i, math.min(i + 23, #list) do
			table.insert(batch, list[k])
		end
		for id, r in measureBatch(batch, opts.Duration or 3.5) do
			res[id] = r
		end
	end
	-- analyse des couches
	local lines, suggest = {}, {}
	local nSil, nTail = 0, 0
	for id, r in res do
		local start = D.START_AT[id] or 0
		if r.Onset > 0.05 and not D.START_AT[id] then
			suggest[id] = math.floor((r.Onset - 0.01) * 100) / 100
		end
		for _, u in uses[id] or {} do
			local L = u.L
			if L.Length and not L.Start then
				local endT = start + L.Length -- Length = secondes de FICHIER
				local fadeStart = endT - math.max(L.Fade or 0.1, if L.Length >= 0.25 then 0.16 else 0)
				if r.Onset > start + 0.05 and fadeStart < r.Onset + 0.05 then
					nSil += 1
					table.insert(lines, ("SILENCE_EN_TETE %-28s %d : blanc %.2fs, coupe à %.2fs"):format(u.Ev, id, r.Onset, endT))
				elseif fadeStart > r.Onset and fadeStart < r.Tail - 0.1 and math.max(L.Fade or 0.1, if L.Length >= 0.25 then 0.16 else 0) < 0.15 and levelAt(r, endT) > 0.5 then -- coupe BRUSQUE : fondu court sur un son encore fort
					nTail += 1
					table.insert(lines, ("QUEUE_COUPEE    %-28s %d : coupe à %.2fs (niveau %d %%), fin réelle %.2fs"):format(u.Ev, id, fadeStart, levelAt(r, fadeStart) * 100, r.Tail))
				end
			end
		end
	end
	table.sort(lines)
	local quiet = {}
	for id, r in res do
		if r.Peak > 0 and r.Avg < 6 then
			table.insert(quiet, id .. " (moy " .. math.floor(r.Avg) .. ")")
		end
	end
	local sug = {}
	for id, v in suggest do
		table.insert(sug, ("[%d] = %.2f"):format(id, v))
	end
	table.sort(sug)
	local header = ("AUDIT SON : %d fichiers mesurés — %d couches dans le blanc en tête, %d couches qui coupent la queue, %d START_AT conseillés, %d prises très faibles")
		:format(#list, nSil, nTail, #sug, #quiet)
	local report = header .. "\n" .. table.concat(lines, "\n")
		.. "\n\nSTART_AT conseillés :\n" .. table.concat(sug, ", ")
		.. "\n\nPrises très faibles (à compenser au volume) :\n" .. table.concat(quiet, ", ")
	return report, suggest, res
end

return SoundAudit

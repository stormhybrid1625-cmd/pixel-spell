--[[
	ServerStorage/WandTools — OUTILS DE CRÉATION (Studio, mode édition)

	Créer une nouvelle carte, prête à remplir, en UNE commande (barre de commande Studio) :

	  require(game.ServerStorage.WandTools).NewSpell({
	      Id = "FROST_NOVA",            -- MAJUSCULES_AVEC_TIRETS, unique
	      Name = "Nova de givre",       -- nom affiché
	      Kind = "Projectile",          -- Projectile | Beam | Zone | Trigger | Multicast | Modifier
	      Element = "Ice",              -- élément NATIF (facultatif ; défaut Arcane, neutre)
	      Desc = "Description courte.", -- facultatif
	  })

	Le fichier est créé dans WandShared/Spells (ou Modifiers) avec :
	  • les données de la carte (valeurs de départ raisonnables à ajuster) ;
	  • son identité sonore (Sound) et visuelle (FX), commentées ;
	  • les ACCROCHES (Hooks / ModReactions) commentées avec des exemples ;
	  • la section INFUSIONS : les 5 éléments (Feu, Glace, Foudre, Toxique, Nature) sont pris en charge
	    AUTOMATIQUEMENT (sons + visuels + effet sur la cible, via WandShared/Elements) ; le modèle montre
	    comment donner à une infusion un comportement PROPRE à ce sort.
	Il apparaît dans le grimoire à la fin (Order = dernier + 1). Ensuite : tester avec
	ServerStorage.WandTest:Invoke("Matrix", player, { Cards = { "FROST_NOVA" }, Targets = { "dummy", "ground", "wall" } }).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WandTools = {}

local KINDS = {
	Projectile = { Type = "Projectile", Folder = "Spells", Family = "Projectile" },
	Beam = { Type = "Projectile", Folder = "Spells", Family = "Beam" },
	Zone = { Type = "Projectile", Folder = "Spells", Family = "Projectile" }, -- projectile qui pose une zone à sa fin
	Trigger = { Type = "Trigger", Folder = "Spells", Family = "Projectile" },
	Multicast = { Type = "Multicast", Folder = "Spells", Family = "Multicast" },
	Modifier = { Type = "Modifier", Folder = "Modifiers" },
}

local function short(name: string): string
	local letters = {}
	for word in name:gmatch("[%wÀ-ÿ]+") do
		table.insert(letters, word:sub(1, 1):upper())
		if #letters == 2 then
			break
		end
	end
	if #letters < 2 then
		return name:sub(1, 2):upper()
	end
	return table.concat(letters)
end

local function maxOrder(): number
	local best = 0
	for _, folderName in { "Spells", "Modifiers" } do
		for _, mod in ReplicatedStorage.WandShared[folderName]:GetChildren() do
			local n = tonumber(mod.Source:match("card%.Order = (%d+)"))
			if n and n > best then
				best = n
			end
		end
	end
	return best
end

local function q(s: string): string
	return string.format("%q", s)
end

-- partie commune : sons / visuels / accroches / infusions (projectiles)
local function spellTail(kind: string): string
	local hooksExample = if kind == "Zone" then "" else [[
		-- OnEnd = function(ctx)
		--     -- ex. laisser une zone au sol de l'élément du sort :
		--     ctx.CreateZone({ Kind = "Patch", Radius = 4, Duration = 3, Damage = 2, Interval = 0.5 })
		-- end,
]]
	return [[
	-- ── SON PROPRE À LA CARTE (facultatif) ─────────────────────────────────────────────────────────
	-- Sans ce champ, la carte prend le profil sonore de son ÉLÉMENT (Elements/<Élément>/Sounds).
	-- Phases : Cast (départ), Travel (boucle de vol), Impact, Bounce, Body (rebond lourd), Beam, Explosion ;
	-- false = phase muette. Une carte infusée garde son identité ET reçoit la couche de l'infusion.
	-- card.Sound = { Cast = "Cast.Lob", Impact = "Impact.Thud" },

	-- ── VISUEL PROPRE À LA CARTE (facultatif) ──────────────────────────────────────────────────────
	-- Trail ("Sparks" | "Rocket"), TrailSparks (étincelles/s), Impact ("Burst" | "Firework"), Flicker, Light,
	-- Blink (cœur qui clignote), Beam ("Lightning" | "Laser"), Sprite (Config.Sprites) + SpriteSize, Core = false.
	card.FX = { TrailSparks = 12 }

	-- ── ACCROCHES : comportement SPÉCIAL du sort (facultatif) ──────────────────────────────────────
	-- ctx : Owner, Stats, CardId, Element (élément ACTUEL, infusion comprise), Pos, Normal, Dir, Age,
	--       CreateZone(spec, scale?), DamageRadius(r, dmg, el?), Damage(hum, dmg, el?), Explode(r, dmg, el?),
	--       FX(msg), Matter
	card.Hooks = {
]] .. hooksExample .. [[
		-- OnHit = function(ctx, humanoid) end,   -- le projectile touche une cible
		-- OnTick = function(ctx, dt) end,        -- chaque image pendant le vol (garder léger)
	}

	-- ── RÉACTIONS À DES MODIFICATEURS précis (facultatif) ──────────────────────────────────────────
	-- card.ModReactions = {
	--     ORBIT = function(stats, stacks) stats.Cage = "Self" end,
	-- }

	-- ── INFUSIONS (Feu, Glace, Foudre, Toxique, Nature) ────────────────────────────────────────────
	-- Prises en charge AUTOMATIQUEMENT : son de chaque phase, explosion, traînée, impact, effet sur la cible
	-- (brûlure, gel, choc, poison, entrave) et réaction avec la matière — définis dans WandShared/Elements.
	-- Pour un comportement PROPRE à ce sort selon l'infusion, utiliser ctx.Element dans une accroche :
	--     OnEnd = function(ctx)
	--         if ctx.Element == "Ice" then ... elseif ctx.Element == "Fire" then ... end
	--     end
]]
end

local TEMPLATES = {}

TEMPLATES.Projectile = function(o)
	return ([[
	local card = { Id = %s, Name = %s, Short = %s, Type = "Projectile", Element = %s,
		Mana = 20, CastDelay = 0.1, Desc = %s,
		-- Damage, Speed (studs/s), Lifetime (s), Size, Radius (explosion, 0 = aucune), Gravity, Bounces, Pierce,
		-- Spread (°), Trajectory ("Straight" | "Wave" | "Spiral"), Knockback, Aura = { Radius, Damage, Interval }
		Proj = proj({ Damage = 8, Speed = 110, Lifetime = 1, Size = 0.8, Radius = 0, Gravity = 0 }) }
]]):format(q(o.Id), q(o.Name), q(o.Short), q(o.Element), q(o.Desc)) .. spellTail("Projectile")
end

TEMPLATES.Beam = function(o)
	return ([[
	local card = { Id = %s, Name = %s, Short = %s, Type = "Projectile", Element = %s,
		Mana = 25, CastDelay = 0.12, Desc = %s,
		-- tir INSTANTANÉ : Range = portée ; Chain = rebonds de cible en cible
		Proj = proj({ Damage = 9, Instant = true, Range = 60, Chain = 0, Size = 0.4 }) }
	card.Sound = { Cast = false, Beam = "Beam.Laser" }
]]):format(q(o.Id), q(o.Name), q(o.Short), q(o.Element), q(o.Desc)) .. spellTail("Beam"):gsub("card%.FX = { TrailSparks = 12 }", 'card.FX = { Beam = "Laser" }')
end

TEMPLATES.Zone = function(o)
	return ([[
	local card = { Id = %s, Name = %s, Short = %s, Type = "Projectile", Element = %s,
		Mana = 30, CastDelay = 0.2, Desc = %s,
		-- projectile lent qui crée une ZONE à sa fin. Kind = type de zone (ZoneService.KINDS : Gas, BlackHole,
		-- FireRing, IceWall, Shield, Patch...) ; Radius, Duration, Damage, Interval
		Proj = proj({ Damage = 2, Speed = 50, Lifetime = 0.8, Size = 0.8, Gravity = 0.4,
			Zone = { Kind = "Gas", Radius = 8, Duration = 5, Damage = 3, Interval = 0.5 } }) }
]]):format(q(o.Id), q(o.Name), q(o.Short), q(o.Element), q(o.Desc)) .. spellTail("Zone")
end

TEMPLATES.Trigger = function(o)
	return ([[
	local card = { Id = %s, Name = %s, Short = %s, Type = "Trigger", Element = %s,
		Mana = 15, CastDelay = 0.08, Desc = %s,
		Proj = proj({ Damage = 4, Speed = 120, Lifetime = 1, Size = 0.6 }),
		-- CHARGE : les Draw cartes suivantes du deck, libérées à l'impact ("Hit"), après Delay s ("Timer")
		-- ou à la disparition ("Expire")
		Trigger = { Kind = "Hit", Draw = 1 } }
]]):format(q(o.Id), q(o.Name), q(o.Short), q(o.Element), q(o.Desc)) .. spellTail("Trigger")
end

TEMPLATES.Multicast = function(o)
	return ([[
	local card = { Id = %s, Name = %s, Short = %s, Type = "Multicast", Draw = 2, Spread = 10,
		Mana = 10, CastDelay = 0, Desc = %s }
	-- Draw = cartes supplémentaires lancées EN MÊME TEMPS ; Spread = éventail (°)
]]):format(q(o.Id), q(o.Name), q(o.Short), q(o.Desc))
end

TEMPLATES.Modifier = function(o)
	return ([[
	local card = { Id = %s, Name = %s, Short = %s, Type = "Modifier",
		Mana = 10, Desc = %s,
		-- MODIFICATEUR : transforme les statistiques des sorts qui le SUIVENT dans le même tir.
		-- Clés reconnues (SpellPlanner.applyMod) : DamageAdd, DamageMult, SpeedMult, SizeMult, LifetimeMult,
		-- Bounces, Pierce, Homing, Trajectory, Knockback, DurationMult, Radius... (voir les autres modules)
		-- Il marche automatiquement sur TOUS les sorts ; un sort peut y réagir spécialement (ModReactions).
		Mod = { DamageAdd = 3 } }
]]):format(q(o.Id), q(o.Name), q(o.Short), q(o.Desc))
end

function WandTools.NewSpell(o)
	assert(type(o) == "table", "NewSpell({ Id = ..., Name = ..., Kind = ... })")
	assert(type(o.Id) == "string" and o.Id:match("^[A-Z][A-Z0-9_]*$"), "Id en MAJUSCULES_AVEC_TIRETS (ex. FROST_NOVA)")
	local kind = KINDS[o.Kind or "Projectile"]
	assert(kind, "Kind inconnu : Projectile | Beam | Zone | Trigger | Multicast | Modifier")
	local WS = ReplicatedStorage.WandShared
	for _, f in { "Spells", "Modifiers" } do
		assert(not WS[f]:FindFirstChild(o.Id), o.Id .. " existe déjà dans " .. f)
	end
	if o.Element then
		assert(WS.Elements:FindFirstChild(o.Element), "élément inconnu : " .. tostring(o.Element))
	end
	local opts = {
		Id = o.Id, Name = o.Name or o.Id, Short = o.Short or short(o.Name or o.Id),
		Element = o.Element or "Arcane", Desc = o.Desc or "À décrire.",
	}
	local body = TEMPLATES[o.Kind or "Projectile"](opts)
	local order = maxOrder() + 1
	local src = ("-- %s — %s (%s, créé avec WandTools.NewSpell)\n"):format(opts.Id, opts.Name, o.Kind or "Projectile")
		.. "-- Une carte = ce fichier : données, son, visuel, accroches. Les 5 infusions sont gérées par WandShared/Elements.\n"
		.. "return function(proj)\n" .. body
		.. ("\tcard.Order = %d -- position dans le grimoire\n"):format(order)
		.. (if kind.Family then ("\tcard.Family = \"%s\" -- famille (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs agissent\n"):format(kind.Family)
			else "\t-- card.AppliesTo = { \"Projectile\", \"Beam\" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette\n")
		.. "\t-- card.Icon = \"rbxassetid://...\" -- icône pixel 16x16 (sinon : glyphe Short)\n"
		.. "\treturn card\nend\n"
	local fn, err = loadstring(src)
	assert(fn, "modèle invalide : " .. tostring(err))
	local mod = Instance.new("ModuleScript")
	mod.Name = o.Id
	mod.Source = src
	mod.Parent = WS[kind.Folder]
	print(("[WandTools] carte %s créée dans WandShared/%s (Order %d). Ouvre le fichier pour l'ajuster."):format(o.Id, kind.Folder, order))
	return mod
end

-- supprime une carte créée par erreur (avec confirmation explicite)
function WandTools.DeleteSpell(id: string, confirm: boolean?)
	assert(confirm == true, "DeleteSpell(id, true) : confirmation requise")
	for _, f in { "Spells", "Modifiers" } do
		local mod = ReplicatedStorage.WandShared[f]:FindFirstChild(id)
		if mod then
			mod:Destroy()
			print("[WandTools] carte " .. id .. " supprimée")
			return true
		end
	end
	return false
end

-- ══ GARDE ANTI-ÉCRASEMENT (Team Create) ══════════════════════════════════════════════════════════
-- Un brouillon de script resté ouvert peut ÉCRASER une modification déjà validée (arrivé à Sparks et au Lest).
-- Chaque correction importante laisse ici une « signature » : un extrait de code qui DOIT exister.
-- En Edit : require(ServerStorage.WandTools:Clone()).Guard() -> liste de ce qui a disparu.
local SIGNATURES = {
	{ "StarterPlayer.StarterPlayerScripts.WandClient.Sparks", "BulkMoveMode.FireCFrameChanged", "Sparks : mode BulkMove valide (sinon spam d'erreurs)" },
	{ "ServerScriptService.WandServer.GrowthService", "g.Weight > 0", "Lest sur Ramure" },
	{ "ServerScriptService.WandServer.GrowthService", "encore SOUS la surface", "Lest : rien sous le sol" },
	{ "ServerScriptService.WandServer.GrowthService", "g.OnEnd", "Ajout d'expiration sur Ramure" },
	{ "ServerScriptService.WandServer.GrowthService", "TipMark", "Branche chargée (mèche)" },
	{ "ServerScriptService.WandServer.ProjectileService", "OnSurface", "Accroche OnSurface (rebonds des rayons)" },
	{ "ServerScriptService.WandServer.ProjectileService", "SpiralRadius", "Cumul de Spirale" },
	{ "ServerScriptService.WandServer.ProjectileService", "payloadLaunch", "Départ de la suite selon la famille" },
	{ "ServerScriptService.WandServer.ZoneService", "supported(zone)", "Zone détruite avec sa surface" },
	{ "ServerScriptService.WandServer.ZoneService", "Matter.Afflict", "Zones qui abîment la matière" },
	{ "ServerScriptService.WandServer.MatterService", "function MatterService.Afflict", "Afflict (matière)" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.SoundFX", "SLOT_HOLD", "Sons : place libérée après l'attaque" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.SoundFX", "ThunderRoll", "Tonnerre continu (éclair maintenu)" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.VFXManager", "local function matterCoat", "Gangue d'élément sur la matière" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.VFXManager", "local function tipMark", "Effet de mèche" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.VFXManager", "local function spreadPoint", "Givre posé sur la surface" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.WandUI", "stepHistory", "Annuler dans le grimoire" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.WandUI", "Catalog.Useless", "Avertissement « Sans effet »" },
	{ "ReplicatedStorage.WandShared.SpellCatalog", "function Catalog.Affects", "Familles de sorts" },
	{ "ReplicatedStorage.WandShared.SpellPlanner", "SpiralAdd", "Cumul de Spirale (planificateur)" },
	{ "ReplicatedStorage.WandShared.SpellPlanner", "Ajout d'expiration CUMUL", "Cumul d'Ajout d'expiration" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.VFXManager", "local function flameStack", "Flammes volumineuses" },
	{ "ReplicatedStorage.WandShared.Elements.Fire.Visuals", "CHAMP DE FLAMMES", "Champ de flammes de la boule de feu" },
	{ "ServerScriptService.WandServer.ZoneService", "ground(from, 600)", "Feu qui retombe même explosé très haut" },
	{ "ReplicatedStorage.WandShared.Elements.Fire.Sounds", "Patch.FireGust", "Brasier qui ronfle" },
	{ "ReplicatedStorage.WandShared.SpellPlanner", "function Planner.ManaDelay", "Délai lié au coût en mana" },
	{ "ReplicatedStorage.WandShared.SpellPlanner", "MANA_DELAY_MAX", "Plafond du délai de mana" },
	{ "ReplicatedStorage.WandShared.SpellPlanner", "card.ManaGrowth", "Coût croissant (Rapidité)" },
	{ "ReplicatedStorage.WandShared.SpellPlanner", "budget.DelayMult", "Rapidité proportionnelle" },
	{ "ReplicatedStorage.WandShared.SpellCatalog", "function Catalog.MaxStackOf", "Cumul max par carte (Rapidité x6)" },
	{ "ServerScriptService.WandServer.TestBench", "MODE MAINTIEN", "Banc de test du Maintien" },
	{ "ServerScriptService.WandServer.TestBench", "function TestBench.RunPerf", "Banc de performance (1.4)" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.VFXManager", "STATUS_DEF[v.Status.Kind]", "États et ambiance dans les modules d'éléments (1.5)" },
	{ "ReplicatedStorage.WandShared.Elements.Fire.Visuals", "Kind = \"Burning\"", "État brûlure (module Feu)" },
	{ "ServerScriptService.WandServer.ProjectileService", "local function hookCards", "Accroches universelles des modificateurs (1.6)" },
	{ "ServerScriptService.WandServer.GrowthService", "local function fireHook", "Ramure annonce les 4 moments (1.6)" },
	{ "ReplicatedStorage.WandShared.SpellPlanner", "ModStacks = table.clone", "Modificateurs portés par le tir (1.6)" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.Sparks", "opts.Priority", "Impacts prioritaires dans la réserve d'étincelles" },
	{ "ServerScriptService.WandServer.ZoneService", "if not zone.Spec.Trail then", "Traînée de feu sans incendie" },
	{ "ServerScriptService.WandServer.ZoneService", "not B(el, \"PatchFalls\") and not zone.Spec.Trail", "Traînées sans dégâts à la matière" },
	{ "ServerScriptService.WandServer.ZoneService", "if zone.Spec.Trail then 8 else 4.5", "Traînée non-feu posée au sol sous le tir" },
	{ "ReplicatedStorage.WandShared.Modifiers.TRAIL_FIRE", "HAS_PATCH", "Traînée élémentaire (élément du sort)" },
	{ "ReplicatedStorage.WandShared.Elements.Toxic.Visuals", "if at and not vis.Dead then", "Flaques toxiques orphelines" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.VFXManager", "vis.Dead = true", "Zones : créations différées annulées" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.WandUI", "local function deckTips", "Aide au deck (conseils)" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.SoundFX", "couche sans fichiers", "SoundFX.Init robuste" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.FpsCounter", "FPS", "Compteur d'images par seconde" },
	{ "ServerScriptService.WandServer.Combat", "local function runReactions", "Effets d'élément pilotés par les données + réactions (2.2-2.4)" },
	{ "ReplicatedStorage.WandShared.Reactions", "Explosion de gaz", "Table des réactions" },
	{ "ServerScriptService.WandServer.ZoneService", "local B = Elements.Behavior", "Comportements de zone déclarés par les éléments" },
	{ "ServerScriptService.WandServer.MatterService", "local B = Elements.Behavior", "Comportements de matière déclarés par les éléments" },
	{ "ReplicatedStorage.WandShared.Elements.Ice.Visuals", "Kind = \"Frozen\"", "Visuel du gel" },
	{ "ServerScriptService.WandServer.ZoneService", "function ZoneService.ReactAt", "Réactions de zone (2.5)" },
	{ "ReplicatedStorage.WandShared.ReactionVisuals", "V.Steam = function", "Effets visuels des réactions" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.Sparks", "opts.Matte", "Étincelles mates" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.VFXManager", "local function barkPart", "Écorce de Ramure partagée" },
	{ "ReplicatedStorage.WandShared.Elements.Nature.Visuals", "RACINES QUI ATTRAPENT", "Racines qui enserrent la cible" },
	{ "ServerScriptService.WandServer.Combat", "S.LockTime * durMult", "Prolongation allonge gel et enracinement" },
	{ "ServerScriptService.WandServer.Combat", "st.Pinned = pin", "Cible bloquée fixée sur place" },
	{ "ReplicatedStorage.WandShared.Elements.Nature.Visuals", "s.Holder = holder -- OBLIGATOIRE", "Racines effacées à la fin" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.SoundFX", "local STATUS: { [string]: { Start", "Sons des états déclarés par les éléments" },
	{ "StarterPlayer.StarterPlayerScripts.WandClient.VFXManager", "SoundFX.Status(s.Holder or root, kind)", "États sans visuel sonores (poison)" },
	{ "ReplicatedStorage.WandShared.Elements.Nature.Sounds", "Status.RootGrab", "Sons de l'enracinement" },
	{ "ServerScriptService.WandServer", "Hold = function(player: Player, aim: Vector3, duration: number", "Banc Maintien (pilotage serveur)" },
}
WandTools.Signatures = SIGNATURES

function WandTools.Guard(): { string }
	local lost = {}
	for _, sig in SIGNATURES do
		local inst: Instance? = game
		for part in string.gmatch(sig[1], "[^%.]+") do
			inst = inst and inst:FindFirstChild(part)
		end
		if not inst then
			table.insert(lost, "SCRIPT INTROUVABLE " .. sig[1] .. " (" .. sig[3] .. ")")
		elseif not string.find((inst :: any).Source, sig[2], 1, true) then
			table.insert(lost, "DISPARU : " .. sig[3] .. "  [" .. sig[1] .. "]")
		end
	end
	if #lost == 0 then
		print(("[WandTools.Guard] OK — %d modifications toujours présentes"):format(#SIGNATURES))
	else
		warn("[WandTools.Guard] " .. #lost .. " modification(s) écrasée(s) :\n  " .. table.concat(lost, "\n  "))
	end
	return lost
end

-- TABLE DE COUVERTURE (statique) : chaque sort x chaque modificateur, d'après le CONTRAT (WandShared.SpellContract).
-- Renvoie (lignes, incohérences). Codes : S stats lues, H accroche, C copies, T déclencheur, L lancement,
-- R réaction spéciale, · sans effet ; suffixe ? = déclaré inutile mais agit ; ! = déclaré utile mais rien détecté.
-- (« ! » peut être un faux positif pour ce qui agit hors des stats, ex. Fragmentation sur un rayon : vérifier au banc.)
function WandTools.Coverage(): ({ string }, { string })
	local WS = game:GetService("ReplicatedStorage").WandShared
	local P, C, Cat = require(WS.SpellPlanner), require(WS.Config), require(WS.SpellCatalog)
	local Contract = require(WS.SpellContract)
	local Reads = Contract.Reads
	local spells, mods = {}, {}
	for _, id in Cat.Order do
		local c = Cat.Get(id)
		if c.Type == "Modifier" then
			table.insert(mods, c)
		elseif c.Family ~= "Multicast" then
			table.insert(spells, c)
		end
	end
	local function ser(t)
		if type(t) ~= "table" then
			return tostring(t)
		end
		local o = {}
		for k, v in t do
			table.insert(o, tostring(k) .. "=" .. ser(v))
		end
		table.sort(o)
		return "{" .. table.concat(o, ",") .. "}"
	end
	local function run(deck)
		local d = table.clone(deck)
		for i = #d + 1, 8 do
			d[i] = ""
		end
		local pl = P.Plan(d, C.DefaultWand, 1)
		local sh = pl.Root.Shots[1]
		return pl, sh, sh and P.Resolve(sh, C.DefaultWand)
	end
	local rows, issues = {}, {}
	for _, sp in spells do
		local bp, bs, base = run({ sp.Id })
		local line = {}
		local reads = Reads[sp.Family] or Reads.Projectile
		for _, m in mods do
			local pl, sh, r = run({ m.Id, sp.Id })
			local code = "·"
			if base and r then
				local changed, eff = {}, false
				for k, v in r do
					if type(v) ~= "table" and base[k] ~= v and k ~= "Mana" then
						table.insert(changed, k .. (if reads[k] then "" else "(ignoré)"))
						eff = eff or reads[k] == true
					end
				end
				local cast = math.abs((pl.CastDelay - (pl.ManaDelay or 0)) - (bp.CastDelay - (bp.ManaDelay or 0))) > 1e-6
					or math.abs(pl.Recharge - bp.Recharge) > 1e-6 or pl.CastMode ~= bp.CastMode or P.Cost(pl) < P.Cost(bp)
				local copies = sh.Copies ~= bs.Copies
				local trig = m.Id:find("^ADD_") ~= nil and m.Id ~= "ADD_MANA" and ser(sh.State) ~= ser(bs.State)
				local hook = m.Hooks and next(m.Hooks) ~= nil
				local aff = Cat.Affects(m, sp)
				local fam = sp.Family
				local trigOK = Contract.Triggers[fam] == nil or Contract.Triggers[fam][m.Id] == true
				if trig and not trigOK then
					trig = false
				end
				if Contract.NoCopies[fam] then
					copies = false
				end
				if Contract.NoHooks[fam] then
					hook = false
				end
				if sp.ModReactions and sp.ModReactions[m.Id] then
					code = "R"
				elseif eff then
					code = "S"
				elseif copies then
					code = "C"
				elseif trig then
					code = "T"
				elseif hook then
					code = "H"
				elseif cast then
					code = "L"
				end
				-- (un modificateur procédural sur un projectile n'ajoute que son délai : ce n'est pas un effet)
				local onlyOwnDelay = code == "L" and not (m.Id == "QUICK" or m.Id == "RECHARGE_DOWN" or m.Id == "ADD_MANA" or m.Id == "CAST_HOLD")
				if onlyOwnDelay then
					code = "·"
				end
				-- infusion de l'élément que le sort a déjà (ex. Glace sur le Bouclier de glace) : normal, rien à changer
				local sameElement = m.Mod and m.Mod.Element ~= nil and m.Mod.Element == sp.Element
				if Contract.Transmits[sp.Family] or sameElement then
					-- (piège : transmet tout ; même élément : aucun effet attendu)
				elseif aff and code == "·" then
					table.insert(issues, "! " .. sp.Id .. " + " .. m.Id .. " : déclaré utile, rien détecté [" .. table.concat(changed, ",") .. "]")
					code = "!"
				elseif not aff and code ~= "·" then
					table.insert(issues, "? " .. sp.Id .. " + " .. m.Id .. " : déclaré inutile mais " .. code .. " [" .. table.concat(changed, ",") .. "]")
					code ..= "?"
				end
			else
				code = "x"
			end
			table.insert(line, code)
		end
		table.insert(rows, sp.Id .. "|" .. sp.Family .. "|" .. table.concat(line, " "))
	end
	local head = {}
	for _, m in mods do
		table.insert(head, m.Id)
	end
	table.insert(rows, 1, "MODS|" .. table.concat(head, ","))
	return rows, issues
end
return WandTools

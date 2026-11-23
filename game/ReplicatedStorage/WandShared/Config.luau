--[[
	WandShared/Config
	Constantes partagées client + serveur.
	Le SERVEUR fait autorité : le client ne lit ces valeurs que pour l'affichage.
]]

export type WandStats = {
	Name: string,
	Capacity: number, -- nombre de slots
	SpellsPerCast: number, -- cartes "tir" piochées par clic (avant multicast)
	CastDelay: number, -- délai de base entre deux tirs (s)
	RechargeTime: number, -- délai quand la lecture revient au début du deck (s)
	ManaMax: number,
	ManaRegen: number, -- mana / seconde
	ManaRegenDelay: number?, -- s sans dépense avant que la régénération reprenne
	SpreadDeg: number, -- dispersion de base (degrés)
	SpeedMult: number, -- multiplicateur global de vitesse
}

local Config = {}

-- ─────────────────────────────────────────────────────────────
-- Limites de sécurité (appliquées côté serveur)
-- ─────────────────────────────────────────────────────────────
Config.Limits = {
	-- Anti-crash : chaque clic dispose d'un budget FINI, quel que soit le deck.
	MaxIterations = 200, -- pioches max par clic (toutes profondeurs de triggers confondues)
	MaxDepth = 4, -- imbrication max : trigger > trigger > trigger > trigger
	MaxProjectilesPerCast = 40, -- projectiles max produits par un seul clic
	-- Anti-surcharge à l'exécution
	MaxLivePerPlayer = 150,
	MaxLiveGlobal = 600,
	MaxFxPerFrame = 200, -- messages VFX max envoyés par frame serveur
	MaxZonesPerPlayer = 12, -- zones persistantes (trou noir, gaz, murs...) par joueur
	MaxZonesGlobal = 80,
	MaxFragments = 8, -- éclats max générés par projectile (Fragmentation)
	-- Sorts procéduraux (Branche) : croissances simultanées et segments max par croissance
	MaxGrowthsPerPlayer = 4,
	MaxGrowthsGlobal = 16,
	MaxGrowthSegments = 240,
	-- Gigantisme : facteur de taille max des zones / explosions ; les effets visuels et les sorts
	-- procéduraux montent plus haut (cumul expérimental de modificateurs, max 3 par carte)
	MaxScale = 5,
	MaxProcScale = 8,
	-- taille max d'un ORBE de projectile (à peu près l'orbe du chaos) : le Gigantisme agrandit les effets,
	-- explosions et zones, mais plus le projectile lui-même au-delà de ça
	MaxProjectileSize = 1.5,
	MaxTrapsPerPlayer = 8,
	-- Anti-abus réseau
	MaxCardIdLength = 32,
	SetDeckInterval = 0.12, -- s entre deux SetDeck appliqués
	CastRequestInterval = 1 / 30, -- s entre deux demandes de tir
}

Config.Physics = {
	Gravity = 60, -- studs/s², multiplié par la stat Gravity du projectile
}

local DefaultWand: WandStats = {
	Name = "Baguette d'apprenti",
	Capacity = 8,
	SpellsPerCast = 1,
	CastDelay = 0.16,
	RechargeTime = 0.45,
	ManaMax = 600, -- (user 2026-11-23 : baguette de test à 600)
	ManaRegen = 60,
		ManaRegenDelay = 0.5, -- la régénération reprend 0,5 s après la dernière dépense
	SpreadDeg = 2,
	SpeedMult = 1,
	-- rang de la baguette : "Moyenne" | "Superieure" | "Ultime" | "Antique" (incantation possible au-dessus de Moyenne)
	-- PROVISOIRE : Supérieure pour tester l'incantation tant que les vrais modèles de baguettes n'existent pas
	Tier = "Superieure",
	IncantSpeed = 1, -- vitesse d'incantation (x)
	OverflowCap = 1.5, -- coût max incantable = 1,5 x mana ACTUEL (Supérieure 1,1-1,5 ; Suprême 2-2,5)
}
Config.DefaultWand = DefaultWand

-- Deck de démo : Dégâts+ > Étincelle à déclencheur qui transporte [Double sort : Boule de feu + Éclat de glace]
Config.DefaultDeck = { "DAMAGE_PLUS", "SPARK_TRIGGER", "DOUBLE", "FIREBALL", "", "", "", "" }

-- ─────────────────────────────────────────────────────────────
-- Textures. Remplace les "rbxassetid://0" par tes propres assets.
-- Tant qu'un id vaut 0, le VFXManager utilise Pixel (carré blanc natif = rendu net).
-- ─────────────────────────────────────────────────────────────
Config.Textures = {
	Pixel = "rbxasset://textures/particles/SquareParticle.png",
	Placeholder = "rbxassetid://0",
}

-- Palette par élément : 3 tons francs, aucun dégradé.
--   Core = centre clair, Mid = teinte principale, Edge = contour sombre.
--   Rotation = rotation fixe des particules (45 = losanges), Accel = gravité des éclats.
--   Flicker (optionnel) = cycle de couleurs en paliers (Chaos).
-- PALETTES : définies dans chaque module d'élément (WandShared/Elements/<Élément>.Palette)
Config.Elements = require(script.Parent:WaitForChild("Elements")).Field("Palette")

-- Sprites pixel art animés (planches horizontales générées par PixelSpell/tools/gen_sprites.js).
-- Affichés dans des BillboardGui / SurfaceGui avec ResampleMode = Pixelated (parfaitement nets).
Config.Sprites = {
	Vortex = { Id = "rbxassetid://96225426966905", Frames = 8, Size = 64, Fps = 12, Loop = true },
	Gas = { Id = "rbxassetid://78844854320876", Frames = 8, Size = 64, Fps = 8, Loop = true },
	Saw = { Id = "rbxassetid://91918061644625", Frames = 4, Size = 32, Fps = 20, Loop = true },
	Teleport = { Id = "rbxassetid://113339981543409", Frames = 8, Size = 64, Fps = 16, Loop = false },
	Shield = { Id = "rbxassetid://101684708461913", Frames = 6, Size = 64, Fps = 10, Loop = true },
	FireRing = { Id = "rbxassetid://109015522108237", Frames = 6, Size = 64, Fps = 10, Loop = true },
	Mine = { Id = "rbxassetid://103465545991687", Frames = 2, Size = 16, Fps = 4, Loop = true },
	Flame = { Id = "rbxassetid://96016511956261", Frames = 8, Size = 32, Fps = 12, Loop = true }, -- cibles en feu
	Shock = { Id = "rbxassetid://80277182659596", Frames = 8, Size = 32, Fps = 16, Loop = true }, -- cibles électrocutées
}

return Config

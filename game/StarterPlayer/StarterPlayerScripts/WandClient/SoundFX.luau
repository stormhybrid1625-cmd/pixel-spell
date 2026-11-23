--[[
	WandClient/SoundFX — Sons des sorts, organisés par CYCLE DE VIE

	Chaque sort a un PROFIL sonore (phases) :
	  Projectile : Cast (départ, optionnel) -> Travel (boucle pendant le vol) -> Impact (collision, seulement
	               si le projectile TOUCHE quelque chose) / Bounce (rebond) -> Explosion (+ Tail de l'élément)
	  Instantané : Cast (optionnel) -> Beam (le faisceau) -> Impact
	  Zone       : Spawn (apparition) -> Loop (tant qu'elle existe) / Tick (bip périodique) -> End (disparition)

	Résolution du profil : défaut de l'ÉLÉMENT (feu, glace...) puis surcharges de la CARTE (bombe, scie,
	fusée...). Une Boule de feu infusée en glace siffle donc comme de la glace ; une Bombe reste une bombe.

	Réalisme / variété :
	  • RANDOMIZER : échantillon tiré dans un pool sans répétition immédiate, hauteur et volume aléatoires,
	    micro-décalage entre couches -> jamais deux fois exactement le même son ;
	  • TAILLE : un projectile plus gros (Gigantisme) sonne plus grave ;
	  • DOPPLER : la boucle de vol monte quand le projectile s'approche de la caméra, descend quand il s'éloigne ;
	  • LIMITEUR : intervalle mini et voix max par événement, 48 voix au total, et seulement les 8 boucles
	    de vol les plus proches (un combo de 40 projectiles ne fait pas 40 boucles).
	  • Mixage : SoundGroup "WandSFX" (compresseur ; réverbération seulement si workspace.SFXReverb = true), sons spatialisés en 3D.

	Banque : bibliothèque Pro Sound Effects (licence Roblox, publique) + explosion intégrée au client.
]]

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local SoundFX = {}
local rng = Random.new()

-- ══ 1. ÉCHANTILLONS (tous vérifiés en jeu) ════════════════════════════════════════════════════════════════════════
local P = {
	-- FEU QUI BRÛLE (remplace les rafales de chalumeau qui sonnaient comme des slashs) :
	--   FireBurn  = feu de cheminée crépitant en boucle (enregistrements de 36-43 s, très doux -> volumes hauts)
	--   FireBurst = vague de flamme qui gronde (attaque vive) ; FireSear = embrasement lent qui siffle (queues)
	FireBurn = { 9112780462, 9112780193, 9112780438, 9112780212 },
	-- souffle de flamme DOUX et continu (briquets-chalumeaux, partie stable après le clic : Start 1,2 s+)
	FireAir = { 9120193024, 9120192302, 9114199775, 9120193280 },
	-- FAISCEAU CONTINU : champ de force (catégorie Energy) = bourdonnement électrique net -> rayon laser tenu
	-- POUSSE des branches : arbre qui se tord et craque (PSE Tree Creak, Twisting) + feuillage qui bruisse
	TreeCreak = { 9120261928, 9120262025 },
	DripPlop = { 9114175929, 9114175774, 9114176054, 9114175824 }, -- PSE Drip Plop Dribble : goutte liquide
	LeavesRustle = { 9116258071 }, -- (9116258282 retiré : quasi muet de 0 à 16 s -> froissements inaudibles 1 fois sur 2)
	BeamHum = { 9114524164, 9114524010 },
	-- FOUDRE : vrais coups de tonnerre (catégorie Thunder) = craquement sec, impact massif, long roulement
	ThunderStrike = { 9116282875, 9116282646, 9116282791, 9116282544, 9116282647 },
	-- ROULEMENT seul (partie après le craquement, mesurée : niveau 40-120 entre 3 et 6 s) : grondement d'orage continu
	ThunderRoll = { 9116282646, 9116282791, 9116282544, 9116282647 },
	FireBurst = { 9114429740, 9114429835, 9114429507, 9114431819, 9114429958, 9114429860, 9114432080 },
	FireSear = { 9114432358, 9114430091, 9114439216 },
	-- (rafales de chalumeau : gardées pour la FUSÉE seulement, c'est un propulseur)
	FireWhoosh = { 9114446852, 9114446277, 9114446802, 9114444052, 9114442751 },
	FireRoar = { 9114446277 },
	FireSizzle = { 9114442751 },
	Zap = { 9114277757, 9114277402, 9114277338, 9114277623, 9114277528 },
	ZapShort = { 9114277757 },
	ZapHum = { 9114277402 },
	ZapCrackle = { 9114277338, 9114277623 },
	ZapWhine = { 9114277528 },
	Ice = { 9114855870, 9114856215 },
	-- (anciens "bloop" = bulles : SUPPRIMÉS partout, demande du joueur) -> remplacés par des chocs mats :
	-- Bloop = choc sourd (ballon), BloopHigh = petit "tok" (caoutchouc). Les noms restent pour ne rien casser.
	Bloop = { 9113262361, 9113262493, 9113262444, 9113262566 }, -- 4 fichiers : moins de vols de voix (rebonds en rafale)
	BloopHigh = { 9118729926, 9118730506 },
	-- DÉGÂTS : un joueur touché = une lame qui tranche + un impact sur le corps (Pro Sound Effects)
	SliceHit = { 9119746598, 9119746592, 9119746759, 9119746751 }, -- (lame : gardée pour l'acier)
	BodyHit = { 9113511790, 9113510797 },
	-- coup MAT sur un sac de frappe : le son de dégâts de base (ni armure, ni épée)
	PunchBag = { 9117969420, 9117969314, 9117968656, 9117968670, 9117969078, 9117967978 },
	-- coups sur la CHAIR (Gore - Misc) : charnus, graves -> le son de dégâts de base
	FleshHit = { 9113519182, 9113519573, 9113520310, 9113519564, 9113520076, 9113519041, 9113518777 },
	Bubbles = { 9125409840, 9125498766 },
	BubbleLoop = { 9125409816 },
	PassBy = { 9125409085 },
	Ricochet = { 9118168612, 9118168610, 9118168962, 9118168943 },
	Laser = { 9116225257, 9116226332, 9116225524, 9116225841, 9116226112 },
	Swish = { 9126283592, 9126283272, 9126284094, 9126283906, 9126283583 },
	WhooshBy = { 9120718279 },
	Boom = { 9126082854, 9126082657 },
	Thunder = { 9119841134, 9119841013 },
	Explosion = { "rbxasset://sounds/impact_explosion_03.mp3" },
	-- dégâts
	Sizzle = { 9119165650, 9119166424, 9119166195, 9119166199, 9119165436, 9119166435, 9119166217, 9119165933 },
	Stab = { 9116197517 },
	-- interface (cartes)
	Paper = { 9117221149, 9117222516, 9117221477, 9117221130, 9117219947, 9117221498 },
	Cardboard = { 9113578540, 9113579415, 9113578399 },
	-- sifflement de balle (passage d'un sort rapide, façon duel de sorciers)
	Whiz = { 9118168273, 9118168320, 9118168585, 9118168291 },
	-- échec / mana vide : moteur qui s'éteint ("Power Down"), raccourci et aigu = magie qui cale
	PowerDown = { 9117869243 },
	-- bois : craquements de branche (pousse), grincements (bois sous tension)
	BranchSnap = { 9113582284, 9113581977, 9113582134, 9113581974, 9113582136, 9113581982 },
	WoodCreak = { 9120829704, 9120829553 },
	WoodCrackle = { 9120831000, 9120830988 },
	-- rebonds : corps physique du choc (balle en caoutchouc = petits sorts, ballon lourd = gros sorts)
	Rubber = { 9118729926, 9118730506, 9118730532, 9118729925, 9118730139, 9118730143, 9118729923 },
	BallBounce = { 9113262361, 9113262493, 9113262444, 9113262566 },
	-- pose d'un bloc de tronc : impacts de bois courts et mats (poteau qui tombe, coups sur bureau creux)
	-- PAS : vraies séries de bruits de pas (Creator Store, packs concrete_plain_step / Dirt_step, marche et course)
	StepConcrete = { 106215312789093, 97516400857987, 100974026237096, 129317472269932, 116023211662573, 135085025171496, 132709106261511, 73813255029014, 83706359800356 },
	StepConcreteRun = { 129823146465298, 100317023382690, 72892716724414, 75734304308808, 78489483264151, 73682510913816, 76495110206916, 113193961396580, 109758933819260 },
	StepDirt = { 109762695813592, 103963258527392, 98375658066754, 138750508569819, 83249973538428, 134689890007261, 101032359799121, 76283126098927, 140165597842270, 109162697779331, 78929988454004 },
	StepDirtRun = { 116498059085928, 91071825592728, 73077365148421, 71697128051364, 110574097038578, 129708619844470, 80027112124187 },
	-- recul au sol : corps qui glisse sur la terre (PSE Baseball Body Slide On Dirt), attaque immédiate
	BodySlide = { 9113312788 }, -- (9113313189 retiré : se lance mais reste muet en 3D, 1 recul sur 2 silencieux)
	-- PROPULSION CÉLESTE (PSE) — départ : énorme souffle avec impact intégré ; impact au sol : corps qui
	-- s'écrase dans la terre (Body Fall Dirt, très fort) + chute lourde (Body Fall Heavy) + chute de corps
	CelestialLaunch = { 9120703361 },
	-- impact au sol : éclats de terre durs (PSE Rocks Dirt Impacts in Ground)
	EarthHit = { 9118688006, 9118687058, 9118684499, 9118685574, 9118685996, 9118686223 },
	BodyFallHeavy = { 9113470178 },
	BodyFall = { 9113472109, 9113477342 },
	WoodPlace = { 9120909025, 9120896809, 9120906197, 9120906019, 9120907787, 9120907256 },
}

-- POINT D'ATTAQUE MESURÉ (s) de chaque enregistrement dont l'impact n'est pas au tout début.
-- Mesuré en jeu (PlaybackLoudness >= 30 % du pic) : un extrait court (Length) démarre ICI, sinon on
-- entendrait le silence d'avant l'impact. À refaire pour tout nouvel échantillon court.
local START_AT: { [number]: number } = {
	-- mesurés par WandClient.SoundAudit (blanc en tête) — le souffle WhooshBy 9120718279 est volontairement exclu
	[9113219817] = 0.11, [9113220079] = 0.11, [9113220110] = 0.11, [9114442751] = 0.26,
	[9114444052] = 0.22, [9114446277] = 0.20, [9114446802] = 0.18, [9114446852] = 0.07,
	[9116225257] = 0.22, [9116225524] = 0.22, [9116226112] = 0.22, [9116226332] = 0.22,
	[9116258071] = 0.11, [9116258282] = 0.39, [9117221130] = 0.31, [9117221149] = 0.28,
	[9117222516] = 0.31, [9117410297] = 0.13, [9118168610] = 0.18, [9118168612] = 0.18,
	[9118168943] = 0.18, [9119165436] = 0.31, [9119165650] = 0.20, [9119165933] = 0.16,
	[9119166195] = 0.28, [9119166199] = 0.09, [9119166217] = 0.13, [9119166424] = 0.18,
	[9119166435] = 0.09, [9119841013] = 0.63, [9119841134] = 1.54, [9120192302] = 0.13,
	[9120193024] = 0.63, [9120193280] = 0.56, [9120261928] = 0.63, [9120262025] = 0.88,
	[9120830988] = 0.09, [9120831000] = 0.13, [9125409816] = 0.05, [9125498766] = 0.22,
	[9126283272] = 0.22, [9126283906] = 0.09,
	-- glissade / impact (mesurés en jeu : PlaybackLoudness >= 30 % du pic)
	[9113312788] = 0.08, [9113313189] = 0.06, [9114036511] = 0.13,
	[9120703361] = 0.55, [9113469691] = 0.47, [9113470178] = 0.09,
	-- feuillage (Nature) : blanc en tête mesuré
	[9114514958] = 0.85, [9114518577] = 0.38, [9114519078] = 0.38,
	-- glace (P.Ice) : blanc en tête mesuré (0,19 s / 0,34 s) -> sans ça l'impact de glace sautait une fois sur deux
	[9114855870] = 0.18, [9114856215] = 0.33,
	[9114175824] = 0.07, -- goutte : blanc en tête
	-- zaps : ~0,15 s de SILENCE en tête (mesuré) -> sans ça, un extrait court jouait le blanc puis coupait le zap
	[9114277402] = 0.15, [9114277338] = 0.15, [9114277623] = 0.12, [9114277528] = 0.15,
	-- ballon (rebond lourd)
	[9113262361] = 0.155, [9113262493] = 0.195, [9113262444] = 0.095, [9113262566] = 0.155,
	-- branche qui casse
	[9113582284] = 0.365, [9113581977] = 0.285, [9113582134] = 0.965, [9113581974] = 0.095,
	[9113582136] = 0.775, [9113581982] = 0.365,
	-- impacts de bois (pose d'un bloc de tronc)
	[9120909025] = 0.245, [9120896809] = 0.005, [9120906197] = 0.215, [9120906019] = 0.325,
	[9120907787] = 0.025, [9120907256] = 0.305,
	-- grincements / caoutchouc
	[9120829704] = 0.645, [9120829553] = 0.045, [9118730139] = 0.045,
	-- coups de lame (attaque mesurée)
	[9119746598] = 0.04, [9119746592] = 0.09,
	-- éboulis (pierre arrachée) : 1er choc mesuré
	[9118586709] = 0.28, [9118586430] = 1.22, [9118586481] = 0, [9118586609] = 0.22,
	-- coups de tonnerre : début du CRAQUEMENT (mesuré ; avant = grondement d'approche, sauté)
	[9116282875] = 1.35, [9116282646] = 2.05, [9116282791] = 2.05, [9116282544] = 1.9, [9116282647] = 2.05,
	-- vagues de flamme (attaque mesurée)
	[9114429740] = 0.28, [9114429835] = 0.17, [9114429507] = 0.07, [9114431819] = 0.28, [9114429958] = 0.26,
	[9114429860] = 0.15, [9114432080] = 0.51, [9114432358] = 0.58, [9114430091] = 0.75, [9114439216] = 1.41,
}

-- ══ BANQUE « EN RÉSERVE » (Pro Sound Effects, qualité vérifiée, pas encore utilisée en jeu) ═══════════════════
-- Non préchargée (aucune voix créée) : on y pioche pour les futurs sorts (création de pierre, tornade...).
SoundFX.Bank = {
	RockDebris = { 9118586709, 9118586430, 9118586481, 9118586609 }, -- éboulis, pierres qui roulent
	Avalanche = { 9113220110, 9113220079, 9113219817 }, -- gros blocs qui s'écroulent (structures de pierre)
	PowerDownLong = { 9117873165, 9117872810, 9117872887, 9117869522, 9117870559, 9117870628 },
	WoodCreakLong = { 9120829478 },
}

-- ══ 2. ÉVÉNEMENTS PONCTUELS ═══════════════════════════════════════════════════════════════════════════════════════
-- Couche : Ids, Volume, Pitch {min,max}, Length (coupe + fondu), Fade, Delay,
--          Repeat = { Count = {min,max}, Window = {min,max} } (crépitements)
-- Événement : Layers, MinGap (s entre deux déclenchements), MaxVoices
local ricoAt, ricoN = -1, 0 -- ricochets de rayon échelonnés
local function ev(minGap: number, maxVoices: number, layers)
	return { MinGap = minGap, MaxVoices = maxVoices, Layers = layers }
end

local E = {
	-- ── Départs (Cast) ──
	["Cast.Rocket"] = ev(0.05, 4, {
		{ Ids = P.FireWhoosh, Volume = 0.38, Pitch = { 1.8, 2.2 }, Length = 0.5, Fade = 0.2 },
	}),
	["Cast.Lob"] = ev(0.05, 3, { -- lancer d'un objet (bombe, fiole, mine)
		{ Ids = P.Swish, Volume = 0.3, Pitch = { 0.7, 0.85 } },
	}),
	["Cast.Heavy"] = ev(0.08, 3, { -- sorts lourds (trou noir)
		{ Ids = P.WhooshBy, Volume = 0.32, Pitch = { 0.6, 0.75 }, Length = 1, Fade = 0.4 },
		{ Ids = P.Zap, Volume = 0.12, Pitch = { 0.45, 0.55 }, Length = 0.5, Fade = 0.2 },
	}),
	["Cast.Snap"] = ev(0.04, 3, { -- sorts instantanés / utilitaires : petit claquement de lancement
		{ Ids = P.Swish, Volume = 0.2, Pitch = { 1.6, 1.9 } },
	}),

	-- ── Collisions (Impact) ──
	["Impact.Glass"] = ev(0.04, 3, { { Ids = P.Ice, Volume = 0.35, Pitch = { 2.0, 2.4 }, Length = 0.5, Fade = 0.2 } }), -- fiole qui éclate
	["Impact.Thud"] = ev(0.04, 3, { { Ids = P.Bloop, Volume = 0.28, Pitch = { 0.55, 0.7 } } }), -- objet qui se pose
	["Impact.Tiny"] = ev(0.02, 4, { { Ids = P.ZapShort, Volume = 0.08, Pitch = { 3.0, 3.6 }, Length = 0.32, Fade = 0.06 } }), -- fragments

	-- ── Rebonds ──
	["Bounce.Soft"] = ev(0.04, 3, { { Ids = P.Bloop, Volume = 0.15, Pitch = { 0.8, 1.0 } } }),
	["Bounce.Metal"] = ev(0.04, 3, { { Ids = P.Ricochet, Volume = 0.15, Pitch = { 1.7, 2.3 }, Length = 0.3, Fade = 0.12 } }),
	["Bounce.Heavy"] = ev(0.05, 3, { { Ids = P.Bloop, Volume = 0.3, Pitch = { 0.42, 0.52 } } }), -- bombe
	-- CORPS du rebond (couche physique, jouée sous la teinte de l'élément ci-dessus) :
	-- extrait très court = juste le "tok" de l'impact, sans le rebond suivant de l'enregistrement
	["Bounce.Body"] = ev(0.025, 6, { { Ids = P.Rubber, Volume = 0.34, Pitch = { 1.35, 1.75 }, Length = 0.16, Fade = 0.06 } }),
	["Bounce.BodyHeavy"] = ev(0.04, 4, {
		{ Ids = P.BallBounce, Volume = 0.5, Pitch = { 0.85, 1.05 }, Length = 0.32, Fade = 0.12 },
		{ Ids = P.Bloop, Volume = 0.14, Pitch = { 0.42, 0.5 } },
	}),
	-- sort très rapide qui ricoche : sifflement qui repart ("piou")
	["Bounce.Ricochet"] = ev(0.06, 3, { { Ids = P.Ricochet, Volume = 0.16, Pitch = { 1.3, 1.7 }, Length = 0.5, Fade = 0.22 } }),

	-- ── Explosions (3 tailles) + queue de l'élément ──
	["Explosion.Small"] = ev(0.04, 4, { { Ids = P.Explosion, Volume = 0.32, Pitch = { 1.5, 1.8 } } }),
	["Explosion.Medium"] = ev(0.05, 4, {
		{ Ids = P.Explosion, Volume = 0.48, Pitch = { 1.15, 1.4 } },
		{ Ids = P.Boom, Volume = 0.2, Pitch = { 1.3, 1.6 }, Length = 0.8, Fade = 0.4 },
	}),
	["Explosion.Big"] = ev(0.08, 3, {
		{ Ids = P.Explosion, Volume = 0.6, Pitch = { 0.85, 1.0 } },
		{ Ids = P.Boom, Volume = 0.45, Pitch = { 0.9, 1.1 }, Length = 2.2, Fade = 0.8 },
	}),
	-- EXPLOSIONS PAR INFUSION : la matière qui explose change le son (remplace le boom de feu générique)
	Firework = ev(0.05, 4, {
		{ Ids = P.Explosion, Volume = 0.4, Pitch = { 1.5, 1.8 } },
		{ Ids = P.ZapShort, Volume = 0.1, Pitch = { 2.6, 3.6 }, Length = 0.32, Fade = 0.06, Repeat = { Count = { 7, 12 }, Window = { 0.25, 1.4 } } },
	}),

	-- ── Sifflements de balle (sorts rapides) ──
	-- Launch : le sort part et s'éloigne ("pew-zzz") ; Flyby : il frôle la caméra ("ZIIIP").
	-- Hauteur = vitesse du sort, volume = distance de passage ; une "teinte" de l'élément s'ajoute.
	["Whiz.Launch"] = ev(0.03, 5, {
		{ Ids = P.Whiz, Volume = 0.28, Pitch = { 0.95, 1.15 } },
		{ Ids = P.Swish, Volume = 0.12, Pitch = { 1.8, 2.2 } },
	}),
	["Whiz.Flyby"] = ev(0.03, 6, {
		{ Ids = P.Whiz, Volume = 0.45, Pitch = { 0.9, 1.1 } },
		{ Ids = P.WhooshBy, Volume = 0.15, Pitch = { 1.6, 2.0 }, Length = 0.5, Fade = 0.25 },
	}),

	-- ── Faisceaux (instantanés) ──
	-- ÉCLAIR : décharge électrique immédiate + CRAQUEMENT de tonnerre + ROULEMENT qui suit et s'éloigne
	["Beam.Lightning"] = ev(0.06, 5, {
		-- ATTAQUE forte et immédiate (avant : 0,34 / 0,54 -> masquée par le roulement, « entendu un peu après »)
		{ Ids = P.Zap, Volume = 0.6, Pitch = { 0.85, 1.0 }, Length = 0.45, Fade = 0.15 },
		{ Ids = { 9116282875 }, Volume = 0.75, Pitch = { 1.0, 1.1 }, Length = 0.9, Fade = 0.5 }, -- crac le plus sec (pic dès son début)
		-- craquement + son PROPRE roulement (la suite naturelle du même enregistrement), fondu long
		{ Ids = P.ThunderStrike, Volume = 0.85, Pitch = { 0.92, 1.05 }, Length = 3.2, Fade = 2.2 }, -- (4,5 s : trop de roulements empilés au tir rapide)
	}),
	-- sauts de cible en cible / arcs d'un arbre de foudre : crac plus court et plus aigu, sans roulement
	-- (sinon 3 sauts = 3 orages qui se superposent)
	["Beam.LightningJump"] = ev(0.05, 4, {
		{ Ids = P.Zap, Volume = 0.24, Pitch = { 1.0, 1.3 }, Length = 0.3, Fade = 0.12 },
		{ Ids = P.ThunderStrike, Volume = 0.23, Pitch = { 1.2, 1.45 }, Length = 1.4, Fade = 1.1 },
	}),
	["Beam.Laser"] = ev(0.04, 4, { { Ids = P.Laser, Volume = 0.32, Pitch = { 1.0, 1.25 }, Length = 0.7, Fade = 0.3 } }),
	-- rayons MAINTENUS (un tir tous les 0,12 s) : sons plus courts et plus discrets, espacés
	-- RICOCHET d'un rayon sur le décor (modificateur Rebond, Rayon tellurique) : tinte clair + éclat court
	["Beam.Ricochet"] = ev(0, 8, {
		{ Ids = P.Laser, Volume = 0.36, Pitch = { 1.45, 1.75 }, Length = 0.4, Fade = 0.18 },
		{ Ids = { 9114277528, 9114277338, 9114277623 }, Volume = 0.16, Pitch = { 1.6, 1.9 }, Length = 0.2, Fade = 0.08 },
	}),
	["Beam.HoldLaser"] = ev(0.1, 3, { { Ids = P.Laser, Volume = 0.16, Pitch = { 1.1, 1.3 }, Length = 0.3, Fade = 0.12 } }),
	-- éclair maintenu : le son CONTINU est porté par SoundFX.HoldBeam (boucles + roulements) ;
	-- ici seulement une petite texture de crépitement, espacée, pour ne pas hacher le son
	["Beam.HoldLightning"] = ev(0.3, 2, {
		{ Ids = P.ZapHum, Volume = 0.06, Pitch = { 0.9, 1.0 }, Length = 0.2, Fade = 0.08 }, -- (crépitement retiré : réservé à l'électrocution)
	}),
	-- roulement de tonnerre pendant un éclair maintenu : lancé toutes les ~1,3 s, chaque roulement
	-- dure ~3 s -> ils se chevauchent en un grondement d'orage continu (fondu d'entrée = pas de coupure)
	["Hold.ThunderRoll"] = ev(0.5, 4, {
		-- grondement d'APPROCHE (début du fichier, début naturel), arrêté en fondu avant le craquement
		-- (avant : début de fichier, quasi muet ~1 s sur 4 prises sur 5 -> orage trop faible)
		{ Ids = P.ThunderRoll, Volume = 1.5, Pitch = { 0.85, 0.97 }, Start = { 3.0, 4.6 }, FadeIn = 0.15, Length = 2.0, Fade = 0.9 },
	}),
	-- coup de tonnerre isolé qui éclate de temps en temps pendant le maintien
	["Hold.ThunderCrack"] = ev(0.6, 2, {
		{ Ids = P.ThunderStrike, Volume = 0.52, Pitch = { 0.95, 1.15 }, Length = 2.6, Fade = 1.9 },
		{ Ids = P.Zap, Volume = 0.28, Pitch = { 0.75, 0.95 }, Length = 0.4, Fade = 0.15 }, -- décharge sèche sous le craquement
	}),

	-- ── Zones ──
	["Zone.VoidOpen"] = ev(0.1, 2, {
		{ Ids = P.Boom, Volume = 0.3, Pitch = { 0.5, 0.6 }, Length = 1.2, Fade = 0.5 },
		{ Ids = P.WhooshBy, Volume = 0.3, Pitch = { 0.45, 0.55 }, Length = 1.2, Fade = 0.5 },
	}),
	["Zone.VoidCollapse"] = ev(0.1, 2, {
		{ Ids = P.Explosion, Volume = 0.5, Pitch = { 0.55, 0.65 } },
		{ Ids = P.Boom, Volume = 0.35, Pitch = { 0.7, 0.8 }, Length = 2, Fade = 0.8 },
	}),
	["Zone.GasBurst"] = ev(0.1, 2, {
		{ Ids = P.Bubbles, Volume = 0.45, Pitch = { 0.7, 0.9 } },
		{ Ids = P.Swish, Volume = 0.2, Pitch = { 0.6, 0.7 } },
	}),
	["Zone.Ignite"] = ev(0.1, 2, { -- embrasement : la flamme prend et se met à brûler
		{ Ids = P.FireAir, Volume = 2.8, Pitch = { 0.65, 0.8 }, Start = { 1.2, 4 }, FadeIn = 0.05, Length = 1.4, Fade = 0.8 }, -- WHOOMP grave
		{ Ids = P.FireBurn, Volume = 3, Pitch = { 0.85, 0.95 }, Start = { 1, 30 }, FadeIn = 0.1, Length = 1.8, Fade = 1 },
	}),
	["Zone.Extinguish"] = ev(0.1, 2, { -- le feu s'éteint : grésillement qui retombe
		{ Ids = P.Sizzle, Volume = 0.22, Pitch = { 0.7, 0.8 }, Length = 0.9, Fade = 0.6 },
		{ Ids = P.FireBurn, Volume = 0.9, Pitch = { 0.8, 0.9 }, Start = { 1, 30 }, FadeIn = 0.15, Length = 1.2, Fade = 1 },
	}),
	-- ── zones au sol de la boule de feu (une identité par infusion) ──
	["Zone.ShieldUp"] = ev(0.1, 2, {
		{ Ids = P.ZapHum, Volume = 0.25, Pitch = { 0.6, 0.7 }, Length = 0.5, Fade = 0.2 },
		{ Ids = P.Swish, Volume = 0.2, Pitch = { 1.3, 1.5 } },
	}),
	["Zone.ShieldDown"] = ev(0.1, 2, { { Ids = P.ZapHum, Volume = 0.18, Pitch = { 0.45, 0.5 }, Length = 0.4, Fade = 0.2 } }),
	["Zone.IceUp"] = ev(0.1, 2, { { Ids = P.Ice, Volume = 0.5, Pitch = { 0.65, 0.8 } } }),
	["Zone.IceBreak"] = ev(0.1, 2, {
		{ Ids = P.Ice, Volume = 0.5, Pitch = { 0.55, 0.65 } },
		{ Ids = P.Ice, Volume = 0.3, Pitch = { 0.9, 1.1 }, Delay = 0.08 },
	}),
	["Zone.MineArm"] = ev(0.1, 3, { { Ids = P.ZapShort, Volume = 0.15, Pitch = { 1.9, 2.1 }, Length = 0.32, Fade = 0.06 } }),
	["Zone.MineBeep"] = ev(0.2, 3, { { Ids = P.BloopHigh, Volume = 0.18, Pitch = { 2.3, 2.4 } } }),

	-- ── Divers ──
	Trigger = ev(0.04, 4, {
		{ Ids = P.ZapShort, Volume = 0.2, Pitch = { 2.6, 3.2 }, Length = 0.32, Fade = 0.06 },
		{ Ids = P.Swish, Volume = 0.12, Pitch = { 1.8, 2.2 } },
	}),
	-- ── Dégâts : coup direct (selon l'élément) et ticks sur la durée (selon le type) ──
	-- CORPS du coup, commun à tous les dégâts directs ; la couche Hit.<élément> s'ajoute par-dessus
	["Hit.Body"] = ev(0.035, 5, { -- coup encaissé : impact charnu + sourd (plus de claquement sec)
		{ Ids = P.FleshHit, Volume = 0.5, Pitch = { 0.8, 0.95 } }, -- fichier entier : sa fin naturelle
		{ Ids = P.PunchBag, Volume = 0.24, Pitch = { 0.5, 0.58 } }, -- PAS de Length : la résonance du sac coupée net = « enceinte qui tombe »
	}),
	-- ── Pièges ──
	["Trap.Set"] = ev(0.08, 3, { -- le piège se pose : petit clic + scintillement
		{ Ids = P.WoodPlace, Volume = 0.22, Pitch = { 1.6, 1.8 }, Length = 0.12, Fade = 0.05 },
		{ Ids = P.ZapShort, Volume = 0.06, Pitch = { 2.8, 3.2 }, Length = 0.32, Fade = 0.06 },
	}),
	["Trap.Snap"] = ev(0.05, 4, { -- déclenchement : déclic mécanique sec
		{ Ids = P.Ricochet, Volume = 0.2, Pitch = { 1.8, 2.1 }, Length = 0.25, Fade = 0.1 },
		{ Ids = P.Cardboard, Volume = 0.32, Pitch = { 1.2, 1.4 }, Length = 0.15, Fade = 0.06 },
	}),
	["Dot.Burn"] = ev(0.08, 3, { { Ids = P.Sizzle, Volume = 0.15, Pitch = { 0.9, 1.1 }, Length = 0.45, Fade = 0.25 } }), -- grésillement
	["Dot.Poison"] = ev(0.08, 3, { { Ids = P.Bubbles, Volume = 0.14, Pitch = { 0.75, 0.9 }, Length = 0.35, Fade = 0.15 } }), -- gargouillis
	["Dot.Bleed"] = ev(0.08, 3, { -- entaille + goutte
		{ Ids = P.Stab, Volume = 0.12, Pitch = { 0.65, 0.75 }, Length = 0.25, Fade = 0.1 },
		{ Ids = P.BloopHigh, Volume = 0.06, Pitch = { 0.9, 1.0 }, Delay = 0.08 },
	}),
	Teleport = ev(0.1, 2, {
		{ Ids = P.Laser, Volume = 0.3, Pitch = { 1.8, 2.2 }, Length = 0.5, Fade = 0.2 },
		{ Ids = P.WhooshBy, Volume = 0.35, Pitch = { 1.1, 1.3 }, Length = 0.9, Fade = 0.3 },
	}),
	Dispel = ev(0.03, 4, {
		{ Ids = P.ZapShort, Volume = 0.2, Pitch = { 2.8, 3.2 }, Length = 0.32, Fade = 0.08 },
		{ Ids = P.Ice, Volume = 0.1, Pitch = { 2.4, 2.8 }, Length = 0.25, Fade = 0.1 },
	}),
	-- mana insuffisant : la baguette "cale" (moteur qui s'éteint, très court) + petit grésillement sec
	NoMana = ev(0.25, 1, {
		{ Ids = P.PowerDown, Volume = 0.42, Pitch = { 1.3, 1.45 }, Length = 0.5, Fade = 0.2 },
		{ Ids = P.Sizzle, Volume = 0.07, Pitch = { 1.7, 1.9 }, Length = 0.18, Fade = 0.08 },
	}),
	-- sort qui échoue (ex. branche sans surface) : arc instable qui se désagrège
	Fizzle = ev(0.2, 2, {
		-- prises Zap à attaque MESURÉE uniquement (757/402 démarraient sur du silence -> « Faux » muet 1 fois sur 2-3)
		{ Ids = { 9114277528, 9114277338, 9114277623 }, Volume = 0.3, Pitch = { 0.6, 0.72 }, Length = 0.45, Fade = 0.16 },
		{ Ids = P.PowerDown, Volume = 0.3, Pitch = { 1.7, 1.9 }, Length = 0.4, Fade = 0.16 },
	}),
	-- ── Mur de glace : chaque colonne jaillit puis se brise ──
	["Ice.Rise"] = ev(0.035, 4, { { Ids = P.Ice, Volume = 0.26, Pitch = { 0.85, 1.15 }, Length = 0.45, Fade = 0.15 } }),
	["Ice.Shatter"] = ev(0.035, 4, { { Ids = P.Ice, Volume = 0.24, Pitch = { 1.3, 1.7 }, Length = 0.5, Fade = 0.2 } }),

	-- ── MATIÈRE & ENVIRONNEMENT (MatterService) ──
	-- impact sur la matière : chaque sorte sonne différemment (bois sourd, pierre qui s'écaille, métal qui tinte...)
	["Matter.Hit.Wood"] = ev(0.05, 3, { { Ids = P.WoodPlace, Volume = 0.4, Pitch = { 0.75, 0.9 }, Length = 0.22, Fade = 0.08 } }),
	["Matter.Hit.Branch"] = ev(0.05, 3, { { Ids = P.WoodPlace, Volume = 0.34, Pitch = { 0.9, 1.1 }, Length = 0.18, Fade = 0.07 } }),
	["Matter.Hit.Leaves"] = ev(0.06, 3, { { Ids = P.BranchSnap, Volume = 0.14, Pitch = { 1.4, 1.7 }, Length = 0.18, Fade = 0.08 } }),
	["Matter.Hit.Surface"] = ev(0.06, 3, { { Ids = P.BranchSnap, Volume = 0.1, Pitch = { 1.6, 1.9 }, Length = 0.14, Fade = 0.06 } }),
	["Matter.Hit.Stone"] = ev(0.05, 3, { { Ids = SoundFX.Bank.RockDebris, Volume = 0.3, Pitch = { 1.1, 1.35 }, Length = 0.35, Fade = 0.15 } }),
	["Matter.Hit.Metal"] = ev(0.05, 3, { { Ids = P.Ricochet, Volume = 0.2, Pitch = { 0.85, 1.05 }, Length = 0.4, Fade = 0.2 } }),
	["Matter.Hit.Ice"] = ev(0.05, 3, { { Ids = P.Ice, Volume = 0.22, Pitch = { 1.2, 1.5 }, Length = 0.3, Fade = 0.12 } }),
	["Matter.Hit.Glass"] = ev(0.05, 3, { { Ids = P.Ice, Volume = 0.2, Pitch = { 1.7, 2.0 }, Length = 0.25, Fade = 0.1 } }),
	-- CASSE : la matière cède
	["Matter.Break.Wood"] = ev(0.08, 3, {
		{ Ids = P.BranchSnap, Volume = 0.45, Pitch = { 0.6, 0.75 }, Length = 0.5, Fade = 0.25 },
		{ Ids = P.WoodPlace, Volume = 0.45, Pitch = { 0.5, 0.6 }, Length = 0.35, Fade = 0.15, Delay = 0.04 },
		{ Ids = P.WoodCrackle, Volume = 0.3, Pitch = { 0.9, 1.1 }, Length = 0.6, Fade = 0.35, Delay = 0.08 },
	}),
	["Matter.Break.Branch"] = ev(0.06, 4, {
		{ Ids = P.BranchSnap, Volume = 0.32, Pitch = { 0.8, 1.0 }, Length = 0.35, Fade = 0.18 },
	}),
	["Matter.Break.Leaves"] = ev(0.08, 3, {
		{ Ids = P.BranchSnap, Volume = 0.22, Pitch = { 1.2, 1.4 }, Length = 0.3, Fade = 0.15 },
		{ Ids = P.BranchSnap, Volume = 0.14, Pitch = { 1.5, 1.8 }, Length = 0.2, Fade = 0.1, Delay = 0.07 },
	}),
	["Matter.Break.Surface"] = ev(0.08, 2, { { Ids = P.BranchSnap, Volume = 0.15, Pitch = { 1.3, 1.6 }, Length = 0.25, Fade = 0.12 } }),
	["Matter.Break.Stone"] = ev(0.1, 3, {
		{ Ids = SoundFX.Bank.Avalanche, Volume = 0.22, Pitch = { 0.9, 1.05 }, Length = 1.4, Fade = 0.9 },
		{ Ids = SoundFX.Bank.RockDebris, Volume = 0.4, Pitch = { 0.85, 1.0 }, Length = 1.2, Fade = 0.7, Delay = 0.1 },
	}),
	["Matter.Break.Metal"] = ev(0.1, 3, {
		{ Ids = P.Ricochet, Volume = 0.3, Pitch = { 0.55, 0.7 }, Length = 0.8, Fade = 0.4 },
		{ Ids = P.Boom, Volume = 0.2, Pitch = { 1.3, 1.5 }, Length = 0.5, Fade = 0.3 },
	}),
	["Matter.Break.Ice"] = ev(0.06, 4, { { Ids = P.Ice, Volume = 0.3, Pitch = { 1.0, 1.3 }, Length = 0.7, Fade = 0.3 } }),
	["Matter.Break.Glass"] = ev(0.06, 4, { { Ids = P.Ice, Volume = 0.3, Pitch = { 1.6, 1.9 }, Length = 0.6, Fade = 0.25 } }),
	-- cratère : la pierre est arrachée et retombe en éboulis
	["Matter.Carve"] = ev(0.12, 3, {
		{ Ids = SoundFX.Bank.RockDebris, Volume = 0.5, Pitch = { 0.8, 0.95 }, Length = 1.5, Fade = 0.9, Delay = 0.05 },
		{ Ids = SoundFX.Bank.Avalanche, Volume = 0.16, Pitch = { 0.8, 0.9 }, Length = 1.2, Fade = 0.8 },
	}),
	-- une surface PREND FEU : petit souffle de flamme qui s'accroche
	["Fire.Catch"] = ev(0.12, 3, {
		{ Ids = P.FireAir, Volume = 1.7, Pitch = { 0.9, 1.1 }, Start = { 1.2, 4 }, FadeIn = 0.06, Length = 0.6, Fade = 0.4 },
	}),
	-- ── Branches (sorts procéduraux) ──
	-- DÉPART de l'arbre selon son INFUSION (plus de grincement) : la matière qui jaillit s'entend
	["Grow.Start"] = ev(0.1, 2, { -- nature : bois qui perce le sol
		{ Ids = P.WoodPlace, Volume = 0.42, Pitch = { 0.65, 0.8 }, Length = 0.3, Fade = 0.12 },
		{ Ids = P.BranchSnap, Volume = 0.3, Pitch = { 0.7, 0.85 }, Length = 0.4, Fade = 0.15 },
	}),
	-- POUSSE (chaque bloc) pour les infusions sans son dédié ci-dessus
	-- AMBIANCE PONCTUELLE d'un arbre vivant (aléatoire, à un endroit différent de l'arbre à chaque fois)
	["Tick.Drip"] = ev(0.08, 4, { { Ids = P.Ice, Volume = 0.1, Pitch = { 2.2, 2.9 }, Length = 0.12, Fade = 0.05 } }), -- glace qui fond
	["Tick.Leaves"] = ev(0.2, 2, { { Ids = P.LeavesRustle, Volume = 0.7, Pitch = { 1.0, 1.25 }, Start = { 1, 9 }, FadeIn = 0.04, Length = 0.45, Fade = 0.25 } }), -- feuillage qui bruisse (avant : papier)
	["Tick.Metal"] = ev(0.2, 2, { { Ids = P.Ricochet, Volume = 0.07, Pitch = { 2.2, 2.6 }, Length = 0.18, Fade = 0.08 } }), -- reflets métalliques
	["Tick.Drop"] = ev(0.12, 3, { { Ids = P.DripPlop, Volume = 0.22, Pitch = { 0.85, 1.15 } } }), -- goutte toxique
	-- recul (modificateur) : choc sourd sous l'impact
	-- RECUL : une cible se fait projeter (souffle d'air grave + coup sourd dans le corps)
	["Hit.Knockback"] = ev(0.08, 4, {
		{ Ids = P.Swish, Volume = 1.1, Pitch = { 0.5, 0.62 }, Length = 0.55, Fade = 0.3 },
		{ Ids = P.PunchBag, Volume = 1.0, Pitch = { 0.7, 0.85 }, Length = 0.5, Fade = 0.25 },
	}),
	-- PAS (marche / course) : impact court dans le sol ; la course frappe plus fort avec un petit grain
	-- de gravier en plus ; l'herbe ajoute un froissement de feuillage
	-- sol dur (béton, pierre, bois...) / sol meuble (herbe, terre, sable, boue, neige) ; légère variation de hauteur
	["Step.Walk"] = ev(0.03, 8, { { Ids = P.StepConcrete, Volume = 0.22, Pitch = { 0.95, 1.06 } } }),
	["Step.Run"] = ev(0.03, 8, { { Ids = P.StepConcreteRun, Volume = 0.3, Pitch = { 0.95, 1.06 } } }),
	["Step.WalkSoft"] = ev(0.03, 8, { { Ids = P.StepDirt, Volume = 0.22, Pitch = { 0.95, 1.06 } } }),
	["Step.RunSoft"] = ev(0.03, 8, { { Ids = P.StepDirtRun, Volume = 0.3, Pitch = { 0.95, 1.06 } } }),
	["Step.Grass"] = ev(0.05, 6, { { Ids = P.LeavesRustle, Volume = 0.22, Pitch = { 1.3, 1.6 }, Start = { 1, 9 }, FadeIn = 0.02, Length = 0.2, Fade = 0.12 } }),
	-- PROPULSION CÉLESTE : départ = souffle grave + coup sourd ; atterrissage = corps qui s'écrase au sol
	["Move.Launch"] = ev(0.05, 4, {
		{ Ids = P.CelestialLaunch, Volume = 1.0, Pitch = { 0.92, 1.05 }, Length = 1.2, Fade = 0.6 },
	}),
	-- impact au sol : chute de corps lourde + coup grave dans le sol + grondement sourd (tout le poids)
	-- impact : chute de corps lourde + éclats de terre durs (2 couches, graves) + sous-basse très discrète
	-- IMPACT AU SOL de la propulsion céleste (user : style JJS — sol qui se fissure, débris lourds, sec et puissant)
	-- PROVISOIRE en attendant le choix du joueur dans l'outil d'écoute (SoundAudition)
	["Move.Land"] = ev(0.1, 4, {
		{ Ids = { "rbxassetid://107670829150182" }, Volume = 0.75, Pitch = { 0.95, 1.05 }, Length = 1.4, Fade = 0.5 }, -- piétinement lourd
		{ Ids = { "rbxassetid://9118617342" }, Volume = 0.55, Pitch = { 0.85, 0.95 }, Length = 0.9, Fade = 0.3 }, -- gros impact de roche
		{ Ids = { "rbxassetid://102757491685632" }, Volume = 0.4, Pitch = { 0.95, 1.05 }, Delay = 0.05, Length = 1.4, Fade = 0.6 }, -- gravats
	}),
	-- RECUL AU SOL : seulement le corps qui glisse sur le sol en freinant (l'impact est joué par le coup
	-- qui provoque le recul, pas ici)
	["Move.Skid"] = ev(0.08, 4, {
		{ Ids = P.BodySlide, Volume = 0.8, Pitch = { 0.85, 1.15 }, FadeIn = 0.06, Length = 1.0, Fade = 0.75 }, -- longue extinction
	}),
	-- DASH : souffle vif et fort + coup d'air grave (corps qui fend l'air) + déchirure aiguë qui file
	["Move.Dash"] = ev(0.05, 6, {
		-- (user 2026-11-23 : volume nettement plus fort)
		-- (user 2026-11-23 d : candidat « B » = Dash 1, VALIDÉ par le joueur (volume 0.42))
		{ Ids = { 123389986399408 }, Volume = 0.42, Pitch = { 0.97, 1.03 } },
	}),
	["Impact.Knock"] = ev(0.05, 4, {
		{ Ids = P.BallBounce, Volume = 0.42, Pitch = { 0.6, 0.72 }, Length = 0.3, Fade = 0.12 },
		{ Ids = P.Boom, Volume = 0.14, Pitch = { 1.6, 1.9 }, Length = 0.35, Fade = 0.15 },
	}),
	-- chaque BLOC de tronc qui se pose = un "tok" de bois court et mat (hauteur selon l'épaisseur)
	["Grow.Step"] = ev(0.02, 10, {
		{ Ids = P.LeavesRustle, Volume = 0.9, Pitch = { 1.0, 1.25 }, Start = { 1, 9 }, FadeIn = 0.05, Length = 0.4, Fade = 0.25 },
		{ Ids = P.TreeCreak, Volume = 1.62, Pitch = { 1.03, 1.32 }, Start = { 0.5, 18.5 }, FadeIn = 0.04, Length = 0.38, Fade = 0.22 },
		{ Ids = P.BranchSnap, Volume = 0.05, Pitch = { 1.4, 1.8 }, Length = 0.08, Fade = 0.03 },
	}),
	-- une branche verrouille une cible (Tête chercheuse)
	["Grow.Lock"] = ev(0.08, 3, {
		{ Ids = P.Swish, Volume = 0.22, Pitch = { 1.5, 1.8 } },
		{ Ids = P.BranchSnap, Volume = 0.2, Pitch = { 1.2, 1.5 }, Length = 0.2, Fade = 0.08 },
	}),
	-- arcs électriques d'un arbre de foudre (décoratifs, fréquents -> très courts et discrets)
	["Beam.Arc"] = ev(0.07, 3, { { Ids = P.ZapShort, Volume = 0.1, Pitch = { 1.8, 2.5 }, Length = 0.32, Fade = 0.06 } }),
	["Grow.End"] = ev(0.1, 2, { -- la ramure sèche et s'effrite : petits craquements éparpillés
		{ Ids = P.BranchSnap, Volume = 0.12, Pitch = { 1.2, 1.6 }, Length = 0.25, Fade = 0.1, Repeat = { Count = { 4, 7 }, Window = { 0.05, 0.8 } } },
	}),
	-- ── Éléments ajoutés (Nature, Foudre infusée) ──

	-- ── Interface (2D) ──
	-- bruits de CARTES : courts extraits de papier manipulé / carton fin, pitchés vers l'aigu (= carte fine)
	["Ui.Open"] = ev(0.05, 3, { -- on feuillette le grimoire
		{ Ids = P.Paper, Volume = 0.65, Pitch = { 1.0, 1.15 }, Length = 0.45, Fade = 0.2 },
	}),
	["Ui.Close"] = ev(0.05, 3, {
		{ Ids = P.Paper, Volume = 0.55, Pitch = { 0.85, 0.95 }, Length = 0.3, Fade = 0.15 },
	}),
	["Ui.Pick"] = ev(0.03, 4, { -- on soulève une carte
		{ Ids = P.Paper, Volume = 0.72, Pitch = { 1.4, 1.7 }, Length = 0.14, Fade = 0.06 },
	}),
	["Ui.Drop"] = ev(0.03, 4, { -- la carte claque dans le slot
		{ Ids = P.Cardboard, Volume = 0.65, Pitch = { 1.7, 2.0 }, Length = 0.18, Fade = 0.07 },
		{ Ids = P.Paper, Volume = 0.36, Pitch = { 1.6, 1.9 }, Length = 0.1, Fade = 0.05 },
	}),
	["Ui.Clear"] = ev(0.03, 4, { -- la carte glisse hors de la baguette
		{ Ids = P.Paper, Volume = 0.55, Pitch = { 1.1, 1.3 }, Length = 0.22, Fade = 0.1 },
		{ Ids = P.Cardboard, Volume = 0.28, Pitch = { 1.2, 1.3 }, Length = 0.15, Fade = 0.06 },
	}),
}

-- ══ 3. BOUCLES (vol des projectiles, zones) ══════════════════════════════════════════════════════════════════════════
-- Wobble = modulation de hauteur (sorts instables) ; la hauteur suit aussi la taille et l'effet Doppler.
local LOOP = {
	["Travel.Spark"] = { Ids = P.ZapCrackle, Volume = 0.06, Pitch = { 1.7, 2.0 } }, -- grésillement
	["Travel.Saw"] = { Ids = P.ZapWhine, Volume = 0.12, Pitch = { 2.8, 3.1 } }, -- lame qui siffle
	["Travel.Rocket"] = { Ids = P.FireWhoosh, Volume = 0.22, Pitch = { 1.6, 1.9 } },
	["Travel.Fuse"] = { Ids = P.FireSizzle, Volume = 0.1, Pitch = { 2.4, 2.6 } }, -- mèche qui grésille
	["Travel.Void"] = { Ids = P.PassBy, Volume = 0.22, Pitch = { 0.55, 0.6 } },
	["Loop.Void"] = { Ids = P.PassBy, Volume = 0.55, Pitch = { 0.33, 0.38 } },
	["Loop.Gas"] = { Ids = P.BubbleLoop, Volume = 0.3, Pitch = { 0.65, 0.75 } },
	["Loop.FireRing"] = { Ids = P.FireBurn, Volume = 4.2, Pitch = { 0.8, 0.92 } }, -- (2 : brasier trop discret) -- brasier (arbre / cercle en feu)
	["Loop.Wildfire"] = { Ids = P.FireBurn, Volume = 4.5, Pitch = { 0.75, 0.9 } }, -- (2,2 : incendie trop discret) -- incendie qui court sur l'herbe / le bois
	["Loop.Shield"] = { Ids = P.ZapHum, Volume = 0.12, Pitch = { 0.42, 0.48 } },
	["Loop.Burn"] = { Ids = P.FireBurn, Volume = 1.3, Pitch = { 1.0, 1.1 } }, -- cible en feu : elle crépite
	-- faisceaux MAINTENUS : bourdonnement électrique continu (rayon) / crépitement (éclair)
	["Loop.BeamLaser"] = { Ids = P.BeamHum, Volume = 0.07, Pitch = { 1.7, 1.85 } }, -- rayon laser tenu
	-- COUCHE DE L'INFUSION sur un faisceau tenu (la matière du rayon change) :
	["Loop.Shock"] = { Ids = P.ZapCrackle, Volume = 0.2, Pitch = { 1.15, 1.35 } }, -- cible électrocutée
	["Loop.BeamLightning"] = { Ids = P.ZapCrackle, Volume = 0.42, Pitch = { 0.95, 1.05 }, Wobble = 0.15 },
	["Loop.BeamLightningHum"] = { Ids = P.ZapHum, Volume = 0.32, Pitch = { 0.95, 1.05 }, Wobble = 0.1 }, -- bourdonnement électrique continu
	-- arbres INFUSÉS : ambiance continue tant qu'ils vivent
}

-- ══ SONS PAR ÉLÉMENT : chaque module WandShared/Elements/<Élément>/Sounds ajoute ses événements et boucles ══
local ELEMENT_BEAM_TINT = {}
do
	local folder = game:GetService("ReplicatedStorage"):WaitForChild("WandShared"):WaitForChild("Elements")
	for _, mod in folder:GetChildren() do
		local sm = mod:FindFirstChild("Sounds")
		if sm then
			local ok, def = pcall(function()
				return require(sm)(P, ev)
			end)
			if ok and def then
				for name, e in def.Events or {} do
					E[name] = e
				end
				for name, l in def.Loops or {} do
					LOOP[name] = l
				end
				ELEMENT_BEAM_TINT[mod.Name] = def.BeamTint
			else
				warn("[Wand] sons de l'élément " .. mod.Name .. " en erreur :", def)
			end
		end
	end
end

-- ══ 4. PROFILS ══════════════════════════════════════════════════════════════════════════════════════════════
-- Phases : Cast, Travel, Impact, Bounce, Explosion (auto selon le rayon si absent), Tail, Beam.
-- false = phase muette (ex. pas de son de départ pour l'éclair : le faisceau suffit).
-- profils par élément : définis dans WandShared/Elements/<Élément>.Sound.Profile
local ElementDefs = require(game:GetService("ReplicatedStorage"):WaitForChild("WandShared"):WaitForChild("Elements"))
local ELEMENT = {}
for _, def in ElementDefs.All() do
	if def.Sound and def.Sound.Profile then
		ELEMENT[def.Id] = def.Sound.Profile
	end
end

-- identité sonore PROPRE à une carte : champ Sound de son module (WandShared/Spells/<ID>)
local CARD = {
	ARC = { Beam = "Beam.Arc" }, -- interne : arcs électriques d'un arbre de foudre (pas une carte)
}
do
	local Cat = require(game:GetService("ReplicatedStorage"):WaitForChild("WandShared"):WaitForChild("SpellCatalog"))
	for id, card in Cat.ById do
		if card.Sound then
			CARD[id] = card.Sound
		end
	end
end

-- Zones (par type de marqueur répliqué)
local ZONE = {
	BlackHole = { Spawn = "Zone.VoidOpen", Loop = "Loop.Void", End = "Zone.VoidCollapse" },
	Gas = { Spawn = "Zone.GasBurst", Loop = "Loop.Gas" },
	FireRing = { Spawn = "Zone.Ignite", Loop = "Loop.FireRing", End = "Zone.Extinguish" },
	Shield = { Spawn = "Zone.ShieldUp", Loop = "Loop.Shield", End = "Zone.ShieldDown" },
	IceWall = { Spawn = "Zone.IceUp", End = "Zone.IceBreak" },
	Mine = { Spawn = "Zone.MineArm", Tick = "Zone.MineBeep", TickEvery = 1 },
	Trap = { Spawn = "Trap.Set" },
	Dispel = { Spawn = "Dispel" },
}

-- zones au sol de la boule de feu : clé "Patch" .. élément (WandShared/Elements/<Élément>.Sound.Patch)
for _, def in ElementDefs.All() do
	if def.Sound and def.Sound.Patch then
		ZONE["Patch" .. def.Id] = def.Sound.Patch
	end
end

-- Sifflement de balle : actif par défaut pour tout projectile rapide, sauf les objets lents / lancés.
local NO_WHIZ = { BOMB = true, MINE = true, BLACK_HOLE = true, FRAGMENT = true, BRANCH = true }

-- Croissances (branches) : sons selon l'élément. Start / Step (chaque segment, limité) / Loop / End
-- Chaque INFUSION a son départ, son bloc, son ambiance (Loop continue OU Tick ponctuel) et sa fin.
-- Persist : la boucle dure toute la vie de l'arbre ; Tick : son aléatoire toutes les Every[1]..Every[2] s.
local GROW = {}
for _, def in ElementDefs.All() do
	if def.Sound and def.Sound.Grow then
		GROW[def.Id] = def.Sound.Grow
	end
end

-- Élément NATIF de chaque type de zone : une zone infusée d'un autre élément reçoit une couche de cet élément
local ZONE_NATIVE = { BlackHole = "Arcane", Gas = "Toxic", IceWall = "Ice", Mine = "Fire", Shield = "Ice", Dispel = "Arcane", FireRing = "Fire", Trap = "Neutral" }
-- États des cibles (boucle tant que l'état dure)
-- sons des ÉTATS sur les cibles (début / boucle / fin), déclarés par les éléments : Elements/<Él>.Sound.Status
local STATUS: { [string]: { Start: string?, Loop: string?, End: string? } } = {}
for _, def in ElementDefs.All() do
	for kind, spec in (def.Sound and def.Sound.Status) or {} do
		STATUS[kind] = spec
	end
end
local WHIZ_MIN_SPEED = 40 -- studs/s en dessous desquels un sort ne siffle pas
local FLYBY_RADIUS = 14 -- distance de passage max à la caméra pour entendre le sifflement
local TRAVEL_LOOP_GAIN = 0.85 -- boucle de vol, animée en continu (respiration, Doppler) sous les sifflements

local function speedPitch(speed: number): number
	return math.clamp(0.75 + speed / 400, 0.8, 1.35)
end

local profileCache = {}
local function profile(card: string?, element: string?)
	local key = (card or "") .. "|" .. (element or "")
	local p = profileCache[key]
	if p then
		return p
	end
	p = table.clone(ELEMENT[element or ""] or ELEMENT.Arcane)
	for k, v in CARD[card or ""] or {} do
		p[k] = v
	end
	profileCache[key] = p
	return p
end

-- ── SON EN COUCHES : identité de la CARTE + matière de l'ÉLÉMENT ──
-- Une carte qui a son propre son (bombe, mur, ramure, rayon...) garde son identité physique ; si elle est
-- INFUSÉE d'un autre élément, cet élément s'AJOUTE à chaque phase (départ, impact, rebond, queue) et
-- REMPLACE la boucle de vol (la matière a changé : une bombe de glace siffle, une fiole de feu ronfle).
-- Une carte sans son propre (boule de feu, éclat...) prend simplement le profil de son élément ACTUEL.
local Catalog = require(game:GetService("ReplicatedStorage"):WaitForChild("WandShared"):WaitForChild("SpellCatalog"))
local layerCache = {}
local function layers(card: string?, element: string?)
	local key = (card or "") .. "|" .. (element or "")
	local hit = layerCache[key]
	if hit then
		return hit[1], hit[2]
	end
	local c = Catalog.ById[card or ""]
	local native = c and c.Element
	local infused = native ~= nil and element ~= nil and element ~= native and ELEMENT[element] ~= nil
	local main, tint
	if CARD[card or ""] then
		main = profile(card, if infused then native else element)
		tint = if infused then ELEMENT[element] else nil
		if tint and tint.Travel then
			main = table.clone(main)
			main.Travel = tint.Travel
		end
	else
		main = profile(card, element)
	end
	layerCache[key] = { main, tint }
	return main, tint
end

-- plus gros = plus grave (Gigantisme x1,5 / x3 / x5...), borné
local function sizePitch(size: number?): number
	return math.clamp(1.15 - ((size or 0.6) - 0.6) * 0.12, 0.55, 1.2)
end
-- plus gros = plus fort
local function sizeGain(size: number?): number
	return math.clamp(1 + ((size or 0.6) - 0.6) * 0.06, 1, 1.5)
end

-- ══ 5. MOTEUR ═════════════════════════════════════════════════════════════════════════════════════════════════
local MAX_VOICES = 48
local MAX_DISTANCE = 240
-- PORTÉE SELON LA TAILLE DU SORT (user 2026-11-23) : k = FxScale du message en cours (Gigantisme)
-- portée max = 220 x k^0.9 (G3 ~ x3-4 -> s'entend de très loin, un peu) ; distance « pleine puissance » = 14 x k^0.8
local curScale = 1
local function rangeK(): number
	return math.clamp(curScale, 1, 5)
end
local MAX_TRAVEL_LOOPS = 8 -- boucles de vol simultanées (les plus proches de la caméra)
local TRAVEL_RANGE = 140

local group: SoundGroup
local dryGroup: SoundGroup -- canal SANS réverbération (bruits de pas)
local uiFolder: Folder
local voices = 0
local active: { [string]: number } = {}
local lastPlay: { [string]: number } = {}

local function resolveId(id): string
	return if type(id) == "number" then "rbxassetid://" .. id else id
end

local function pick(def)
	local ids = def.Ids
	if #ids == 1 then
		return ids[1]
	end
	local i
	repeat
		i = rng:NextInteger(1, #ids)
	until i ~= def._last -- jamais deux fois de suite le même échantillon
	def._last = i
	return ids[i]
end

-- ── POOL DE VOIX PERSISTANTES (anti-latence) ───────────────────────────────────────────────────────────────
-- Roblox doit (re)charger l'audio de chaque Sound créé ou cloné, et décharge l'audio d'un Sound détruit.
-- Créer/détruire un Sound par lecture donnait jusqu'à ~250 ms de retard (parfois aucun son).
-- Chaque échantillon a donc des VOIX pré-créées, préchargées au démarrage et jamais détruites :
-- on les déplace (Attachment) et on les relance. Si toutes les voix d'un échantillon jouent, la plus
-- ancienne est coupée (voice stealing). Les boucles ont leurs propres voix (jamais volées par un one-shot).
type Voice = { Att: Attachment?, Sound: Sound, Token: number, Busy: boolean, Since: number }
local pools: { [string]: { Voice } } = {}
local voiceOf: { [Sound]: Voice } = {}
local VOICES_ONESHOT = 6
local VOICES_LOOP = 8
local VOICES_2D = 4

-- Voix SUPPLÉMENTAIRES pour les échantillons très sollicités (le feu sert au départ, à l'impact, à la queue
-- d'explosion et aux arbres) : sinon, en tir rapide, une nouvelle lecture "vole" une voix et COUPE la précédente.
local EXTRA_VOICES: { [string]: number } = {}
for _, list in { { 9112780462, 9112780193, 9112780438, 9112780212 }, { 9120193024, 9120192302, 9114199775, 9120193280 }, { 9116282875, 9116282646, 9116282791, 9116282544, 9116282647 } } do
	for _, id in list do
		EXTRA_VOICES["rbxassetid://" .. id] = 10
	end
end
-- échantillons UNIQUES très sollicités (crépitement de feu, zap court) : sinon vol de voix en rafale
for _, id in { 9114442751, 9114277757 } do
	EXTRA_VOICES["rbxassetid://" .. id] = 10
end
-- glace (P.Ice, 2 fichiers seulement) : le mur de glace joue des dizaines de colonnes à la fois
for _, id in { 9114855870, 9114856215 } do
	EXTRA_VOICES["rbxassetid://" .. id] = 14
end
-- pas : 6 joueurs qui courent = beaucoup de pas qui se chevauchent -> jamais de pas coupé.
-- Ils passent par un canal SEC (sans réverbération : sinon chaque pas rapproché "fait écho")
-- et portent moins loin que les sorts (portée pensée pour les explosions).
local DRY_IDS: { [string]: boolean } = {}
for _, list in { P.StepConcrete, P.StepConcreteRun, P.StepDirt, P.StepDirtRun } do
	for _, id in list do
		EXTRA_VOICES["rbxassetid://" .. id] = 4
		DRY_IDS["rbxassetid://" .. id] = true
	end
end
for _, id in { 9113262361, 9113262493, 9113262444, 9113262566 } do
	EXTRA_VOICES["rbxassetid://" .. id] = 8 -- rebonds (joués graves = longs) : bombe qui rebondit en rafale
end
for _, id in { 9116282875, 9116282646, 9116282791, 9116282544, 9116282647 } do
	EXTRA_VOICES["rbxassetid://" .. id] = 14 -- tonnerres longs (jusqu'à 4,5 s) : beaucoup de voix pour ne jamais en couper un
end

-- FEUILLES (un seul fichier !) : chaque segment de Ramure, les zones nature, les tirs nature l'utilisent -> 449 vols
-- en 32 arbres au banc de test. 18 voix (sons courts, < 1 s).
for _, id in P.LeavesRustle do
	EXTRA_VOICES["rbxassetid://" .. id] = 18
end
for _, id in P.TreeCreak do
	EXTRA_VOICES["rbxassetid://" .. id] = math.max(EXTRA_VOICES["rbxassetid://" .. id] or 0, 10)
end

-- FEU : tous ses fichiers servent à la fois (départ, impact, brasiers, arbres, incendie, cibles en feu)
for _, list in { P.FireBurn, P.FireAir, P.FireBurst, P.FireSear, P.FireWhoosh } do
	for _, id in list do
		local key = "rbxassetid://" .. id
		EXTRA_VOICES[key] = math.max(EXTRA_VOICES[key] or 0, 14)
	end
end

local function getPool(id: string, is3D: boolean, isLoop: boolean): { Voice }
	local key = id .. (if isLoop then "#loop" elseif is3D then "#3d" else "#2d")
	local pool = pools[key]
	if pool then
		return pool
	end
	pool = {}
	-- boucles : 8 jouent + celles qui finissent leur fondu ; les sons très sollicités (mèche des bombes) en ont plus
	local count = if isLoop then math.max(VOICES_LOOP, (EXTRA_VOICES[id] or 0) + 2) elseif is3D then (EXTRA_VOICES[id] or VOICES_ONESHOT) else VOICES_2D
	for _ = 1, count do
		local s = Instance.new("Sound")
		s.SoundId = id
		s.SoundGroup = if DRY_IDS[id] then dryGroup else group
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 14 -- (était 6 : la caméra est à ~12 studs du joueur, ses propres sorts étaient atténués de moitié) proche = nettement plus fort (passages, explosions à bout portant)
		s.RollOffMaxDistance = 220
		if DRY_IDS[id] then -- pas : portée courte (on n'entend pas les pas à 200 studs)
			s.RollOffMinDistance = 10
			s.RollOffMaxDistance = 80
		end
		s.Volume = 0
		local att = nil
		if is3D then
			att = Instance.new("Attachment")
			att.Name = "Voice"
			att.Parent = workspace.Terrain
			s.Parent = att
		else
			s.Parent = uiFolder
		end
		local v: Voice = { Att = att, Sound = s, Token = 0, Busy = false, Since = 0 }
		voiceOf[s] = v
		table.insert(pool, v)
	end
	pools[key] = pool
	return pool
end

local function acquire(id: string, is3D: boolean, isLoop: boolean): Voice
	local pool = getPool(id, is3D, isLoop)
	local chosen = nil
	for _, v in pool do
		if not v.Busy then
			chosen = v
			break
		end
	end
	if not chosen then -- toutes occupées : on vole la plus ancienne
		-- diagnostic : un vol = un son coupé net (SoundService.WandSFXSteals / WandSFXLastSteal)
		SoundService:SetAttribute("WandSFXSteals", (SoundService:GetAttribute("WandSFXSteals") or 0) + 1)
		SoundService:SetAttribute("WandSFXLastSteal", id)
		local key = "Steal_" .. (string.match(id, "%d+") or "?") .. (if isLoop then "_loop" else "")
		SoundService:SetAttribute(key, (SoundService:GetAttribute(key) or 0) + 1) -- vols par fichier (diagnostic)
		-- on coupe la voix la MOINS audible : la plus éloignée de la caméra (à défaut, la plus ancienne)
		local cam = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position
		chosen = pool[1]
		local bestScore = -math.huge
		for _, v in pool do
			local d = if cam and v.Att then (v.Att.WorldPosition - cam).Magnitude else 0
			local score = d + (os.clock() - v.Since) * 2 -- à distance égale, la plus ancienne
			if score > bestScore then
				bestScore, chosen = score, v
			end
		end
	end
	chosen.Sound:Stop()
	chosen.Token += 1
	chosen.Busy = true
	chosen.Since = os.clock()
	return chosen
end

local function release(v: Voice, token: number)
	if v.Token ~= token then
		return -- la voix a déjà été réattribuée : surtout ne pas couper le nouveau son
	end
	v.Sound:Stop()
	v.Sound.Looped = false
	v.Busy = false
end

-- Prépare une voix : échantillon tiré au hasard, volume / hauteur aléatoires. Renvoie (Sound, Voice, token).
local function hasFree(raw, is3D: boolean, isLoop: boolean): boolean
	for _, v in getPool(resolveId(raw), is3D, isLoop) do
		if not v.Busy then
			return true
		end
	end
	return false
end

local recentStart: { [any]: number } = {}
local function newSound(def, pitchMul: number, pos: Vector3?, volMul: number?, isLoop: boolean?): (Sound, Voice, number)
	local raw = pick(def)
	-- plusieurs échantillons possibles : on préfère un fichier qui a une voix LIBRE plutôt que d'en voler
	-- une (voler = couper net un son en cours)
	if #def.Ids > 1 and not hasFree(raw, pos ~= nil, isLoop == true) then
		for _, alt in def.Ids do
			if hasFree(alt, pos ~= nil, isLoop == true) then
				raw = alt
				break
			end
		end
	end
	-- ANTI-DOUBLON : le MÊME fichier lancé deux fois dans la même image (ex. impact + couche Hit qui
	-- partagent ZapShort) s'additionne en phase -> son « filtré / métallique » qui sonne buggé.
	-- On prend un autre fichier du pool ; s'il n'y en a pas, la couche est sautée.
	if not isLoop then
		local now = os.clock()
		if now - (recentStart[raw] or -1) < 0.03 then
			local alt
			for _, cand in def.Ids do
				if now - (recentStart[cand] or -1) >= 0.03 then
					alt = cand
					break
				end
			end
			if not alt then
				return nil :: any, nil :: any, 0
			end
			raw = alt
		end
		recentStart[raw] = now
	end
	local v = acquire(resolveId(raw), pos ~= nil, isLoop == true)
	local s = v.Sound
	if pos and s.SoundGroup ~= dryGroup then
		local k = rangeK()
		s.RollOffMaxDistance = 220 * k ^ 0.9
		s.RollOffMinDistance = 14 * k ^ 0.8
	end
	if v.Att and pos then
		v.Att.WorldPosition = pos
	end
	s.Looped = isLoop == true
	s.Volume = def.Volume * rng:NextNumber(0.85, 1.1) * (volMul or 1)
	s.PlaybackSpeed = rng:NextNumber(def.Pitch[1], def.Pitch[2]) * pitchMul
	-- extrait pris à un endroit aléatoire d'un long enregistrement (papier, boucles...)
	s.TimePosition = if def.Start then rng:NextNumber(def.Start[1], def.Start[2]) else (START_AT[raw] or 0)
	return s, v, v.Token
end

local function worldHolder(pos: Vector3): Attachment
	local att = Instance.new("Attachment")
	att.Name = "SFX"
	att.WorldPosition = pos
	att.Parent = workspace.Terrain
	return att
end

-- fondu par paliers (3 marches) puis done()
-- alive() : faux si la voix a été réattribuée entre-temps (on ne touche plus à son volume)
-- fondu LISSE (un palier toutes les ~30 ms) : en 3 paliers, sur un son fort, chaque marche s'entendait
-- comme une coupure. Courbe en carré = descente naturelle (l'oreille entend en log).
local function fadeOut(s: Sound, fade: number, done: () -> (), alive: (() -> boolean)?)
	local v = s.Volume
	local steps = math.max(3, math.ceil(fade / 0.03))
	for i = 1, steps do
		task.delay(fade * (i - 1) / steps, function()
			if not alive or alive() then
				local k = 1 - i / steps
				s.Volume = v * k * k
			end
		end)
	end
	task.delay(fade, done)
end

local function playLayer(layer, pos: Vector3?, pitchMul: number, onEnd: () -> (), volMul: number?)
	local s, v, token = newSound(layer, pitchMul, pos, volMul, false)
	if not s then -- doublon exact dans la même image : couche sautée
		onEnd()
		return
	end
	voices += 1
	local finished = false
	local function alive()
		return v.Token == token
	end
	local function cleanup()
		if finished then
			return
		end
		finished = true
		voices -= 1
		onEnd()
		release(v, token)
	end
	-- montée douce (extrait pris au milieu d'un long enregistrement : pas d'attaque sèche)
	if layer.FadeIn then
		local target = s.Volume
		s.Volume = target * 0.1
		local steps = math.max(3, math.ceil(layer.FadeIn / 0.03))
		for i = 1, steps do
			task.delay(layer.FadeIn * i / steps, function()
				if v.Token == token then
					s.Volume = target * (0.1 + 0.9 * i / steps)
				end
			end)
		end
	end
	s:Play()
	if layer.Length then
		-- fondu MINIMAL 0,16 s pour toute couche de plus de 0,25 s : aucun son n'est coupé sèchement (SoundAudit)
		local fade = math.max(layer.Fade or 0.1, if layer.Length >= 0.25 then 0.16 else 0)
		task.delay(math.max(0, layer.Length / s.PlaybackSpeed - fade), function()
			fadeOut(s, fade, cleanup, alive)
		end)
	else
		-- durée réelle restante (voix préchargée : TimeLength est connu)
		local remaining = if s.TimeLength > 0 then (s.TimeLength - s.TimePosition) / s.PlaybackSpeed else 3
		task.delay(remaining + 0.05, cleanup)
	end
end

-- Joue un événement ponctuel. pos = nil -> son 2D (interface).
local IS_STUDIO = game:GetService("RunService"):IsStudio()
local SLOT_HOLD = 0.6
function SoundFX.Play(name: string?, pos: Vector3?, pitchMul: number?, volMul: number?)
	local ev = name and E[name]
	if not ev and IS_STUDIO and type(name) == "string" then
		-- banc de test : un événement sonore demandé mais introuvable (faute de frappe, son oublié)
		local SS = game:GetService("SoundService")
		local miss = SS:GetAttribute("WandSFXMissing") or ""
		if not miss:find(name, 1, true) and #miss < 300 then
			SS:SetAttribute("WandSFXMissing", miss .. name .. " ")
		end
	end
	local function audit(result: string)
		if IS_STUDIO and workspace:GetAttribute("WandSFXLog") and type(name) == "string" then
			local SS = game:GetService("SoundService")
			local log = SS:GetAttribute("WandSFXAudit") or ""
			if #log < 60000 then
				SS:SetAttribute("WandSFXAudit", log .. name .. "=" .. result .. ";")
			end
		end
	end
	if not ev or not group then
		audit("INCONNU")
		return
	end
	local now = os.clock()
	if now - (lastPlay[name] or 0) < ev.MinGap then
		audit("trop_rapproche")
		return
	end
	if (active[name] or 0) >= ev.MaxVoices or (voices >= MAX_VOICES and string.sub(name, 1, 3) ~= "Ui.") then
		audit("plus_de_voix")
		return
	end
	if pos and (pos - workspace.CurrentCamera.CFrame.Position).Magnitude > MAX_DISTANCE * rangeK() ^ 0.9 then
		audit("trop_loin")
		return
	end
	audit("ok")
	lastPlay[name] = now
	active[name] = (active[name] or 0) + 1
	local pending = 0
	local released = false
	local function release()
		if not released then
			released = true
			active[name] = math.max(0, (active[name] or 1) - 1)
		end
	end
	local function layerDone()
		pending -= 1
		if pending <= 0 then
			release()
		end
	end
	-- la place de l'événement est rendue après l'ATTAQUE (SLOT_HOLD), pas à la fin de la queue : sinon un long
	-- roulement de tonnerre (4 s) bloquait les éclairs suivants -> sort éclair muet au tir rapide.
	-- (la queue continue de jouer ; MAX_VOICES protège toujours le total)
	task.delay(SLOT_HOLD, release)
	for _, layer in ev.Layers do
		local count = if layer.Repeat then rng:NextInteger(layer.Repeat.Count[1], layer.Repeat.Count[2]) else 1
		for _ = 1, count do
			pending += 1
			local delay = layer.Delay or 0
			if layer.Repeat then
				delay += rng:NextNumber(layer.Repeat.Window[1], layer.Repeat.Window[2])
			end
			if delay <= 0 then
				-- IMMÉDIAT : passer par task.delay repoussait le son d'une image (~16 ms)
				playLayer(layer, pos, pitchMul or 1, layerDone, volMul)
			else
				local sc = curScale
				task.delay(delay, function()
					local old = curScale
					curScale = sc
					playLayer(layer, pos, pitchMul or 1, layerDone, volMul)
					curScale = old
				end)
			end
		end
	end
end

-- Boucle attachée à une Part ; renvoie le Sound (montée en 3 paliers).
-- Boucle (voix dédiée). La position est mise à jour chaque frame par l'appelant (followLoop).
local function startLoop(def, part: BasePart, pitchMul: number, gain: number?): Sound
	local s, v, token = newSound(def, pitchMul, part.Position, gain, true)
	s.TimePosition = rng:NextNumber(0, 1) -- départ aléatoire : deux boucles ne sont jamais en phase
	local target = s.Volume
	s.Volume = 0
	s:Play()
	for i = 1, 8 do -- montée lisse (~0,2 s) : la boucle démarre au milieu de son fichier
		task.delay(0.025 * i, function()
			if v.Token == token then
				s.Volume = target * i / 8
			end
		end)
	end
	return s, target
end

local function followLoop(s: Sound?, pos: Vector3)
	local v = s and voiceOf[s]
	if v and v.Att then
		v.Att.WorldPosition = pos
	end
end

-- arrête une boucle : fondu à la dernière position connue, puis la voix retourne au pool
local function stopLoop(s: Sound?, lastPos: Vector3?)
	local v = s and voiceOf[s]
	if not (s and v) then
		return
	end
	local token = v.Token
	if lastPos then
		followLoop(s, lastPos)
	end
	fadeOut(s, 0.25, function()
		release(v, token)
	end, function()
		return v.Token == token
	end)
end

-- ── Boucles de VOL : seules les 8 plus proches jouent ; Doppler + wobble ─────────────────────────────────
type Traveler = {
	Part: BasePart, Def: any, PitchMul: number, Sound: Sound?, BaseSpeed: number, LastPos: Vector3, Seed: number,
	-- sifflement de balle
	Whiz: boolean, Tint: string?, Speed: number, Age: number, PrevDist: number?, Closing: boolean, Launched: boolean, LastWhiz: number,
	BaseVol: number?, LoopT0: number?,
	-- modulation par les MODIFICATEURS (Vague / Spirale / Orbite / Tête chercheuse)
	ModDepth: number?, ModRate: number?,
}
local travelers: { [BasePart]: Traveler } = {}
local selectTimer = 0
local clock = 0

-- isOwn : projectile tiré par CE joueur -> son sifflement de départ a déjà été joué au clic (PredictCast)
-- mods : { Traj, Homing, Heavy } -> la boucle de vol change de caractère :
--   Vague = ondulation lente et large ; Spirale = vibrato rapide ; Orbite = houle lente ;
--   Tête chercheuse = vibrato serré "qui cherche" ; Lest = plus grave.
local TRAJ_MOD = {
	Wave = { 0.16, 7 }, Spiral = { 0.12, 15 }, Orbit = { 0.1, 3.5 }, Boomerang = { 0.07, 5 },
}
function SoundFX.Travel(part: BasePart, card: string?, element: string?, size: number?, isOwn: boolean?, mods: any?): () -> ()
	local main = layers(card, element)
	local name = main.Travel
	local def = name and LOOP[name] or nil
	local whiz = not NO_WHIZ[card or ""]
	if not def and not whiz then
		return function() end
	end
	mods = mods or {}
	local mod = TRAJ_MOD[mods.Traj or ""]
	local depth, rate = if mod then mod[1] else nil, if mod then mod[2] else nil
	if mods.Homing then
		depth, rate = (depth or 0) + 0.05, rate or 24
	end
	travelers[part] = {
		ModDepth = depth, ModRate = rate,
		Part = part, Def = def, PitchMul = sizePitch(size) * (if mods.Heavy then 0.82 else 1), Sound = nil, BaseSpeed = 1,
		LastPos = part.Position, Seed = rng:NextNumber(0, 100),
		Whiz = whiz, Tint = "Tint." .. (element or "Arcane"), Speed = 0, Age = 0, PrevDist = nil,
		Closing = false, Launched = isOwn == true, LastWhiz = if isOwn then clock else -1,
	}
	selectTimer = 0 -- sélection immédiate : la boucle de vol démarre dès la frame suivante
	return function()
		local t = travelers[part]
		travelers[part] = nil
		if t and t.Sound then
			stopLoop(t.Sound, t.LastPos)
		end
	end
end

local function updateTravel(dt: number)
	clock += dt
	local camPos = workspace.CurrentCamera.CFrame.Position
	selectTimer -= dt
	if selectTimer <= 0 then
		selectTimer = 0.15
		-- sélection des boucles audibles : les plus proches, dans la portée
		local list = {}
		for _, t in travelers do
			local d = (t.Part.Position - camPos).Magnitude
			if d < TRAVEL_RANGE and t.Def then
				table.insert(list, { t, d })
			elseif t.Sound then
				stopLoop(t.Sound, t.LastPos)
				t.Sound = nil
			end
		end
		table.sort(list, function(a, b)
			return a[2] < b[2]
		end)
		for i, entry in list do
			local t = entry[1]
			if i <= MAX_TRAVEL_LOOPS then
				if not t.Sound then
					t.Sound, t.BaseVol = startLoop(t.Def, t.Part, t.PitchMul, TRAVEL_LOOP_GAIN)
					t.LoopT0 = clock
					t.BaseSpeed = t.Sound.PlaybackSpeed
				end
			elseif t.Sound then
				stopLoop(t.Sound, t.LastPos)
				t.Sound = nil
			end
		end
	end
	-- Doppler (approche = plus aigu) + wobble, uniquement pour les boucles actives (<= 8)
	for part, t in travelers do
		local pos = part.Position
		followLoop(t.Sound, pos) -- la voix suit le projectile
		if t.Sound and dt > 0 then
			local vel = (pos - t.LastPos) / dt
			local toCam = camPos - pos
			local approach = if toCam.Magnitude > 0.1 then vel:Dot(toCam.Unit) else 0
			-- Doppler marqué : un sort qui fonce sur toi monte et grossit, il retombe en s'éloignant
			local doppler = math.clamp(1 + approach / 250, 0.75, 1.3)
			local wobble = if t.Def.Wobble then 1 + t.Def.Wobble * math.sin(clock * 9 + t.Seed) else 1
			if t.ModDepth then
				wobble *= 1 + t.ModDepth * math.sin(clock * t.ModRate + t.Seed * 3)
			end
			-- VIE : micro-variations continues (la flamme respire, l'énergie crépite), propres à chaque
			-- projectile grâce à sa graine : deux sorts identiques ne sonnent jamais pareil en vol
			local flutter = 1 + 0.2 * math.noise(clock * 14, t.Seed)
			local drift = 1 + 0.03 * math.noise(clock * 5, t.Seed + 7.3)
			t.Sound.PlaybackSpeed = t.BaseSpeed * doppler * wobble * drift
			if t.BaseVol then
				local fadeIn = math.clamp((clock - (t.LoopT0 or 0)) / 0.12, 0, 1)
				t.Sound.Volume = t.BaseVol * fadeIn * flutter * math.clamp(doppler, 0.85, 1.2)
			end
		end

		-- ── sifflement de balle ──
		if t.Whiz and dt > 0 then
			t.Age += dt
			local instSpeed = (pos - t.LastPos).Magnitude / dt
			t.Speed = if t.Age < 0.05 then instSpeed else t.Speed * 0.7 + instSpeed * 0.3
			local d = (pos - camPos).Magnitude
			-- départ : le sort quitte la baguette près de la caméra (tes propres tirs)
			if not t.Launched and t.Age > 0.05 then
				t.Launched = true
				if d < 25 and t.Speed > WHIZ_MIN_SPEED then
					local pm = speedPitch(t.Speed) * t.PitchMul
					SoundFX.Play("Whiz.Launch", pos, pm)
					SoundFX.Play(t.Tint, pos, pm, 0.8)
					t.LastWhiz = clock
				end
			end
			-- passage : la distance cesse de diminuer = point le plus proche de la caméra
			if t.Age > 0.12 and t.PrevDist then
				if t.Closing and d > t.PrevDist and t.PrevDist < FLYBY_RADIUS
					and t.Speed > WHIZ_MIN_SPEED and clock - t.LastWhiz > 0.4 then
					local closeness = 1 - (t.PrevDist / FLYBY_RADIUS) * 0.6 -- plus il passe près, plus c'est fort
					local pm = speedPitch(t.Speed) * t.PitchMul
					SoundFX.Play("Whiz.Flyby", t.LastPos, pm, closeness)
					SoundFX.Play(t.Tint, t.LastPos, pm, closeness * 0.8)
					t.LastWhiz = clock
				end
				t.Closing = d < t.PrevDist
			end
			t.PrevDist = d
		end
		t.LastPos = pos
	end
end

-- ── ZONES : Spawn -> Loop / Tick -> End ──────────────────────────────────────────────────────────────────────────────
type ZoneSound = { Part: BasePart, Def: any, Loop: Sound?, TickAcc: number, LastPos: Vector3 }
local zones: { [BasePart]: ZoneSound } = {}

function SoundFX.Zone(marker: BasePart, kind: string): () -> ()
	local isPatch = kind == "Patch"
	local def = if isPatch then (ZONE["Patch" .. tostring(marker:GetAttribute("Element"))] or ZONE.PatchFire) else ZONE[kind]
	if not def then
		return function() end
	end
	SoundFX.Play(def.Spawn, marker.Position)
	-- zone INFUSÉE d'un autre élément : couche de cet élément à l'apparition, en continu et à la fin
	local element = marker:GetAttribute("Element")
	local tint = if element and not isPatch and element ~= ZONE_NATIVE[kind] then ELEMENT[element] else nil
	local tintLoop = nil
	if tint then
		SoundFX.Play(tint.Impact or tint.Cast, marker.Position)
		if tint.Travel and LOOP[tint.Travel] then
			tintLoop = startLoop(LOOP[tint.Travel], marker, 0.8, 0.9)
		end
	end
	local z: ZoneSound = {
		Part = marker, Def = def, TickAcc = 0, LastPos = marker.Position,
		Loop = if def.Loop and LOOP[def.Loop] then startLoop(LOOP[def.Loop], marker, 1) else nil,
		TintLoop = tintLoop,
	}
	zones[marker] = z
	return function()
		if zones[marker] ~= z then
			return
		end
		zones[marker] = nil
		stopLoop(z.Loop, z.LastPos)
		stopLoop(z.TintLoop, z.LastPos)
		SoundFX.Play(def.End, z.LastPos)
		if tint then
			SoundFX.Play(tint.Tail or tint.Impact, z.LastPos)
		end
	end
end

local function updateZones(dt: number)
	for part, z in zones do
		if part.Parent then
			z.LastPos = part.Position
		end
		followLoop(z.Loop, z.LastPos) -- zones mobiles (bouclier)
		followLoop(z.TintLoop, z.LastPos)
		if z.Def.Tick then
			z.TickAcc += dt
			if z.TickAcc >= (z.Def.TickEvery or 1) then
				z.TickAcc = 0
				SoundFX.Play(z.Def.Tick, z.LastPos)
			end
		end
	end
end

-- ── ÉTATS (cible en feu...) : boucle attachée à un holder qui suit la cible ──────────────────────────────────
local statusLoops: { [BasePart]: Sound } = {}
function SoundFX.Status(part: BasePart, kind: string): () -> ()
	local spec = STATUS[kind]
	if not spec then
		return function() end
	end
	if spec.Start then
		SoundFX.Play(spec.Start, part.Position)
	end
	local def = spec.Loop and LOOP[spec.Loop]
	local s = def and startLoop(def, part, 1, 1)
	if s then
		statusLoops[part] = s
	end
	return function()
		if s then
			if statusLoops[part] == s then
				statusLoops[part] = nil
			end
			stopLoop(s, part.Position)
		end
		if spec.End then
			SoundFX.Play(spec.End, part.Position)
		end
	end
end

-- ── FAISCEAU MAINTENU : attaque (son de tir normal) + boucle continue qui suit le faisceau ────────────
-- Base = le rayon lui-même (laser / éclair) ; s'il est INFUSÉ, la matière de l'élément s'ajoute en continu
-- (boucle au point d'arrivée) + des petits sons ponctuels : un rayon laser devient un rayon de givre, de feu...
-- teinte d'un rayon MAINTENU infusé : définie dans WandShared/Elements/<Élément>/Sounds (BeamTint)
local BEAM_TINT = ELEMENT_BEAM_TINT
-- boucle POSITIONNÉE libre (incendie...) : renvoie { Move(pos), Stop() }
function SoundFX.PointLoop(name: string, pos: Vector3)
	local def = LOOP[name]
	if not def or not group then
		return nil
	end
	local s = startLoop(def, { Position = pos } :: any, 1, 1)
	local last = pos
	return {
		Move = function(p: Vector3)
			last = p
			followLoop(s, p)
		end,
		Stop = function()
			stopLoop(s, last)
		end,
	}
end

function SoundFX.HoldBeam(kind: string, pos: Vector3, element: string?, card: string?)
	local _, tint = layers(card, element)
	SoundFX.Play(if kind == "Lightning" then "Beam.Lightning" else "Beam.Laser", pos)
	if tint and tint.Cast then
		SoundFX.Play(tint.Cast, pos, 1, 0.8)
	end
	-- éclair maintenu : PAS de crépitement (réservé à l'électrocution) -> bourdonnement + tonnerre continu
	local base = startLoop(LOOP[if kind == "Lightning" then "Loop.BeamLightningHum" else "Loop.BeamLaser"], { Position = pos } :: any, 1, 1)
	local bases = {}
	local storm = kind == "Lightning"

	local extra = {}
	local spec = tint and BEAM_TINT[element or ""]
	if spec then
		for _, name in spec.Loops do
			if LOOP[name] then
				table.insert(extra, (startLoop(LOOP[name], { Position = pos } :: any, 1, 1)))
			end
		end
	end
	local mid, tip = pos, pos
	local alive = true
	if storm then
		task.spawn(function() -- roulements qui se chevauchent + un coup de tonnerre de temps en temps
			local nextCrack = os.clock() + rng:NextNumber(1.8, 2.6) -- le 1er craquement long de l'attaque sonne encore
			task.wait(0.05) -- l'orage démarre AVEC l'attaque (0,6 s avant : creux au début du maintien)
			while alive do
				SoundFX.Play("Hold.ThunderRoll", mid)
				if os.clock() >= nextCrack then
					SoundFX.Play("Hold.ThunderCrack", tip)
					nextCrack = os.clock() + rng:NextNumber(1.6, 2.8) -- (2,5-4 s : orage trop calme)
				end
				task.wait(rng:NextNumber(0.65, 0.85)) -- grondements de ~2 s : 2-3 se chevauchent = tonnerre CONSTANT
			end
		end)
	end
	if spec and spec.Tick then
		task.spawn(function()
			while alive do
				task.wait(rng:NextNumber(spec.Every[1], spec.Every[2]))
				if alive then
					SoundFX.Play(spec.Tick, tip, 1, 0.7)
				end
			end
		end)
	end
	return {
		-- mid = milieu du faisceau (le rayon), at = point d'arrivée (la matière qui frappe)
		Move = function(p: Vector3, at: Vector3?)
			mid, tip = p, at or p
			followLoop(base, mid)
			for _, s in bases do
				followLoop(s, mid)
			end
			for _, s in extra do
				followLoop(s, tip)
			end
		end,
		Stop = function()
			alive = false
			stopLoop(base, mid)
			for _, s in bases do
				stopLoop(s, mid)
			end
			for _, s in extra do
				stopLoop(s, tip)
			end
		end,
	}
end

-- ── CROISSANCES : boucle pendant la pousse, coupée dès que plus aucun segment n'arrive ──────────────────
local growthSounds: { [number]: any } = {}
local stepQueueAt = 0 -- prochaine place libre pour un son de pousse

local function updateGrowthSounds()
	local now = os.clock()
	for id, g in growthSounds do
		if g.Loop and not g.Def.Persist and now - g.Last > 0.45 then
			stopLoop(g.Loop, g.Pos)
			g.Loop = nil
		end
		-- ambiance ponctuelle de l'arbre vivant (gouttes, feuillage...) à un point au hasard de l'arbre
		if g.Def.Tick and now >= g.NextTick then
			local ev = g.Def.Every
			g.NextTick = now + rng:NextNumber(ev[1], ev[2])
			local pts = g.Points
			SoundFX.Play(g.Def.Tick, if #pts > 0 then pts[rng:NextInteger(1, #pts)] else g.Pos)
		end
	end
end

local function growthEvent(kind: string, msg, element: string)
	local id = tonumber(msg.g)
	local p = if typeof(msg.p) == "Vector3" then msg.p else nil
	if not id then
		return
	end
	if kind == "GrowStart" then
		local def = GROW[element] or GROW.Nature
		local z = math.clamp(tonumber(msg.z) or 1, 0.5, 5)
		local pm = math.clamp(1.1 - (z - 1) * 0.08, 0.75, 1.1) -- grosse ramure = plus grave
		SoundFX.Play(def.Start, p, pm)
		local g = { Def = def, Loop = nil, Last = os.clock(), Pos = p or Vector3.zero, Points = {}, NextTick = os.clock() + 0.5 }
		if def.Loop and LOOP[def.Loop] and p then
			g.Loop = startLoop(LOOP[def.Loop], { Position = p } :: any, pm, 1)
		end
		growthSounds[id] = g
	elseif kind == "Grow" then
		local g = growthSounds[id]
		local def = if g then g.Def else (GROW[element] or GROW.Nature)
		local at = if typeof(msg.d) == "Vector3" then msg.d else p
		if g then
			g.Last = os.clock()
			if at then
				-- quelques points de l'arbre pour placer l'ambiance (20 max, renouvelés)
				if #g.Points < 20 then
					table.insert(g.Points, at)
				else
					g.Points[rng:NextInteger(1, 20)] = at
				end
			end
		end
		-- bloc épais = plus grave ; les fines branches sonnent plus sec
		local w = tonumber(msg.w) or 1
		-- les segments arrivent PAR PAQUETS (même image) : on les ÉTALE (~35 ms) au lieu de les jeter,
		-- pour entendre chaque bloc posé
		local pm, vm = math.clamp(1.3 - w * 0.12, 0.55, 1.35), math.clamp(0.55 + w * 0.3, 0.6, 1.3)
		local now = os.clock()
		local slot = math.max(now, stepQueueAt)
		if slot - now < 0.6 then
			stepQueueAt = slot + rng:NextNumber(0.025, 0.04)
			if slot <= now then
				SoundFX.Play(def.Step, at, pm, vm)
			else
				task.delay(slot - now, SoundFX.Play, def.Step, at, pm, vm)
			end
		end
		if msg.l then
			SoundFX.Play("Grow.Lock", at)
		end
	elseif kind == "GrowEnd" then
		local g = growthSounds[id]
		growthSounds[id] = nil
		local def = if g then g.Def else (GROW[element] or GROW.Nature)
		if g and g.Loop then
			stopLoop(g.Loop, g.Pos)
		end
		SoundFX.Play(def.End, p)
	end
end

-- ══ 6. ROUTAGE DES MESSAGES SERVEUR ═════════════════════════════════════════════════════════════════════════════════
local function handleMsg(msg: { [string]: any })
	local p = if typeof(msg.p) == "Vector3" then msg.p else nil
	local kind = msg.k
	local element = if type(msg.e) == "string" then msg.e else "Arcane"
	local card = if type(msg.c) == "string" then msg.c else nil
	local prof, tint = layers(card, element)

	if kind == "Knock" then -- une cible est projetée par Recul (Combat.Push avec knock)
		local s = tonumber(msg.s) or 40
		SoundFX.Play("Hit.Knockback", p, math.clamp(1.15 - s / 300, 0.8, 1.1), math.clamp(0.6 + s / 90, 0.7, 1.4))
		return
	end
	if kind == "Dash" then
		SoundFX.Play("Move.Dash", p)
		return
	end
	if kind == "Skid" then
		local s = tonumber(msg.s) or 30
		SoundFX.Play("Move.Skid", p, 1, math.clamp(0.6 + s / 80, 0.7, 1.4))
		return
	end
	if kind == "Launch" then
		-- (user 2026-11-22) propulsion céleste : plus de son au décollage, seul l'impact au sol reste
		return
	elseif kind == "Land" then
		local s = tonumber(msg.s) or 100
		SoundFX.Play("Move.Land", p, 1, math.clamp(0.75 + s / 250, 0.85, 1.4)) -- harder hit = louder
		return
	end
	if kind == "Cast" then
		if prof.Cast then
			SoundFX.Play(prof.Cast, p)
		end
		if tint and tint.Cast then
			SoundFX.Play(tint.Cast, p, 1, 0.8) -- la matière infusée s'entend dès le départ
		end
	elseif kind == "Impact" then
		local size = tonumber(msg.s)
		local pm, gain = sizePitch(size), sizeGain(size)
		-- collision : seulement si le projectile a vraiment touché quelque chose
		if msg.x and prof.Impact then
			SoundFX.Play(prof.Impact, p, pm, gain)
		end
		if msg.x and tint and tint.Impact then
			SoundFX.Play(tint.Impact, p, pm, gain * 0.85)
		end
		if msg.kb then
			SoundFX.Play("Impact.Knock", p, pm, gain)
		end
		-- explosion : taille selon le rayon, puis la queue de l'élément (celui de l'infusion s'il y en a une)
		local r = tonumber(msg.r) or 0
		if r > 0 then
			-- l'INFUSION change la matière de l'explosion (glace, foudre, toxique, nature) ; le feu garde le boom
			local exEl = if E["Explosion." .. element] then "Explosion." .. element else nil
			if prof.Explosion then
				SoundFX.Play(prof.Explosion, p, if r >= 20 then 0.8 else 1, gain)
			elseif exEl then
				SoundFX.Play(exEl, p, if r >= 9 then 0.85 elseif r >= 5 then 1 else 1.15, gain)
			else
				SoundFX.Play(if r >= 9 then "Explosion.Big" elseif r >= 5 then "Explosion.Medium" else "Explosion.Small", p, if r >= 20 then 0.8 else 1, gain)
			end
			local tail = if tint then (tint.Tail or tint.Impact) else prof.Tail
			if tail then
				SoundFX.Play(tail, p)
			end
		end
	elseif kind == "Bounce" then
		-- REBOND en 3 couches : corps physique (selon la taille) + teinte de l'élément + ricochet si rapide.
		-- Volume selon la vitesse d'arrivée sur la surface (choc franc = fort, glissade = discret).
		local size = tonumber(msg.s) or 0.6
		local pm = sizePitch(size)
		local speed = tonumber(msg.v) or 60
		local energy = math.clamp(speed / 90, 0.3, 1.25)
		local heavy = size >= 1.8
		local body = if prof.Body ~= nil then prof.Body elseif heavy then "Bounce.BodyHeavy" else "Bounce.Body"
		if body then
			SoundFX.Play(body, p, pm, energy)
		end
		if prof.Bounce then
			SoundFX.Play(prof.Bounce, p, pm, math.max(0.6, energy) * 1.4)
		end
		if tint and tint.Bounce and tint.Bounce ~= prof.Bounce then
			SoundFX.Play(tint.Bounce, p, pm, math.max(0.6, energy) * 1.1)
		end
		if speed > 70 and not heavy and prof.Body ~= false then
			SoundFX.Play("Bounce.Ricochet", p, pm * math.clamp(speed / 110, 0.85, 1.25), math.clamp((speed - 70) / 60, 0.4, 1))
		end
	elseif kind == "Beam" then
		local name = prof.Beam or "Beam.Laser"
		if msg.h then -- tick d'un rayon maintenu
			name = if name == "Beam.Lightning" then "Beam.HoldLightning" elseif name == "Beam.Laser" then "Beam.HoldLaser" else name
		elseif msg.j and name == "Beam.Lightning" then -- saut d'éclair / arc d'arbre : crac court
			name = "Beam.LightningJump"
		end
		if msg.j and name == "Beam.Laser" then
			-- segment après un REBOND : tous arrivent dans la même image -> ricochets ÉCHELONNÉS (0,05 s chacun),
			-- joués au point de rebond (sinon MinGap / anti-doublon les avalaient)
			local now = os.clock()
			ricoN = if now - ricoAt < 0.02 then ricoN + 1 else 1
			ricoAt = now
			task.delay(ricoN * 0.05, function()
				SoundFX.Play("Beam.Ricochet", p, 1 + ricoN * 0.04)
			end)
		else
			SoundFX.Play(name, p)
		end
		if tint and not msg.h then
			-- rayon infusé : la matière claque au point d'arrivée
			SoundFX.Play(tint.Impact or tint.Cast, if typeof(msg.d) == "Vector3" then msg.d else p, 1, 0.8)
		end
	elseif kind == "Trigger" then
		SoundFX.Play("Trigger", p)
	elseif kind == "Dmg" then
		-- tick de brûlure / poison / saignement, ou coup direct selon l'élément
		local name = if type(msg.t) == "string" then "Dot." .. msg.t else "Hit." .. element
		-- (son de coup « corps » retiré à la demande : en attente d'un nouveau son de dégâts)
		SoundFX.Play(if E[name] then name else "Hit.Arcane", p, 1, if msg.t then 1 else 0.85)
	elseif kind == "TrapFire" then
		SoundFX.Play("Trap.Snap", p)
	elseif kind == "Teleport" then
		SoundFX.Play("Teleport", p)
	elseif kind == "Dispel" then
		SoundFX.Play("Dispel", p)
	elseif kind == "NoMana" then
		SoundFX.Play("NoMana", nil)
	elseif kind == "GrowStart" or kind == "Grow" or kind == "GrowEnd" then
		growthEvent(kind, msg, element)
	elseif kind == "Fizzle" then
		local own = msg.u == game:GetService("Players").LocalPlayer.UserId
		SoundFX.Play("Fizzle", if own then nil else p) -- son échec de SON propre sort : en 2D, bien net
	end
end

-- Tir LOCAL prédit : le son de départ et le sifflement jouent à l'instant du clic, sans attendre le
-- serveur (sinon : + un aller-retour réseau). Le message Cast du serveur est ignoré pour ses propres tirs.
function SoundFX.PredictCast(card: string?, element: string?, pos: Vector3, speed: number?, instant: boolean?)
	local prof, tint = layers(card, element)
	if prof.Cast then
		SoundFX.Play(prof.Cast, pos)
	end
	if tint and tint.Cast then
		SoundFX.Play(tint.Cast, pos, 1, 0.8)
	end
	if not instant and not NO_WHIZ[card or ""] and (speed or 100) > WHIZ_MIN_SPEED then
		local pm = speedPitch(speed or 100)
		SoundFX.Play("Whiz.Launch", pos, pm)
		SoundFX.Play("Tint." .. (element or "Arcane"), pos, pm, 0.8)
	end
end

function SoundFX.Handle(msg: { [string]: any })
	curScale = tonumber(msg.z) or 1
	local ok, err = pcall(handleMsg, msg)
	curScale = 1
	if not ok then
		warn("[SoundFX]", err)
	end
end

function SoundFX.Init()
	group = Instance.new("SoundGroup")
	group.Name = "WandSFX"
	group.Volume = 4.2 -- (user 2026-11-23 : BEAUCOUP plus fort ; était 2.4) volume général (user 2026-11-22 : un peu plus fort ; était 2) (était 0.9 : trop faible même au maximum)
	group.Parent = SoundService
	local comp = Instance.new("CompressorSoundEffect") -- "colle" les sons, évite la saturation
	comp.Threshold = -18
	comp.Ratio = 3
	comp.Attack = 0.005
	comp.Release = 0.15
	comp.GainMakeup = 3
	comp.Priority = 1
	comp.Parent = group
	-- RÉVERBÉRATION : désactivée par défaut, seulement sur les maps qui la demandent
	-- (attribut workspace "SFXReverb" = true, ex. grotte / salle fermée). Les pas n'en ont jamais.
	local reverb: ReverbSoundEffect? = nil
	local function applyReverb()
		local want = workspace:GetAttribute("SFXReverb") == true
		if want and not reverb then
			local r = Instance.new("ReverbSoundEffect") -- un peu d'espace (salle / grotte)
			r.DecayTime = 1.3
			r.Density = 1
			r.Diffusion = 1
			r.DryLevel = 0
			r.WetLevel = -14
			r.Priority = 2
			r.Parent = group
			reverb = r
		elseif not want and reverb then
			reverb:Destroy()
			reverb = nil
		end
	end
	applyReverb()
	workspace:GetAttributeChangedSignal("SFXReverb"):Connect(applyReverb)
	dryGroup = Instance.new("SoundGroup")
	dryGroup.Name = "WandSFXDry"
	dryGroup.Volume = group.Volume
	comp:Clone().Parent = dryGroup
	dryGroup.Parent = SoundService
	uiFolder = Instance.new("Folder")
	uiFolder.Name = "WandUISounds"
	uiFolder.Parent = SoundService

	-- PRÉCHARGEMENT : toutes les voix sont créées et leurs fichiers préchargés au démarrage,
	-- pour qu'aucun son ne doive se charger au moment où il est déclenché en jeu.
	for name, ev in E do
		local is3D = string.sub(name, 1, 3) ~= "Ui."
		-- joués en 2D (retour au joueur lui-même) : on prépare aussi leurs voix 2D
		local also2D = name == "NoMana" or name == "Fizzle"
		for _, layer in ev.Layers do
			if not layer.Ids then warn("[SoundFX] couche sans fichiers dans", name) layer.Ids = {} end
			for _, id in layer.Ids do
				getPool(resolveId(id), is3D, false)
				if also2D then
					getPool(resolveId(id), false, false)
				end
			end
		end
	end
	for loopName, def in LOOP do
		if type(def.Ids) ~= "table" then
			warn("[Wand] boucle sonore " .. tostring(loopName) .. " sans fichiers (Ids vide) : ignorée")
		else
			for _, id in def.Ids do
				getPool(resolveId(id), true, true)
			end
		end
	end
	task.spawn(function()
		-- PRÉCHARGEMENT PAR PAQUETS (bug rare : plus aucun son après avoir rejoint). Avant : une seule requête de
		-- ~1500 voix au démarrage, qui pouvait saturer la file de chargement de Roblox sur une connexion lente.
		-- Maintenant : UNE voix par fichier (les autres voix du même fichier partagent le cache), par paquets de 20.
		local byId, list = {}, {}
		for snd in voiceOf do
			if not byId[snd.SoundId] then
				byId[snd.SoundId] = true
				table.insert(list, snd)
			end
		end
		for k = 1, #list, 20 do
			local batch = table.move(list, k, math.min(k + 19, #list), 1, {})
			pcall(function()
				ContentProvider:PreloadAsync(batch)
			end)
			task.wait(0.05)
		end
		-- diagnostic : fichiers toujours pas chargés après le préchargement (visible dans la console F9)
		task.delay(10, function()
			local missing = 0
			for _, snd in list do
				if not snd.IsLoaded then
					missing += 1
				end
			end
			if missing > 0 then
				warn(("[SoundFX] %d / %d fichiers son pas encore chargés 10 s après le démarrage"):format(missing, #list))
			end
		end)
		-- surveillance : si un groupe de sons a disparu, on le recrée et on y rebranche les voix
		task.spawn(function()
			while true do
				task.wait(3)
				if not group or not group.Parent or not dryGroup or not dryGroup.Parent then
					warn("[SoundFX] groupe de sons perdu : reconstruction")
					if not group or not group.Parent then
						group = Instance.new("SoundGroup")
						group.Name = "WandSFX"
						group.Volume = 2.4
						group.Parent = SoundService
					end
					if not dryGroup or not dryGroup.Parent then
						dryGroup = Instance.new("SoundGroup")
						dryGroup.Name = "WandSFXDry"
						dryGroup.Volume = group.Volume
						dryGroup.Parent = SoundService
					end
					for snd in voiceOf do
						snd.SoundGroup = if DRY_IDS[snd.SoundId] then dryGroup else group
					end
				end
			end
		end)
		-- (plus de "chauffage" : lancer les ~1500 voix EN MÊME TEMPS à volume 0 dépassait la limite de sons
		-- simultanés de Roblox -> des voix restaient bloquées MUETTES pour toute la partie, au hasard
		-- (1 recul / 1 dash sur 2 silencieux). Le préchargement des fichiers ci-dessus suffit.)
		SoundFX.Ready = true
	end)
	RunService.RenderStepped:Connect(function(dt)
		updateTravel(dt)
		updateZones(dt)
		updateGrowthSounds()
	end)
end

-- tables internes exposées aux OUTILS (SoundAudit, contrôle de cohérence) — lecture seule
SoundFX.Debug = { P = P, E = E, LOOP = LOOP, START_AT = START_AT, ZONE = ZONE, CARD = CARD, ELEMENT = ELEMENT, GROW = GROW }

return SoundFX

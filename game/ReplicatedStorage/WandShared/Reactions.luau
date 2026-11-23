--[[
	WandShared/Reactions — RÉACTIONS ENTRE ÉLÉMENTS (phases 2.4 et 2.5). Une ligne = une réaction.

	Targets : sur une CIBLE. Quand une cible reçoit un coup de l'élément `Hit` alors qu'elle porte la marque `On`
	          (élément actif : "Toxic", "Fire"... ou blocage : "Frozen", "Rooted"), Run(r) s'exécute AVANT l'effet normal.
	  r : Hum, Pos, Owner, Amount, Stacks(el), Consume(marque), Explode(rayon, dégâts, el), DamageAround(rayon, dégâts, el),
	      Damage(dégâts, el), AddStacks(el, n), Visual(nom, taille), Label(texte). Retourner true = le coup ne pose pas son effet.

	Zones : sur une ZONE AU SOL. Quand un sort de l'élément `Hit` (impact, explosion, rayon, ou une nouvelle zone) touche
	        une zone de l'élément `On`, Run(z) s'exécute. La réaction est À L'ÉCHELLE DE LA ZONE (z.Radius).
	  z : Pos, Radius, Owner, Element, Remove(), Explode(rayon, dégâts, el), DamageIn(dégâts, el), Ignite(),
	      Extinguish(), CreatePatch(élément, rayon, durée), Visual(nom, taille), Label(texte)
	  GARDE-FOUS (ZoneService) : une zone ne réagit qu'UNE fois (Cooldown = elle peut re-réagir après x s),
	  les zones NÉES d'une réaction ne déclenchent rien, 8 réactions de zone max par seconde, dégâts plafonnés ici.
	Les effets visuels/sonores (Visual) sont dans WandShared/ReactionVisuals.
]]

local Reactions = {}

Reactions.Targets = {
	-- Feu sur une cible empoisonnée : le poison s'embrase -> EXPLOSION DE GAZ (consomme le poison)
	{ Hit = "Fire", On = "Toxic", Name = "Explosion de gaz", Run = function(r)
		local n = r.Stacks("Toxic")
		r.Consume("Toxic")
		r.Explode(5 + n * 0.5, 8 + n * 3, "Fire")
		r.Visual("GasBlast", 1 + n * 0.15)
		r.Label("EXPLOSION DE GAZ")
	end },
	-- Feu sur une cible gelée : VAPEUR (dégèle, brûle un peu autour)
	{ Hit = "Fire", On = "Frozen", Name = "Vapeur", Run = function(r)
		r.Consume("Frozen")
		r.DamageAround(4, 6, "Fire")
		r.Visual("Steam", 1.2)
		r.Label("VAPEUR")
	end },
	-- Feu sur une cible enracinée : les RACINES S'EMBRASENT (libère la cible, brûlure renforcée)
	{ Hit = "Fire", On = "Rooted", Name = "Racines en feu", Run = function(r)
		r.Consume("Rooted")
		r.Damage(r.Amount * 0.5, "Fire")
		r.AddStacks("Fire", 1)
		r.Visual("Blaze", 1)
		r.Label("RACINES EN FEU")
	end },
	-- Foudre sur une cible gelée : ÉCLATEMENT (dégâts x1,5, la glace se brise)
	{ Hit = "Lightning", On = "Frozen", Name = "Éclatement", Run = function(r)
		r.Consume("Frozen")
		r.Damage(r.Amount * 0.5, "Lightning")
		r.Visual("Shatter", 1)
		r.Label("ÉCLATEMENT")
	end },
	-- (Foudre + poison = arc toxique : Lightning.Status.Chain.Spreads)
	-- (Glace + poison = poison gelé : Toxic.Status.PausedBy)
	-- (Nature + poison = pourriture : Nature.Status.LockTimeMultIf)
}

Reactions.Zones = {
	-- Feu sur une zone TOXIQUE : toute la flaque explose (taille de la zone), puis brûle
	{ Hit = "Fire", On = "Toxic", Name = "Explosion de gaz", Run = function(z)
		local r = z.Radius * 1.3
		z.Remove()
		z.Explode(r, math.clamp(8 + z.Radius * 2, 8, 45), "Fire")
		z.CreatePatch("Fire", z.Radius, 2.5)
		z.Visual("GasBlast", z.Radius / 3)
		z.Label("EXPLOSION DE GAZ")
	end },
	-- Feu sur une zone de GIVRE : le givre s'évapore. RAPPORT DE TAILLE (z.Ratio = surface du coup / surface de la zone) :
	-- un gros coup efface la zone ; un petit n'en fait fondre qu'une part (durée réduite) + vapeur locale
	{ Hit = "Fire", On = "Ice", Name = "Vapeur", Run = function(z)
		if z.Ratio >= 0.5 then
			z.Remove()
			z.Clash()
			z.DamageIn(4, "Fire")
			z.Visual("Steam", z.Radius / 2.5)
			z.Label("VAPEUR")
		else
			z.Shrink(z.Ratio * 1.4)
			z.VisualAt("Steam", z.HitRadius / 2.5)
			z.Retry(0.4)
		end
	end },
	-- Glace sur une zone de FEU : le brasier s'éteint (même rapport de taille : un petit coup n'éteint qu'une part)
	{ Hit = "Ice", On = "Fire", Name = "Extinction", Run = function(z)
		if z.Ratio >= 0.5 then
			z.Remove()
			z.Clash()
			z.Extinguish()
			z.Visual("Steam", z.Radius / 2.5)
			z.Label("EXTINCTION")
		else
			z.Shrink(z.Ratio * 1.4)
			z.ExtinguishAt()
			z.VisualAt("Steam", z.HitRadius / 2.5)
			z.Retry(0.4)
		end
	end },
	-- Foudre sur une zone TOXIQUE : la flaque s'électrise, tous ceux qui sont dedans sont frappés (peut se répéter)
	{ Hit = "Lightning", On = "Toxic", Name = "Flaque électrifiée", Cooldown = 2, Run = function(z)
		z.DamageIn(math.clamp(5 + z.Radius, 5, 20), "Lightning")
		z.Visual("Electrify", z.Radius)
		z.Label("FLAQUE ÉLECTRIFIÉE")
	end },
	-- Feu sur une zone NATURE (tapis de feuilles) : les feuilles s'enflamment, la zone devient un brasier
	{ Hit = "Fire", On = "Nature", Name = "Feuilles en flammes", Run = function(z)
		z.Remove()
		z.Ignite()
		z.CreatePatch("Fire", z.Radius, 3)
		z.Visual("Blaze", z.Radius / 3)
		z.Label("FEUILLES EN FLAMMES")
	end },
}


-- ARBRES (Ramure, sorts procéduraux) : un sort de l'élément `Hit` touche un arbre infusé `On`.
--   t : Pos (point de contact), Radius (étendue de l'arbre), HitRadius, Size (échelle visuelle), Owner, Element,
--       Strip() (l'arbre perd son infusion : flammes / givre / gaz disparaissent), SetElement(el), Extinguish(),
--       Ignite(), Explode(rayon, dégâts, el), DamageAround(dégâts, el), Visual(nom, taille), Label(texte)
--   Wear = true : il faut assez de contacts (somme des rayons >= 35 % de l'arbre) ; avant, seul Local(t) s'exécute
--   (petite réaction au point de contact). Sans Wear : la réaction est immédiate.
Reactions.Growths = {
	-- Glace sur un arbre de FEU : les flammes s'éteignent (vapeur)
	{ Hit = "Ice", On = "Fire", Name = "Extinction", Wear = true,
		Local = function(t) t.Visual("Steam", t.HitRadius / 2.5) end,
		Run = function(t)
			t.Strip()
			t.Extinguish()
			t.Visual("Steam", t.Size)
			t.Label("EXTINCTION")
		end },
	-- Feu sur un arbre de GIVRE : le givre fond (vapeur)
	{ Hit = "Fire", On = "Ice", Name = "Vapeur", Wear = true,
		Local = function(t) t.Visual("Steam", t.HitRadius / 2.5) end,
		Run = function(t)
			t.Strip()
			t.DamageAround(4, "Fire")
			t.Visual("Steam", t.Size)
			t.Label("VAPEUR")
		end },
	-- Feu sur un arbre TOXIQUE : la sève toxique explose, l'arbre s'embrase
	{ Hit = "Fire", On = "Toxic", Name = "Explosion de gaz", Run = function(t)
		t.SetElement("Fire")
		t.Explode(math.clamp(4 + t.Radius * 0.4, 5, 16), math.clamp(8 + t.Radius, 8, 40), "Fire")
		t.Visual("GasBlast", t.Size)
		t.Label("EXPLOSION DE GAZ")
	end },
	-- Feu sur un arbre NATURE : les feuilles s'enflamment, l'arbre devient un arbre de feu
	{ Hit = "Fire", On = "Nature", Name = "Feuilles en flammes", Run = function(t)
		t.SetElement("Fire")
		t.Ignite()
		t.Visual("Blaze", t.Size)
		t.Label("FEUILLES EN FLAMMES")
	end },
	-- Foudre sur un arbre TOXIQUE : la sève s'électrise autour de l'arbre (peut se répéter)
	{ Hit = "Lightning", On = "Toxic", Name = "Sève électrifiée", Cooldown = 2, Run = function(t)
		t.DamageAround(math.clamp(5 + t.Radius * 0.5, 5, 20), "Lightning")
		t.Visual("Electrify", t.Size)
		t.Label("SÈVE ÉLECTRIFIÉE")
	end },
}

return Reactions

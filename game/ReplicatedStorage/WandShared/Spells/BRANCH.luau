-- BRANCH — Ramure (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "BRANCH", Name = "Ramure", Short = "RM", Type = "Projectile", Category = "Procedural", Element = "Nature",
		Mana = 35, Recharge = 0.25, CastDelay = 0.45,
		Desc = "EXPÉRIMENTAL. Vise une surface solide : 5 troncs en jaillissent et poussent au hasard dans l'espace, en hauteur comme en largeur, en contournant les obstacles. Avec Tête chercheuse, une branche verrouille l'ennemi qui entre dans la zone à sa pointe et se tend vers lui. Infusé de foudre, l'arbre foudroie ce qui l'approche. Blessent et entravent au contact.",
		Proj = proj({ Damage = 0, Instant = true, Range = 45, Size = 0.5,
			Growth = { Kind = "Branch", Arms = 5, Duration = 2.4, Life = 7, Step = 1.6, Thick = 1.3, Damage = 5, Interval = 0.4, Fork = 0.12,
				Sense = 12, SenseMax = 20, ZapRange = 7, ZapMax = 13, Chain = 3 } }) }
	card.Order = 47 -- position dans le grimoire
	card.Family = "Procedural" -- famille de comportement (Projectile | Beam | Procedural | Trap | Self | Multicast) : décide quels modificateurs ont un effet
	card.Icon = "rbxassetid://90651286565550"
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Cast = "Cast.Nature" } -- la croissance a ses propres sons (GROW)
	-- RÉACTIONS À DES MODIFICATEURS précis posés avant la carte (voir SpellPlanner.Resolve)
	card.ModReactions = {
		-- Orbite sur un sort procédural = CAGE autour du lanceur
		ORBIT = function(stats)
			stats.Cage = stats.Cage or "Self"
		end,
	}
	card.Rank = "Superieur" -- Moyen | Superieur | Supreme (classification : voir SpellCatalog.RankLabel)
	return card
end

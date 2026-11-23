-- FRAGMENT — Fragmentation (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "FRAGMENT", Name = "Fragmentation", Short = "FR", Type = "Modifier",
		Mana = 15, CastDelay = 0.1, Desc = "Les sorts qui suivent éclatent en 6 fragments quand ils disparaissent.", Mod = { Fragments = 6 } }
	card.Order = 58 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	-- sons propres à la carte (phases Cast / Travel / Impact / Bounce / Body / Beam ; false = muet)
	card.Sound = { Cast = false, Travel = false, Impact = "Impact.Tiny", Bounce = false, Body = false }
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { TrailSparks = 4, Light = 0.5 }
	return card
end

-- ICE_SHARD — Éclat de glace (Sort (projectile))
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "ICE_SHARD", Name = "Éclat de glace", Short = "GL", Type = "Projectile", Element = "Ice",
		Mana = 12, CastDelay = 0.08, Desc = "Très rapide, traverse 2 cibles et les ralentit.",
		Proj = proj({ Damage = 9, Speed = 180, Lifetime = 1, Size = 0.7, Pierce = 2 }) }
	card.Order = 3 -- position dans le grimoire
	card.Icon = "rbxassetid://126007399256851"
	-- recette visuelle (Trail, TrailSparks, Impact, Flicker, Light, Blink, Beam, Sprite...)
	card.FX = { TrailSparks = 10 }
	return card
end

-- IGNORE_OBSTACLES — Ignore Obstacles (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "IGNORE_OBSTACLES", Name = "Ignore Obstacles", Short = "IO", Type = "Modifier", Category = "Procedural",
		Mana = 50, CastDelay = 0.25,
		Desc = "Rayons : traversent les murs cassables en les détruisant, et rebondissent sur ce qui est indestructible. Sorts procéduraux : la matière générée traverse le décor en cassant les murs cassables au lieu de les contourner. Projectiles et rayons : traversent aussi la matière générée par les sorts (ramure, cages...).",
		Mod = { Phase = true } }
	card.Order = 48 -- position dans le grimoire
	card.AppliesTo = { "Procedural", "Beam", "Projectile" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

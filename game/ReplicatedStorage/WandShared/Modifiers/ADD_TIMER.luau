-- ADD_TIMER — Ajout de minuterie (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "ADD_TIMER", Name = "Ajout de minuterie", Short = "+M", Type = "Modifier",
		Mana = 12, Desc = "Le prochain projectile libère la carte qui le suit après 0,35 s de vol.",
		Mod = { AddTrigger = table.freeze({ Kind = "Timer", Draw = 1, Delay = 0.35 }) } }
	card.Order = 32 -- position dans le grimoire
	card.AppliesTo = { "Projectile", "Beam" } -- familles affectées (absent = toutes) ; sinon « Sans effet » dans la baguette
	return card
end

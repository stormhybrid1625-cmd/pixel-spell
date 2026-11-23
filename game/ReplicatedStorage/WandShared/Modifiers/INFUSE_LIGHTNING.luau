-- INFUSE_LIGHTNING — Infusion : Foudre (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "INFUSE_LIGHTNING", Name = "Infusion : Foudre", Short = "FO", Type = "Modifier", Element = "Lightning",
		Mana = 10, Desc = "Les sorts suivants deviennent Foudre : +20 % de dégâts, plus rapides, et chaque coup SAUTE vers une cible proche (60 %). Choc : immobilise 0,35 s.", Mod = { Element = "Lightning", SpeedMult = 1.25, DamageMult = 1.2 } }
	card.Order = 28 -- position dans le grimoire
	return card
end

-- INFUSE_NATURE — Infusion : Nature (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "INFUSE_NATURE", Name = "Infusion : Nature", Short = "NA", Type = "Modifier", Element = "Nature",
		Mana = 8, Desc = "Les sorts suivants deviennent Nature (+2 dégâts) : racines qui ralentissent ; 3 coups en 3 s ENRACINENT la cible 1 s.", Mod = { Element = "Nature", DamageAdd = 2 } }
	card.Order = 30 -- position dans le grimoire
	return card
end

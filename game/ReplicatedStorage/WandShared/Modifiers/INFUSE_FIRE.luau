-- INFUSE_FIRE — Infusion : Feu (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "INFUSE_FIRE", Name = "Infusion : Feu", Short = "FE", Type = "Modifier", Element = "Fire",
		Mana = 8, Desc = "Les sorts suivants deviennent Feu et gagnent +3 dégâts. BRÛLURE qui se cumule (jusqu'à 3 niveaux). Enflamme le bois et l'herbe.", Mod = { Element = "Fire", DamageAdd = 3 } }
	card.Order = 26 -- position dans le grimoire
	return card
end

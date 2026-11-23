-- INFUSE_TOXIC — Infusion : Toxique (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "INFUSE_TOXIC", Name = "Infusion : Toxique", Short = "TX", Type = "Modifier", Element = "Toxic",
		Mana = 8, Desc = "Les sorts suivants deviennent Toxiques : POISON qui se cumule (jusqu'à 5 niveaux, 4 s). Une cible empoisonnée subit 10 % de dégâts en plus. Zones plus durables.", Mod = { Element = "Toxic", DamageAdd = 1 } }
	card.Order = 29 -- position dans le grimoire
	return card
end

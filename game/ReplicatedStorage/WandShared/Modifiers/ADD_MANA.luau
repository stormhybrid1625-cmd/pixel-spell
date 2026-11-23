-- ADD_MANA — Ajout de mana (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "ADD_MANA", Name = "Ajout de mana", Short = "M+", Type = "Modifier",
		Mana = -20, MaxStack = 2, Recharge = 0.5, CastDelay = 0.6, Desc = "Rend 20 mana sur le coût de ce tir (un tir ne peut pas devenir négatif). Cumulable 2 fois au plus ; chaque exemplaire ralentit la baguette.", Mod = {} }
	card.Order = 39 -- position dans le grimoire
	return card
end

-- RECHARGE_DOWN — Recharge éclair (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "RECHARGE_DOWN", Name = "Recharge éclair", Short = "RC", Type = "Modifier",
		Mana = 40, CastDelay = 0.35, Recharge = -0.3, Desc = "Réduit le temps de recharge de la baguette de 0,3 s.", Mod = {} }
	card.Order = 38 -- position dans le grimoire
	return card
end

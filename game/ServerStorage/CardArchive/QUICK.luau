-- QUICK — Rapidité (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "QUICK", Name = "Rapidité", Short = "R-", Type = "Modifier",
		Mana = 3, Desc = "Réduit le délai avant le tir suivant ET la recharge, en proportion. Chaque exemplaire réduit PLUS que le précédent (-6 %, -9 %, -13,5 %, -20 %, -30 %, -46 %). Cumulable jusqu'à 6 : chaque exemplaire coûte DEUX FOIS plus de mana que le précédent (3, 6, 12, 24, 48, 96).", Mod = {} }
	card.Order = 37 -- position dans le grimoire
	card.MaxStack = 6 -- cumul exceptionnel (3 pour les autres modificateurs)
	card.ManaGrowth = 2 -- coût de l'exemplaire n = Mana x 2^(n-1) : la vitesse se paie très cher
	-- RÉDUCTION EXPONENTIELLE : l'exemplaire n retire DelayCut x DelayCutGrowth^(n-1) du délai restant
	-- (6 %, 9 %, 13,5 %, 20 %, 30 %, 46 %) -> cumul x0,94 / 0,86 / 0,74 / 0,59 / 0,41 / 0,22
	card.DelayCut = 0.06
	card.DelayCutGrowth = 1.5
	return card
end

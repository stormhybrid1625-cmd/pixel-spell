-- INFUSE_ICE — Infusion : Glace (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "INFUSE_ICE", Name = "Infusion : Glace", Short = "GC", Type = "Modifier", Element = "Ice",
		Mana = 8, Desc = "Les sorts suivants deviennent Glace et vont plus vite, mais font 15 % de dégâts en moins. Ralentit ; 3 coups en 3 s GÈLENT la cible 1,2 s.", Mod = { Element = "Ice", SpeedMult = 1.15, DamageMult = 0.85 } }
	card.Order = 27 -- position dans le grimoire
	return card
end

-- CAST_HOLD — Maintien (Modificateur)
-- Une carte = ce fichier : données (coût, stats, description), identité sonore (Sound), recette visuelle (FX).
-- Les infusions (Feu, Glace...) sont gérées par les modules d'éléments ; ici, seulement ce qui est PROPRE à la carte.
return function(proj)
	local card = { Id = "CAST_HOLD", Name = "Maintien", Short = "HO", Type = "Modifier", Category = "CastMode",
		Mana = 5,
		Desc = "Lancement MAINTENU : garde le clic enfoncé. Le coût du tir est payé au départ, puis 30 % de ce coût toutes les 0,12 s (pas de régénération pendant le maintien). Les projectiles partent une fois ; les RAYONS (Rayon, Éclair) deviennent un faisceau continu qui suit ta visée (40 % des dégâts toutes les 0,12 s) ; les sorts procéduraux suivent ta visée en continu (mur de glace = tracé continu, Ramure = une branche par tick là où tu vises). Recharge à la fin du maintien.",
		Mod = { CastMode = "Hold" } }
	card.Order = 51 -- position dans le grimoire
	return card
end

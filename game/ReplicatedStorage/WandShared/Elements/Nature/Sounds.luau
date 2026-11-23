-- SONS de l'élément NATURE : du FEUILLAGE (froissements, haie qui encaisse), jamais de bois qui grince.
-- Les prises PSE de feuillage sont très faibles (niveau moyen 1 à 9 contre ~60) : volumes élevés voulus.
-- Chargé par WandClient.SoundFX : P = banques d'échantillons, ev(minGap, maxVoices, couches) = constructeur.
local HEDGE = { 9114514958 } -- PSE Foliage, impacts dans une haie épaisse, froissement croquant (attaque à 0,85 s)
local RUSTLE = { 9114518577, 9114519078 } -- PSE Foliage Rustle : rafales de feuilles (attaque à ~0,4 s)
local EARTH = { 9118586709, 9118586430, 9118586481, 9118586609 } -- PSE éboulis : la terre qui s'ouvre (grave)

return function(P, ev)
	return {
		Events = {
			-- ÉTAT « enraciné » : les racines jaillissent et serrent (bois qui grince + branches + feuillage), puis lâchent
			-- RACINES QUI JAILLISSENT et serrent (sans grincement) : la terre qui s'ouvre (éboulis grave), les racines qui
			-- fouettent l'air autour du corps, puis le feuillage qui se referme en masse. Fort : le joueur doit le SAVOIR.
			["Status.RootGrab"] = ev(0.1, 4, {
				{ Ids = EARTH, Volume = 2.2, Pitch = { 0.5, 0.6 }, FadeIn = 0.02, Length = 0.55, Fade = 0.3 },
				{ Ids = P.Swish, Volume = 1.6, Pitch = { 0.55, 0.7 }, Delay = 0.05, Length = 0.35, Fade = 0.15 },
				{ Ids = HEDGE, Volume = 3.2, Pitch = { 0.85, 1.0 }, Start = { 0.78, 0.85 }, FadeIn = 0.02, Delay = 0.12, Length = 0.6, Fade = 0.3 },
				{ Ids = RUSTLE, Volume = 3.4, Pitch = { 0.9, 1.05 }, Start = { 0.32, 0.4 }, FadeIn = 0.03, Delay = 0.18, Length = 0.8, Fade = 0.4 },
			}),
			-- les racines se RETIRENT : feuillage qui se détache + un peu de terre
			["Status.RootRelease"] = ev(0.1, 3, {
				{ Ids = RUSTLE, Volume = 2.8, Pitch = { 1.05, 1.2 }, Start = { 0.32, 0.4 }, FadeIn = 0.03, Length = 0.5, Fade = 0.3 },
				{ Ids = EARTH, Volume = 1.4, Pitch = { 0.7, 0.8 }, Length = 0.35, Fade = 0.2 },
			}),
			-- départ : une rafale de feuilles s'arrache de la baguette
			["Cast.Nature"] = ev(0.04, 4, {
				{ Ids = RUSTLE, Volume = 3, Pitch = { 1.15, 1.35 }, Length = 0.7, Fade = 0.35 },
				{ Ids = P.Swish, Volume = 0.14, Pitch = { 1.0, 1.2 } },
			}),
			-- impact : le feuillage encaisse le choc et se froisse
			["Impact.Nature"] = ev(0.03, 4, {
				{ Ids = HEDGE, Volume = 1.3, Pitch = { 0.95, 1.15 }, Length = 0.7, Fade = 0.3 },
				{ Ids = P.LeavesRustle, Volume = 0.9, Pitch = { 1.0, 1.2 }, Start = { 1, 9 }, FadeIn = 0.03, Length = 0.5, Fade = 0.3 },
			}),
			-- explosion : une gerbe de feuilles soufflée d'un coup
			["Explosion.Nature"] = ev(0.05, 4, {
				{ Ids = HEDGE, Volume = 1.8, Pitch = { 0.75, 0.9 }, Length = 0.9, Fade = 0.4 },
				{ Ids = RUSTLE, Volume = 3.5, Pitch = { 0.85, 1.0 }, Length = 1.1, Fade = 0.6 },
				{ Ids = P.LeavesRustle, Volume = 1.2, Pitch = { 0.9, 1.1 }, Start = { 1, 9 }, FadeIn = 0.03, Length = 0.9, Fade = 0.5 },
				{ Ids = P.Boom, Volume = 0.18, Pitch = { 0.9, 1.05 }, Length = 0.7, Fade = 0.35 },
			}),
			-- la cible est fouettée par le feuillage
			["Hit.Nature"] = ev(0.035, 4, {
				{ Ids = HEDGE, Volume = 0.6, Pitch = { 1.1, 1.3 }, Length = 0.45, Fade = 0.2 },
			}),
			-- ZONE NATURE (tapis de feuilles) : rafale douce à la pose, feuilles qui retombent à la fin — aucun bois
			["Patch.LeafSpawn"] = ev(0.1, 2, {
				{ Ids = RUSTLE, Volume = 2.4, Pitch = { 1.05, 1.2 }, Length = 0.8, Fade = 0.4 },
				{ Ids = P.LeavesRustle, Volume = 0.8, Pitch = { 1.0, 1.15 }, Start = { 1, 9 }, FadeIn = 0.03, Length = 0.6, Fade = 0.3 },
			}),
			["Patch.LeafEnd"] = ev(0.1, 2, { { Ids = RUSTLE, Volume = 1.5, Pitch = { 0.9, 1.0 }, Length = 0.7, Fade = 0.4 } }),
			-- teinte nature sur un autre sort : petit froissement
			["Tint.Nature"] = ev(0.03, 4, { { Ids = P.LeavesRustle, Volume = 0.5, Pitch = { 1.2, 1.4 }, Start = { 1, 9 }, FadeIn = 0.02, Length = 0.25, Fade = 0.12 } }),
		},
		Loops = {
			-- le bois serre et grince (PSE Wood Creak long : fichier de la BANQUE DE RÉSERVE, absent de P)
			["Loop.Rooted"] = { Ids = { 9114518577, 9114519078 }, Volume = 2.2, Pitch = { 0.9, 1.0 } },
			["Travel.Nature"] = { Ids = P.LeavesRustle, Volume = 0.9, Pitch = { 1.15, 1.3 } }, -- feuilles qui bruissent en vol
			["Loop.BeamNature"] = { Ids = P.LeavesRustle, Volume = 1.3, Pitch = { 1.0, 1.15 } },
		},
		BeamTint = { Loops = { "Loop.BeamNature" }, Tick = "Tick.Leaves", Every = { 0.5, 1 } },
	}
end

-- SONS de l'élément : événements en couches (Events), boucles (Loops), teinte d'un rayon maintenu (BeamTint).
-- Chargé par WandClient.SoundFX : P = banques d'échantillons, ev(minGap, maxVoices, couches) = constructeur.
return function(P, ev)
	return {
		Events = {
			["Cast.Lightning"] = ev(0.04, 4, { -- départ d'un sort infusé foudre : décharge sèche
				{ Ids = P.Zap, Volume = 0.26, Pitch = { 1.2, 1.5 }, Length = 0.3, Fade = 0.12 },
				{ Ids = P.ThunderStrike, Volume = 0.14, Pitch = { 1.4, 1.6 }, Length = 1.0, Fade = 0.8 },
			}),
			["Impact.Lightning"] = ev(0.04, 4, { -- le projectile foudroie ce qu'il touche : claquement + crac de tonnerre court
				{ Ids = P.Zap, Volume = 0.26, Pitch = { 1.2, 1.5 }, Length = 0.3, Fade = 0.12 },
				{ Ids = P.ThunderStrike, Volume = 0.31, Pitch = { 1.1, 1.3 }, Length = 1.8, Fade = 1.3 },
			}),
			["Tail.Lightning"] = ev(0.1, 2, { -- après une explosion foudroyante : le tonnerre roule au loin
				-- grondement d'APPROCHE pris au début du fichier (début naturel), arrêté avant le craquement
				{ Ids = P.ThunderStrike, Volume = 0.6, Pitch = { 0.85, 0.95 }, Start = { 0, 0.05 }, FadeIn = 0.25, Length = 1.3, Fade = 0.7, Delay = 0.15 },
			}),
			["Explosion.Lightning"] = ev(0.06, 4, { -- décharge : crac de foudre sec + claquement électrique
				{ Ids = P.ThunderStrike, Volume = 0.42, Pitch = { 1.0, 1.15 }, Length = 1.6, Fade = 1.2 },
				{ Ids = P.Zap, Volume = 0.32, Pitch = { 0.75, 0.95 }, Length = 0.4, Fade = 0.15 },
				{ Ids = P.Boom, Volume = 0.2, Pitch = { 1.0, 1.2 }, Length = 0.7, Fade = 0.35 },
			}),
			-- ZONE FOUDRE : la zone naît sur un COUP DE TONNERRE (craquement + roulement court) et une décharge
			["Patch.ThunderSpawn"] = ev(0.15, 2, {
				{ Ids = P.ThunderStrike, Volume = 0.42, Pitch = { 0.95, 1.1 }, Length = 2.4, Fade = 1.7 },
				{ Ids = P.Zap, Volume = 0.3, Pitch = { 0.8, 1.0 }, Length = 0.4, Fade = 0.15 },
			}),
			["Tint.Lightning"] = ev(0.03, 4, { { Ids = P.ZapShort, Volume = 0.12, Pitch = { 1.6, 2.0 }, Length = 0.32, Fade = 0.06 } }),
			["Hit.Lightning"] = ev(0.035, 4, { -- la cible est électrocutée : claquement + grésillement
				{ Ids = P.Zap, Volume = 0.26, Pitch = { 1.4, 1.7 }, Length = 0.25, Fade = 0.1 },
				{ Ids = P.ZapCrackle, Volume = 0.14, Pitch = { 1.2, 1.4 }, Length = 0.35, Fade = 0.15, Delay = 0.03 },
			}),
			["Grow.StartZap"] = ev(0.1, 2, { -- décharge + tonnerre court
				{ Ids = P.Zap, Volume = 0.42, Pitch = { 0.8, 1.0 }, Length = 0.5, Fade = 0.2 },
				{ Ids = P.Thunder, Volume = 0.26, Pitch = { 1.3, 1.5 }, Length = 1, Fade = 0.5, Delay = 0.04 },
			}),
			["Grow.StepZap"] = ev(0.02, 10, {
				{ Ids = P.TreeCreak, Volume = 1.35, Pitch = { 1.09, 1.38 }, Start = { 0.5, 18.5 }, FadeIn = 0.04, Length = 0.38, Fade = 0.22 },
				{ Ids = P.ZapShort, Volume = 0.07, Pitch = { 2.2, 2.8 }, Length = 0.32, Fade = 0.06 },
			}),
			["Grow.EndZap"] = ev(0.1, 2, { { Ids = P.Zap, Volume = 0.28, Pitch = { 0.5, 0.6 }, Length = 0.6, Fade = 0.4 } }),
		},
		Loops = {
			["Loop.BeamZap"] = { Ids = P.ZapCrackle, Volume = 0.22, Pitch = { 1.0, 1.15 } },
			["Loop.TreeZap"] = { Ids = P.ZapCrackle, Volume = 0.18, Pitch = { 0.85, 0.95 } },
		},
		BeamTint = { Loops = { "Loop.BeamZap" }, Tick = "Beam.Arc", Every = { 0.12, 0.25 } },
	}
end

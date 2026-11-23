-- SONS de l'élément : événements en couches (Events), boucles (Loops), teinte d'un rayon maintenu (BeamTint).
-- Chargé par WandClient.SoundFX : P = banques d'échantillons, ev(minGap, maxVoices, couches) = constructeur.
return function(P, ev)
	return {
		Events = {
			["Cast.Fire"] = ev(0.04, 6, { -- la flamme JAILLIT (souffle doux) et crépite ; fondus longs, rien ne se coupe
				{ Ids = P.FireAir, Volume = 1.3, Pitch = { 1.1, 1.35 }, Start = { 1.2, 4 }, FadeIn = 0.04, Length = 0.7, Fade = 0.5 },
				{ Ids = P.FireBurn, Volume = 1.1, Pitch = { 1.15, 1.3 }, Start = { 1, 30 }, FadeIn = 0.03, Length = 0.8, Fade = 0.6 },
			}),
			["Impact.Fire"] = ev(0.03, 6, { -- la flamme s'écrase : souffle + grésillement, puis crépitement qui retombe
				{ Ids = P.FireAir, Volume = 1.3, Pitch = { 0.85, 1.0 }, Start = { 1.2, 4 }, FadeIn = 0.02, Length = 0.6, Fade = 0.45 },
				{ Ids = P.FireBurn, Volume = 1.5, Pitch = { 1.0, 1.15 }, Start = { 1, 30 }, FadeIn = 0.02, Length = 1.1, Fade = 0.8 },
				{ Ids = P.Sizzle, Volume = 0.14, Pitch = { 1.05, 1.25 }, Length = 0.4, Fade = 0.2 },
			}),
			["Tail.Fire"] = ev(0.06, 4, { -- après l'explosion : les flammes brûlent puis s'éteignent doucement
				{ Ids = P.FireBurn, Volume = 1.7, Pitch = { 0.85, 1.0 }, Start = { 1, 30 }, FadeIn = 0.05, Length = 2.2, Fade = 1.5, Delay = 0.05 },
				{ Ids = P.FireAir, Volume = 1.1, Pitch = { 0.7, 0.8 }, Start = { 1.2, 4 }, FadeIn = 0.05, Length = 1.1, Fade = 0.8 },
			}),
			-- CHAMP DE FLAMMES : le brasier RONFLE par bouffées (souffle grave + crépitement qui enfle)
			["Patch.FireGust"] = ev(0.4, 3, {
				{ Ids = P.FireAir, Volume = 2.4, Pitch = { 0.55, 0.7 }, Start = { 1.2, 4 }, FadeIn = 0.2, Length = 1.4, Fade = 0.8 },
				{ Ids = P.FireBurn, Volume = 2.4, Pitch = { 0.8, 0.95 }, Start = { 1, 30 }, FadeIn = 0.2, Length = 1.1, Fade = 0.7 },
			}),
			["Tint.Fire"] = ev(0.03, 4, { { Ids = P.FireAir, Volume = 0.9, Pitch = { 1.4, 1.7 }, Start = { 1.2, 4 }, FadeIn = 0.02, Length = 0.35, Fade = 0.22 } }),
			["Hit.Fire"] = ev(0.035, 4, {
				{ Ids = P.Sizzle, Volume = 0.28, Pitch = { 1.15, 1.35 }, Length = 0.3, Fade = 0.12 },
			}),
			["Grow.StartFire"] = ev(0.1, 2, { -- une flamme s'embrase et se met à brûler
				{ Ids = P.FireAir, Volume = 1.6, Pitch = { 0.7, 0.85 }, Start = { 1.2, 4 }, FadeIn = 0.08, Length = 1.3, Fade = 0.8 },
				{ Ids = P.FireBurn, Volume = 1.3, Pitch = { 0.95, 1.05 }, Start = { 1, 30 }, FadeIn = 0.2, Length = 1.4, Fade = 0.8, Delay = 0.1 },
			}),
			["Grow.StepFire"] = ev(0.07, 5, { -- (0.02 / 10 : deux arbres en feu saturaient les voix du feu) -- bloc de bois qui prend feu en se posant
				{ Ids = P.TreeCreak, Volume = 1.35, Pitch = { 0.92, 1.15 }, Start = { 0.5, 18.5 }, FadeIn = 0.04, Length = 0.38, Fade = 0.22 },
				{ Ids = P.FireBurn, Volume = 0.8, Pitch = { 1.1, 1.3 }, Start = { 1, 30 }, FadeIn = 0.06, Length = 0.3, Fade = 0.15 },
			}),
		},
		Loops = {
			["Travel.Fire"] = { Ids = P.FireBurn, Volume = 1.5, Pitch = { 1.15, 1.3 } }, -- boule qui BRÛLE en volant (crépitement)
			["Loop.BeamFire"] = { Ids = P.FireAir, Volume = 1.2, Pitch = { 1.0, 1.15 } }, -- jet de flamme
			["Loop.BeamFireCrackle"] = { Ids = P.FireBurn, Volume = 1.4, Pitch = { 1.1, 1.25 } },
		},
		BeamTint = { Loops = { "Loop.BeamFire", "Loop.BeamFireCrackle" } },
	}
end

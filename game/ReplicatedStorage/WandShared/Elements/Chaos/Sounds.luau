-- SONS de l'élément : événements en couches (Events), boucles (Loops), teinte d'un rayon maintenu (BeamTint).
-- Chargé par WandClient.SoundFX : P = banques d'échantillons, ev(minGap, maxVoices, couches) = constructeur.
return function(P, ev)
	return {
		Events = {
			["Cast.Chaos"] = ev(0.04, 4, {
				{ Ids = P.Zap, Volume = 0.25, Pitch = { 0.6, 1.8 }, Length = 0.4, Fade = 0.15 },
				{ Ids = P.Swish, Volume = 0.18, Pitch = { 0.8, 1.4 } },
			}),
			["Impact.Chaos"] = ev(0.03, 5, { { Ids = P.Zap, Volume = 0.24, Pitch = { 0.7, 1.6 }, Length = 0.3, Fade = 0.12 } }),
			["Bounce.Chaos"] = ev(0.04, 3, { { Ids = P.Zap, Volume = 0.12, Pitch = { 0.8, 1.8 }, Length = 0.2, Fade = 0.08 } }),
			["Tail.Chaos"] = ev(0.06, 3, { { Ids = P.Zap, Volume = 0.18, Pitch = { 0.5, 0.8 }, Length = 0.6, Fade = 0.3, Delay = 0.04 } }),
			["Tint.Chaos"] = ev(0.03, 4, { { Ids = P.Zap, Volume = 0.1, Pitch = { 0.7, 1.6 }, Length = 0.2, Fade = 0.08 } }),
			["Hit.Chaos"] = ev(0.035, 4, {
				{ Ids = P.Zap, Volume = 0.22, Pitch = { 0.6, 1.5 }, Length = 0.2, Fade = 0.08 },
			}),
			["Grow.StartChaos"] = ev(0.1, 2, {
				{ Ids = P.Zap, Volume = 0.38, Pitch = { 0.45, 1.7 }, Length = 0.6, Fade = 0.25 },
				{ Ids = P.Swish, Volume = 0.2, Pitch = { 0.7, 1.4 } },
			}),
			["Grow.StepChaos"] = ev(0.02, 10, {
				{ Ids = P.TreeCreak, Volume = 1.17, Pitch = { 0.92, 1.49 }, Start = { 0.5, 18.5 }, FadeIn = 0.04, Length = 0.38, Fade = 0.22 },
				{ Ids = P.ZapShort, Volume = 0.08, Pitch = { 1.2, 2.8 }, Length = 0.32, Fade = 0.06 },
			}),
		},
		Loops = {
			["Travel.Chaos"] = { Ids = P.ZapHum, Volume = 0.09, Pitch = { 0.9, 1.3 }, Wobble = 0.25 },
			["Loop.BeamChaos"] = { Ids = P.ZapHum, Volume = 0.16, Pitch = { 0.7, 1.4 }, Wobble = 0.3 },
			["Loop.TreeChaos"] = { Ids = P.ZapHum, Volume = 0.11, Pitch = { 0.8, 1.2 } },
		},
		BeamTint = { Loops = { "Loop.BeamChaos" } },
	}
end

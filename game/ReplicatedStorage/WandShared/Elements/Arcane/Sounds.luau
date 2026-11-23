-- SONS de l'élément : événements en couches (Events), boucles (Loops), teinte d'un rayon maintenu (BeamTint).
-- Chargé par WandClient.SoundFX : P = banques d'échantillons, ev(minGap, maxVoices, couches) = constructeur.
return function(P, ev)
	return {
		Events = {
			["Cast.Arcane"] = ev(0.04, 4, {
				{ Ids = P.Swish, Volume = 0.32, Pitch = { 1.3, 1.6 } },
				{ Ids = P.ZapShort, Volume = 0.14, Pitch = { 1.9, 2.4 }, Length = 0.32, Fade = 0.1 },
			}),
			["Impact.Arcane"] = ev(0.03, 5, { { Ids = P.ZapShort, Volume = 0.22, Pitch = { 2.2, 2.8 }, Length = 0.32, Fade = 0.08 } }),
			["Bounce.Arcane"] = ev(0.04, 3, { { Ids = P.ZapShort, Volume = 0.12, Pitch = { 2.6, 3.0 }, Length = 0.32, Fade = 0.06 } }),
			["Tint.Arcane"] = ev(0.03, 4, { { Ids = P.ZapShort, Volume = 0.1, Pitch = { 2.4, 2.9 }, Length = 0.32, Fade = 0.06 } }),
			["Hit.Arcane"] = ev(0.035, 4, {
				{ Ids = P.ZapShort, Volume = 0.2, Pitch = { 1.7, 2.0 }, Length = 0.32, Fade = 0.06 },
			}),
			["Grow.StartArcane"] = ev(0.1, 2, {
				{ Ids = P.ZapHum, Volume = 0.3, Pitch = { 0.65, 0.75 }, Length = 0.7, Fade = 0.3 },
				{ Ids = P.Swish, Volume = 0.22, Pitch = { 1.2, 1.4 } },
			}),
			["Grow.StepArcane"] = ev(0.02, 10, {
				{ Ids = P.TreeCreak, Volume = 1.17, Pitch = { 1.15, 1.38 }, Start = { 0.5, 18.5 }, FadeIn = 0.04, Length = 0.38, Fade = 0.22 },
				{ Ids = P.ZapShort, Volume = 0.07, Pitch = { 2.6, 3.0 }, Length = 0.32, Fade = 0.06 },
			}),
		},
		Loops = {
			["Travel.Arcane"] = { Ids = P.ZapCrackle, Volume = 0.08, Pitch = { 1.1, 1.3 } },
			["Loop.TreeArcane"] = { Ids = P.ZapHum, Volume = 0.1, Pitch = { 0.55, 0.62 } },
		},
	}
end

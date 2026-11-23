-- SONS de l'élément : événements en couches (Events), boucles (Loops), teinte d'un rayon maintenu (BeamTint).
-- Chargé par WandClient.SoundFX : P = banques d'échantillons, ev(minGap, maxVoices, couches) = constructeur.
return function(P, ev)
	return {
		Events = {
			["Cast.Steel"] = ev(0.04, 4, {
				{ Ids = P.Ricochet, Volume = 0.2, Pitch = { 1.7, 2.1 }, Length = 0.35, Fade = 0.12 },
				{ Ids = P.Swish, Volume = 0.22, Pitch = { 0.9, 1.1 } },
			}),
			["Impact.Steel"] = ev(0.03, 4, { { Ids = P.Ricochet, Volume = 0.28, Pitch = { 1.0, 1.3 }, Length = 0.8, Fade = 0.3 } }),
			["Tint.Steel"] = ev(0.03, 4, { { Ids = P.Ricochet, Volume = 0.1, Pitch = { 2.3, 2.6 }, Length = 0.15, Fade = 0.06 } }),
			["Hit.Steel"] = ev(0.035, 4, { { Ids = P.Stab, Volume = 0.32, Pitch = { 0.95, 1.15 } } }), -- coupure
			["Grow.StartSteel"] = ev(0.1, 2, { -- métal qui s'arrache du sol
				{ Ids = P.Ricochet, Volume = 0.3, Pitch = { 0.7, 0.85 }, Length = 0.7, Fade = 0.3 },
				{ Ids = P.Stab, Volume = 0.25, Pitch = { 0.7, 0.8 } },
			}),
			["Grow.StepSteel"] = ev(0.02, 10, { -- claquement métallique
				-- l'acier POUSSE : métal qui chante en s'étirant + torsion grave et métallique
				{ Ids = P.Ricochet, Volume = 0.3, Pitch = { 1.2, 1.5 }, Length = 0.35, Fade = 0.18 },
				{ Ids = P.ZapWhine, Volume = 0.06, Pitch = { 2.2, 2.6 }, Length = 0.3, Fade = 0.18 },
				{ Ids = P.TreeCreak, Volume = 1.3, Pitch = { 0.75, 0.9 }, Start = { 0.5, 18.5 }, FadeIn = 0.04, Length = 0.38, Fade = 0.22 },
			}),
		},
		Loops = {
			["Loop.BeamSteel"] = { Ids = P.ZapWhine, Volume = 0.12, Pitch = { 2.4, 2.7 } }, -- lame qui chante
		},
		BeamTint = { Loops = { "Loop.BeamSteel" }, Tick = "Bounce.Metal", Every = { 0.3, 0.6 } },
	}
end

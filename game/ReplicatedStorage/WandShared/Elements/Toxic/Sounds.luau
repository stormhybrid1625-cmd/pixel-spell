-- SONS de l'élément : événements en couches (Events), boucles (Loops), teinte d'un rayon maintenu (BeamTint).
-- Chargé par WandClient.SoundFX : P = banques d'échantillons, ev(minGap, maxVoices, couches) = constructeur.
return function(P, ev)
	return {
		Events = {
			-- ÉTAT « empoisonné » : bulles qui éclatent au contact, puis bouillonnement sourd
			["Status.PoisonIn"] = ev(0.15, 3, { { Ids = P.Bubbles, Volume = 0.55, Pitch = { 0.85, 1.05 }, Length = 0.7, Fade = 0.3 } }),
			["Cast.Toxic"] = ev(0.04, 4, {
				{ Ids = P.Bloop, Volume = 0.32, Pitch = { 0.8, 1.1 } },
				{ Ids = P.Swish, Volume = 0.18, Pitch = { 1.0, 1.2 } },
			}),
			["Impact.Toxic"] = ev(0.03, 4, { { Ids = P.Bubbles, Volume = 0.33, Pitch = { 1.0, 1.3 }, Length = 0.5, Fade = 0.2 } }),
			["Explosion.Toxic"] = ev(0.05, 4, { -- la fiole crève : éclaboussure grasse + bouillonnement, boom étouffé
				{ Ids = P.Bubbles, Volume = 0.6, Pitch = { 0.55, 0.7 } },
				{ Ids = P.DripPlop, Volume = 0.55, Pitch = { 0.45, 0.6 } },
				{ Ids = P.Boom, Volume = 0.24, Pitch = { 0.75, 0.9 }, Length = 0.7, Fade = 0.35 },
				{ Ids = P.Swish, Volume = 0.18, Pitch = { 0.5, 0.6 } },
			}),
			["Tail.Toxic"] = ev(0.06, 3, { { Ids = P.Bubbles, Volume = 0.28, Pitch = { 0.7, 0.9 }, Delay = 0.05 } }),
			["Tint.Toxic"] = ev(0.03, 4, { { Ids = P.BloopHigh, Volume = 0.1, Pitch = { 1.3, 1.5 } } }),
			["Hit.Toxic"] = ev(0.035, 4, {
				{ Ids = P.Sizzle, Volume = 0.16, Pitch = { 0.7, 0.85 }, Length = 0.3, Fade = 0.12 }, -- chair qui ronge
			}),
			["Grow.StartToxic"] = ev(0.1, 2, { -- ça bouillonne et éclate
				{ Ids = P.Bubbles, Volume = 0.48, Pitch = { 0.65, 0.8 } },
				{ Ids = P.Bloop, Volume = 0.25, Pitch = { 0.5, 0.6 } },
			}),
			["Grow.StepToxic"] = ev(0.02, 10, {
				{ Ids = P.TreeCreak, Volume = 1.17, Pitch = { 0.98, 1.21 }, Start = { 0.5, 18.5 }, FadeIn = 0.04, Length = 0.38, Fade = 0.22 },
				{ Ids = P.Bloop, Volume = 0.09, Pitch = { 0.8, 1.1 } },
			}),
			["Patch.ToxicSpill"] = ev(0.1, 2, { -- la fiole se répand en flaque
				{ Ids = P.Bubbles, Volume = 0.42, Pitch = { 0.6, 0.75 } },
				{ Ids = P.DripPlop, Volume = 0.35, Pitch = { 0.6, 0.75 } },
			}),
		},
		Loops = {
			["Loop.Poisoned"] = { Ids = P.BubbleLoop, Volume = 0.32, Pitch = { 0.85, 0.95 } }, -- la cible bouillonne
			["Travel.Toxic"] = { Ids = P.BubbleLoop, Volume = 0.11, Pitch = { 1.0, 1.15 } },
			["Loop.BeamToxic"] = { Ids = P.BubbleLoop, Volume = 0.22, Pitch = { 1.1, 1.25 } },
			["Loop.TreeToxic"] = { Ids = P.BubbleLoop, Volume = 0.2, Pitch = { 0.7, 0.8 } },
		},
		BeamTint = { Loops = { "Loop.BeamToxic" }, Tick = "Tick.Drop", Every = { 0.25, 0.5 } },
	}
end

-- SONS de l'élément : événements en couches (Events), boucles (Loops), teinte d'un rayon maintenu (BeamTint).
-- Chargé par WandClient.SoundFX : P = banques d'échantillons, ev(minGap, maxVoices, couches) = constructeur.
return function(P, ev)
	return {
		Events = {
			-- ÉTAT « gelé » : la glace se referme d'un coup (craquement grave + éclat), puis dégel en gouttes
			["Status.Freeze"] = ev(0.1, 3, {
				{ Ids = P.Ice, Volume = 0.6, Pitch = { 0.72, 0.85 }, Length = 0.8, Fade = 0.35 },
				{ Ids = P.Ice, Volume = 0.32, Pitch = { 1.4, 1.65 }, Delay = 0.05, Length = 0.4, Fade = 0.2 },
			}),
			["Status.Thaw"] = ev(0.1, 3, {
				{ Ids = P.Ice, Volume = 0.3, Pitch = { 1.2, 1.4 }, Length = 0.5, Fade = 0.25 },
				{ Ids = P.DripPlop, Volume = 0.45, Pitch = { 0.9, 1.1 }, Delay = 0.1 },
			}),
			["Cast.Ice"] = ev(0.04, 4, {
				{ Ids = P.Swish, Volume = 0.32, Pitch = { 1.5, 1.8 } },
				{ Ids = P.Ice, Volume = 0.13, Pitch = { 1.9, 2.3 }, Length = 0.3, Fade = 0.12 },
			}),
			["Impact.Ice"] = ev(0.03, 5, { { Ids = P.Ice, Volume = 0.33, Pitch = { 1.2, 1.6 }, Length = 0.6, Fade = 0.2 } }),
			["Bounce.Ice"] = ev(0.04, 3, { { Ids = P.Ice, Volume = 0.14, Pitch = { 2.2, 2.6 }, Length = 0.2, Fade = 0.08 } }),
			["Explosion.Ice"] = ev(0.05, 4, { -- éclatement de glace : la gangue vole en éclats + souffle glacé
				{ Ids = P.Ice, Volume = 0.6, Pitch = { 0.7, 0.85 } },
				{ Ids = P.Ice, Volume = 0.35, Pitch = { 1.3, 1.6 }, Delay = 0.035 },
				{ Ids = P.Boom, Volume = 0.22, Pitch = { 1.1, 1.3 }, Length = 0.8, Fade = 0.4 },
				{ Ids = P.WhooshBy, Volume = 0.22, Pitch = { 1.5, 1.8 }, Length = 0.7, Fade = 0.4 },
			}),
			["Tail.Ice"] = ev(0.06, 3, { { Ids = P.Ice, Volume = 0.28, Pitch = { 0.8, 1.0 }, Delay = 0.03 } }),
			["Tint.Ice"] = ev(0.03, 4, { { Ids = P.Ice, Volume = 0.1, Pitch = { 2.4, 2.8 }, Length = 0.2, Fade = 0.08 } }),
			["Hit.Ice"] = ev(0.035, 4, {
				{ Ids = P.Ice, Volume = 0.25, Pitch = { 1.8, 2.2 }, Length = 0.25, Fade = 0.1 },
			}),
			["Grow.StartIce"] = ev(0.1, 2, { -- la glace craque et se forme
				{ Ids = P.Ice, Volume = 0.5, Pitch = { 0.7, 0.85 } },
				{ Ids = P.Ice, Volume = 0.28, Pitch = { 1.2, 1.4 }, Delay = 0.08, Length = 0.5, Fade = 0.2 },
			}),
			["Grow.StepIce"] = ev(0.02, 10, {
				-- la glace se FORME : craquement cristallin net + bois qui gèle et craque dans l'aigu
				{ Ids = P.Ice, Volume = 0.42, Pitch = { 1.25, 1.6 }, Length = 0.4, Fade = 0.2 },
				{ Ids = P.TreeCreak, Volume = 1.4, Pitch = { 1.5, 1.85 }, Start = { 0.5, 18.5 }, FadeIn = 0.04, Length = 0.38, Fade = 0.22 },
			}),
			["Patch.FrostSpread"] = ev(0.1, 2, { -- givre qui se pose : crissement léger, discret
				{ Ids = P.Ice, Volume = 0.12, Pitch = { 1.9, 2.2 }, Length = 0.35, Fade = 0.2 },
			}),
			["Patch.FrostMelt"] = ev(0.1, 2, { { Ids = P.Ice, Volume = 0.1, Pitch = { 1.8, 2.1 } } }),
			["Patch.FrostTick"] = ev(0.2, 2, { { Ids = P.Ice, Volume = 0.045, Pitch = { 2.3, 2.7 } } }), -- petits craquements de givre
		},
		Loops = {
			["Loop.Frozen"] = { Ids = { 9117410297 }, Volume = 2.4, Pitch = { 0.78, 0.88 } }, -- la glace crisse en tenant la cible
			["Travel.Ice"] = { Ids = P.WhooshBy, Volume = 0.11, Pitch = { 1.6, 1.8 } }, -- sifflement
			-- GIVRE qui se forme : craquements secs et crissements cristallins (PSE Celery Break, monté dans l'aigu)
			-- — avant : glaçons qui glissent (« glaçons dans un liquide », refusé) ; prise très faible -> volume élevé
			["Loop.BeamFrost"] = { Ids = { 9113734503 }, Volume = 2.6, Pitch = { 1.35, 1.5 } },
			-- crépitement fin du givre (PSE cellophane froissée), seconde couche du rayon de glace
			["Loop.FrostCrackle"] = { Ids = { 9117410297 }, Volume = 5, Pitch = { 1.2, 1.35 } },
			-- zone de givre posée : crépitement fin très bas, à peine audible (avant : Loop.BeamFrost, trop présent)
			["Loop.FrostPatch"] = { Ids = { 9117410297 }, Volume = 1.6, Pitch = { 1.45, 1.6 } },
		},
		BeamTint = { Loops = { "Loop.BeamFrost", "Loop.FrostCrackle" }, Tick = "Impact.Ice", Every = { 0.12, 0.3 } }, -- givre qui craque en continu,
	}
end

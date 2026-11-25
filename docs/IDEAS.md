# Ideas

Out-of-scope ideas and feature requests are logged here instead of being built.

## From the research report, 24 Nov 2026

Full reasoning and sources: `reports/Foundations from successful arena games.md`.

- Recovery window after a strong push: briefly reduce air steering and jetpack thrust so a
  pushed bot cannot cancel the push at once (Smash-style hitstun). New rule, not in the GDD.
  Revisit after the first knockback playtest.
- Corner correction: nudge a bot around a ceiling lip or ledge corner it clips by a few
  pixels (Celeste uses 4 px). A forgiveness helper the GDD does not list.
- Hit freeze that scales with push strength (2 frames up to 6 to 8 at melee and blast
  centres, none on rapid-fire hits). The GDD says two or three frames on a heavy hit.
- A visible catch-up for trailing players beyond the card pick (Ultimate Chicken Horse's
  "Underdog" points). Decide after the phase 2 playtest.
- A cheap tiebreak before sudden death: round wins, then total knockouts.
- A distinct charge ring on the aim stick for charged weapons.

## From task 1.1

- A port setting in the menu.
- A visible reason on the join screen when the match is full.

## From the phase 1 audit (25 Nov 2026)

- Aim assist. The GDD describes it as on by default for new players (Controls), but no
  stage lists it and it is not built. Rahul to say which stage it belongs to.
- A Spring Plate that launches along its angle. The GDD says "straight up or along its
  angle"; plates only rest on upward faces today, so every launch is straight up.
- A setting in the menu to reduce screen shake. The effect supports it; nothing sets it.
- A config entry of its own for the dash's bullet immunity. It follows the dash time
  today, which gives 4 ticks (0.133 s) against the GDD's 0.15 s.


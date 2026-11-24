# Movement, knockback and impact feel in successful 2D action games

Scope: concrete tuning techniques and numbers, compared with the starting values in `docs/GDD.md` ("Core gameplay" and "Game physics and feel"). Research date: 2026-11-24.

Provenance labels used below:
- [SOURCE CODE]: read from a game's published source code.
- [DEV]: stated by the developer.
- [WIKI-DATAMINED]: community wiki formula, derived from game data.
- [FAN/GUIDE]: fan guide or estimate, lower reliability.
- [INFERENCE]: my calculation or reasoning, not stated by any source.

Unit conversions for Celeste use the player's normal hitbox height of 11 px as "1 character height". The Celeste screen is 320x180 px and a tile is 8 px. The GDD measures distance in "bot heights".

Tick note: the GDD simulation runs at 30 Hz, so 1 tick = 33.3 ms. Render runs at 60 fps, so 1 render frame = 16.7 ms. All "frames" in Smash sources are 60 Hz frames.

## Forgiveness mechanics: coyote time, input buffer, corner correction

### Takeaway
Celeste's source code uses a 0.1 s coyote window (`JumpGraceTime = 0.1`) and 4 px corner correction. The GDD's 0.1 s windows match the best-documented reference exactly. At a 30 Hz tick, 0.1 s is exactly 3 ticks, which is fine. I found no developer-stated TowerFall numbers.

### Cited Findings
- [SOURCE CODE] Celeste `Player.cs`: `JumpGraceTime = 0.1` (coyote time, seconds), `DashCornerCorrection = 4`, `UpwardCornerCorrection = 4` (pixels, half a tile, about 0.36 character heights), `WallJumpCheckDist = 3` (px). — [Celeste Player.cs, NoelFB/Celeste on GitHub](https://raw.githubusercontent.com/NoelFB/Celeste/master/Source/Player/Player.cs)
- [SOURCE CODE] In `Player.cs` the jump input is read with `Input.Jump.ConsumeBuffer()`, so jump is buffered. The buffer length is set in `Input.cs`, which I could not retrieve (HTTP 404 at the path I tried). — [Celeste Player.cs](https://raw.githubusercontent.com/NoelFB/Celeste/master/Source/Player/Player.cs)
- [DEV] Maddy Thorson's article lists 10 forgiveness and feel mechanics: coyote time, jump buffering, a halved-gravity jump peak, jump corner correction, dash corner correction, semi-solid popping, lift momentum storage ("a few frames"), a wide wall-jump window, an even wider super wall-jump window, and stamina refunds. The article gives coyote and buffer only as "a short time", with no numbers. — [Celeste & Forgiveness, maddymakesgames.com](https://maddymakesgames.com/articles/celeste_and_forgiveness/index.html)
- [DEV] Wall-jump window: "2 pixels" from the wall, which the article calls a quarter of a tile at 320x180. The super wall-jump window is "5 pixels" ("I think it's"), more than half a tile. — [Celeste & Forgiveness](https://maddymakesgames.com/articles/celeste_and_forgiveness/index.html)
- Discrepancy: the article says 2 px, and the source code constant `WallJumpCheckDist` is 3 px. The difference may come from how the check is measured (hitbox edge vs. offset). — [Article](https://maddymakesgames.com/articles/celeste_and_forgiveness/index.html) vs. [Player.cs](https://raw.githubusercontent.com/NoelFB/Celeste/master/Source/Player/Player.cs)
- [DEV] The examples were first a Twitter thread on 13 March 2020. Thorson said "I don't think we invented any of these." — [GameSpot](https://www.gamespot.com/articles/celeste-dev-explains-how-they-made-their-game-feel/1100-6474775/); [Blizzard Watch](https://blizzardwatch.com/2020/03/13/celeste-developer-game-feel/)
- [FAN/GUIDE] One design blog claims a "5-frame" coyote window for Celeste. That does not match the source value of 0.1 s (6 frames at 60 fps), so treat the blog as unreliable. — [daytenrose substack, "21 coyote time"](https://daytenrose.substack.com/p/21-coyote-time)

### Inferences
- [INFERENCE] The GDD's 0.1 s coyote window and 0.1 s jetpack/dash buffer are well supported. Keep them as starting values.
- [INFERENCE] At 30 Hz, 0.1 s is exactly 3 ticks, so it quantizes cleanly. Write the config value as a tick count (3) or as seconds that the code rounds to ticks, so the window is not 2 ticks on one machine and 3 on another.
- [INFERENCE] Touch input on budget Android phones adds latency between finger and game, and the GDD's 30 Hz tick quantizes input to 33 ms. Both make an early press more likely than with a gamepad. If playtests show missed dashes, a buffer of 4 ticks (0.133 s) is a reasonable first adjustment. This is a proposal, not a sourced value.
- [INFERENCE] The GDD applies coyote time to wall-jump ("a bot that has just left a ledge can still wall-jump for 0.1 seconds"). Celeste applies coyote to the ground jump. The wording "left a ledge ... wall-jump" is ambiguous: it may mean "just left a wall". Ask Rahul which is intended. A grace window after leaving a wall (Celeste's equivalent is the 2 to 5 px distance window, not a timer) is the more common pattern.
- [INFERENCE] Corner correction is not in the GDD. Celeste uses 4 px (about 0.36 character heights) for upward and dash corner correction. For a jetpack game where bots climb into ceiling lips, this is the forgiveness most likely to matter after coyote and buffer. Log it in `docs/IDEAS.md` if it is not part of phase 1.

### Gaps
- Celeste's input buffer length: not verified. `Input.cs` was not retrievable at the path I tried. Do not quote a number until someone reads the file.
- TowerFall coyote, buffer and corner-correction values: I found no developer statement or source code. TowerFall's source is not public.
- No source found on how touch input latency on Android changes the ideal buffer length.

## Jump and fall shaping: gravity, variable height, terminal velocity, air control, acceleration

### Takeaway
Celeste's run : rise : fall-cap ratio is 90 : 105 : 160 px/s, which is 1 : 1.17 : 1.78. The GDD's 6 : 7 : 12 is 1 : 1.17 : 2.0, so the ratios are almost the same. In absolute terms the GDD is about 27% slower than Celeste in run speed (6 vs 8.2 heights/s), which is reasonable for an arena shooter where aiming happens during movement. Celeste reaches full run speed in about 0.09 s, and that very fast acceleration is a main reason it does not feel slippery.

### Cited Findings
- [SOURCE CODE] Celeste constants: `MaxRun = 90`, `RunAccel = 1000`, `RunReduce = 400`, `AirMult = 0.65`, `Gravity = 900`, `MaxFall = 160`, `FastMaxFall = 240`, `HalfGravThreshold = 40`, `JumpSpeed = -105`, `JumpHBoost = 40`, `VarJumpTime = 0.2`. Units are px and px/s. Hitbox `new Hitbox(8, 11, -4, -11)`, so the player is 11 px tall. — [Celeste Player.cs](https://raw.githubusercontent.com/NoelFB/Celeste/master/Source/Player/Player.cs)
- [DEV] Holding jump halves gravity at the top of the jump, which gives more time to adjust the landing. — [Celeste & Forgiveness](https://maddymakesgames.com/articles/celeste_and_forgiveness/index.html)

Conversions of Celeste values to character heights (11 px) [INFERENCE from source values]:

| Celeste value | px/s | heights/s | GDD value |
|---|---|---|---|
| Max run | 90 | 8.2 | Run 6 |
| Jump launch speed | 105 | 9.5 | Jetpack climb 7 |
| Normal fall cap | 160 | 14.5 | Fall cap 12 |
| Fast-fall cap (holding down) | 240 | 21.8 | none |
| Gravity | 900 px/s² | 82 h/s² | not given |
| Time to reach max run from rest | 90/1000 = 0.09 s | | not given |
| Time to stop from max run on ground | 90/400 = 0.225 s | | not given |
| Air acceleration | 0.65 x ground | | "full steering" |

### Inferences
- [INFERENCE] The GDD's ratios are well aligned with Celeste. The fall cap is relatively a little higher (2.0 x run vs 1.78 x), and fall-to-rise is 1.71 vs 1.52. Faster falling than rising is the standard way to avoid floatiness, and the GDD rule "falling is faster than rising" matches it. No change proposed.
- [INFERENCE] The GDD does not set gravity, ground acceleration, deceleration or air acceleration. Those values decide floaty vs. tight more than top speeds do. Proposal for first values, scaled from Celeste to the GDD's run speed of 6: ground acceleration that reaches full run in about 0.1 s (60 heights/s², 3 ticks); ground deceleration to stop in about 0.2 s; air acceleration about 0.65 x ground. Put all of them in the tuning config resource.
- [INFERENCE] Celeste's gravity of 82 heights/s² with a fall cap of 14.5 reaches terminal speed in about 0.18 s. If the GDD uses a similar time to terminal (0.15 to 0.2 s), gravity is about 60 to 80 heights/s² for a fall cap of 12. Treat this as a starting range, not a sourced number.
- [INFERENCE] "Full left and right steering in the air" (GDD) plus "momentum carries" can conflict. Full air steering at ground acceleration lets a player cancel dash momentum and knockback almost instantly. Celeste reduces air acceleration to 0.65 x and also uses `WallJumpForceTime` and an end-of-dash speed to protect momentum. Proposal: air acceleration below ground acceleration, and reduced steering during knockback (see the knockback section).
- [INFERENCE] The jetpack replaces the jump, so variable jump height comes from the 0.15 s thrust ramp. Celeste's variable jump window is 0.2 s (`VarJumpTime`). The two are in the same range. At 30 Hz, 0.15 s is 4.5 ticks, which does not quantize cleanly. Use 0.133 s (4 ticks) or 0.167 s (5 ticks).
- [INFERENCE] Absolute speeds in heights/s only translate between games if the camera shows a similar number of character heights per screen. Celeste shows 180/11, about 16 character heights vertically. If the GDD arena camera shows many more bot heights (likely with 8 players on a phone), the same heights/s will look slower on screen. Check the bot-heights-per-screen value before tuning speeds.

### Gaps
- TowerFall, Hollow Knight and Dead Cells gravity, run and fall values: no developer-stated or source numbers found.
- No developer source found for Math for Game Programmers jump talks within the tool budget.

## Jetpack and fuel design: Mini Militia, Soldat and similar

### Takeaway
I found no reliable source with numbers for Mini Militia or Soldat jetpack thrust, fuel duration or refill rules. The GDD's 2.5 s of thrust with a 2 s ground refill cannot be compared with evidence from this research.

### Cited Findings
- The official Mini Militia store listing mentions dual-stick shooting with jetpack flight, but does not describe fuel or refill. — [App Store, Mini Militia - Doodle Army 2](https://apple.co/2GY2SMd)
- The Soldat community wiki says weapon settings are in `weapons.ini`. The page does not mention jet fuel. — [Soldat Wiki, Weapon Mod](https://wiki.soldat.pl/index.php/Weapon_Mod)

### Inferences
- [INFERENCE] Celeste has no jetpack, but its dash refills only on landing, and the GDD jetpack also refills on the ground. Both designs reward touching the ground, which makes the floor part of the rhythm.

### Gaps
- Mini Militia fuel duration, refill rate and refill rule: not found. Measure by recording gameplay video, and label the result as a fan measurement.
- Soldat jet values: Soldat's source code was open-sourced, and its map and game settings include a jet fuel value per map. I did not verify this within the budget, so no number is given.
- No player-review evidence found on what players praise or complain about in jetpack fuel.

## Dash design: distance, duration, cooldown, invulnerability, momentum

### Takeaway
The GDD dash of 3 bot heights in 0.15 s is almost identical to Celeste's dash (240 px/s for 0.15 s = 36 px = 3.3 heights). The 3 s cooldown is much longer than the references found: Celeste 0.2 s with a ground refill, and Hollow Knight's Shade Cloak 1.5 s (wiki). Full-dash bullet immunity (0.15 s) matches Hollow Knight's Shade Cloak, which is invulnerable for the whole dash.

### Cited Findings
- [SOURCE CODE] Celeste: `DashSpeed = 240`, `EndDashSpeed = 160`, `EndDashUpMult = 0.75`, `DashTime = 0.15`, `DashCooldown = 0.2`, `DashRefillCooldown = 0.1`, `DashAttackTime = 0.3`. — [Celeste Player.cs](https://raw.githubusercontent.com/NoelFB/Celeste/master/Source/Player/Player.cs)
- [WIKI] Hollow Knight Shade Cloak: its own cooldown of 1.5 s, separate from the normal dash. The player can dash through enemies and their attacks, but environmental hazards still deal damage. A dash during the cooldown is a normal dash without the phase-through. Dashmaster does not shorten the Shade Cloak cooldown. — [Hollow Knight Wiki, Shade Cloak](https://hollowknight.wiki/w/Shade_Cloak)
- Conflict: Fextralife gives a 2 s cooldown — [Fextralife](https://hollowknight.wiki.fextralife.com/Shade+Cloak). A guide gives 0.6 s and conflicting i-frame counts (4 vs 8 frames) — [RogueRanker](https://rogueranker.com/shade-cloak-hollow-knight/). Treat both as lower reliability than the Hollow Knight Wiki.

Conversions [INFERENCE]:

| | Distance | Duration | Peak speed | Exit speed | Cooldown | I-frames |
|---|---|---|---|---|---|---|
| Celeste | 36 px = 3.3 heights | 0.15 s | 21.8 h/s | 14.5 h/s (EndDashSpeed) | 0.2 s, refills on landing | none found in source read |
| Hollow Knight Shade Cloak | not found | not found | not found | not found | 1.5 s (wiki) | whole dash, not hazards |
| GDD | 3 heights | 0.15 s | 20 h/s | "normal momentum resumes" | 3 s, 1 charge | 0.15 s, bullets only |

### Inferences
- [INFERENCE] Distance and duration are well supported. Keep 3 heights and the duration, but use a tick-aligned duration: 0.133 s (4 ticks, 22.5 h/s) or 0.167 s (5 ticks, 18 h/s).
- [INFERENCE] "Then normal momentum resumes" is undefined. Celeste sets exit speed to 160/240 = 0.67 of dash speed, and 0.75 of that for upward dashes. Without a defined exit speed, a dash at 20 h/s that drops to the run cap of 6 h/s will feel like a sudden stop, and the GDD's "dash into a jetpack burn flings the bot further" will not happen. Proposal: an exit speed of about 2/3 of dash speed that then decays under normal air drag. Source: Celeste `EndDashSpeed`.
- [INFERENCE] Proposal to discuss, not a change: the 3 s cooldown is 2 x Hollow Knight's Shade Cloak and 15 x Celeste's. In a 45 s round, 3 s allows about 15 dashes per round, and the i-frames make each dash a defensive tool. A long cooldown may be right for a shooter, but there is no reference supporting exactly 3 s. Test 1.5 s and 3 s. The Hollow Knight Wiki value is the closest reference for an invulnerable dash.
- [INFERENCE] Hollow Knight's invulnerable dash still takes hazard damage. The GDD gives bullet immunity only, which is consistent: knockback from blasts and hazards still applies. State in the config whether blast push applies during the dash.
- [INFERENCE] Bullet immunity at 30 Hz is 4 or 5 ticks. With lag compensation, the server must decide immunity at the tick the hit is resolved, not when the client saw it.

### Gaps
- Dead Cells and Brawlhalla dodge numbers (distance, i-frames, cooldown): not found in this research.
- Hollow Knight dash distance and duration: not found.
- Whether Celeste's dash has any invulnerability: not seen in the part of the source read.

## Knockback that grows as health drops: Smash, Brawlhalla, Rivals of Aether

### Takeaway
In Smash, knockback grows linearly with the target's damage percent, with no cap. A weak move can launch about 5 times further at 150% than at 10% (my calculation from the SmashWiki formula). Hitlag in Smash is 6 to 15 frames for a 10 to 15 damage hit and is capped at 20 to 30 frames, far more than the GDD's 2 to 3 frames. Smash also adds hitstun (0.4 frames per knockback unit) and directional influence (about 18 degrees in Melee, about 9.74 degrees in Smash 4 and Ultimate). The GDD has neither hitstun nor DI.

### Cited Findings
- [WIKI-DATAMINED] Melee-onward knockback: (((((p/10 + p·d/20) · 200/(w+100) · 1.4) + 18) · s) + b) · r. p = target percent after damage, d = damage, w = weight, s = scaling/100, b = base knockback, r = ratios (launch rate 0.5x to 2.0x, rage, and others). The page renders the fractions without notation, so the exact form is my reading. Knockback rises with percent for most attacks; set-knockback moves do not scale. — [SmashWiki, Knockback](https://www.ssbwiki.com/Knockback)
- [WIKI-DATAMINED] Launch speed = knockback x 0.03, and it decays by 0.051 per frame. — [SmashWiki, Knockback](https://www.ssbwiki.com/Knockback)
- [WIKI-DATAMINED] Hitstun = knockback x 0.4 frames; 100 knockback gives 40 frames of hitstun. — [SmashWiki, Hitstun](https://ssbwiki.com/Hitstun). Smash 4: floor(KB x 0.4) - 1 — [Kuroganehammer, Smash 4 formulas](https://kuroganehammer.com/Smash4/Formulas). In Ultimate, hitstun above 32 frames speeds up the launch, and hitstun scales much more slowly at higher knockback. — [SmashWiki, Knockback](https://www.ssbwiki.com/Knockback)
- [WIKI-DATAMINED] Hitlag: Melee floor(d/3 + 3); Brawl and Smash 4 floor((d x 0.3846 + 5) x h x e); Ultimate floor((d x 0.65 + 6) x h x e x s). Cap 20 frames in Melee, 30 from Brawl on. A 15% move gives 8 frames in Melee, 10 in Brawl and Smash 4, 15 in Ultimate. Electric attacks multiply hitlag by 1.5. Attacks with no knockback cause no hitlag. — [SmashWiki, Hitlag](https://ssbwiki.com/Hitlag)
- [WIKI-DATAMINED] DI: maximum about 18 degrees in Melee (Brawl the same); Smash 4 halved it to 0.17 rad, about 9.74 degrees, and Ultimate reuses that. Maximum deviation comes from holding perpendicular to the launch angle. DI does not apply to knockback that does not cause tumbling. DI and momentum cancelling are less effective on moves with strong knockback scaling. — [SmashWiki, Directional influence](https://www.ssbwiki.com/Directional_influence); [SmashWiki, Knockback](https://www.ssbwiki.com/Knockback)
- [WIKI] Brawlhalla: higher Strength means more knockback and damage from the same attack; damage also depends on the defender's Defense vs. the attacker's Strength. No formula found. — [Brawlhalla Wiki, Stats](https://brawlhalla.wiki.gg/wiki/Stats)

Worked example [INFERENCE from the SmashWiki formula]: a 10-damage move, s = 1.0, b = 0, w = 100, r = 1. At p = 10: (1 + 5) x 1.4 + 18 = 26.4. At p = 150: (15 + 75) x 1.4 + 18 = 144. Ratio about 5.5 x. Hitlag for that hit: Melee 6 frames, Brawl 8, Ultimate 12 (60 Hz frames, 100 to 200 ms).

### Inferences
- [INFERENCE] "Up to double below 25 health" is ambiguous. It can mean a step (1 x above 25 health, 2 x below), or a ramp that reaches 2 x somewhere below 25. Smash uses a continuous linear increase. A step at 25 makes a single hit suddenly push twice as far, and with the +20 repair on a knockout, a bot can jump back over the threshold. Proposal: a continuous ramp, for example from 1.0 x at full health to 2.0 x at 0 health, or from 1.0 x at 50 health to 2.0 x at 0. Ask Rahul which reading the GDD means.
- [INFERENCE] A 2 x maximum is mild compared with Smash (about 5 x across a normal stock). That is reasonable because in the GDD health also kills, while in Smash only launches kill. No change proposed. Playtest whether ring-outs happen often enough.
- [INFERENCE] The GDD has no hitstun. With full air steering and a jetpack that can fire at once, a pushed bot can cancel most knockback, which weakens "everything pushes". Smash solves this with hitstun (0.4 frames per knockback unit) plus limited DI. Proposal, for Rahul to decide because it adds a rule: a short window after a strong push (melee, scrap blast, blast) in which air steering and jetpack thrust are reduced, scaled to push strength, with some steering left (like DI). Log it in `docs/IDEAS.md` if it is outside phase 1.
- [INFERENCE] GDD 2 to 3 freeze frames = 33 to 50 ms at 60 fps = 1 to 1.5 ticks at 30 Hz. That is less than Melee's minimum hitlag for any damaging hit (floor(d/3 + 3) is at least 3 frames, and about 6 frames for 10 damage). Proposal: scale freeze with push strength, for example 2 frames for a light heavy hit up to about 6 to 8 frames (100 to 133 ms) for melee and blast centres, with a cap. Do not freeze on bolt-thrower and nail-gun hits; Smash gives no hitlag to hits without knockback, and constant freezes from rapid fire would make the game stutter.
- [INFERENCE] In Smash, hitlag freezes only attacker and victim. In an 8-player networked game, a simulation freeze of two bots is hard to predict and reconcile. A safer approach: make the freeze render-only on each phone (pause the victim's and attacker's sprites and the camera for N render frames while the simulation continues), or freeze the whole local view briefly. This needs a netcode check.

### Gaps
- Brawlhalla knockback formula, hitstun and hitpause: not found.
- Rivals of Aether developer notes on knockback scaling: not found within the budget.
- SDI distance in Smash: not on the Hitlag page and not fetched.

## Juice: screenshake, hit pause, and readability on a small phone screen

### Takeaway
The documented core of Vlambeer's talk is many small additions to a dull shooter: screen shake opposite to gunfire, hit pause, recoil, muzzle flash, bigger and faster bullets, knockback, and random enemy explosions. I found no source with specific shake or hit-pause numbers, and no source on motion sickness or phone readability.

### Cited Findings
- [DEV, reported] Jan Willem Nijman's "The Art of Screenshake" (Control Conference, Amsterdam, 2013) turns a dull side-scrolling shooter into a better one with 30 minor tweaks. Examples include a slight screen shake opposite to the direction of the player's gunfire, and a 33% chance that enemies explode harmlessly on death. Article dated 2 January 2014. No frame counts for hit pause or shake amounts are given. — [Game Developer, "Vlambeer co-founder shares advice on building better action games"](https://gamedeveloper.com/design/vlambeer-co-founder-shares-advice-on-building-better-action-games)
- [FAN/GUIDE] A fan recreation of the talk lists effects including lower time to kill, higher rate of fire, larger bullets, muzzle flash, faster bullets, lower accuracy, camera lerp, screen shake, player knockback, hit pause, weapon recoil and random enemy explosions. This is a recreation, not Nijman's own list. — [DK Liao, The Art of Screenshake Recreation devlog](https://dkliao.itch.io/the-art-of-screenshake-recreation/devlog/451576/quick-breakdown-of-all-the-effects)

### Inferences
- [INFERENCE] The GDD already covers hit pause, screen shake with a reduce setting, a hit flash, sound and slow motion on the final knockout. The Vlambeer items not in the GDD are directional shake (shake opposite to the shot, not random), recoil on the shooter, and muzzle flash. These are presentation, not new features, so they fit inside "impact feel".
- [INFERENCE] On a small screen with 8 players, every hit by anyone shaking the camera would make the game hard to read. Proposal: full shake only for events involving the local player (their own hits, hits on them, nearby blasts), with distance falloff for other blasts. No source; this is reasoning.

### Gaps
- "Juice it or lose it" (Jonasson and Purho): not retrieved; no techniques or numbers cited.
- Steve Swink, "Game Feel": not retrieved.
- Nuclear Throne specifics: not retrieved.
- No source found on motion-sickness or readability complaints about screen shake on phones.

## Wall-slide and wall-jump tuning

### Takeaway
Celeste's source gives a complete wall set: a wall-jump horizontal speed of 130 px/s (11.8 heights/s) with the normal jump speed of 105 px/s, so the launch is about 39 degrees above horizontal; a forced-direction lockout of 0.16 s; a slow start to the wall slide (20 px/s, 1.8 heights/s); and a 2 to 3 px distance window. The GDD has no wall values yet.

### Cited Findings
- [SOURCE CODE] Celeste: `WallJumpForceTime = 0.16` (s), `WallJumpHSpeed = MaxRun + JumpHBoost = 130` (px/s), `WallSpeedRetentionTime = 0.06` (s), `WallSlideStartMax = 20` (px/s), `WallSlideTime = 1.2` (s), `WallJumpCheckDist = 3` (px). Jump speed is 105 px/s. — [Celeste Player.cs](https://raw.githubusercontent.com/NoelFB/Celeste/master/Source/Player/Player.cs)
- [DEV] Wall-jump window 2 px, super wall-jump window about 5 px. — [Celeste & Forgiveness](https://maddymakesgames.com/articles/celeste_and_forgiveness/index.html)

### Inferences
- [INFERENCE] Launch angle atan(105/130) is about 39 degrees above horizontal. Horizontal speed is 1.44 x max run.
- [INFERENCE] Proposed first values, scaled from Celeste to the GDD's run speed of 6 (factor 6/8.2 = 0.73): wall-jump horizontal speed about 8.6 heights/s, vertical about 7 heights/s (equal to jetpack climb), input lockout 0.167 s (5 ticks), slide speed cap starting near 1.3 to 2 heights/s, and a wall-contact grace window of about 0.2 to 0.3 bot heights. All are in the config resource.
- [INFERENCE] With touch, "push away from the wall" on the left stick is the wall-jump input. The 0.16 s forced direction stops the stick from instantly steering back into the wall, which is important when the stick is a thumb on glass.

### Gaps
- Wall values in other well-regarded games (Mega Man X, Hollow Knight, TowerFall): not found.
- The meaning of Celeste's `WallSlideTime = 1.2` (time before full slide speed vs. maximum slide time) was not confirmed from the code read.

## Known feel failures: floaty, slippery or unfair movement

### Takeaway
I found no developer postmortem or critical review that names causes of floaty or slippery movement in platform shooters within the budget. The closest evidence is the Celeste code: very fast ground acceleration (0.09 s to full speed), fall faster than rise, reduced air acceleration, and many small forgiveness windows.

### Cited Findings
- [DEV] Thorson presents the forgiveness mechanics as invisible help that makes the game feel fair, and says they were not invented for Celeste. — [Celeste & Forgiveness](https://maddymakesgames.com/articles/celeste_and_forgiveness/index.html); [GameSpot](https://www.gamespot.com/articles/celeste-dev-explains-how-they-made-their-game-feel/1100-6474775/)
- [SOURCE CODE] Acceleration 1000 px/s² vs. max run 90 px/s, and fall cap above rise speed. — [Celeste Player.cs](https://raw.githubusercontent.com/NoelFB/Celeste/master/Source/Player/Player.cs)

### Inferences
- [INFERENCE] The likely floaty risks in the GDD are: a fall cap reached too slowly (low gravity), and jetpack thrust that ramps slowly enough that taps feel unresponsive. The ramp is 0.15 s, about 4 to 5 ticks, near Celeste's 0.2 s variable jump window, so it should be acceptable.
- [INFERENCE] The likely slippery risk is low ground deceleration. Celeste stops from full run in about 0.225 s. Only the oil and Ice Rink surfaces should be slippery.
- [INFERENCE] The likely unfair risk in a networked shooter is a push the victim cannot see coming. Hit flash, hit pause and directional shake on the victim's screen help explain each push.

### Gaps
- No postmortems from Game Developer or reviews of Mini Militia, Soldat or other platform shooters about floatiness were found within the research budget.

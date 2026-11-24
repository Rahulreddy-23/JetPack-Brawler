# Bots and bosses: believable fair AI for a 2D jetpack arena shooter, and well-designed boss fights

Scope: (1) bots filling empty slots, bound by the same rules as players; (2) one-on-one boss fights with one signature trick and 2-3 phases, first boss Dabba (tiffin-tin stack that splits into three smaller tins).
Research date: 24 Nov 2026. Evidence quality is flagged per item. Where I could not open a primary source I say so in Gaps. Items marked "Inference" are my reasoning, not sourced facts.

GDD context read first (docs/GDD.md):
- Solo campaign: 10 one-on-one fights, 2-3 minutes each, health bar with 2-3 phases, 3 rebuilds per fight, up to 3 bolts (win, beat par time, no rebuilds). Dabba: "Splits into three small tins when damaged", teaches "Moving and aiming". Beaten champions "join the bot pool in multiplayer with the same behaviour". All ten share "one bot brain for moving, aiming and dodging; each adds a single trick".
- Bots paragraph (Playing with friends): four levels Easy to Very Hard; Easy "react slowly, miss often and walk into traps"; Medium "aim steadily and use the jetpack well"; Hard "dash out of fire, lead moving targets and lay traps"; Very Hard "react at the speed of a top human player, knock bombs back, punish every mistake and should beat most players"; at every level "same health, no seeing through walls and no reactions faster than a human".
- CLAUDE.md adds: bots run on the host, difficulty changes only reaction time, aim error and which skills are used.

---

## 1. Human limits to respect: reaction time, aim acquisition, tracking error, and what shipped bots use per difficulty

### Takeaway
Measured simple visual reaction time is roughly 190-270 ms depending on the measurement (lab mean vs a web test that includes display and input lag), and published bot-AI guidance puts "fair" AI reaction delay in the low hundreds of ms (0.2-0.4 s per one search-snippet of Rabin's Game AI Pro chapter, not read in full). Shipped bots vary difficulty mainly with reaction time and aim accuracy numbers (Quake III stores both as per-skill characteristics), which is exactly the lever set our design allows. I found no solid published data for aim-tracking error by skill tier, so aim-error ranges below are tuning starting points, not sourced numbers.

### Cited Findings
Measured human data
- Simple visual reaction time, college-age mean about 190 ms; auditory about 160 ms; typical simple RT "on the order of 200 ms"; researchers treat 100-200 ms as the lower limit of a valid trial. Choice RT grows with number of options (Hick's law, RT = a + b*log2(n+1), constants not given). — [Wikipedia: Mental chronometry](https://en.wikipedia.org/wiki/Mental_chronometry) (cites Kosinski 2008 literature review, Clemson; secondary summary of a lab review)
- Human Benchmark's click-when-green test: median 273 ms, mean 284 ms, with the caveat that input and monitor lag are included. — [Insider Gaming summary](https://insider-gaming.com/what-is-reaction-time-and-does-it-make-you-better-at-cs2-or-valorant/); Blur Busters gives "around 270 ms ... includes input lag" — [Blur Busters](https://www.blurbusters.com/human-reflex-part1-input-lag-and-the-limits-of-human-reaction-time) (via search snippet; page returned 403 to my fetch). I could not open humanbenchmark.com directly, so the 273 ms figure is second-hand. A "120 ms median" figure on Gitnux has no verifiable primary source; ignore it. — [Gitnux](https://gitnux.org/reaction-time-statistics/)
- A PMC review notes post-2000 reported ranges of 150-400 ms. — [PMC4374455](https://pmc.ncbi.nlm.nih.gov/articles/PMC4374455) (via search snippet only)
- Olympic sprinters' false-start-gated reactions: mean 166 ms (men) and 169 ms (women) at Beijing, with best 1-in-1000 starts at 109-121 ms; an IAAF-commissioned 2009 study suggests top sprinters can sometimes react in 80-85 ms. These are auditory and elite-athlete, so they bound the physiological floor, not what a gamer does. — [Wikipedia: Mental chronometry](https://en.wikipedia.org/wiki/Mental_chronometry)
- Do esports players react faster? Evidence is weak and mixed. A Wisconsin-La Crosse study (10 gamers vs 10 non-gamers) found experienced gamers about 30 ms faster on simple tasks; a Vienna Test System study of 18 professional and 21 non-professional esports players found no group differences in simple visual, acoustic or choice reaction; a Turkish 60-person study found no visual/auditory reaction difference but faster aim accuracy in esports players. — [UW-La Crosse](https://www.uwlax.edu/news/posts/an-esports-edge/); [study listing incl. Vienna/Turkish results via search](https://digitalcommons.wku.edu/ijesab/vol14/iss5/45); [Research Square preprint](https://assets-eu.researchsquare.com/files/rs-4528756/v1_covered_6747e2bf-03e1-466f-b2fa-0a3167b3aaf5.pdf). All small samples; two are not peer-reviewed. I only saw search-snippet summaries.
- KovaaK's reliability pilot (Frontiers 2024) found it reliable for measuring shooting proficiency but cautions that scores may not transfer to real competitive skill; NVIDIA's analysis of 15,000+ KovaaK's players found the most skilled players' median score rose more than 2x at 25 ms vs 85 ms system latency. Neither gives tracking-error benchmarks by tier. — [Frontiers 2024](https://www.frontiersin.org/journals/sports-and-active-living/articles/10.3389/fspor.2024.1309991/pdf); [NVIDIA](https://developer.nvidia.com/blog/improving-player-performance-with-low-latency-as-evident-from-fps-aim-trainer-experiments/) (snippets only)

Reaction guidance for AI
- Steve Rabin's Game AI Pro chapter "Agent Reaction Time" frames the question as how fast AI should react and, per a search snippet, puts the answer somewhere between 0.2 and 0.4 s, possibly longer by context; it covers simple RT, recognition (go/no-go) and complex-task RT. I could not open the full chapter (O'Reilly returned 403, gameaipro.com PDF 404). — [O'Reilly listing, Game AI Pro ch. 5](https://www.oreilly.com/library/view/game-ai-pro/9781482254792/K23980_C005.xhtml)
- Laird and Duchi (AAAI 2001), Soar Quakebot, pilot study (1 expert opponent, 5 human players, 8 blind judges, 11 bot variants): decision time at 0.50 s gave skill ratio 0.0 vs the expert; 0.25 s gave 0.23; 0.10 s gave 0.625; 0.05 s gave 0.71; as-fast-as-possible (~0.025 s) gave 0.93. Humanness rating (1-10) was highest at 0.10 s (6.3), then 0.05 s (5.6), AFAP 5.0, 0.50 s 4.3, 0.25 s 2.6. The 0.10 s bot was unanimously judged human on the binary question by judges other than the most experienced one. At 0.50 and 0.25 s the bots visibly crashed into walls. The authors say human behavior in interactive tasks is best modeled with a primitive decision step of 50-100 ms and chose 100 ms as the better estimate because perception and motor delay were not modeled. — [Laird and Duchi 2001 (PDF)](https://www.qrg.northwestern.edu/Resources/aigames.org/2001/Laird.pdf)
- Same study, aiming: three levels (poor, "good" = shoot at the enemy's current position, "best" = superhuman, leads the target using exact depth and velocity). Skill ratio 0.0 / 0.56 / 0.93. Humanness ratings 6.7 / 6.7 / 5.0: judges penalized the superhuman aimer and did not penalize "shoot where the enemy is now". Skill by human experience vs the expert: novices 0.036, medium 0.25, high 0.37. Tactic complexity had no measurable skill effect in this pilot. Conclusion: decision time and aiming skill are the two critical parameters, and can be varied for skill while keeping humanness in some ranges. — [Laird and Duchi 2001](https://www.qrg.northwestern.edu/Resources/aigames.org/2001/Laird.pdf)
- Khoo et al. (AAAI 2002), citing Laird and Duchi: aiming skill "does not require human-like cognition to control"; since NPCs usually have perfect information, varying aim simply means adding noise to the relevant sensor. Decision time needs the control program to be efficient so no slowdown is perceived. — [Khoo et al., Efficient, Realistic NPC Control Systems](https://www.qrg.northwestern.edu/Resources/aigames.org/papers2002/SSS202AKhoo.pdf)

Shipped per-difficulty parameters
- Quake III Arena: each bot defines characteristics for skills 1, 4 and 5 ("I Can Win", "Hardcore", "NIGHTMARE!"); skills 2 and 3 ("Bring it on", "Hurt me plenty") are interpolated between 1 and 4; unset values fall back to default_c.c. Characteristic indices include reaction time ("in seconds", float 0-5), aim accuracy (float 0-1, plus per-weapon accuracy) and view max change (float 1-360). Weapon/item preferences and chats can also vary by skill. — [Q3 bot manual, skill levels](https://icculus.org/gtkradiant/documentation/bot_manual/characteristics.html); [ioquake3 chars.h](https://sources.debian.org/src/ioquake3/1.36%2Bsvn2287-1/code/game/chars.h) (the latter via search snippet; I did not read the exact per-skill values)
- van Waveren on the bot he disliked before writing his own: "At the hardest level, the bot just couldn't lose ... the moment it showed itself, it scored a kill. At lower levels, the bot had a less accurate aim, but then it also did less intelligent things." — [TU Delft Outlook article, "Soldiers for the virtual battlefield" (2001)](https://repository.tudelft.nl/file/File_f7fa0a9a-1cb3-441b-bd12-f1d6426be5b1). This is a magazine interview with the thesis author, not the thesis.
- Community claims of a "Nightmare bot reaction 0.5 s" are anecdotal and unsourced. — [Steam forum](https://steamcommunity.com/app/2200/discussions/0/3393916911752586130/?ctp=3). Do not use.
- Counter-Strike (Booth): the GDC description says the official bot was well received "because it plays in a believable, human-like way" and lists "modeling human limitations such as reaction times and attention prioritization" as core; the session text names no numbers and the full talk is members-only. — [GDC Vault, The Making of the Official Counter-Strike Bot](https://gdcvault.com/play/1013625/The-Making-of-the-Official)
- Left 4 Dead (Booth, slides): survivor bots have a Believability/Fairness goal with "Imperfect knowledge - simulated senses; Simulated aiming; Reaction times; Reliable and predictable decision making". No numbers on the slides. — [Booth, The AI Systems of Left 4 Dead (PDF)](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)

### Inferences
- Working numbers for our bots (my proposal, to be tuned on devices): effective total latency from "enemy becomes visible" to "bot input changes" of about 200-250 ms for Very Hard (human simple RT plus a modeled motor delay, since a phone-and-thumb player cannot beat the roughly 190 ms lab mean), 300-400 ms for Hard/Medium, 450-700 ms for Easy. These sit inside the 0.2-0.4 s guidance and above the lab floor. A mobile touch player's real latency is higher than desktop mouse, so even Very Hard at about 220 ms is "top human".
- Reaction time should be sampled per event (acquire target, enemy changes direction, incoming projectile seen) with a small random spread (e.g. +/-20-30 percent), not a constant, so reactions do not look metronomic. This is design reasoning; I have no source on the best distribution.
- Aim error should be modeled as angular noise on the aim point plus a lag/smoothing constant on turn rate (the Q3 "view max change" analogue), scaled by difficulty. Starting guesses: Easy about 8-12 degrees (misses most shots at mid range), Medium 4-6, Hard 2-3 with target leading, Very Hard 1-1.5 with leading. These are untested guesses, not sourced.
- Laird's finding that "shoot at the current position" is judged as human while perfect target leading is judged as inhuman supports the GDD's split (Hard bots "lead moving targets") but suggests leading should itself carry error and be gated by a speed estimate that has delay, not exact velocity.
- Do not let difficulty change anything except reaction delay, aim noise and skill set. The Q3 design (separate per-skill characteristics for reaction, accuracy, view speed, item/weapon prefs) maps directly onto a Godot Resource per difficulty with the same fields.

### Gaps
- No peer-reviewed or aggregate dataset found for aim-tracking error (degrees or pixels) by skill tier; Aim Lab and KovaaK's percentile data is not published in a citable form I could reach.
- Could not read van Waveren's thesis text itself (the only TU Delft file retrievable was a magazine article), Rabin's full chapter, Booth's CS talk, or the exact per-skill values in Quake III's bot character files.
- Mobile-touch-specific reaction and aim data (thumbs on glass) not found.

---

## 2. Shipped bot designs: architecture, perception, aim models

### Takeaway
Shipped arena bots use cheap layered architectures: Quake III used four layers (areas/movement base, fuzzy-logic short-term goals, state-dependent long-term goals, plus team layer); Counter-Strike and Left 4 Dead used hierarchical state machines with a dedicated vision component and memory of recognised entities; F.E.A.R. used a 3-state FSM plus planner; Blaston (VR) used per-body-part FSMs with human-limit constraints. Perception fairness in all of them is enforced with explicit line-of-sight, field-of-view and "only react to what a human could see" rules. For up to 7 bots on a phone, a small FSM or utility layer with a vision query and a short memory is the proven pattern; planners and learned models are overkill.

### Cited Findings
- Quake III Arena bot (van Waveren): "four layers"; bottom layer holds the bot's input/output (environment representation as areas, which determine reachable moves including jumps to non-adjacent areas); next layer handles short-term objectives with fuzzy logic ("weigh the pros and cons"); third layer sets long-term goals via "a number of state dependent procedures"; a team layer enables collaboration. The bot "isn't supposed to use" engine-wide knowledge: it calculates whether a human could see an opponent before it may open fire. — [TU Delft Outlook, van Waveren interview](https://repository.tudelft.nl/file/File_f7fa0a9a-1cb3-441b-bd12-f1d6426be5b1) (interview, not thesis text)
- Left 4 Dead (Booth): each actor has Locomotion, Body, Vision and Intention components. Vision "owns line-of-sight, field of view, and 'am I able to see X' queries" and "maintains recognized set of entities". Intention is a hierarchical FSM plus stack of Behaviors containing Actions. SurvivorBots run two concurrent behavior systems, Main (decision, attention, target selection, attack) and Legs (movement, slaved to Main). Bots were also used for automated stress tests with accelerated game time. — [Booth, L4D AI Systems slides](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)
- Left 4 Dead fairness and trust cheats (developer statements): players must believe the bot replacements are "fair"; bots cannot deal friendly-fire damage; they never use Molotovs; a far-out-of-place bot is teleported near the team "when no human is looking at it". — same slides.
- F.E.A.R. (Orkin): the state machine has only three states (Goto, Animate, UseSmartObject), with A* used both for paths and for planning action sequences (STRIPS-like). — [GDC Vault, Three States and a Plan](https://gdcvault.com/play/1013394/Three-States-and-a-Plan); [Orkin slides, GDC 2006](https://pages.cs.wisc.edu/~dyer/cs540/handouts/gdc2006_orkin_jeff_fear.pdf) (snippets only; I did not open them)
- Blaston (VR dueling, Resolution Games), bots: each bot has four body parts (head, torso, two hands), each a finite state machine, driven by a message system; head tracks incoming projectiles, torso dodges what the head saw; "a bot can only dodge a projectile it has already seen"; hands have limited reach; no view behind; movement confined to the same podium. Designers can configure parameters to create different bots. No reaction or aim numbers published. Bots minimise damage taken when trapped. — [Resolution Games, The Inner Workings of a Blaston Bot](https://www.resolutiongames.com/blog/the-inner-workings-of-a-blaston-bot)
- Khoo et al. (FlexBot, Half-Life): priority-stack behavior-based design (shoot supersedes all others; separate stacks for movement actuators and others, combined by a union operator each cycle). Argument: "people are often willing to ascribe far more intelligence to very simple but obvious actions than is often warranted", so avoid over-engineering cognition. Their actuator split (movement vs everything else) gave "emergent" less-predictable behavior. — [Khoo et al. 2002](https://www.qrg.northwestern.edu/Resources/aigames.org/papers2002/SSS202AKhoo.pdf)
- Soar Quakebot: perception limited to unobstructed objects in a view cone and nearby sound; the world updated 10 times a second; bot runs at 5-10 percent of a 400 MHz Pentium II. — [Laird and Duchi 2001](https://www.qrg.northwestern.edu/Resources/aigames.org/2001/Laird.pdf)
- Genre history: Quake III's bots were commissioned after id staff found the earlier ones "didn't behave at all like human beings", and the bot code lives in its own library. — [Fabien Sanglard, Quake 3 source review: AI](https://fabiensanglard.net/quake3/a.i.php) (quoting Masters of Doom)

### Inferences
- Recommended minimal architecture for GDScript on the host: per-bot (a) Vision query (distance, FOV angle, one ray cast to target against walls, throttled to about 10-15 Hz per bot rather than every physics tick); (b) Memory: last-seen position and time per enemy, forgotten after about 2-4 s; (c) a flat FSM or small utility scorer with 5-7 states (seek weapon, engage, evade, recover/refuel, retreat-to-pickup, fight-at-edge); (d) an Output stage that writes the same input struct a player produces. This mirrors Booth's Vision/Intention split and Khoo's priority stack without needing planners.
- F.E.A.R.-style GOAP and Soar-style rule systems are too costly and unnecessary for 2-8 players at 45-second rounds on a budget Android phone that also hosts the match.
- Throttle perception and decision updates (stagger bots across frames: with 7 bots, update 1-2 bots' brains per physics tick). Laird shows a 100 ms decision step looks human, so a 10 Hz brain is both cheap and fair. This is an inference from Laird plus general engineering.
- Distinct "personalities" through parameter sets (aggression, preferred range, jetpack greed) are cheap variety; Blaston and Q3 both use per-bot parameter files (Blaston: "can be configured by designers").

### Gaps
- Halo 2/3 (Isla) perception and memory talks and Halo's behavior-tree details: not retrieved. The only Halo hit was a Microsoft doc page I did not open.
- Could not verify UT bot internals or CS bot (Booth) architecture beyond the session description.
- Exact aim-error implementations (overshoot, smoothing) in shipped bots not found in primary sources; only the Khoo statement that aim noise can simply be added to sensors.

---

## 3. Making bots feel human and fair; mobile bot tuning so first-timers win early

### Takeaway
Judges in the one controlled study penalized superhuman aim and too-slow decisions, and rewarded decisions at roughly human latency; designers (Soren Johnson) argue perceived fairness is what matters and hidden advantages are what get called "cheating". Mobile games quietly give new players easier bot-filled lobbies (PUBG Mobile is the best documented case, by outside reporting not developer statements); the lever there is lobby composition and bot skill, not bot stat boosts.

### Cited Findings
- What players perceive as AI cheating (Soren Johnson, Maxis designer, Spore and Civilization IV): hidden advantages that are not explained; behavior that looks like AI teamwork; single random events that visibly hurt the player; instant rewards that undo much effort; sense the game breaks its own rules. "Perception becomes reality"; visible balancing mechanics (Mario Kart item rubber-banding) feel acceptable, hidden rubber-banding feels suspicious; small incremental AI bonuses went unnoticed, while "free units under fog of war" felt unfair. — [Game Developer, Analysis: Game AI and Our Cheatin' Hearts](https://www.gamedeveloper.com/game-platforms/analysis-game-ai-our-cheatin-hearts)
- Game AI may be accused of inhuman play when it exceeds human limits (e.g. above the roughly 300 actions per minute of pro StarCraft II players); developers sometimes cap AI action rate; labelling an AI "superhuman" may worsen negative reactions. — [arXiv 2503.15514, Superhuman Game AI Disclosure](https://arxiv.org/html/2503.15514v2) (search-snippet level)
- Laird: the bot rated most human used a 0.10 s decision time; humans rated 6.8-8.3 on humanness vs a best bot of 6.7, so no variant fully matched humans; only the judge with the most Quake experience identified every bot correctly. Bots at 0.25 s and 0.50 s looked bad because they could not avoid walls. — [Laird and Duchi 2001](https://www.qrg.northwestern.edu/Resources/aigames.org/2001/Laird.pdf)
- van Waveren's critique of an earlier bot: the top level "just couldn't lose", scoring a kill the instant it appeared; lower levels merely aimed worse and "did less intelligent things" (so difficulty that only degrades aim feels dumb). — [TU Delft Outlook](https://repository.tudelft.nl/file/File_f7fa0a9a-1cb3-441b-bd12-f1d6426be5b1)
- Booth (L4D): "Reliable and predictable decision making" is a stated fairness property for bot teammates; bots prioritize human teammates; a survivor bot that is far out of position is teleported only when no human is looking. — [L4D AI slides](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)
- PUBG Mobile (outside reporting, never confirmed by the publisher): early matches are filled with easy bots and the real-player share rises with account level, with a noticeable difficulty jump around level 10; new players report unusual first-win rates. — [Wccftech](https://wccftech.com/pubg-mobile-bots/); [Twinfinite](https://twinfinite.net/guides/pubg-mobile-bots-does-it-have/); [GamesRadar on console bots for new players](https://www.gamesradar.com/pubg-adds-bots-to-help-new-players-not-just-die-immediately). Developers have not officially commented per these reports.
- Brawl Stars: I found no official Supercell statement about bot use in matchmaking. Fan sources say bot-heavy lobbies at low trophy counts (up to about 1000 trophies "bots are super easy") and dedicated Bot Brawl / Co-Op Brawl modes; players complain about "teammates that seem like bots" in regular matches. — [speedrun.com forum post](https://www.speedrun.com/pl-PL/brawl_stars/forums/yye6t) (fan, unverified); [sikayetvar complaints](https://www.sikayetvar.com/en/brawl-stars-us/brawl-stars-matchmaking-feels-unfair-after-months-of-imbalanced-matches)
- Blaston bots act as believable duel opponents using the same body limits as players; the developer notes restrictions were added "to try and make the bots act in a somewhat believable manner". — [Resolution Games](https://www.resolutiongames.com/blog/the-inner-workings-of-a-blaston-bot)

### Inferences
- Deliberate-mistake toolkit consistent with the above, to implement as cheap parameters: (1) reaction delay randomized per event; (2) a short "acquire" ramp before the first shot (aim starts off-target and converges over 150-400 ms by difficulty) so bots do not snipe instantly on first sight, which is the "scored a kill the moment it showed itself" failure; (3) forget/lose-track after losing sight (memory timeout) and search the last-seen position; (4) a commitment window so targets are not switched every tick (e.g. keep a target for at least 1-2 s unless a threat is close), with occasional deliberate switching to a nearer threat; (5) occasional hesitation (0.2-0.5 s pause) when entering open space or after taking damage; (6) bots miss on first shots against a newly dashing target.
- Easy-bot design: because Q3 and van Waveren show "bad aim only" feels dumb, Easy should also make poor tactical choices (low fuel management, walks into hazards, overuses jetpack) while keeping rules identical. This is allowed under the "which skills the bot uses" lever.
- Since our design forbids hidden stat changes, first-time-player win rates must come from bot count and bot level mix per lobby (a PUBG-style lever), not rubber-banding. If bots are ever silently tuned per player, disclose it (Johnson).
- Because hidden rubber-banding is the thing players call cheating, any dynamic adjustment should only pick which pre-defined difficulty tier fills the slot.

### Gaps
- No developer-confirmed data on how Brawl Stars, Mini Militia, PUBG Mobile or Clash Royale tune bots for early wins; all evidence is player and press inference.
- No quantitative first-match win-rate targets from any shipped game found.
- Booth's CS talk (human-like deliberate mistakes, "attention prioritization") is paywalled; I only have the abstract.

---

## 4. Navigation for 2D platform arenas with flight; cost on mobile CPUs

### Takeaway
Two proven approaches for 2D platformers: hand-authored waypoint/instruction graphs (Soldat's bots, per its community wiki) and generated graphs of platform nodes with jump/drop links computed from the character's movement constants. For a jetpack character that can fly anywhere, a full jump-link graph is unnecessary; a coarse grid or small hand-placed waypoint set plus local steering is cheaper and sturdier. I found no primary source on TowerFall, Rivals of Aether or Mini Militia bots.

### Cited Findings
- Soldat bot navigation is waypoint-scripted: waypoints carry instructions (Move Left, Move Right, Jump, Crouch, Use Jetpack, Wait X seconds, Stop and camp) and are per-map; so it is authored, not a general pathfinder. — [Soldat wiki: WayPoint](https://wiki.soldat.pl/index.php/WayPoint)
- Generalized platformer pathfinding writeups: build a graph of platform nodes with edges for walking, jumping and dropping; A* searches the graph; jump links are computed per agent from its own jump height and max speed so "each kind of AI needs its own navmesh"; links can be enabled only if the character's jump height is sufficient. — [GameDev.net, Generalized Platformer AI Pathfinding](https://gamedev.net/tutorials/programming/artificial-intelligence/generalized-platformer-ai-pathfinding-r3924); [Game Developer, The Hobbyist Coder 3: 2D platformers pathfinding](https://www.gamedeveloper.com/design/the-hobbyist-coder-3-2d-platformers-pathfinding-part-1-2); Godot add-on [Surfacer](https://github.com/SnoringCatGames/surfacer)
- Godot users note NavLink2D often needs manual setup per edge. — [Godot forum](https://forum.godotengine.org/t/need-help-with-2d-platformer-pathfinding/116356)
- A forum proposal builds jetpack traversal into A* nodes (pathfollower triggers the jetpack on arrival at a jump node), and a Xonotic forum report says bots use jetpack only vertically, not horizontally. — [GameDev.net thread](https://gamedev.net/forums/topic/508047-a-unique-scenario-relating-to-bot-ai/4315870); [Xonotic forum](https://forums.xonotic.org/printthread.php?tid=5034). Forum-level evidence only.
- Q3's own bot uses "areas" with adjacency for walking and extra reachabilities for jumps, so non-adjacent areas can be reached by jumping; this is a graph-of-areas model. — [TU Delft Outlook](https://repository.tudelft.nl/file/File_f7fa0a9a-1cb3-441b-bd12-f1d6426be5b1)

### Inferences
- Because the GDD's movement is hand-written on the network tick with fuel-limited jetpack, dash and wall-slide, bot navigation should output the same inputs (move axis, jetpack, dash, jump) and use a precomputed per-map coarse grid (for example 1 cell = 1-2 bot heights, solid/open flags, flood-filled distance fields to pickups) instead of runtime A*. A distance-field lookup per target is O(1) per query on a phone. This is my engineering reasoning; I did not find a benchmark.
- With free flight the main navigation hazards are: getting stuck on ledges and ceilings, wasting fuel, and hovering over hazards. Handle them with steering (seek target, avoid hazard cells, avoid walls with whisker rays) rather than jump-link graphs; reserve explicit links only for wall-jump or one-way platform quirks if the arenas need them.
- Stagger path/perception recomputation across frames and cap to roughly 5-10 Hz for 7 bots; the Soar bot used 5-10 percent of a 400 MHz CPU at 30-50 decision cycles per second, indicating even rule-heavy AIs of 2001 were cheap, but GDScript is slower than C++, so keep per-bot work to a few ray casts and table lookups per tick. No measurement of GDScript cost was found.
- Hand-authoring a small number of hint points per map (cover, pickup, edge-fight spots) à la Soldat waypoints is cheap and gives map-aware behaviour.

### Gaps
- No primary sources for TowerFall, Rivals of Aether, or Mini Militia bots/CPUs. Search returned nothing usable.
- No sourced benchmark for GDScript cost of ray casts, path queries, or 7-bot AI on budget Android.
- No source on jetpack-specific AI beyond forum posts.

---

## 5. Bots in a server-authoritative networked game

### Takeaway
The standard pattern is a bot that produces the same input/command structure as a human client ("fake client" in the Half-Life SDK, Q3's bot input/output layer), run on the server. I found no primary source specific to netfox or Godot, so the application to our stack is inference.

### Cited Findings
- FlexBot SDK for Half-Life creates NPCs "through a 'fake client' interface" and provides sensors and actuators; the actuator set (rotate, translate, strafe, pitch, shoot, fire secondary, jump, switch weapon, reload, duck, use) is expected on every program cycle as one action vector. — [Khoo et al. 2002](https://www.qrg.northwestern.edu/Resources/aigames.org/papers2002/SSS202AKhoo.pdf)
- Q3 bot bottom layer: input is environment representation and output is "all the possible moves"; bots do not read engine-global information beyond what a human could see. — [TU Delft Outlook](https://repository.tudelft.nl/file/File_f7fa0a9a-1cb3-441b-bd12-f1d6426be5b1)
- L4D: bots allowed the designers to "assume 4 player Survivor team for game tuning and balance", and automated stress tests ran 4 SurvivorBots at accelerated game time; "Drop in/out" replacement was valuable. — [L4D AI slides](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)

### Inferences
- Implement each bot as a pseudo-peer on the host whose brain writes a standard InputState (same struct and clamping as a network client) into the same per-tick input queue; the host's movement and weapon code never knows the difference. Then authority is automatically symmetrical (no bot-only damage paths, same health, same fuel, same cooldowns).
- The bot sensing layer should read the same authoritative state clients see after fog/visibility rules; give it only (position, velocity, health, weapon, visible flag) per enemy that passes the LOS/FOV check. Do not hand it raw global state.
- Bot reaction delay can be implemented as a ring buffer of observations (read the world snapshot from N ms ago) so no special timer logic is needed; this also gives you reaction-time tuning for free.
- Headless bot-vs-bot matches at accelerated time are a ready-made regression and balance test (L4D did this), matching CLAUDE.md's "headless run finishes without errors" check.

### Gaps
- Nothing specific on netfox bot support or on Godot/GDScript bot input injection; verify in the netfox docs and sample projects when implementing.

---

## 6. Boss design principles: telegraphing, pattern-then-punish, phases, difficulty ramps, one skill per boss

### Takeaway
Developers and analysts converge on readable telegraphs, repeating patterns learned across attempts, phases that layer new patterns, and escalation that does not overwhelm players as the fight ends. Our "one signature trick, one taught skill per boss, 2-3 phases" structure matches this. I could not find primary developer statements with numbers (telegraph durations, phase health splits); those are not available for Cuphead, Hollow Knight, Dead Cells or Furi in what I could reach.

### Cited Findings
- Cuphead (StudioMDHR, Game Informer boss-building feature): Jared Moldenhauer says the team built the stomach phase's pattern first, "before we had any concrete idea or layout of what exactly this stomach would look like", i.e. mechanic first, visuals later; rejected an animation as "too visually distracting" and simplified it so the attack read clearly; Chad Moldenhauer: "There's tons of back and forth" iterating. The reporter (not a quote) says the team tries to keep final phases from being the longest or hardest so players are not overwhelmed. The boss in question has three phases. — [Game Informer, How Studio MDHR builds a Cuphead boss](https://www.gameinformer.com/feature/2022/12/27/how-studio-mdhr-builds-a-cuphead-boss)
- Cuphead design process is "extremely iterative" and often starts from how it would play; Mega Man was a gameplay influence for its difficulty. — [Kotaku interview coverage](https://kotaku.com/cuphead-developers-talk-cut-bosses-and-whats-in-the-cup-1820126327) (snippet-level)
- Game Maker's Toolkit's Cuphead boss video (via transcript fragments): telegraph duration changes the difficulty; later chapters layer multiple patterns; phases let players learn which patterns belong to which phase. I could not fetch the full transcript. — [GMTK, How Cuphead's Bosses Try to Kill You (subtitles)](https://amara.org/videos/TbmQ6Ac3Z6pb/en/3100937)
- Hollow Knight vs Silksong (Team Cherry, William Pellen, via ACMI interview coverage): Hollow Knight bosses were more reactive to player position; Silksong moved to proactive bosses that pick move-and-movement; boss geometry was adjusted for Hornet's reach. — [ACMI, From Ludum Dare to Pharloom](https://www.acmi.net.au/stories-and-ideas/from-ludum-dare-to-pharloom/); [GamesRadar](https://www.gamesradar.com/games/platformer/compared-to-hollow-knight-silksong-reworked-how-the-bosses-pick-their-attacks-and-suddenly-i-realize-why-i-got-crushed-so-often) (secondhand; headline-level)
- Furi (The Game Bakers): the team centered the game on reflexes and learning boss attack patterns; the hard mode redesigns patterns and timings; Emeric Thoa says the charging dash adds depth to patterns the team can create. — [Wikipedia: Furi](https://wikipedia.com/wiki/Furi); [Game Developer, Furi design decisions](https://www.gamedeveloper.com/design/furi-some-tough-design-decisions-striving-to-make-a-memorable-game) (snippet-level; I did not read the post)
- Dead Cells (Motion Twin): designer Sebastien Benard said the balance of difficulty took a long time and that players were not playing as designers intended during Early Access; no boss-telegraph statements found. — [Game Informer interview](https://www.gameinformer.com/interview/2018/12/30/dead-cells-designer-discusses-scrapped-ideas-roguelikes-and-the-potential-for) (snippet-level)
- General design commentary (opinion/trade press): telegraphing is essential to fairness, a missing telegraph feels cheap; a fast but readable telegraph can work (Elden Ring's Malenia); 2-3 phases suit most bosses, one phase for short/early fights, three for final bosses; each phase should add a challenge that forces adaptation; heuristic: if a dying player calls the fight unfair the design needs changing, if they think they nearly had it it is working; a boss should recap what the player learned and teach something new. — [Game Developer, Boss Battle Design and Structure](https://www.gamedeveloper.com/design/boss-battle-design-and-structure); [Game Developer, Enemy attacks and telegraphing](https://gamedeveloper.com/design/enemy-attacks-and-telegraphing); [Game Developer, 3 Elements That Every Great Boss Fight Needs](https://www.gamedeveloper.com/design/3-elements-that-every-great-boss-fight-needs); [GamesRadar on Elden Ring fairness](https://www.gamesradar.com/games/action-rpg/tomb-raider-legacy-of-atlantis-boss-fight-lead-points-to-elden-ring-as-a-stellar-example-of-how-to-make-sure-theyre-fair/). These are opinion pieces with no measured data.

### Inferences
- Our table already enforces "one skill per boss". Keep each phase transition tied to a different use of the same trick (Dabba: phase 1 shoot the stack; phase 2 three tins with simple patterns; phase 3 faster/enraged tins), not new mechanics, to avoid breaking "teaches moving and aiming".
- Telegraph timing guidance (my starting numbers, not sourced): first-boss attack wind-ups of 0.6-1.0 s with a distinct sprite/sound cue; a tell must be readable on a phone-sized screen with a thumb on the screen, so exaggerate (flash, squash, sound). Telegraph should be longer than Very-Hard bot reaction (about 220 ms) plus mobile input latency by a clear margin on early bosses.
- Pattern-then-punish: each attack should end with a 0.8-1.5 s vulnerable window for Dabba-tier bosses; shorten for later champions. The GMTK point that telegraph duration is a difficulty dial suggests using the same dial in hard mode.
- Phase transitions should briefly make the boss invulnerable or distracted (for splits, spawn animation) so the player is not hit during the change; this is common design practice, but I have no primary source here.
- Phases should be triggered by health thresholds on the server and recorded as data in a boss config resource (consistent with the "numbers live in config" rule).

### Gaps
- Primary-source numbers on telegraph durations, phase health splits and damage tuning from Cuphead, Hollow Knight, Dead Cells, Furi were not found.
- Did not read GMTK's Boss Keys (it is about Zelda dungeon structure, not fights) or his other boss episodes in full.
- Could not read Game Developer posts in full; only snippets.

---

## 7. Splitting bosses (Dabba): what is fun vs tedious; piece counts and health

### Takeaway
I found no reliable developer or analytic source with piece counts and per-piece health for splitting bosses, so any numbers below are inference. The one documented example (Yellow Devil) shows that the split itself is fine and learnable; the complaints centre on a huge attack area, a tiny/brief weak point and heavy pattern memorization. For Dabba, the risk is hit-count tedium, not the split.

### Cited Findings
- Mega Man's original Yellow Devil splits into 19 parts moving in a fixed, learnable sequence; the order of disassembly and reassembly never changes; its weakness (Thunder Beam) hits a single eye; commentators describe it as painful and memorization-driven, and its hitbox keeps it controversial. — [Mega Man Maker wiki](https://wiki.megamanmaker.com/index.php/Yellow_Devil); [GamingBolt, 14 hardest retro bosses](https://gamingbolt.com/14-hardest-retro-bosses-of-all-time/2); [ComicBook](https://comicbook.com/gaming/list/mega-man-bosses-fans-still-argue-about-list). Secondary; none is a dedicated design analysis. Mega Man X5's Shadow Devil and later Rainbow Devil show the splitting idea reused with variations. — [SSB wiki](https://www.ssbwiki.com/Yellow_Devil)
- Tabletop multi-part monster discussion: removing a part also removes an attack, "at a certain point the math turns inevitably against the monster", but part HP should not be so low that collapse happens too quickly. — [EN World thread](https://www.enworld.org/threads/tuning-big-single-creatures-into-multi-part-creatures.716038/latest). Analogous reasoning only, not video games.
- Explicitly: no sources found for King Slime, other slime bosses, or any shipped game's per-piece health fraction.

### Inferences
- Health budget for Dabba (my proposal, unvalidated): treat total fight health as the sum of parts rather than multiplying it: e.g. stack = 100 percent of phase-1 budget; each of three small tins at 25-30 percent of the stack's budget, so total phase-2 health is about 75-90 percent of phase 1 and the three together are killable within a similar time. Total fight target 2-3 minutes (the GDD's bound).
- Fun vs tedious levers: (1) pieces must behave differently or at least in staggered phases (one shoots, one charges, one hovers) so the player prioritises targets, which gives the "moving and aiming" lesson; (2) bad: three identical pieces with equal health that you must each grind down, and pieces that leave the screen or hide; (3) when one piece dies the survivors should speed up or change pattern a little (reward and escalation), not keep the same load; (4) keep a visible health bar per piece plus a shared bar, so the player always sees progress; (5) keep the total pieces on screen at or below 3-4 on a phone screen.
- Mega Man's lesson: a fixed deterministic pattern is learnable; randomness in piece movement would add frustration, but a few randomised choices from a short list gives the "no autopilot" feel. Keep Dabba deterministic enough for first-time learners.
- Do not scale to 19 pieces: the GDD's 3 pieces is within the range that proven games find manageable; I have no data contradicting it.

### Gaps
- No design analysis, postmortem or developer quote on splitting bosses or their per-piece health.
- No data on typical TTK per piece.

---

## 8. Fight length, retries, lives, health tuning; par-time and no-damage bonuses

### Takeaway
I found no developer-sourced numbers for boss fight length or life limits that I could cite. The structure (3 rebuilds per fight, par time, no-rebuild bonus) is a combination of familiar designs (Cuphead's grades, Mega Man's lives). The tuning must be done by instrumented playtests; below are formulas, not sourced values.

### Cited Findings
- Cuphead boss grading and Run and Gun/Mega Man influence are mentioned in coverage, but no numeric tuning data was available in the sources I opened. — [Kotaku](https://kotaku.com/cuphead-developers-talk-cut-bosses-and-whats-in-the-cup-1820126327) (snippet)
- Cuphead's reporter-stated approach of not making final phases the longest or hardest. — [Game Informer](https://www.gameinformer.com/feature/2022/12/27/how-studio-mdhr-builds-a-cuphead-boss)
- Developers' heuristic "dies and says unfair vs nearly had it". — [Game Developer boss-design articles above](https://www.gamedeveloper.com/design/boss-battle-design-and-structure)
- Dead Cells team recommended its easy mode when a high-profile player complained about difficulty, and said difficulty balance took a long time. — [PC Gamer](https://pcgamer.com/games/roguelike/dead-cells-studio-thanks-guillermo-del-toro-for-playing-its-game-gently-suggests-he-try-the-easy-mode/); [Game Informer](https://www.gameinformer.com/interview/2018/12/30/dead-cells-designer-discusses-scrapped-ideas-roguelikes-and-the-potential-for) (snippet-level)

### Inferences
- Fight time formula: TTK_min = boss total HP / (player DPS x hit rate x uptime). With a 2-3 minute target, an average first-time player with 50 percent uptime should need about 2.5-3 minutes and a skilled player (par time) about 1.5-2 minutes. Set par time at roughly the 60th-70th percentile of playtest completion times so it is attainable, not the speedrun time.
- Three rebuilds means the player can die three times; consider tuning so the median first-timer wins with 1-2 rebuilds used, and the no-rebuild bolt is achievable by the top 20-30 percent. Log rebuild counts per fight from the start (headless bot tests can proxy).
- Telemetry per phase (deaths per phase, time per phase) shows which phase is the wall; use Rahul's device tests plus bot-driven headless runs with Medium bot as the "player" for early balance.
- First boss should be passable by a new player in 2-3 attempts; par-time bolts should reward learning, not require perfect play.

### Gaps
- No sourced numbers for typical boss duration, deaths per boss, or lives limits in Cuphead, Hollow Knight, Dead Cells, Mega Man or Furi in the pages I reached.
- No source on par-time design specifically.

---

## 9. Reusing bosses as multiplayer bots: precedent and problems

### Takeaway
I found no shipped-game precedent or postmortem for reusing campaign bosses as multiplayer bots under player rules; this is a gap. The conflict in our own design is visible from the GDD itself: the champions' tricks (splitting body, hovering with bullet-blocking blades, invisibility, vortex, arena-closing walls) rely on boss-only rules that clash with "same health, same hit area, no seeing through walls".

### Cited Findings
- GDD text: "Beaten champions join the bot pool in multiplayer with the same behaviour"; bots "follow the same rules as players: the same health"; every bot has the same hit area, speed and health regardless of look (parts are cosmetic). Champions: Dabba splits into three; Fanatic blades block bullets from the sides; Static turns invisible; Mixie's vortex pulls players; Lifter pulls weapons; Big Crush closes walls. — [GDD.md, Solo campaign and Playing with friends sections]
- Planned later mode "Boss Raid" (four friends vs one giant champion) is already listed as Later in the GDD.
- Shipped bots that sit outside player rules do exist in the genre as cooperative characters: L4D uses designer "cheats" (no friendly fire, teleport when unseen) to keep teammate bots trusted. — [L4D AI slides](https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf)

### Inferences
- Problem 1: a multiplayer champion-bot would have the champion's trick as an extra ability, breaking "bots obey player rules". Resolve by deciding what a champion is in multiplayer: either (a) the bot is a normal bot with a cosmetic skin and the trick is dropped, or (b) the trick is turned into a player-legal equipment/skill (e.g. Dabba's split = a gadget any robot could have). Per CLAUDE.md, if GDD and code disagree, ask Rahul; this is a GDD contradiction to raise: "same behaviour" vs "same rules as players".
- Problem 2: Dabba's three-piece split means one entity occupies three hit areas; against seven opponents in a 45-second round that is a damage sponge and violates same health. Same for invisibility (violates "no vision through walls" spirit, hides from players unfairly), vortex (is it a weapon?), blade shield (extra defence).
- Problem 3: boss patterns are tuned for one-on-one with a fixed target; in a free-for-all they need target selection, so the boss brain must handle multiple targets, which the shared "one bot brain" should already do.
- Recommendation: keep the ladder bosses separate from the multiplayer bot pool in the first release, or ship only "reskin" versions; this also aligns with scope-by-stage rules (Boss Raid is Later). I flag this as a plan risk rather than a proven failure.

### Gaps
- No shipped example of campaign bosses reused as rule-bound multiplayer bots located. Searches of FPS/mobile titles returned no relevant postmortems.

---

## 10. Flags: parts of our plan that proven games suggest may not work

### Takeaway
Four items need Rahul's decision or a tuning guard; the rest of the plan matches published practice.

### Cited Findings
- Superhuman aim is judged non-human; "shoot at the current position" was judged human and exact target leading was not. — [Laird and Duchi 2001](https://www.qrg.northwestern.edu/Resources/aigames.org/2001/Laird.pdf)
- A difficulty system that only degrades aim feels dumb. — [TU Delft Outlook](https://repository.tudelft.nl/file/File_f7fa0a9a-1cb3-441b-bd12-f1d6426be5b1)
- Hidden or unexplained AI advantages are what players call cheating. — [Game Developer, Cheatin' Hearts](https://www.gamedeveloper.com/game-platforms/analysis-game-ai-our-cheatin-hearts)
- 0.25-0.5 s decision times made the bot crash and look unlike a human. — [Laird and Duchi 2001](https://www.qrg.northwestern.edu/Resources/aigames.org/2001/Laird.pdf)

### Inferences
1. "Very Hard bots ... should beat most players" while "no reactions faster than a human": compatible only if Very Hard keeps its edge in consistency (no mistakes, perfect fuel use, good positioning) rather than speed. Laird's study shows a bot at a human-like 0.1 s decision step still got a skill ratio of 0.625 against an expert, so human-speed bots can already be strong; there is no need to go faster. Check with headless bot-vs-bot and bot-vs-Rahul tests.
2. "Hard bots lead moving targets": gate it with delayed, noisy velocity estimates; perfect lead is read as inhuman (Laird).
3. "Easy bots ... walk into traps": fine under "which skills the bot uses", as long as it is not a hidden handicap; it should not change health or hit area.
4. Champion bots in the multiplayer pool breaking player rules (Section 9): the biggest design conflict.
5. Scale: 7 bots plus netcode on a phone host: plan for staggered brains at 10-15 Hz and cheap perception (see Section 4). I have no measured GDScript numbers; profile early in Phase 1.
6. First-time-player wins: do it through bot level mix in the lobby (the PUBG Mobile lever) rather than secret stat changes (Johnson).

### Gaps
- The GDD conflict in item 4 cannot be resolved by research; needs Rahul.

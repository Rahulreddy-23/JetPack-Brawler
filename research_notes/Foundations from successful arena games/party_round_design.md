# Short-round party brawlers: what makes them fun and replayable, compared with the Jetpack Brawler GDD

Research date: 24 Nov 2026. Evidence quality note for the report writer: the search tool returned summaries, and many fetched pages (GDC Vault, Steam reviews, Reddit, Liquipedia, GameSpot, Nintendo Life, Move or Die's own site) were blocked or empty. Where a figure came only from a search-result summary and I could not open the page, the line says "(search summary)". Almost no developer postmortem text was retrievable for ROUNDS, Stick Fight, Gang Beasts, Nidhogg, Bopl Battle or Move or Die. Gaps are listed honestly; nothing below is filled from memory.

Our design as read from /docs/GDD.md (Match flow, The twist, Modes/maps/weapons): five 45 s elimination rounds; 3 s countdown; hazard closes from 30 s; timeout goes to most health then most damage; points 2 per knockout (uncapped) + 3/2/1 placement; ~8 s gap (2 s replay, 5 s card pick, 1 s start); the "player with the fewest points" picks 1 of 3 Chaos Cards (random on timeout, tie goes to the one knocked out earliest that round); card applies to all players, one active at a time, a picked card leaves the pool for the match; prototype pool is 4 cards, 10 at release, 20 later; final tie is a sudden-death round; Scrap Ghosts cannot damage anyone.

## ROUNDS (Landfall): loser-picks cards, balance, stacking, what went wrong, and how our variant differs

### Takeaway
ROUNDS is strong precedent that "the loser chooses a power-up" feels fair and keeps losers playing, but in ROUNDS the card is personal and stacks, which is a different mechanism from our global, replacing card. I found no retrievable Landfall statement on card balance, and only thin, low-volume player complaints (pick-wait pacing, repeated cards, combo strength).

### Cited Findings
- Steam page: ROUNDS is described as "a 1v1 rogue-lite shooter where each round gets more intense", the losing player of each round unlocks upgrades, 65+ powerups, 70+ maps. Core mode is 1v1 (the store page gave no player cap). — [Steam appdetails API](https://store.steampowered.com/api/appdetails?appids=1557740&l=english)
- Structure as described by reviewers: best-of-three fights, first to win two fights wins the round, the loser then picks from a random selection of five cards (common/rare/epic); players can see the opponent's cards (counterplay). — [Rounds Network review](https://rounds.network/rounds-review-my-new-favorite-multiplayer-roguelike/)
- A second review gives five rounds per match, each a best of 3, loser of a round picks from five random perk cards; reviewer wants a larger pool. The two reviews describe the structure differently, so the exact nesting of "round"/"game" is unverified. — [Bits and Pieces](https://bitsandpieces.games/2024/02/23/rounds/)
- Reviewer framing: the loser-pick "balances itself by giving trailing players more abilities to catch up"; a player with a strong build keeps winning but the opponent gets more abilities to come back. Presented as a strength. — [Rounds Network review](https://rounds.network/rounds-review-my-new-favorite-multiplayer-roguelike/)
- Gfinity: a game lasts about 10 minutes; the writer says losing "wasn't a punishment" because losing earns chaotic powers, short matches meant no pressure of "40-minute-long matches", and "nobody ends the game feeling bad". The same piece is entirely positive and raises no balance criticism. — [Gfinity](https://www.gfinityesports.com/article/i-hate-1v1-competitive-games-but-rounds-is-the-unhinged-exception)
- Reception: 96% positive of 25,891 Steam reviews, "Overwhelmingly Positive" (search summary of the store page); Metacritic user score 8.1 from 50 ratings, no critic reviews. — [Steam](https://store.steampowered.com/app/1557740/ROUNDS/?snr=1_remoteplaytogether_4__103), [Metacritic](https://www.metacritic.com/game/rounds/)
- Complaints I could find (all small samples): one Metacritic user's only gripe is pacing, "you gotta wait for the opponent to pick a card"; one says it "could get repetitive"; two ask for a 4-player mode. Of 12 Metacritic user reviews shown, 0 mention card balance or snowballing as a complaint. — [Metacritic user reviews](https://www.metacritic.com/game/rounds/user-reviews/)
- Balance/variety notes: after a couple of hours the Rounds Network reviewer saw many repeated cards and wanted more rare/epic cards; the Bits and Pieces reviewers found a homing + ricochet combo very strong ("bullets did bounce back and home in on me most of the time"). — [Rounds Network](https://rounds.network/rounds-review-my-new-favorite-multiplayer-roguelike/), [Bits and Pieces](https://bitsandpieces.games/2024/02/23/rounds/)
- Aggregator summary says Steam feedback mentions "unbalanced interactions and overpowered cards" and G2A says cards "stack over time" and are "sometimes a bit unbalanced"; both are secondary and unquantified. — [G2A / search summary](https://www.g2a.com/news/reviews/rounds-review-roguelike-fps-duels-with-massive-replay-value/) (page timed out when fetched; claim is from the search summary only)
- ROUNDS patch notes on SteamDB show Landfall-era tuning of individual cards (for example Grow: max damage +180% to +160%, Healing field activation 2 s to 1.5 s, a stat removed from Toxic cloud), i.e. card balance was patched after release. Which developer account/date is unclear. — [SteamDB patchnotes](https://steamdb.info/patchnotes/18913813) (search summary)

### Inferences
- Precedent that worked: loser-picks as a catch-up with reviewers calling it non-punishing; short sessions. Precedent that is thin: nobody I found documents snowballing or match-length failure in ROUNDS; that absence is partly the tool's limits, not proof.
- Difference from ours: (1) ROUNDS card is private to the loser and stacks into a build, which is the source of both its depth and its balance complaints (combos, repeated cards). Ours is global and replaced each round, so combo and stacking risk is removed, but so is the picker's personal catch-up; the picker's only edge is choosing a rule that suits them. The GDD's claim "nobody snowballs" is plausible for the card itself but the card is also a much weaker comeback tool than ROUNDS'. (2) ROUNDS is 1v1 with a clear loser; with 2 to 8 players "lowest points" is a looser notion (see ambiguity below). (3) ROUNDS offers 5 cards; we offer 3.
- GDD arithmetic issue worth fixing: with a 4-card prototype pool, 3 offered, and a picked card leaving the pool, pick 1 leaves 3 cards (no real choice at pick 2), and by pick 3 only 2 remain so three cannot be offered. A match has 4 picks (after rounds 1 to 4). To always offer 3 choices for 4 picks, the pool needs at least 6 cards; 7-round custom rooms need at least 8. This is purely from the document's numbers.
- GDD ambiguity: "the last-placed player" (The twist) vs "the player with the fewest points" (Match flow step 5) could mean last in this round or lowest cumulative. These pick very different players and different snowball behaviour (cumulative lowest may be the same player picking every round).
- Pick-wait: the only ROUNDS pacing complaint found is the wait while the opponent picks; our 5 s timer with random fallback is consistent with avoiding that, and the eliminated players are not waiting on the pick at all.

### Gaps
- No Landfall interview, devlog or postmortem about the loser-pick design or card balance was retrievable. Steam review text, Reddit and Steam discussions (the main source for "snowballing", "unfun cards", "too long") were not retrievable; counts of how widespread complaints are cannot be given.
- Whether ROUNDS' 3 to 4 player modes use the same loser rule: not verified.

## Round structure, scoring, anti-stalling and the "one more round" effect in named games (Stick Fight, Duck Game, TowerFall, Samurai Gunn, Nidhogg, Boomerang Fu, Move or Die, Gang Beasts, Ultimate Chicken Horse, Bopl Battle)

### Takeaway
The named games almost all use one-hit or very fast kills, last-standing rounds, and tiny gaps between rounds. Verified numbers are sparse. Credited reasons for replay are short rounds with low cost of failure, easy rules, group/rivalry context, and "tuned well" core feel rather than variety. I found nothing retrievable on anti-stalling in these specific games beyond TowerFall's miasma variant (weak source) and Smash tournament rules.

### Cited Findings
- Stick Fight: 4 players, each round on a different map, win by defeating the other three (falling off the map counts), weapons "appear periodically" and can be equipped mid-fight, lasers/spikes kill instantly, some maps are boss fights where one player gets boosts and others must defeat them. Reviewers cite fast pace, deaths within "the first 5 seconds". Round count per match not stated. — [Wikipedia: Stick Fight](https://en.wikipedia.org/wiki/Stick_Fight:_The_Game)
- Duck Game: "players die in one hit, and the last player standing wins the round". Review sources conflict on match length: one says sets of ten rounds with the first to ten wins; others say the target is configurable. — [Wikipedia: Duck Game](https://en.wikipedia.org/wiki/Duck_Game); [Gaming Trend review](https://gamingtrend.com/reviews/insert-ducking-awesome-pun-here-duck-game-review/) (search summary)
- Duck Game single-player ships unlockable modifiers such as moon gravity and explosive props; critics compare the multiplayer to Brawl, TowerFall and Samurai Gunn; criticisms cited are inconsistent level design and weak single-player. — [Wikipedia: Duck Game](https://en.wikipedia.org/wiki/Duck_Game)
- Samurai Gunn: 2 to 4 players, matches "typically consist of players defeating each other with one hit", sword plus gun with three bullets per life. No round/score/stalling detail retrievable. — [Wikipedia: Samurai Gunn](https://en.wikipedia.org/wiki/Samurai_Gunn)
- Boomerang Fu: a point goes to "the last one standing", or the mode can award a point per kill; up to six local players; power-ups from blue books whose spawn rate hosts can adjust; each player holds up to three power-ups; Metacritic 78 (5 reviews); critics fault the lack of online play and limited modes. — [Wikipedia: Boomerang Fu](https://en.wikipedia.org/wiki/Boomerang_Fu)
- TowerFall (Matt Thorson): "I designed the experience of TowerFall for being played with a group of friends"; "If the game is tuned well, it doesn't actually require that much variation to be satisfying"; variants are "cool... when you're with friends and you're just being silly"; fast play made it unreadable for spectators so he added trails and particles. — [Game Developer: The magic of TowerFall](https://www.gamedeveloper.com/design/the-magic-of-i-towerfall-i-depth-simplicity-community)
- TowerFall: "designed to be played by a group of players who meet periodically, on weekends or lunch breaks", with depth so that "an overarching narrative can form between sessions". — [Game Developer: Road to the IGF](https://gamedeveloper.com/design/road-to-the-igf-matt-thorson-s-i-towerfall-ascension-i-)
- TowerFall anti-stall: a community patch-note document says the Sudden Death variant starts miasma 1 s into the match instead of 5 s, in context of "dodge stalling". Author and officiality unclear. — [Patch notes doc](https://docs.google.com/document/d/1s620ARtObxV3DDBmhWnqTGElmYzflXO3lYKu-4t8s6Q/export?format=pdf) (search summary)
- Ultimate Chicken Horse: each round is estimated to last about a minute; if nobody reaches the goal or everybody does, no one scores; match ends at a point target or after a set number of rounds. — [Wikipedia: UCH](https://en.wikipedia.org/wiki/Ultimate_Chicken_Horse)
- Developer (Clever Endeavour, IGF interview): "each run phase is very short, usually under 20 seconds", so "if players fail early, they don't have to wait very long until the next round and they don't get bored"; "make it too hard for your friends, but easy enough for you"; bonus points for arriving first but "the main goal is simply to make it there alive". — [Game Developer: Road to the IGF, UCH](https://gamedeveloper.com/design/road-to-the-igf-clever-endeavour-games-i-ultimate-chicken-horse-i-)
- UCH reviewer view: the scoring flaw is that all-finish gives no points, and players can score because a rival fails a simple track; game is best in short sessions "before fatigue sets in". — [The Skinny](https://www.theskinny.co.uk/tech/gaming/ultimate-chicken-horse)
- Move or Die (Those Awesome Guys): co-creator Nicolae Berbec: "It's a four player party game that ruins friendships, and the rules change every 20 seconds." Wikipedia: health drops fast if you stop moving; each round adds different rules; hazards include death tiles and falling blocks. Mutators update released March 2016, adding options like jetpacks and double jumps. — [Player.One](https://www.player.one/move-or-die-gameplay-so-fun-it-will-ruin-friendships-says-co-creator-520587), [Wikipedia: Move or Die](https://en.wikipedia.org/wiki/Move_or_Die), [Capsule Computers](https://www.capsulecomputers.com.au/?p=276166) (search summary)
- Smash (time vs stock): stock matches have no inherent end, so tournaments add a time limit on top of stocks; Ultimate guidance lists 6 to 8 minutes for singles. Stalling is defined as avoiding conflict to win by time-out, and is distinguished from camping ("a camping opponent still intends to fight"). — [SmashWiki: Stalling](https://www.ssbwiki.com/Stalling), [SmashWiki: Tournament rulesets](https://www.ssbwiki.com/Tournament_rulesets_(SSBU)) (search summary)
- Landfall's Henriksson (about their battle-royale joke game, not Stick Fight): "every single one of them doesn't need to be balanced and thought out"; "If everyone doesn't take the game so seriously we can have a lot more fun". — [Game Developer: Landfall](https://gamedeveloper.com/design/how-landfall-games-finds-the-fun-in-physics-engines)

### Inferences
- Our 45 s round plus about 8 s gap (about 4 to 5 minutes per match by the GDD's numbers) is in the same band as the short, low-wait structures developers describe (UCH runs under 20 s with explicit "don't wait long" intent; ROUNDS is about 10 min per game). The documented risk is not round length but waiting time for the eliminated, which the ghost role addresses.
- The GDD's timeout rule (health, then damage) is the Smash-style "time-out" problem. Smash tournaments cap stalling by rules on top of stocks; our hazard from 30 s plus kill points is the in-game equivalent. The GDD is consistent with this precedent; nothing I found says 15 s of hazard is too short or too long.
- Thorson's quote is a caution for our "rules change every round" pitch: the rule-changing layer is a bonus, and the core 45 s fight must be fun with no card. The GDD's phase-1 test ("first-timer can win with two sticks") fits.

### Gaps
- Nidhogg, Gang Beasts, Bopl Battle, Samurai Gunn, Boomerang Fu, Stick Fight: no developer talk, round-length number, between-round time or anti-stalling statement retrieved (Wikipedia for Bopl Battle returned 404).
- No credible source on what reviewers credit for "one more round" per game beyond the quotes above; no Steam review data.
- TowerFall match defaults (kills to win, arrow economy) not retrieved.

## Move or Die and Ultimate Chicken Horse: rule mutators and scoring that keep weaker players in the game

### Takeaway
UCH has an explicit, documented catch-up scoring system (Comeback "Underdog" points, plus trap, solo and postmortem points), and its developer says the original flaw was players who fell behind "couldn't catch up". Move or Die's developer statements I could retrieve say nothing about handicapping weaker players; the mutator update is documented, but who picks mutators was not confirmable.

### Cited Findings
- UCH point types (Rules & Modifiers): Goal, Solo (only player to reach goal), Postmortem (reach the goal after dying), Trap (another player dies on your trap), Coin, Comeback ("extra points when you reach the goal as an Underdog"; Underdog = "haven't reached the goal for the past 2 (or more) turns while others have"), and First/Second/Third/Fourth by finishing order. All are configurable; numeric defaults are not given in the article. — [Clever Endeavour support: Custom rules and presets](https://cleverendeavourgames.freshdesk.com/support/solutions/articles/32000028991-custom-rules-and-presets)
- Developer statement (VentureBeat): the team found people "falling behind during a match couldn't catch up"; "Between refining comeback points and elements that ensured the underdog could still have a chance at success, the game took on a new shape." The designer (Richard Atlas) also said "People get overwhelmed when they have too much choice" and "We prefer to give them smaller options at one time." — [VentureBeat](https://venturebeat.com/business/ultimate-chicken-horse-from-game-jam-prototype-to-hilarious-party-game)
- UCH original scoring was letters like HORSE, a letter for each failure. — [Clever Endeavour FAQ](https://cleverendeavourgames.freshdesk.com/support/solutions/articles/32000029013-how-did-you-come-up-with-ultimate-chicken-horse-) (search summary)
- Opinion: the Escapist review argues bonuses can still fail to close large point gaps in some matches (search summary of the review; page not opened). — [Escapist](https://escapistmagazine.com/?p=60404)
- Move or Die mutators update dated 10 March 2016 (press release 8 March) added mutators such as jetpacks, double jumps, skin swapping and death ghosts; one changelog fix "prevented the same player from being selected twice in a row for mutator selection", which implies mutators are assigned to one player at a time, but the excerpt does not say how that player is chosen. — [Capsule Computers](https://www.capsulecomputers.com.au/?p=276066), [Move or Die changelog](https://www.moveordiegame.com/updates/mutators/) (search summary only, site certificate expired when fetched)
- Developer quote on structure: "Move or Die is a game that keeps evolving, specifically because of its structure... It allows more and more content." — [Player.One](https://www.player.one/move-or-die-gameplay-so-fun-it-will-ruin-friendships-says-co-creator-520587)
- Player.One's article contains no developer statement on skill balance or on who picks mutators.

### Inferences
- UCH's lesson for us is that catch-up is explicit and visible in the scoring (a defined "Underdog" status), and was added after playtesting showed trailing players quit mentally. Our only catch-up is the Chaos Card pick; the GDD has no score-based catch-up and says none is needed. UCH suggests that is a risk to playtest: a player two rounds behind in a 5-round match may have no path to winning (the matter is made sharper because 5 rounds is short and kills are worth up to 14 points a round with 8 players).
- UCH "postmortem points" is a direct precedent for giving eliminated players a path to score; our ghosts get coins from scrap bolts but the GDD does not say whether those count toward match points.
- Move or Die gives no evidence for or against loser-chosen global rule changes. Do not cite it as precedent for that.

### Gaps
- No developer statement on weaker-player design for Move or Die found. Move or Die's mutator selection rule not confirmed.
- UCH numeric point values and default points-to-win not retrieved; UCH Underdog logic is documented only as above.

## Comeback and catch-up mechanics: when they feel fair vs like punishment (Mario Kart, Mario Party, Smash)

### Takeaway
Catch-up is accepted when it keeps everyone in the race and is hard to see or is luck the players expect (Mario Kart). It draws "punishment for the leader" criticism when it targets the leader directly (blue shell) or when final results hinge on random bonuses (Mario Party). The documented evidence is journalistic opinion plus two developer quotes, not data.

### Cited Findings
- Hideki Konno (Kotaku, 2011): the shell was meant to keep the pack together: "we wanted to create a race where everyone was in it until the end." — [Wikipedia: Blue shell](https://en.wikipedia.org/wiki/Blue_shell)
- Kosuke Yabuki (Eurogamer, 2017): Nintendo tested removing the shell but "it feels like something's missing... So for now we've kept it in." — [Wikipedia: Blue shell](https://en.wikipedia.org/wiki/Blue_shell)
- Item design changed over time: in Mario Kart 64 only 4th to 8th place could receive the shell; from Double Dash it more often went to those near the front when the leader pulled away; from Super Circuit to MK7 the shell flew over the track and could not hit racers it passed. — [Wikipedia: Blue shell](https://en.wikipedia.org/wiki/Blue_shell)
- Reception: the Guardian called it "the most controversial item in the Mario universe" (2017); Kotaku's Nathan Grayson defended it as "The Great Equalizer", the series' "most despised and best item" (2014); PCMag and Den of Geek called it the "Blue Shell of Death". — [Wikipedia: Blue shell](https://en.wikipedia.org/wiki/Blue_shell)
- Game Developer essay on rubber-banding: it works when subtle; it is "a bit egregious" when computer racers "teleport" to keep up; in Split/Second catch-up serves the core mechanic (power plays only available when behind) and the reviewer found leading unfun because you "can't trigger the game's main selling point". Note the "design principles" list in my fetch was a summarizer's synthesis of this essay, not verified verbatim author text. — [Game Developer: Rubber banding as a design requirement](https://gamedeveloper.com/design/rubber-banding-as-a-design-requirement)
- Mario Party: GameSpot user review complains random bonus stars mean "you can be the best Mario Party player and still finish dead last"; GamesRadar says Mario Party has been "the poster child" for random outcomes since the 1990s and that Super Mario Party Jamboree finally lets players turn the random elements off; US Gamer says Super Mario Party reduced bonus stars to two awards that "don't monumentally change the tides of who wins"; MarioWiki notes bonus star pools grew in MP7/MP8/MPDS while three were picked at random, and MP9 changed the economy. All via search summaries. — [GameSpot user review](https://gamespot.com/super-mario-party/user-reviews/2200-12796126/), [GamesRadar](https://gamesradar.com/games/puzzle/with-super-mario-party-jamboree-nintendos-finally-letting-you-cut-out-the-random-nonsense-thats-defined-its-multiplayer-games-for-decades), [US Gamer](https://www.usgamer.net/articles/super-mario-party-review), [MarioWiki](https://mariowiki.com/Mario_Party_(series))
- Smash: stock play is preferred in tournaments for its "orderly" structure, with time added only as a cap (SmashWiki, search summary). I found no designer statement on stock vs time as a catch-up. — [SmashWiki](https://www.ssbwiki.com/Stalling)

### Inferences
- Chaos Card as global, non-targeted catch-up avoids the "punish the leader" complaint (the card cannot target anyone). It also gives little help to the player who picks, so the main risk is the opposite: players may not feel the comeback at all. Neither risk is evidenced for our design; both are playtest questions.
- Mario Party precedent supports the GDD's choice to score on kills and placement (skill) rather than random bonuses; there is no random bonus in our scoring.
- Visible catch-up is the more accepted form: ROUNDS' picks and UCH's "Underdog" status are announced to everyone. Our card pick is announced to everyone too, which is consistent.

### Gaps
- No research data (surveys, telemetry) on perceived fairness of catch-up in party games found; all evidence is opinion/journalism. The GMTK or Deconstructor of Fun videos on Mario Kart/Party were not retrievable.

## Rule modifiers and mutators: which kinds players enjoy vs find frustrating, and a check of our twelve cards

### Takeaway
I could not retrieve review-level evidence on control inversion, forced position swaps or one-hit-kill modifiers. What exists: one-hit kill is the core of the best-reviewed arena brawlers (Duck Game, Samurai Gunn, TowerFall) so it is not inherently frustrating when it is the baseline; physics/weapon modifiers are what developers ship as optional modifiers. The only generic design evidence found says punishments players cannot react to feel bad.

### Cited Findings
- Duck Game ships physics/props modifiers (moon gravity, explosive props) as unlockables in single-player; players "die in one hit" by default. — [Wikipedia: Duck Game](https://en.wikipedia.org/wiki/Duck_Game)
- Move or Die's mutators update added jetpacks, double jumps, skin swapping and death ghosts. — [Capsule Computers](https://www.capsulecomputers.com.au/?p=276166) (search summary)
- Rocket League has long shipped mutators and a Rumble mode with 11 randomized power-ups that spawn on a timer; Player.One said at launch that the power-ups can make it more difficult for the average player to score. I found no player-reception data. — [Epic help: Rumble](https://www.epicgames.com/help/rocket-league-c-202300000001622/gameplay-c-202300000001682/what-is-rumble-mode-in-rocket-league-a202300000014075), [Player.One](https://www.player.one/rocket-league-rumble-mode-introduced-new-patch-includes-11-power-ups-launch-554978)
- Thorson: variants are "cool... when you're with friends and you're just being silly", while a well-tuned base game "doesn't actually require that much variation". — [Game Developer](https://www.gamedeveloper.com/design/the-magic-of-i-towerfall-i-depth-simplicity-community)
- General design opinion: random effects that punish a player who had no chance to prevent them feel bad; random events should reward risk. One commenter in the same results argues difficulty is intentional in party games. (Card-game design essay; indirect relevance.) — [Game Developer: no gain from pain](https://www.gamedeveloper.com/design/card-games-no-gain-from-pain-part-1) (search summary)
- Landfall designer Henriksson: not every weapon "needs to be balanced and thought out" in a joke game. — [Game Developer: Landfall](https://gamedeveloper.com/design/how-landfall-games-finds-the-fun-in-physics-engines)

### Inferences
- Check of our 12 cards against what I could source (all are inferences, not evidence of reception):
  - Moon Boots, Ice Rink, Tiny Town, Big Heads, Rubber Rounds, Rocket Party, Boom Box: physics/weapon/scale changes, the category developers ship as optional modifiers (Duck Game, Move or Die, Rocket League). No evidence of frustration found.
  - Sudden Death (one hit kills, pistols only): one-hit kill is the baseline in Duck Game, Samurai Gunn and TowerFall, so the effect is proven fun in those, but those are built around it (ammo limits, parry, fast respawn of rounds). In ours it is a 45 s round with 100 HP and 1 s TTK normally; risk is the hazard timer plus pistols-only making stalling attractive. Flag for playtest, not a rejection.
  - Body Swap (forced position swap every 20 s): the closest "forced" mechanic; no source found on forced swaps. The generic principle (no ability to react) applies; note the 20 s swap divides a 45 s round into 20/20/5 with swaps landing at 20 s and 40 s, and the closing hazard begins at 30 s.
  - Glass Cannon, Free Fuel (no dash), Butterfingers: no precedent found; Free Fuel removes a core movement skill and Butterfingers punishes melee hits; judged only from the GDD text.
  - No card inverts controls, so the most commonly feared category in the question is absent from the pool.
- Because the card applies to everyone including the picker, pure "punish" cards (cards that make players worse off) fall equally on all; that fits the "chaos for everyone" tone and sidesteps the one-sided punishment issue.

### Gaps
- No player-review corpus (Steam reviews, Reddit threads) on mutators or on inverted controls or position swaps was retrievable; I cannot say how widespread any opinion is. No postmortem on mutator selection found. Evidence on one-hit-kill frustration in short party rounds is absent.

## Scoring formats for 4 to 8 players over a fixed number of rounds: kills vs placement, and tie handling

### Takeaway
Battle-royale tournaments weight placement heavily and kills at a lower rate (and the scale is tuned per event); party games mostly use last-standing or finishing order. Our 2 per kill vs 3/2/1 placement is far more kill-weighted than any BR format I found, which matches its stated anti-hiding rationale.

### Cited Findings
- Apex Legends Global Series: 1 point per kill plus placement points. An EA forum post quoting older rules lists 12, 9, 7, 5, 4, then 3 for 6th/7th (labelled "Majors 1 to 3 only", may not be current). — [SI: ALGS match point explained](https://www.si.com/esports/apex-legends/apex-legends-global-series-match-point-explained), [EA forum post](https://forums.ea.com/discussions/apex-legends-feedback-en/gold-knockdown-change-ideas/8497944/replies/8497954) (search summary)
- ALGS criticism: TSM's ImperialHal argued placement gaps are too small, noting that nine kills and finishing 17th equals second place with no kills. — [AFK Gaming](https://afkgaming.com/esports/news/tsm-imperialhal-expresses-concerns-over-algs-points-system) (search summary, page not opened)
- ALGS finals use a "match point" format (a team must reach a threshold then win a game) per SI; one non-official guide gives 50 points as the threshold and 20/15/12 for the top 3, contradicting the 12/9/7 table above, so treat with caution. — [SI](https://www.si.com/esports/apex-legends/apex-legends-global-series-match-point-explained), [Expert Beacon](https://expertbeacon.com/how-does-apex-tournament-scoring-work/)
- Fortnite FNCS: scoring varies by event. A Chapter 4 Season 1 Community Cup gave 25/22/20 for 1st/2nd/3rd with 1 point per elimination; a later Community Cup gave 65/56/52; the 2023 Global Championship gave 2 points per elimination in Rounds 1 and 2 and 4 in Finals. Tiebreak order in Community Cup rules: total points, total Victory Royales, average eliminations, average placement, total seconds. — [Epic: FNCS Community Cup rules](https://www.fortnite.com/competitive/news/fncs-community-cup-chapter-4-season-3-official-rules), [Epic: FNCS Global Championship 2023](https://www.fortnite.com/news/fncs-global-championship-2023-official-rules) (search summary)
- UCH awards no points if everyone or nobody reaches the goal (see earlier section); Boomerang Fu awards a point to the last one standing or per kill depending on mode. — [Wikipedia: UCH](https://en.wikipedia.org/wiki/Ultimate_Chicken_Horse), [Wikipedia: Boomerang Fu](https://en.wikipedia.org/wiki/Boomerang_Fu)

### Inferences
- Ratios (computed from the cited numbers): ALGS first place is worth 12 kills; FNCS Community Cup C4S1 first place is worth 25 kills; ours is 3 points = 1.5 kills for first place. In an 8 player round all 7 knockouts are worth 14 points, against only 6 placement points in total. So a player can win the match by kills while rarely winning rounds. That is the opposite of the BR concern (camping) and matches the GDD's reasoning, but it also means the final kill matters little and the round winner's bonus is small.
- ImperialHal's complaint inverted: BR pros complain that placement is too small relative to kills; our scoring has the same property deliberately. Worth stating that the GDD's anti-hiding aim is valid but the round-win incentive is weak, which interacts with Chaos Card triggers: "last place" will usually be a low-kill player, not someone who finished badly.
- Tie handling: FNCS shows a layered auto-tiebreak (points, then wins, then average kills). The GDD goes straight to a sudden-death round. A cheaper first-level tiebreak is round wins, then total knockouts; tied for fewest points at card time is already handled by "knocked out earliest that round".
- Round 1: everyone has zero points before it, so the rule "fewest points" is undefined until the first round scores; the tiebreak "knocked out earliest" applies, which is workable.

### Gaps
- Official current ALGS and FNCS 2026 tables not retrieved (Liquipedia and EA official page blocked or 404; the FNCS 2026 attachment not visible). Figures above are per-event samples, not the current format.
- No source found on scoring for 4 to 8 player party games over a fixed number of rounds beyond the above.

## Roles for eliminated players (Among Us, Bomberman, Fall Guys, Spelunky)

### Takeaway
Developers who have addressed it admit a dead player's experience is the weak point (Among Us: "If you get killed first that sucks. Your game is boring"). Documented working precedents: Bomberman revenge carts (dead players can attack from the edge) and UCH postmortem points. The consistent design tension (stated by Innersloth) is that powers that affect the game risk harming it, and powers that do not are "just a mini-game". Our ghost design (no direct damage, small nudges) takes the cautious side.

### Cited Findings
- Innersloth's Marcus Bromander (Twitch show, 1 Oct 2020): "We do want to make being ghosts more fun" and "If you get killed first that sucks. Your game is boring." Forest Willard said changing ghost roles is "the hardest part" and the team considered "Guardian Angels". — [Inverse](https://www.inverse.com/gaming/among-us-ghost-update)
- Sportskeeda (secondary, not direct quotes): ghosts likely know who the impostors are so any influence could let them communicate with the living; a feature with no effect would be just a mini-game, while one that does affect the game could harm the experience; in public games most dead players leave to join a new game because waiting takes longer. — [Sportskeeda](https://sportskeeda.com/esports/among-us-developer-s-discuss-changes-ghosts-can)
- Among Us ghosts can only complete remaining tasks and cannot vote or interact with living players (search summary). — [GameSpot](https://www.gamespot.com/articles/among-us-players-could-become-guardian-angels-after-dying/1100-6483091/) (page 403; search summary)
- Bomberman R manual: "Players who have already lost can continue to attack by throwing bombs from outside the Wall Blocks around the edge of the stage" (Revenge Carts). — [Konami Bomberman R manual](https://www.konami.com/games/bomberman/r/us/en/manual/league.html)
- UCH has Postmortem points for players who reach the goal after dying (see section 3). — [Clever Endeavour support](https://cleverendeavourgames.freshdesk.com/support/solutions/articles/32000028991-custom-rules-and-presets)
- Move or Die's 2016 update added "death ghosts" as a mutator. — [Capsule Computers](https://www.capsulecomputers.com.au/?p=276066) (search summary)
- Spelunky 2 deathmatch: Steam news mentions a "ghost deathmatch timer" and a lives counter; a Gamer Tweak guide says a ghost can still help a living friend until revived (co-op context). No description of deathmatch ghost powers retrieved. — [Gamer Tweak](https://gamertweak.com/how-to-revive-friends-spelunky-2-multiplayer)

### Inferences
- With 45 s rounds an eliminated player waits at most about 40 s, much shorter than Among Us, so the "leave to start a new game" failure is unlikely in same-room play; the real risk is boredom in the waiting seconds, which Bomberman handles with damaging revenge carts and we handle with non-damaging ghosts. The Innersloth quote supports having powers that "stir the fight" but warns about powers with outcome influence; the GDD's Spring Plate/nudge/coins appear to sit in the middle. Ghosts "collect scrap bolts that count as coins": whether coins feed the match score is unspecified and, if they do, is the "decide the result" lever.
- Ghost interacting with crates and dropped weapons (the GDD) can indirectly influence kills; this is the same "affects the game vs mini-game" tension Innersloth describes.

### Gaps
- Fall Guys spectating: no source retrieved. Spelunky deathmatch ghost powers: not retrieved (PC Gamer article empty on fetch). Bomberman revenge-cart numbers (timing, bomb count): not retrieved. No evidence on the share of eliminated players who stay engaged.

## Closing hazards and shrinking arenas in short rounds: timing and telegraphing

### Takeaway
The clearest precedent is Bomberman's "Hurry Up", which warns on screen and then drops indestructible walls from the edge inward; sources say the Super Bomberman trigger was about 1.5 minutes. I found no reliable source for the ratio of hazard start to round length in the other games, so the 30 s of 45 s (two-thirds elapsed) cannot be benchmarked with evidence.

### Cited Findings
- Super Bomberman: "After a minute and a half the game displays a message to 'Hurry Up!' and then starts dropping indestructible walls around the edge of the play field", killing anyone struck. — [StrategyWiki: Super Bomberman gameplay](https://strategywiki.org/wiki/Super_Bomberman/Gameplay) (search summary; page 403 on fetch)
- Bomberman R: "When time is running out, Pressure Blocks will start to fall" from the outer edge inward; being crushed is instant game over; if all remaining players are crushed simultaneously the result is a draw. Exact trigger time not stated on the page. — [Konami manual](https://www.konami.com/games/bomberman/r/us/en/manual/league.html)
- TowerFall Sudden Death variant begins miasma 1 s into the match (community doc, weak source). — [Patch notes doc](https://docs.google.com/document/d/1s620ARtObxV3DDBmhWnqTGElmYzflXO3lYKu-4t8s6Q/export?format=pdf) (search summary)
- Thorson: speed made spectating unreadable until he added particle trails to improve readability. — [Game Developer](https://www.gamedeveloper.com/design/the-magic-of-i-towerfall-i-depth-simplicity-community)

### Inferences
- Our timeout rule (most health, then most damage) is only reached if the hazard does not kill everyone; Bomberman's draw-on-simultaneous-crush shows the case should be defined: the GDD describes a "closing" hazard for four maps but not whether it kills outright, nor what happens when it kills the last two together.
- Telegraph: Bomberman uses an explicit message before the closure; the GDD's hazard starts at 30 s with no stated warning cue. Worth specifying (screen cue, audio), since 15 s of hazard in a 45 s round is short.
- Fortnite-style storms were not retrievable; do not rely on them.

### Gaps
- No Bomberman time-limit value, and no data on shrink timing relative to round length in Duck Game, Stick Fight, Gang Beasts or Bopl Battle.

## Weapon pickups and crates: spawn cadence, how many weapons is enough, joke weapons

### Takeaway
Retrievable sources confirm only that arena brawlers use periodic weapon drops and that joke weapons do not need balancing (Landfall quote about a different game). There is no sourced number for "how many weapons feels like enough in a first prototype".

### Cited Findings
- Stick Fight: weapons "appear periodically on the map and can be equipped mid-fight." — [Wikipedia: Stick Fight](https://en.wikipedia.org/wiki/Stick_Fight:_The_Game)
- Duck Game: reviewer describes each match as "a mad dash across the map to grab the best weapons" before devolving into a "feathery massacre". — [Gaming Trend](https://gamingtrend.com/reviews/insert-ducking-awesome-pun-here-duck-game-review/) (search summary)
- Boomerang Fu: power-ups from blue books, hosts can adjust how fast the books appear, players hold up to three. — [Wikipedia: Boomerang Fu](https://en.wikipedia.org/wiki/Boomerang_Fu)
- Samurai Gunn: three bullets per life. — [Wikipedia: Samurai Gunn](https://en.wikipedia.org/wiki/Samurai_Gunn)
- Landfall's Henriksson: they can have many weapons because "every single one of them doesn't need to be balanced and thought out"; "We can just add a bunch of cool ideas into weapons". (Context: Totally Accurate Battlegrounds.) — [Game Developer: Landfall](https://gamedeveloper.com/design/how-landfall-games-finds-the-fun-in-physics-engines)
- ROUNDS cards are rarity-tiered (common, rare, epic) and reviewers want more rare and epic ones after a couple of hours. — [Rounds Network](https://rounds.network/rounds-review-my-new-favorite-multiplayer-roguelike/)

### Inferences
- The GDD lists 12 weapons for the full design and "Rocket Party" makes every pickup a rocket launcher; Landfall's quote supports joke weapons as tolerable, but I have no sourced prototype count. The GDD's own principle (do not add content outside the stage) is not contradicted.

### Gaps
- No spawn cadence numbers (seconds between drops) for any game; no source on prototype weapon counts; Stick Fight/Duck Game wikis not retrieved.

## Session length and retention for same-room mobile party games in India and similar markets (Mini Militia, Ludo King, Among Us)

### Takeaway
I found no credible retention or session-length data for Mini Militia or Among Us in India. For Ludo King, figures conflict widely and mostly come from secondary summaries. Qualitative sources support local-hotspot play with friends as a driver of Mini Militia's reach.

### Cited Findings
- Mini Militia: described as a cultural phenomenon in India; over 100 million Google Play downloads; Kotaku's entry says people were introduced to it in school, hostels or at LAN parties; a TapTap fan piece says up to 12 players over local Wi-Fi hotspot made it the "college canteen" game (fan opinion, and conflicts with Apple's listing of up to 6 online players). — [Wikipedia mirror](https://wiki.riteme.site/wiki/Mini_Militia), [Sportskeeda](https://www.sportskeeda.com/esports/which-country-made-mini-militia-tracing-game-s-origin), [Kotaku](https://kotaku.com/games/mini-militia-doodle-army-2), [TapTap](https://www.taptap.io/id/post/10562029) (all via search summaries)
- Ludo King: a quick mode lasts five minutes; a traditional match 30 to 90 minutes; fourth in active users in India in the first three quarters of 2024; supports up to six players; no DAU, retention or same-room data on the page. — [Naavik](https://naavik.co/digest/ludo-king-takes-over-the-indian-mobile-games-market/)
- Ludo King session time (conflicting, via search summaries, pages not opened): about 15 to 16 minutes per day per player; about 45 minutes per user; daily time rose from 32 to 49 minutes during the 2020 lockdown. DAU before lockdown about 14 to 15 million, peaking at 51 million (developer account). — [PocketGamer.biz](https://www.pocketgamer.biz/interview/67033/how-a-small-indian-studio-got-10-million-daus/), [KPMG report](https://assets.kpmg.com/content/dam/kpmg/in/pdf/2021/06/digital-mobile-casual-gaming-in-india.pdf), [Wikipedia: Ludo King](https://en.wikipedia.com/wiki/Ludo_King)
- Among Us: in public games most dead players leave rather than wait (secondary, Sportskeeda above); no India-specific data.

### Inferences
- Ludo King's 5 minute quick mode versus 30 to 90 minute traditional play is a data point that a roughly 5 minute match (ours is about 4 to 5 minutes by the GDD's numbers) is a validated length for the Indian casual market. This is an inference from a feature, not from retention data.
- Same-room hotspot play is a plausible driver for Mini Militia; our "friends and cousins in one room" target has qualitative support but no figures.

### Gaps
- No Mini Militia session length, DAU or retention figure; no Among Us India data; no source for session length of same-room versus online play. The Ludo King numbers should not be quoted without checking the original sources (Gametion, Sensor Tower, KPMG).

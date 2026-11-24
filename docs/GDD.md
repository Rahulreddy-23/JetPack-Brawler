# Jetpack Brawler: Game Design Document

24 Nov 2026 · Rahul reddy

> Transcription note: this file was written from the document Rahul pasted into the build
> session on 24 Nov 2026. Tables were rebuilt from flattened text; no rule or number was
> changed. The phase diagram in "Build plan" was an image and is not in this file. Decisions
> made after this date are recorded in `docs/DECISIONS.md`, which wins over this file where
> they differ.

## Summary

Jetpack Brawler (working title) is a 2D jetpack arena shooter for 2 to 8 friends on Android,
built on 45-second rounds and one rule Mini Militia never had: the player who loses a round
picks a Chaos Card that changes the rules for everyone.

The design keeps what made Mini Militia a canteen classic (twin sticks, jetpacks, play over a
phone hotspot) and fixes what drove players away (hackers, pay-to-win purchases, forced ads,
long samey matches).

The fighters are junkyard robots built from household scrap, and a ten-fight solo campaign
against boss bots gives players something to do when friends are offline.

| Decision | Choice | Why |
|---|---|---|
| Platform | Android first | Largest friend-group reach in India; iOS can follow from the same project |
| Session | Five rounds of 45 seconds, about 5 minutes | Fits a break; nobody waits long after dying |
| Players | 2 to 8, bots fill empty slots | Small enough for stable netcode, big enough for chaos |
| Hook | Chaos Cards picked by the round's loser | Every match plays differently and the weakest player always has a say |
| Connection | Hotspot and Wi-Fi first, online room codes second | The hotspot session is where the fun is proven, and it costs nothing to run |
| Money | Cosmetics only, optional rewarded ads | Nothing bought changes a fight |
| Engine | Godot 4 with the netfox networking addon | Free, strong in 2D, ready-made prediction and lag compensation |
| Art | Junkyard robots in a flat doodle style, one character rig | Keeps the art load small enough for one person |

## Research

Mini Militia won on local multiplayer and lost its players through monetization, cheating and
neglect, and no 2D game has clearly taken its place.

### What made it work

| Ingredient | Why it mattered | Verdict |
|---|---|---|
| Twin-stick controls | One thumb moves, the other aims and fires; learnable in a minute (TapTap review) | Keep |
| Jetpack | Adds height, dives and escapes to a flat side-on map; the game's signature | Keep and extend |
| Hotspot play | Up to 12 players on local Wi-Fi with no data cost, against 6 online; reviewers call this the main reason it spread | Keep, make it the first thing built |
| Low-end friendly | Simple doodle graphics ran on any phone | Keep |
| Short respawns, small maps | A fight every few seconds | Keep, push further with rounds |
| Dual wield, mines, melee | Depth for players who stayed | Keep the depth, trim the list |

It passed 100 million installs on Google Play (Exodus report of the Play listing).

### Where it fell down

- Pay-to-win. After Miniclip's 2019 rework, App Store reviewers complained that loot boxes,
  premium currency and weapon upgrades favoured paying players (App Store listing).
- Hackers. Modded clients are the most repeated complaint in store reviews, with reports that
  the in-match report button did nothing in custom rooms.
- Forced ads. Review roundups describe frequent unskippable ads after matches (GameBrain
  summary).
- Lost features. Players asked for the old LAN play, custom servers and Capture the Flag to
  come back after updates changed or removed them.
- Slow updates. The latest iOS release is version 5.6.0 from 11 September 2024.
- Sameness. Deathmatch on the same maps with the same loadouts; nothing changes between match
  one and match fifty.

### The gap

Lists of "games like Mini Militia" mostly point to 3D shooters such as PUBG Mobile, Pixel Gun
3D and Modern Combat 5 (Beebom list). Those need good phones, mobile data and 20-minute
sessions. The 2D, same-room, five-minute slot is still open, but it is not empty:
Appsomniacs, the original studio, has relaunched Mini Militia Classic with 12-player Wi-Fi
play restored. The nostalgia slot is taken, so this game has to win on changing rules and
party play.

### Ideas worth borrowing

| Game | Idea | How it is used here |
|---|---|---|
| ROUNDS | The round's loser picks an upgrade card | Chaos Cards, but applied to everyone so nobody snowballs |
| Stick Fight | Rounds under a minute, random weapon drops, deadly maps | 45-second rounds, crate drops, one hazard per map |
| Duck Game | Instant restart, absurd weapons | Under 5 seconds between rounds; joke weapons beside serious ones |
| TowerFall | Catching and deflecting projectiles | Melee swing knocks grenades and rockets back |
| Brawl Stars | Three-minute mobile matches, generous aim assist | Session length target, optional aim assist for new players |
| Soldat | Movement skill separates good from great | Dash and wall-jump on top of the jetpack |

## Design pillars

Every feature has to serve at least one of these five rules, and none may break rule 4.

1. Fighting within 10 seconds. From tapping Play in a lobby to the first shot takes under 10
   seconds. No loadout screens between rounds.
2. Friends first. Joining a friend takes one tap on a hotspot or one six-character code
   online. Strangers are a later feature.
3. Chaos with rules. Surprises come from cards, crates and map hazards that everyone can see
   coming. They never come from lag or randomness nobody can read.
4. Nothing bought wins a fight. Every weapon, map, mode and card is free from the first
   launch.
5. Small enough to finish. One character rig and a small first release; the Build plan fixes
   the counts for each stage. Variety comes from rules, which are cheap, and not from content,
   which is expensive.

## World and story

The game is set in the Heap, a giant scrapyard where thrown-away household machines have
woken up and brawl every night for spare parts.

### Premise

Lightning hits an old transmission tower and the yard's junk comes alive. The bots call
themselves Scrappers. Each is built from whatever was lying around: a pressure cooker for a
body, a scooter headlamp for an eye, a ceiling fan for a hat.

Every night the yard's broken magnet crane runs the Scrap Cup, a brawl where the winner takes
the best parts. Nobody dies. A beaten bot bursts into nuts, springs and panels, and is bolted
back together for the next round.

### Why this theme fits the game

| The game needs | The theme gives |
|---|---|
| A jetpack that cannot stay on forever | A steam pack made from a pressure cooker: the gauge drops while flying, it whistles when empty, and pressure rebuilds on the ground |
| Rounds and respawns | Bots are rebuilt, so coming back makes sense |
| No blood or gore | Parts fly off; nothing is gory |
| Chaos Cards | The Crane's brain is faulty and it keeps changing the rules; the round's loser pulls its lever |
| Cosmetics to sell | Every bot is swappable junk: heads, bodies, steam packs |
| Art one person can make | Rigid metal parts need no bending limbs or cloth |
| Its own identity | Everyday household objects as fighters; no other mobile shooter looks like this |

### Cast

| Character | Role | Personality |
|---|---|---|
| Your Scrapper | The player, named and built by them | Newly awake, assembled from leftovers; speaks only through pixel eyes on a small screen face |
| The Crane | Host of the Scrap Cup and dealer of Chaos Cards | Pompous, forgetful, changes the rules halfway through a sentence |
| Radio | Commentator and tutorial guide; a cracked transistor radio | Excitable, calls fights like a cricket match |
| Big Crush | Reigning champion and final boss; the yard's car compactor | Silent, slow, patient |
| The champions | Nine fighters on the Cup ladder | One strong trait each; listed under Solo campaign |

### Story

The story is told in three comic panels before each solo fight, with no voice acting.

1. Waking up. Your Scrapper switches on with parts missing. Radio finds you and explains the
   Cup: beat a champion, win one of their parts.
2. The climb. You fight up the ladder. Each win adds a visible part to your bot, and the Crane
   keeps bending the rules against the newcomer.
3. Sunrise. Radio learns the Heap is to be cleared at dawn and Big Crush will flatten
   everything. Beating him jams the compactor and saves the yard. The Crane opens the Cup to
   everyone, which is the multiplayer game.

### Look and sound

- Colours: rust orange, teal paint, cream enamel and signal yellow, against a night sky with
  city glow.
- Lettering: hand-painted signboard letters and stencil numbers, like shop and lorry signs.
- Sound: clanks, springs and cooker whistles. The music is a junk percussion band of tins,
  pipes and horns.
- Emotes: shown as pixel faces on each bot's screen.

### Weapons in this world

| Weapon | Junkyard version |
|---|---|
| Pistol | Rivet gun |
| SMG | Nail gun |
| Assault rifle | Bolt thrower |
| Shotgun | Scrap blaster, fires a handful of nuts |
| Sniper | Antenna rifle |
| Rocket launcher | Festival rocket tube |
| Grenade launcher | Tin-can lobber |
| Flamethrower | Stove burner |
| Railgun | Welding beam |
| Minigun | Sewing-machine gun |
| Boomerang blade | Fan blade |
| Vortex grenade | Mixer bomb |

### Name ideas

Dabba Gang, Bolt Gang, Junk Jets, Robo Gully. All are short and easy to say aloud; Scrap Brawl
and Scrap Riot were dropped as hard to pronounce. Rust on its own is the name of a well-known
survival game, so it is not usable; Rusty Gang or Rusty Cup keep the word. Scrap Cup stays as
the name of the tournament inside the game. A quick web search found no game with any of
these four names, which is not a Play Store or trademark check. CATS: Crash Arena Turbo Stars
is a large junk-robot game on Google Play, so the art and name should stay clearly apart from
it.

## Core gameplay

A match is five 45-second elimination rounds on a small arena, scored on points, with
twin-stick shooting and three movement tools: jetpack, dash and wall-jump.

### Controls

The default layout is two sticks and two buttons, so a new player can join in within a
minute. Dash and wall-jump are optional skills: a first-timer must be able to win rounds with
the two sticks alone, and the playtest checks this.

- Left stick: run; push up to fire the jetpack; push down to drop through thin platforms.
  Pushing away from a wall while sliding on it does a wall-jump.
- Right stick: aim; drag past the outer ring to fire. Releasing a charged weapon (antenna
  rifle, lobber) fires it. A quick tap on the right stick swings a melee hit, which also
  knocks back bombs and rockets. Holding the stick always shoots, even at point-blank range.
- Dash button: a short burst in the direction of the left stick.
- Gadget button: tap to place or throw the held gadget.
- Weapon icon: tap to swap between the two weapon slots. Walking over a weapon picks it up.
- Aim assist: light snapping toward the nearest enemy, on by default for new players and
  switchable off.
- Settings: button size and position are adjustable, and a separate melee button can be
  turned on for experienced players. There is no crouch.

### Movement

The jetpack cannot stay on forever. As in Mini Militia, it burns fuel in the air and refills
on the ground; here it is a steam pack with a pressure gauge that whistles when empty. The
dash is new: it has one charge, works in mid-air, and gives a brief window where bullets
miss. Sliding down a wall slows the fall and allows a jump off it. Together these let a
skilled player change direction three times before landing, which is where the skill ceiling
comes from.

### Combat

Everyone spawns with a pistol. Better weapons appear at fixed map spots and in crates that
drop from the sky every 10 seconds. Health does not regenerate; medkits drop in crates. Each
knockout repairs 20 health for the attacker, so fighting pays better than waiting for others
to weaken each other, and the closing hazard cuts hiding short.

### Bombs and traps

Every player has a gadget button, starts each round with one Cooker Bomb, and can carry two
gadgets picked up from crates.

| Gadget | What it does | Best use |
|---|---|---|
| Cooker Bomb | 3-second timer, large blast; can be punched or shot away | Throw it, or knock an enemy's bomb back at them |
| Magnet Bomb | Sticks to walls, crates and bots; 2-second fuse | Tag a fleeing enemy |
| Blinker Mine | Arms after 1 second, explodes when a bot comes near | Guard a weapon spawn or a narrow gap |
| Spring Plate | Launches whoever steps on it | Throw enemies into a hazard, or use it as your own jump pad |
| Oil Slick | Slippery patch for 8 seconds; catches fire | Pair with the stove burner |
| Magnet Trap | Holds a bot for 1.5 seconds and pulls the weapon from its hands | Set up an easy shot for a teammate |
| Decoy | A copy of your bot that stands still and explodes when shot or touched | Bait snipers |
| Glue Patch | Slows movement and blocks the dash | Trap someone as the hazard closes in |

- Each player can have two traps placed at once; placing a third removes the oldest.
- Traps blink faintly in their owner's colour, so everyone can see them. Invisible traps feel
  unfair.
- Traps can be shot to destroy them, hurt their owner too, and are cleared when the round
  ends.
- The first six ship at launch; Decoy and Glue Patch follow in an update.

### Match flow

1. Lobby: host picks mode and map, or leaves both on random.
2. Round starts after a 3-second countdown, players spawn spread out.
3. At 30 seconds the map hazard closes in, so no round passes 45 seconds. If more than one bot
   is still standing at 45 seconds, the one with the most health wins the round, and equal
   health goes to the most damage dealt.
4. The last bot standing wins the round. Points: 2 for every knockout with no cap, plus 3 for
   first place, 2 for second and 1 for third. A hunter with three knockouts outscores a winner
   who hid all round, so finding a safe corner and sneaking the last hit does not pay.
5. A 2-second slow-motion replay of the final knockout plays, then the player with the fewest
   points picks one of three Chaos Cards on a 5-second timer. No tap means a random pick. If
   players are tied for fewest points, the one knocked out earliest in that round picks.
6. After five rounds the most points wins. A tie is settled by one sudden-death round. One tap
   for a rematch.

Points are used because five rounds among eight players would often tie on round wins alone.
A first-to-5-wins format could run to 33 rounds with eight players, so it is not offered.
Hosts can choose 3, 5 or 7 rounds and 45, 60 or 90 seconds in custom rooms.

### Starting values to tune

These are first guesses for the prototype, to be changed by playtesting.

| Setting | Starting value |
|---|---|
| Health | 100, no regeneration |
| Time to kill, bolt thrower at mid range | About 1 second; also test 1.5 seconds with first-time players |
| Jetpack fuel | 2.5 seconds of thrust, full refill in 2 seconds on the ground |
| Dash | 1 charge, 3-second cooldown, 0.15 seconds of bullet immunity |
| Round cap | 45 seconds, hazard from 30 seconds |
| Rounds per match | 5 |
| Gap between rounds | About 8 seconds: a 2-second replay, a 5-second card pick, a 1-second start |
| Arena size | About 2 screens wide, 1.5 screens tall |

## Game physics and feel

The fun comes from one rule: everything pushes. Every hit, blast and gadget moves bots
around, and the arena punishes whoever gets moved to the wrong place.

### Three layers of physics

| Layer | What it covers | How it is built | Why |
|---|---|---|---|
| Bot movement | Running, jetpack, dash, wall-slide, knockback | Hand-written movement on the network tick, not the engine's rigid-body physics | It must feel identical on every phone and be predictable enough for the netcode to replay |
| Gameplay objects | Bullets, bombs, crates, dropped weapons, spring plates | Simple hand-written motion (gravity, bounce, push), simulated by the host | The host decides where a bomb lands, so all players see the same result |
| Show physics | Parts flying off a broken bot, shell casings, debris, dust | The engine's rigid-body physics, run separately on each phone | Looks chaotic and costs nothing to sync because it never affects the fight |

The third layer is where the slapstick lives: a beaten bot bursts into bouncing parts. It can
be as wild as we like because it changes no outcome.

### Movement feel

- Jetpack: thrust builds over about 0.15 seconds instead of switching on instantly, so short
  taps give small hops and holding gives a climb. Fuel runs out; falling is faster than
  rising.
- Air control: full left and right steering in the air. Momentum carries, so a dash into a
  jetpack burn flings the bot further.
- Dash: a fixed short distance in a fixed time, then normal momentum resumes.
- Forgiveness: a jetpack or dash input pressed up to 0.1 seconds early still counts, and a bot
  that has just left a ledge can still wall-jump for 0.1 seconds. Players never notice these,
  but controls feel sharp because of them.

### Knockback is the core

| Source | Push | Fun it creates |
|---|---|---|
| Bolt thrower, nail gun | Tiny nudge per hit | Sustained fire walks a flying bot off course |
| Scrap blaster | Strong push on the target and recoil on the shooter | Fire downward for an extra hop; blast enemies off ledges |
| Melee | Strong push; sends bombs and rockets back | The best close-range save in the game |
| Rockets and bombs | Large push that fades with distance from the blast | Rocket-jumping; throwing three bots into the lava at once |
| Spring Plate | Launch straight up or along its angle | Trap, or a jump pad for yourself |
| Vortex and magnets | Pull instead of push | Drag a hiding bot into the open |

- Push grows as health drops. A bot at low health flies about twice as far from the same hit.
  Fights end with a bot sailing across the arena, not with a health bar quietly reaching
  zero. This is an experiment for the first playtest.
- The arena finishes the job. Lava, crushers, the closing hazard and the map edge turn a push
  into a knockout, and the knockout is credited to whoever pushed.
- Chaos Cards multiply it. Low gravity, bouncing bullets and slippery floors all change these
  same numbers, so each card makes the physics feel new.

### Surfaces

Normal floor grips fully. Oil and the Ice Rink card cut grip so bots slide and cannot stop
quickly. Conveyor belts carry bots and loose objects. Thin platforms can be dropped through.

### Impact feel

- Two or three frozen frames on a heavy hit, so it lands with weight.
- Screen shake sized to the blast, with a setting to reduce it.
- A brief flash and a clank on every hit, and a different sound when a hit knocks a part off.
- Slow motion on the final knockout of a round.

### Starting values

Distances are in bot heights. All are first guesses to tune in phase 1.

| Setting | Starting value |
|---|---|
| Run speed | 6 per second |
| Jetpack climb speed | 7 per second at full thrust |
| Fall speed limit | 12 per second |
| Dash | 3 in 0.15 seconds |
| Push from a bolt-thrower hit | 0.1 |
| Push from a scrap blast at close range | 1.5, and 1 of recoil on the shooter |
| Push from melee | 2.5 |
| Push at the centre of a rocket or bomb blast | 5, fading to nothing at 3 from the centre |
| Extra push at low health | Up to double below 25 health |

### How we know it is fun

Phase 1 has no enemies worth fighting yet, so the test is the movement and the push alone:
flying around one map and knocking a dummy bot into a hazard should be enjoyable for 10
minutes. If it is not, tune these numbers before building anything else.

## The twist

Four additions make this more fun than Mini Militia with friends: Chaos Cards, a job for dead
players, shareable final kills, and a fair shop.

### Chaos Cards

After each round the last-placed player is shown three random cards and picks one. The card
changes the rules for every player. One card is active at a time; each new pick replaces the
last. A picked card leaves the pool for the rest of the match, so nobody can force the same
rule every round. Each card shows a large icon and a two-word name so it can be read in a
second. A later Maximum Chaos mode can stack cards that are known to work together.

The loser gets the choice so the weakest player in the room always has power over the next
round. Because the card affects everyone, the leader gets no lasting advantage and nobody
snowballs.

| Card | Effect |
|---|---|
| Moon Boots | Gravity halved |
| Rubber Rounds | Bullets bounce twice |
| Rocket Party | Every weapon pickup is a rocket launcher |
| Glass Cannon | Double damage, half health |
| Free Fuel | Unlimited jetpack, no dash |
| Butterfingers | Weapons are dropped when hit by melee |
| Big Heads | Heads are twice as large and headshots count |
| Ice Rink | Floors are slippery |
| Body Swap | All players trade positions every 20 seconds |
| Sudden Death | One hit kills, pistols only |
| Boom Box | Players explode when eliminated |
| Tiny Town | Everyone is half size and 30% faster |

The table is the pool to choose from: 4 cards in the prototype, 10 at first release, 20 in
the full design. Each card is a small change to shared settings (gravity, damage, spawn
table), so a new card is quick to code; the real cost is effects and playtesting.

### A job for dead players

A knocked-out bot becomes a Scrap Ghost until the round ends, which with 45-second rounds is
never more than about 40 seconds. A ghost can fly anywhere and has small powers that stir the
fight without deciding it:

- Drop one Spring Plate per round.
- Nudge loose objects such as crates and dropped weapons.
- Collect scrap bolts scattered around the arena, which count as coins.
- Send emotes.

Ghosts cannot damage anyone directly. Players who dislike elimination can play Classic Brawl,
which has respawns.

### Shareable final kills

At first release the match-winning knockout replays in slow motion inside the game, with
player names and the active card on screen, and players can capture it with the phone's own
screen recorder. A one-tap share button that exports a video clip is a separate engineering
feature and comes after launch. Clips help marketing but cannot be relied on as the main
channel.

The share feature at first release is a match summary card. One tap at the end of a match
sends an image to WhatsApp showing the funny awards and the rivalry score between friends. It
costs far less to build than video export and is made to start arguments in group chats.

### Compared with Mini Militia

| | Mini Militia | Jetpack Brawler |
|---|---|---|
| Match shape | Timed deathmatch, constant respawn | Elimination rounds of 45 seconds, plus a respawn mode |
| Variety | Same rules every match | Rules change every round through cards |
| Falling behind | The leader keeps leading | Last place picks the next card |
| After dying | Respawn timer | Scrap Ghost with small powers |
| Movement | Jetpack | Jetpack, dash, wall-jump, melee deflect |
| Paying | Weapons and upgrades for sale | Cosmetics only |
| Ads | Forced after matches | Optional, rewarded only |

## Solo campaign

The Scrap Cup ladder is ten one-on-one fights played offline, each against a champion with
one signature trick, ending with Big Crush.

- Each fight lasts 2 to 3 minutes. The champion has a health bar with two or three phases.
- The player gets three rebuilds per fight.
- Winning awards one of that champion's parts as a cosmetic.
- Each fight gives up to three bolts: one for winning, one for beating a par time, one for
  using no rebuilds.
- Beaten champions join the bot pool in multiplayer with the same behaviour, so the same work
  fills empty seats in friend matches.

| # | Champion | Built from | Signature trick | How to beat it | Teaches |
|---|---|---|---|---|---|
| 1 | Dabba | A stack of tiffin tins | Splits into three small tins when damaged | Shoot each tin | Moving and aiming |
| 2 | Fanatic | A ceiling fan | Spinning blades block bullets from the sides; it hovers | Attack from above or below | Jetpack control |
| 3 | Whistle | A pressure cooker | Builds pressure, then vents a ring of steam | Dash away on the whistle, hit it while it cools | Dash timing |
| 4 | Meter | An auto-rickshaw | Charges the full width of the arena and leaves oil behind | Wall-jump over it; it stuns itself on the wall | Wall-jump |
| 5 | Static | An old television | Turns invisible and leaves fake copies | The real one flickers; mines reveal it | Mines, reading the screen |
| 6 | Mixie | A mixer-grinder | A vortex pulls in the player and loose items | Throw a bomb into the vortex to jam it | Bombs |
| 7 | Tangle | Fairy lights and a fuse box | Lays tripwires and electrifies floor sections | Shoot the fuse boxes; cross on Spring Plates | Traps |
| 8 | Nut and Bolt | Twin scooter-part bots | One shields, one snipes; the survivor rebuilds its twin in 5 seconds | Break both within 5 seconds | Target priority |
| 9 | Lifter | A salvage magnet | Pulls the weapon from your hands and bends bullets back | Melee and bombs while the magnet recharges | Melee and gadgets |
| 10 | Big Crush | The car compactor | Arena walls close in; three phases reuse earlier tricks while the Crane deals a Chaos Card each phase | Everything learned so far | The whole game |

All ten champions share one bot brain for moving, aiming and dodging; each adds a single
trick on top. After launch, a hard mode replays the ladder with Chaos Cards active, and new
champions arrive in updates.

## Modes, maps and weapons

The full design has four multiplayer modes, the solo campaign, four maps and twelve weapons,
and the Build plan says which ship first; everything else waits until players ask for it.

### Modes

| Mode | Rules | When |
|---|---|---|
| Chaos Cup | The signature mode: five 45-second elimination rounds, a Chaos Card after each | Prototype |
| Classic Brawl | 5 minutes of free-for-all with respawns, most knockouts wins; the Crane can deal a new card every minute | Prototype |
| Bomb Tag | One player carries a ticking bomb and passes it with a melee hit; it explodes every 20 seconds | First release |
| Scrap Cup (solo) | Champion fights, offline; see Solo campaign | First release |
| Practice | Any multiplayer mode against bots, offline | First release |
| Team Rounds | Chaos Cup in teams of 2, 3 or 4 | First update |
| Boss Raid | Four friends against one giant champion, reusing the campaign bosses | Later |
| Capture the Flag | 5-minute match with respawns | Later |
| Survival | 1 to 4 players against waves of bots | Later |

### Maps

Each arena is about two screens wide so eight players find each other within five seconds,
and each has one hazard that closes the round.

| Map | Layout | Closing hazard |
|---|---|---|
| Terrace Tanks | Rooftops with water tanks and dish antennas; open sky, long sight lines | Monsoon gusts push bots off the edges |
| Recycling Plant | Tight corridors, conveyor belts, crushers | Walls close in from both sides |
| Smelter | Tall and vertical, favours the jetpack | Molten metal rises from the floor |
| Magnet Yard | An overhead magnet gives the centre low gravity | The magnet strengthens and pulls bots up toward the grinder |

### Weapons

| Weapon | Role | Quirk |
|---|---|---|
| Pistol | Starting sidearm | Unlimited ammo |
| SMG | Close range spray | Fast, inaccurate while flying |
| Assault rifle | All-rounder | The baseline everything is tuned against |
| Shotgun | Close burst | Recoil pushes the shooter back; works as a second dash |
| Sniper | Long range | Charge to fire; shows a laser line while charging |
| Rocket launcher | Area damage | Rockets can be knocked back with melee |
| Grenade launcher | Indirect fire | Bouncing rounds |
| Flamethrower | Area denial | Leaves fire on the ground for 3 seconds |
| Railgun | Pierces walls | Two shots only |
| Minigun | Suppression | Spin-up time; too heavy to jetpack with |
| Boomerang blade | Skill shot | Returns to the thrower and can hit on the way back |
| Vortex grenade | Crowd control | Pulls players and loose weapons to one point |

## Playing with friends

There are three ways to play together, built in this order: same room on a hotspot, online by
room code, and public matchmaking last.

| Way to play | How it works | Needs |
|---|---|---|
| Hotspot or Wi-Fi | One phone hosts; others on the same network see the room and tap to join, with a QR code or short number code as the fallback when auto-discovery fails | No internet, no account |
| Online room | Host gets a six-character code and a WhatsApp link; tapping the link installs the game if needed and opens the lobby | Internet; no account |
| Quick match | Matched with strangers of similar skill | Dedicated servers; added only after launch numbers justify it |

- Bots fill empty slots at four difficulty levels, from Easy to Very Hard, so two friends can
  still have an eight-player brawl. Easy bots react slowly, miss often and walk into traps,
  so a first-timer can win. Medium bots aim steadily and use the jetpack well. Hard bots dash
  out of fire, lead moving targets and lay traps. Very Hard bots react at the speed of a top
  human player, knock bombs back, punish every mistake and should beat most players. At every
  level bots follow the same rules as players: the same health, no seeing through walls and
  no reactions faster than a human can manage.
- If the host leaves: the match ends cleanly and any player can tap Host Rematch. Moving a
  live match to another phone is left out of the first release because it is costly to build
  and matches last only five minutes.
- Emote wheel: eight quick taunts and cheers, usable alive or as a ghost. No text chat at
  launch, which also avoids moderation work.
- End-of-match awards: funny titles such as "Most self-inflicted deaths" and "Jetpack hog"
  give the room something to laugh at.
- Rivalry record: the game remembers head-to-head results with each friend ("You 14, Arjun
  9") and shows it in the lobby.
- One-tap rematch keeps the same room, mode and players.

Hotspot play is what sets the game apart in hostels, trains and classrooms. The WhatsApp room
link is how it spreads, because cheap mobile data means most friend groups now play from
separate places. Both ship in the first release.

## Progression and monetization

All gameplay is free and unlocked from the first launch; the game earns from cosmetics and
optional rewarded ads.

### Progression

- Playing earns XP and coins. Levels unlock cosmetics, never weapons or stats.
- Cosmetic slots: character skin, hat, jetpack trail, elimination effect, emotes, victory
  pose.
- Weekly challenges ("win a round with the boomerang") give coins and a reason to return.

### Build your own Scrapper

Every player assembles their own bot from four choices, and this is the centre of both
progression and the shop.

| Slot | Examples |
|---|---|
| Head | Television, radio, headlamp, kettle |
| Body | Cooker, tiffin stack, engine block |
| Steam pack | Cooker pack, twin fans, festival rockets |
| Paint | Any colour, plus stickers and rust patterns |

- New players start with three heads, three bodies and three packs, which already gives 27
  different bots.
- Parts are won from champions, earned through levels, or bought in the shop.
- All parts are cosmetic. Every bot has the same hit area, speed and health whatever it looks
  like.

### Revenue

| Source | What the player gets | Notes |
|---|---|---|
| Cosmetic shop | Skins, trails, emotes for coins or gems | Rotates weekly |
| Supporter pack | One-time purchase: a skin set and double coins | A low price point for players who want to pay once |
| Rewarded ads | Watch by choice for bonus coins or a free cosmetic roll | Never shown mid-session, never forced |
| Season pass | Cosmetic track over 8 weeks | After launch, once there are enough cosmetics to fill it |

This model earns less per player than selling power. The bet is that fairness plus shared
clips bring far more players, and running costs stay close to zero while friends host their
own matches. Prices are an open question to test during soft launch.

## Art and audio

The look is junkyard robots drawn as flat doodle art with thick outlines and big heads,
chosen because one person can produce it consistently and because the fun comes from motion
and effects, which are code.

- One character rig. A single skeleton with about eight animations (idle, run, fly, dash,
  wall-slide, melee, hit, eliminated). Arms are driven by the aim stick in code. Every skin
  is a swap of head, body and jetpack sprites on that rig, so a new skin is three small
  images.
- Maps from tiles. About 40 tiles per map plus three parallax background layers. No
  hand-painted levels.
- Juice over detail. Screen shake, a few frames of freeze on a hit, muzzle flashes, shell
  casings, dust on landing, slow motion on the final kill. These make a simple game feel
  expensive and need no artist.
- Readable at phone size. Each player has a strong outline colour; bullets and explosions are
  brighter than anything in the background.
- One source for art. Either one consistent paid asset pack or one freelance artist for the
  character sheet and UI. Mixing packs is what makes a game look cheap.
- Audio. Licensed sound packs for weapons and impacts, one menu track, two battle loops, and
  a short announcer set ("Round one", "Final kill").

## Tech approach

Build in Godot 4 with a server-authoritative model, where one phone acts as the server for
friend matches and dedicated servers arrive only with public matchmaking.

### Engine and netcode

- Godot 4. Free, open source, strong 2D tooling and Android export.
- netfox addon. An MIT-licensed set of Godot 4 addons covering synced timing, interpolation,
  and client-side prediction with server reconciliation; its noray companion handles
  connecting players across home routers (netfox on GitHub).
- Shooter-style networking, not fighting-game rollback. Each phone predicts its own player
  instantly and shows other players slightly in the past. The server decides hits, damage,
  ammo and pickups.
- Simulation at 30 ticks per second, 8 players maximum, which keeps data use low enough for
  mobile networks.
- Chaos Cards are server settings. A card changes shared numbers (gravity, damage, spawn
  table) on the server, and the server sends each change to every phone with the exact tick
  it starts on.

### Three connection setups

| Setup | Who is the server | Cheating exposure | Running cost |
|---|---|---|---|
| Hotspot | The host's phone, found by local network broadcast | Friends in one room; not a concern | None |
| Online room | The host's phone, reached through noray | The host phone checks every player's movement, firing and pickups; only the host itself goes unchecked | One small relay server to start; measure real capacity and data use in phase 4 |
| Quick match | Dedicated headless Godot server in an India region | Low; server owns all results | Scales with players; deferred |

### Targets

- 60 frames per second on a budget Android phone with 3 to 4 GB of memory, held through a
  20-minute session without overheating or heavy battery drain.
- Download under 80 MB.
- Playable up to 150 ms ping.
- No backend at launch beyond the relay. Purchases restore through Google Play; unlocks are
  saved on the phone, with optional Google Play Games cloud save.

### To verify in the first week

netfox's example projects were written for Godot 4.1. Before building any weapon or boss, put
two Android phones on one hotspot and check three things. First, that netfox syncs movement
on the current Godot release. Second, that the phones find each other: auto-discovery can be
unreliable on some Android hotspots, so build the QR or code fallback at the same time.
Third, that the sticks, jetpack and dash are comfortable for two thumbs. Also confirm how a
WhatsApp link can carry a room code through a Play Store install.

## Build plan

Build in five phases and stop at each gate; the phase 2 hotspot playtest is the real test of
the idea, and it comes before any online or shop work.

(The phase diagram from the original document is not reproduced here; see the transcription
note at the top.)

Week counts assume part-time solo work and are rough. If four friends on a hotspot do not ask
for another round at the end of phase 2, change the core before building anything else.

The solo campaign is not in the diagram. It needs no networking, so the first champion,
Dabba, is built in phase 1 as the test of whether the game is fun alone. This matches the one
champion in the prototype column below; the others wait until the hotspot gate is passed.
Budget about two part-time weeks per champion including its comic panels: roughly 20 weeks
for ten champions, 10 for five and 6 for three.

### Scope by stage

The rest of this document describes the full design. Only the prototype column is built
before the hotspot playtest, and nothing moves to the next column until its gate is passed.

| Feature | Prototype | First release | Full design |
|---|---|---|---|
| Maps | 1 | 3 | 4 |
| Weapons | 4 | 8 | 12 |
| Gadgets | 2 | 4 | 8 |
| Chaos Cards | 4 | 10 | 20 |
| Champions | 1 | 5, ending with Big Crush (proposed) | 10 |
| Players per match | 4 | 8 | 8 |
| Multiplayer modes | 2 | 3 | 4, then more |
| Scrapper parts | 3 | 20 | Grows with updates |
| Connection | Hotspot | Hotspot and online rooms | Adds quick match |
| Shop | None | Cosmetics and rewarded ads | Adds season pass |
| Final-kill clips | None | In-game replay and a shareable summary card | One-tap video share |

### Who builds and checks it

| Role | Model | Job |
|---|---|---|
| Lead and phase reviewer | Claude Fable, in Claude Code | Plans each task, delegates, and reviews the whole phase against this document before a gate |
| Implementer | Claude Sonnet | Writes the code for one task at a time |
| Independent code reviewer | Claude Opus | Reviews every change without seeing the implementer's reasoning |
| Second-opinion reviewer | ChatGPT | Looks for design, gameplay and architecture issues the Claude models may share a blind spot on |
| Bug and security hunter | Gemini | Hunts crashes, netcode trust holes and security mistakes, and nothing else |
| Playtester and decision maker | Rahul | Tests on real phones and decides every gate |

## Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| Real-time netcode | The hardest part of the project for one developer | Hotspot first, 8-player cap, netfox instead of custom code |
| Empty online lobbies | A new game has too few players for matchmaking | Friend rooms and bots at launch; quick match deferred |
| Art quality | Inconsistent art sinks store conversion | One rig, one art source, effects carry the feel |
| Low revenue per player | Cosmetics earn less than selling power | Near-zero running costs; shared clips for growth |
| Cheating online | It ruined Mini Militia's public games | Server decides results; dedicated servers before any ranked play |
| Scope creep | Cards, modes and weapons are all tempting to add | Counts are fixed per stage in Scope by stage; nothing is added to a stage once it starts |

## Open questions

- [ ] Android only at launch, or iOS as well?
- [ ] How many hours a week can go into this? The week counts above scale with the answer.
- [ ] Is the main audience friends in the same room, or friends in different cities? If the
  second, online rooms move ahead of the party layer.
- [ ] Theme: junkyard robots chosen (see World and story). Confirm or change it before any art
  is bought.
- [ ] Final name. "Jetpack Brawler" is a placeholder and has not been checked on the Play
  Store.
- [ ] Budget for art and for the relay server.
- [ ] Champions at first release: ten, five, or three (Dabba, Whistle, Big Crush)? Five is in
  Scope by stage; three is the safest, and the rest arrive in updates either way.
- [ ] Age rating: complete the Google Play content questionnaire early; cartoon violence and
  purchases both affect the result.

## Sources

- Mini Militia - Doodle Army 2, App Store listing: features, version history, purchases,
  player reviews.
- TapTap review of Mini Militia: what made the game popular, local and online player counts.
- netfox on GitHub: addon features, licence, Godot version notes.
- Linked in the text from search listings, not read in full: the Exodus report, GameBrain
  summary and Beebom list.
- Notes on ROUNDS, Stick Fight, Duck Game, TowerFall, Brawl Stars and Soldat are from general
  knowledge of those games.
- Mini Militia Classic on APKMirror and its App Store listing, from search listings: the
  Appsomniacs relaunch and 12-player LAN play.

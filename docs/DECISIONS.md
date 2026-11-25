# Decisions

Decisions Rahul made after the GDD was written. Where this file and `docs/GDD.md` differ,
this file wins.

## 24 Nov 2026

1. Phase split of the prototype (the GDD's phase diagram was not available):
   - Phase 1: project and netfox setup; synced movement (run, jetpack, dash, wall-jump) with
     touch sticks and join-by-IP on one network; knockback with 4 weapons, melee, 2 gadgets,
     a dummy bot and one hazard map; the Dabba fight.
   - Phase 2: rounds, scoring, Chaos Cards, 4 players, bots, Classic Brawl, hotspot discovery
     with a code fallback. Ends at the hotspot playtest gate.
2. Prototype content:
   - Map: Smelter.
   - Weapons: rivet gun, bolt thrower, scrap blaster, festival rocket tube.
   - Gadgets: Cooker Bomb, Spring Plate.
   - Chaos Cards: Moon Boots, Glass Cannon, Free Fuel, Ice Rink.
3. Round timing: a 3-second countdown before round 1 only. Between rounds: 2-second replay,
   5-second card pick, 1-second start (about 8 seconds). The GDD's "under 5 seconds between
   rounds" line does not apply.
4. Device testing: Rahul has two Android phones and a cable. Android debug export is set up
   in the first task.

5. Melee button: a separate melee button is shown by default. The quick tap on the aim stick
   still swings a melee hit as well. This changes the GDD, which offered the button only as
   an option for experienced players. Reason: the research found no game that uses
   tap-to-melee, and players coming from Brawl Stars expect a tap on that stick to shoot.

6. Product owner: Rahul told the lead to act as product owner and take the decisions on what
   the independent reviewers (branches `dev` and `geminiceo`) raise, and on open design
   questions. Still Rahul's alone: the game's name, anything that costs money, publishing,
   the number of bosses in the first release, and whether a gate is passed.

7. Health bars (25 Nov 2026): a bot's health bar appears above it only while its health is
   changing, for every bot alike, and disappears again shortly after. The lead had proposed
   a bar that is always shown, because the GDD does not say how a player reads another
   bot's health and the low-health push cannot be judged without it; Rahul chose to show it
   only on a change. The fill changes colour below 25 health, where the extra push starts. How
   long it stays after a change is a first guess in the config (1.5 seconds).

## Product owner decisions (taken by the lead under decision 6; Rahul can overrule any)

- Card pool: the prototype keeps 4 Chaos Cards. A picked card leaves the pool, and when fewer
  than three cards remain the pool is refilled with the picked cards except the one active
  now. The GDD's "leaves the pool for the rest of the match" cannot work with 4 cards and 4
  picks.
- Who picks the card: the player with the fewest points in the match so far, as Match flow
  says. "Last-placed" in The twist means the same thing.
- Last bots knocked out together by the hazard: the 45-second rule applies to them (most
  health just before, then most damage dealt in the round).
- Champions in multiplayer: a beaten champion joins the bot pool as a normal bot that wears
  the champion's look and follows player rules. Champion tricks stay in the solo fights.

- Push window: a bot that has just been pushed keeps that push for a short window set in
  the config, during which ground braking and steering are reduced. Without it a grounded
  bot stops almost at once and knockback, the core of the design, would not read. Raised by
  the movement research and by the geminiceo audit.
- Order inside phase 1: Dabba (task 1.6) is built last, after Rahul has played the
  movement, knockback and hazard sandbox on phones. Touch controls get a phone test as soon
  as task 1.1 is merged, before more buttons are added.

## Lead's calls (not Rahul's decisions; correct them if wrong)

- Phase 1 uses grey-box shapes only. No art is bought or imported.
- Solo play runs as a host with no clients, so there is one movement code path.
- Trades: when two bots knock each other out on the same tick, both are out, each is credited
  with the other's knockout, and neither gets the 20-health repair. The GDD does not cover
  this; without a rule the result depended on which hit the host processed first.
- Push numbers are distances (25 Nov 2026): the GDD's push table gives distances in bot heights,
  and the code now moves a bot that far on flat ground with a neutral stick (architecture D10).
  The earlier reading, each number a speed times 2, moved a grounded bot a fifth of the design
  distance. The low-health multiplier multiplies the distance, so 0 health is twice as far.
  Distances add across ticks as they do within one (30 bolts of 0.1 move a bot 3.0). In the air a
  push carries further than on the ground (about five times with the present brakes), and a
  blast lifts the bot so its sideways travel follows the air figures; judge on phones, the knob
  is push_window_control (lower it and pushes carry less in the air, with a longer window).
- "Up to double below 25 health" is read as: push multiplier 1 at 25 health or more, rising in
  a straight line to 2 at 0 health.
- The hazard's 30 seconds and the 45-second cap are counted from the end of the countdown,
  not from its start.
- Push numbers are distances, as the GDD says: on flat ground with a neutral stick a push of
  P moves the bot P bot heights, and in the air it carries further because air braking is
  weaker. The low-health multiplier applies to the distance, so a bot at 0 health goes
  twice as far. Until 25 Nov 2026 the code read the numbers as speeds, which gave about a
  fifth of the distance on the ground and three to four times, not twice, at low health;
  the phase audit found it and the correction is in progress.
- Knockout credit lasts 3 seconds after the last hit or push (first guess; not in the GDD).
- Hit freeze holds the picture of the bot that was hit for two or three frames, not the whole
  screen. Freezing the whole screen needed a GPU read-back on every heavy hit, which is a
  hitch risk on budget phones, and it also froze the touch sticks. The simulation never
  pauses either way.
- Wall-jump needs a wall-slide first (falling, touching the wall, stick pushed into it), plus
  the 0.1-second grace after leaving the wall, and its speeds are tuned so that jumping off
  one wall and steering back to it gains no height. Without this a bot could climb a single
  wall forever with an empty tank at nearly jetpack speed.
- Run speed follows how far the stick is pushed, so pushing nearly straight up for the
  jetpack does not also run sideways at full speed.
- Speed leaving a dash is 10 bot heights per second (first guess; the GDD only says momentum
  resumes). Plain run speed would not give the dash-into-jetpack fling the GDD describes.
- The Smelter has a ceiling. One tank of fuel climbs further than the arena is tall, so
  without it bots would leave the map.
- netfox carries one small local patch, recorded in `addons/NETFOX_PATCHES.md` once it
  lands, that bounds the tick accepted on incoming packets.
- netfox diff states are turned off for the prototype. Experiment E1 showed that with them
  on, a phone can keep a wrong value (for example another bot's health) indefinitely; with
  them off every trace matched. The cost is about seven times the data (roughly 78 KB/s per
  player with 4 bots), which is fine on a hotspot and must be revisited before online rooms.
- Renderer: Compatibility (OpenGL), as the Godot 4.7 documentation recommends for low-end
  phones and 2D.
- The host alone decides hits, damage and knockouts, as the GDD's Tech approach says. Each
  phone predicts only its own bot's movement and the look of its own shots.

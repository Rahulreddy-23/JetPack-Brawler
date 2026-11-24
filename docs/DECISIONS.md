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
- "Up to double below 25 health" is read as: push multiplier 1 at 25 health or more, rising in
  a straight line to 2 at 0 health.
- The hazard's 30 seconds and the 45-second cap are counted from the end of the countdown,
  not from its start.
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
- Renderer: Compatibility (OpenGL), as the Godot 4.7 documentation recommends for low-end
  phones and 2D.
- The host alone decides hits, damage and knockouts, as the GDD's Tech approach says. Each
  phone predicts only its own bot's movement and the look of its own shots.

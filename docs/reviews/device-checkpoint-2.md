# Device checkpoint 2: the knockback sandbox on two phones

For Rahul. This is the play test behind the phase 1 gate: is flying around and knocking a
dummy bot into the hazard fun for 10 minutes, and does it stay in sync between two phones.
It is not the gate itself; you decide that afterwards.

Build: `builds/jetpack-brawler-debug.apk`, made from `main` at `24f0224` on 25 Nov 2026,
21:01. 28.6 MB, package `com.jetpackbrawler.prototype`, 64-bit ARM only, Android target 36,
one permission (internet). The build is not in the repository; it is on this Mac only. On
the Mac the full test suite passes on this commit (52 of 52).

The phone checks are still pending. This build has the corrected push distances, so it is
the first one fit for the 10-minute phase 1 playtest. Two network fixes are still in
progress and are not in it; see "Known limits".

If you have not done device checkpoint 1 (sticks, jetpack and dash), do it first with this
same build: its checks 6 to 16 still apply and are not repeated here.

## What is in the build

One grey-box arena (the Smelter), up to 4 players, joined by typing the host's IP address.

- Every bot has 100 health and a rivet gun with endless ammo.
- Four pickup spots: bolt thrower and scrap blaster on the two upper ledges, festival rocket
  tube in the middle, Spring Plate low on the left. A taken pickup returns after 15 seconds.
- Every bot starts each life with one Cooker Bomb.
- A dummy bot stands on the floor in the middle. It does not move or shoot.
- A bot's health bar appears above it when its health changes and disappears again after
  about 1.5 seconds. Your own health is also always shown in the corner.
- The sandbox runs in 45-second cycles: molten metal starts rising at 30 seconds, and at 45
  seconds everything resets. A knocked-out bot comes back after 2 seconds, or at the next
  cycle if the metal is already rising.
- There are no rounds, scores, Chaos Cards or thinking bots. Those are phase 2.

## Controls

- Left stick: run; push up for the steam pack; push down on a yellow platform to drop.
- Right stick: aim. Push it past the ring to fire. A quick tap on it swings a melee hit.
- Buttons around the right stick: DASH, MELEE, GADGET (throw the Cooker Bomb or Spring Plate),
  SWAP (rivet gun or the picked-up weapon). With the right stick released, the white aim line,
  melee swings and gadget throws follow the direction your bot faces.

## Install and connect

Same as checkpoint 1: see `docs/reviews/device-checkpoint-1.md`, sections Install and
Connect.

## What to check

For each check you run, answer yes, no, or describe what you saw.

Shooting and knockback (the main point)

1. Shoot the dummy with the rivet gun. Does it lose health and flash on each hit?
2. Pick up the scrap blaster and fire at the dummy from close range. Does the dummy fly
   back clearly after a brief hit freeze (its picture holds for a few frames)? Do you feel
   the recoil push you the other way?
3. Stand in the air and fire the scrap blaster straight down. Do you get an extra hop?
4. Wear the dummy down until the bar that appears above it on each hit changes colour (25
   health or less), then hit it again. Is it pushed visibly further than at full health? Is
   the bar easy to read, and does it stay long enough to read (about 1.5 seconds)?
5. Knock the dummy into the molten metal after it has risen. Is it knocked out at once,
   with a strong screen shake, and does that moment feel good?
6. Melee the dummy (tap the right stick, and also the MELEE button). Does it get pushed?
   Which of the two do you reach for?
7. Do the four buttons sit where your right thumb finds them without looking? Do you ever
   press one by accident while aiming?
8. Flick the right stick quickly past the ring and let go. Does exactly one shot fire, in
   the direction you flicked?

Weapons and gadgets

9. Bolt thrower: does holding fire feel like a stream, and does it run out of ammo and
   switch back to the rivet gun?
10. Rocket tube: does the rocket fly straight, explode on the dummy or a wall, and push
    things near the blast? Fire one at your own feet: are you hurt and thrown, and does the
    screen shake? (The screen shakes when your own bot is hit, near a blast and on any
    knockout; it does not shake when you hit someone else.)
11. Punch a rocket that is flying at you (needs the second phone to fire it). Does it turn
    around?
12. Aim upward, let go of the stick, then tap GADGET. Does the Cooker Bomb follow the white
    aim line as it returns to horizontal? Does the bomb bounce and explode about 3 seconds later?
13. Pick up the Spring Plate, throw it on the floor, and walk the other phone's bot over
    it. Is that bot launched upward? Is the plate drawn in your bot's colour?
14. Throw a second bomb from a new life right after the first one exploded. Does the new
    bomb ever appear for a moment where the old one blew up? (A known risk that cannot be
    checked on the Mac.)

Two phones in sync

15. On both phones at once: do the dummy's health bar, position and knockout look the
    same? Watch one knockout into the metal on both screens.
16. Have each phone shoot the other. Do hits land when they look like they should on the
    shooter's screen?
17. While moving on phone B, does your own bot ever jump back a short distance for a moment
    and then carry on? Say how often. (A known fault under bad Wi-Fi timing, still being
    worked on.)
18. Phone B taps Leave and joins again; then phone A leaves and hosts again and B joins.
    After each, are the pickups present, and are there no leftover bombs or plates from
    before?
19. At the 45-second reset: do both phones reset together, with every bot back at full
    health and its bomb back?

Fun

20. After 10 minutes, do you want to keep going? What was the best moment and what was the
    most annoying thing?
21. Is anything too strong, too weak, too slow or too fast? In particular: does a bot hit
    in mid-air, or lifted by a blast, fly too far, about right, or not far enough? Does
    sustained bolt thrower fire push a flying bot too much? After being nicked while
    running, is turning back too sluggish? Every such number is in `config/tuning.tres`
    and is quick to change.

Performance

22. Is either phone warm or stuttering after 10 minutes? Does it stutter when several bombs
    or rockets go off together?

## Known limits of this build

- Pushes now travel the design's distances on the ground (a melee hit 2.5 bot heights, a
  close scrap blast 1.5, a blast at its centre 5, twice those at very low health). In the
  air they carry about five times as far, and a blast usually lifts a bot, so expect bots
  to fly a long way. That is the first thing to judge (check 21); one number tunes it.
- Grey boxes only: no art, no sound.
- The hit freeze holds the hit bot's picture for a few frames; the game itself never pauses.
- If the host phone is put in the background, the match breaks. That is not handled yet.
- More than two phones has not been tried.
- On poor Wi-Fi timing a bot can be shown one step behind for a few frames (check 17): when
  a burst of a player's input packets is late, the host sends positions that are one step
  behind until the input arrives. Measured on the Mac with packets held on purpose: up to
  about 30 pixels. The cause is known and the fix is in progress; it is not in this build.
- A deliberately malformed network packet from a device on the same hotspot can crash the
  host. It cannot happen by accident. The fix is under review and is not in this build.

## What I need back

Send the build commit, numbered answers, phone models and Android versions, and anything
else that felt wrong. After the full playtest, you decide whether the phase 1 gate passes.

# Device checkpoint 1: sticks, jetpack and dash on two phones

For Rahul. This is the GDD's "verify in the first week" check. It is not the phase gate.

Build: `builds/jetpack-brawler-debug.apk`, made from `main` at `b90d525` on 25 Nov 2026,
16:59. 28.6 MB, package `com.jetpackbrawler.prototype`, 64-bit ARM only, Android target 36,
one permission (internet). The build is not in the repository; it is on this Mac only.

Nothing in this build has run on a phone. Everything below is unverified until you do it.

## What is in the build

This script was written for the first, movement-only build. The current build is the full
knockback sandbox (weapons, melee, gadgets, a dummy, the rising metal and effects), described
in `docs/reviews/device-checkpoint-2.md`. The checks below are still the ones to do first:
they are about the sticks, the steam pack, the dash and the connection, and they do not need
the weapons. There are three more buttons on screen now (MELEE, GADGET and SWAP, around the
right stick with DASH); for check 6, say also whether they get in the way.

## Install

1. On each phone: Settings, About phone, tap Build number seven times, then turn on USB
   debugging in Developer options.
2. Connect one phone by cable and accept the debugging prompt on the phone.
3. In a terminal in the project folder:

   ```bash
   ~/Library/Android/sdk/platform-tools/adb devices
   ```

   ```bash
   ~/Library/Android/sdk/platform-tools/adb install -r builds/jetpack-brawler-debug.apk
   ```

4. Repeat steps 2 and 3 for the second phone.

## Connect

1. Phone A: turn on its hotspot. Phone B: join that hotspot over Wi-Fi.
2. Phone A: open the game and tap Host. The top of the screen shows "Hosting on" followed
   by one or more addresses and a port.
3. Phone B: open the game, tap the address field, type the address from phone A, tap Join.
   If phone A shows several addresses, try each; the hotspot one usually starts with
   192.168.

## What to check

Answer each with yes, no, or what you saw.

Connection

1. Does the on-screen keyboard open when you tap the address field?
2. Does phone B join, and does each phone show both bots?
3. Does the other bot move smoothly, without jumps, on both phones?
4. On phone B tap Leave, then join again. Does its bot come back?
5. On phone A tap Leave. Does phone B return to the menu with a message?

Controls (the main point of this checkpoint)

6. Can you reach both sticks and the dash button without shifting your grip? Keep steering
   or flying with your left thumb. With your right thumb, aim, tap dash, then aim again.
   Can you do it without releasing the left stick or needing a third finger?
7. Is the bot ever hidden under a thumb?
8. Push the left stick up: does the steam pack feel right? Is a quick tap a hop you can
   see, or too small? (Measured on the Mac: a 3-tick tap lifts about 18 pixels.)
9. When you push up for the steam pack, does the bot drift sideways when you did not mean
   it to?
10. Dash: is the 3-second wait too long, too short, or right?
11. Slide down a wall and push away from it: does the wall-jump trigger when you expect?
12. Push down on a yellow platform: do you drop through it?
13. Does the fuel gauge empty in about 2.5 seconds of flying and refill on the ground in
    about 2 seconds?

Interruptions

14. While holding a stick, pull down the notification shade, then go back to the game. Are
    the sticks back to neutral, and does the next touch control the correct stick?
15. Lock phone B for a few seconds and unlock it. What happens to its bot on phone A?
16. Switch phone A (the host) to another app for a few seconds and come back. What does
    phone B see? This case is known to be unhandled; the result tells us how bad it is.

Performance

17. After 10 minutes, is either phone warm or stuttering?

## Known limits of this build

- If a burst of a player's input packets is late, bots can be shown one step behind for a
  few frames. The cause is known; the fix is in progress and is not in this build.
- When the camera reaches the edge of the arena you see a black band. That is deliberate,
  so a bot on the floor is not under your thumbs.
- A player-to-player test with more than two phones has not been tried.

## What I need back

The numbered answers, the phone models and Android versions, and anything that felt wrong
that the list does not cover. Feel problems with the steam pack, dash and sticks are tuning
numbers in `config/tuning.tres` and are quick to change.

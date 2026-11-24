# Touch-screen twin-stick shooter controls and first-minute onboarding (research notes, November 2026)

Scope note for the report writer. The GDD scheme (docs/GDD.md, "Core gameplay > Controls") is: left stick moves, up fires the jetpack, down drops through platforms, away-from-wall does a wall-jump; right stick aims and fires past an outer ring, releasing a charged weapon fires it, a quick tap on the right stick is melee; dash button; gadget button; weapon-swap icon; aim assist (light snap, on by default for new players); adjustable button size and position; optional separate melee button.

Evidence quality is uneven. Official developer material on exact stick sizes, dead zones and aim-assist strength for Brawl Stars, Call of Duty Mobile, PUBG Mobile, Free Fire, Bullet Echo, Archero and Brawlhalla mobile was NOT found; most game-specific detail below comes from third-party guides and is labelled as such. Each section ends with Gaps listing what is missing. Items marked "(search summary only)" were seen in search-result summaries but the page itself was not read in full.

---

## 1. Stick design: fixed vs floating vs dynamic, sizes, dead zones, outer ring, thumb reach

### Takeaway
Proven practice is that both fixed and dynamic sticks exist and neither is universally better; the best-sourced evidence is that a fixed stick is clearer for first-timers and that successful shooters (Call of Duty Mobile, Brawl Stars) expose a lock/fixed option and a drag-to-reposition layout editor. Physical target-size research supports roughly 9 to 10 mm minimum targets, with primary controls much larger. No source gave hard dead-zone numbers.

### Cited Findings
- Developer article distinguishes dynamic sticks (appear where the thumb lands, movement measured from that anchor; suited to comfort because thumbs rest anywhere) from static sticks (always visible, fixed position). The author chose static sticks "for a clearer first-time experience" and because they avoid hiding monsters or traps under the thumbs; the article notes a dynamic stick "without prior visual indication, it may not be easily understood". Same article offers touch-to-move as the "Beginner / one finger" option and thumb sticks as "Advanced / two thumbs". It gives no dead-zone, size or thumb-reach numbers. — [Game Developer: From keyboard and mouse to on-screen analog thumb sticks](https://gamedeveloper.com/programming/from-keyboard-and-mouse-to-on-screen-analog-thumb-sticks)
- Call of Duty Mobile (official 2019 Activision post): Settings > Controls > Custom Layout opens a mock HUD where elements can be dragged and have size and opacity changed; options include Fixed Joystick, Joystick Sprint, Auto-Run, and "Fixed R-Fire Button" (locks the fire button to one place on the right instead of moving to where the finger touches). Moving the joystick to the right and fire to the left is suggested for left-handers. The post states no defaults for these options and gives no sizes. — [Activision: Getting a Grip on the Call of Duty Mobile Controls](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls)
- Brawl Stars: "Settings > Edit Controls" lets players adjust and position controls; patch note wording: "Customizable Control Settings has been added to the Setting Screen & Training Cave" (optional update, 14 April 2020). No developer rationale quoted. Player comments in the article say it helps avoid mis-taps (one stopped accidentally using a gadget instead of attacking; another stopped wasting supers). The article does not say which controls can be resized. — [PiunikaWeb: Brawl Stars customizable controls update](https://piunikaweb.com/2020/04/14/brawl-stars-customizable-controls-update-now-live)
- Brawl Stars has four coloured joysticks in third-party description: left = move, right (red) = attack, yellow = Super, green = Equipment/gadget (unlocks at Power Level 7). Third-party guide, not official. — [LDShop Brawl Stars beginner guide](https://www.ldshop.gg/blog/brawl-stars-gp/brawl-stars-beginner's-guide-2025.html)
- Brawl Stars has a Joystick Move / Tap to Move control option (third-party). — [GameSkinny beginner guide](https://www.gameskinny.com/tips/brawl-stars-beginners-guide-tips-and-strategies/) (search summary only)
- Third-party guides suggest locking the Brawl Stars movement joystick for consistency; these are commercial blogs and should be treated as opinion. — [Lootbar control guide](https://www.lootbar.com/blog/en/best-brawl-stars-control-settings-and-layout-guide.html) (search summary only)
- Generic guidance (low-authority tutorials): stick base roughly 120 to 140 px, high-contrast base and semi-transparent so it does not hide combat, limit the move stick's active zone to the left half so it does not collide with buttons. — [Abratabia virtual joystick guide](https://www.abratabia.com/game-controls/virtual-joystick.php) and [Phaser joystick write-up](https://phaser.io/news/2025/12/i-built-the-best-virtual-joystick-for-phaserjs) (both search summary only; pixel sizes are not tied to a physical screen so are not usable as dp)
- Physical target size research: Parhi, Karlson and Bederson (MobileHCI 2006) recommend about 9.2 mm for discrete one-handed thumb taps and 9.6 mm for serial taps; larger targets were generally faster and error rates did not differ significantly among the larger sizes tested. — [Microsoft Research page for the study](https://www.microsoft.com/en-us/research/?p=155150)
- Nielsen Norman Group: minimum tap target 1 cm x 1 cm; fingertip about 1.6 to 2 cm wide; thumb impact area about 2.5 cm wide; primary action in a high-motion context about 2 cm x 2 cm; "targets must first be big enough, and then also spaced well enough". It recommends limiting the number of on-screen elements so key targets can be larger and further apart. — [NN/g: Touch target size](https://www.nngroup.com/articles/touch-target-size/)
- Android/Google accessibility guidance: interactive elements at least 48 dp wide and tall; the drawn icon can be smaller (a 24 dp icon padded to a 48 dp touch area). Guideline, not a conformance rule. — [Google Accessibility Help: Touch target size](https://support.google.com/accessibility/android/answer/7101858) (search summary only)
- Thumb reach (Hoober, 2013 observation study, 780 observed screen-touchers): 49% one-handed, 36% cradled, 15% two-handed; one-handed use 67% right thumb / 33% left; two-handed use 90% portrait, only 10% landscape. The author's own 2017 correction tells readers to ignore his reach drawings because they were coarse and later observation showed people touch the screen centre faster and more accurately than corners and edges. This study is about portrait phone UI, not landscape gaming. — [UXmatters: How Do Users Really Hold Mobile Devices?](https://www.uxmatters.com/mt/archives/2013/02/how-do-users-really-hold-mobile-devices.php)

### Inferences
- GDD uses fixed-position sticks plus an "outer ring"; that matches the clearer-for-first-timers argument above. A floating/dynamic option for the move stick is cheap and common (Call of Duty Mobile offers the fixed/non-fixed choice) but should not be the default for a one-minute learn; proposal: default fixed, add "floating left stick" in settings only if playtests show thumb drift.
- Converting to dp: Android defines 1 dp as 1/160 inch at baseline, so 48 dp is about 7.6 mm nominal, which is below the 9 to 10 mm research figure. Proposal (arithmetic, not a sourced figure): make action buttons at least about 56 to 64 dp (roughly 9 to 10 mm) and the sticks much larger (NN/g thumb-impact 2.5 cm is about 130 dp). Treat these as starting values for a settings resource and tune on a real 6 to 6.7 inch phone.
- Hoober's thumb-zone maps are weak evidence for landscape games (portrait, 2013, author disowned the drawings); do not cite thumb-zone heat maps as proof of placement. Better to place sticks in the lower corners and verify by playtest.

### Gaps
- No official stick diameters, dead-zone percentages or outer-ring radius for Brawl Stars, Call of Duty Mobile, PUBG Mobile, Free Fire, Bullet Echo, Archero or Brawlhalla mobile were found. No source gave a dead-zone value.
- No evidence found on how Bullet Echo, Archero or Brawlhalla mobile lay out sticks (searches did not return them; not researched further because of the call budget).
- No landscape-specific thumb-reach study found.

---

## 2. Fire schemes: drag-and-release, auto-fire when aimed, separate fire button, tap for auto-aim

### Takeaway
Brawl Stars' scheme is drag to aim and release to fire, with a plain tap giving an auto-aimed "quick-fire"; it is widely documented and was the genre's major mobile precedent for a tap-vs-drag split on one stick. Call of Duty Mobile offers both an automatic mode and a separate fire button, selectable in settings. Accidental-fire complaints are visible mainly as player requests for repositionable controls; no complaint statistics were found.

### Cited Findings
- Brawl Stars: drag the attack joystick to aim and release to fire; tapping it triggers an auto-aimed quick-fire at the nearest damageable target; the Super joystick works the same way. Third-party guides say auto-aim suits close range and manual aim suits long range, arcs and skillshot Supers, and that relying only on auto-aim is a common mistake. No Supercell document explaining the design rationale or the tap threshold was found. — [Pocket Tactics / Fandom wiki summaries via search](https://brawlstars.fandom.com/wiki/Mega_Box); [Game8 Edit Controls guide](https://game8.co/games/Brawl-Stars/archives/316910); [jeu.video aim settings](https://jeu.video/en/guide/brawl-stars-aim-settings) (all search summary only; fan/commercial sources)
- Call of Duty Mobile has Simple and Advanced fire modes (switchable in Controls). In Advanced, a separate hip-fire button appears and the Fire button fires (aiming down sights first if the weapon supports it); in Simple, the post only says auto hip-fire range can be limited. Dragging on the right side aims and looks. — [Activision official post](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls)
- Brawl Stars customisation rationale as reported by players is accidental-press avoidance (gadget instead of attack; wasted super). — [PiunikaWeb](https://piunikaweb.com/2020/04/14/brawl-stars-customizable-controls-update-now-live)
- Mini Militia (Doodle Army 2): described as dual stick, one stick for movement and one for aiming and shooting; Wikipedia says the shooting mechanics can be challenging for new players and mastery needs practice. A reported review says it is tricky at first but intuitive with practice; I found no reviewer calling the controls clumsy. The criticism found in reviews was about pay-to-win, ads and updates, not controls. I could not read the Wikipedia page directly (fetch returned 404 for the URL tried), so this rests on search summaries. — [Wikipedia: Mini Militia](https://en.wikipedia.org/wiki/Mini_Militia) (search summary only)
- Mini Militia has no auto-fire-when-aimed mechanic that I could confirm from a reliable source; the details of its fire threshold were not found.

### Inferences
- GDD "drag past the outer ring to fire" matches the Mini Militia / twin-stick convention (fire is a function of drag distance), and the Brawl Stars precedent shows a one-stick tap/drag split is workable in a mobile shooter. The GDD's "tap on the right stick = melee" is different from Brawl Stars, where a tap on that stick is an auto-aimed attack. A player coming from Brawl Stars may expect a tap to shoot; the tap threshold and what happens when a tap lands while the thumb is already past the ring needs careful definition.
- Because the GDD fires on drag past the ring, a "release to fire" charged weapon (antenna rifle, lobber) means one stick has two different fire semantics depending on the weapon. That is a source of confusion; proposal: show a distinct charge ring/animation for charged weapons so the semantics are visible.

### Gaps
- No quantitative missed-input or accidental-fire data for any of these games.
- No source on PUBG Mobile, Free Fire, Bullet Echo, Archero or Brawlhalla fire schemes was obtained.
- Tap-versus-drag time/distance thresholds for Brawl Stars not found.

---

## 3. Overloading one stick (aim + fire threshold + quick-tap melee; move + up-for-jetpack + down-to-drop)

### Takeaway
I found no measured error-rate data on overloaded sticks. The only sourced developer point is that multi-axis virtual sticks lose the physical feedback that makes directional nuance possible; the one dense evidence base for "up on the move stick = jetpack/fly" is the Mini Militia design itself, which reviewers treat as its signature feature rather than a control problem. Treat the GDD's overloading as a risk to playtest, not as a proven pattern or proven failure.

### Cited Findings
- A mobile platformer postmortem (Mikey Shorts, 2013) argues multi-axis virtual sticks "require too much directional nuance without providing the requisite physical feedback"; its fix was removing vertical axes (claimed to reduce the physical feedback needed "by 50%", with no data given). Single developer opinion, 2013, platformer not shooter. — [Game Developer: Mikey Shorts case study](https://gamedeveloper.com/design/mikey-shorts-a-case-study-of-optimizing-controls-for-mobile-platformers)
- Mini Militia: one stick for movement and jetpack thrust and the other for 360-degree aiming (from a low-quality SEO blog; treat cautiously); reviewers describe the jetpack as the thing that makes the game stand out, "adds a vertical element to combat". — [Doodle Army 2 blog post surfaced by search](https://ava.ead.domalberto.edu.br/doodle-army-2-mini-militia) (low quality, search summary only); [Wikipedia: Mini Militia](https://en.wikipedia.org/wiki/Mini_Militia) (search summary only)
- Searches for jetpack or fly-control complaints returned only itch.io comments about unrelated indie games (slow-starting jetpack lift; a jetpack tied to double-tap inputs hard to understand). No Mini Militia-specific complaint about stick-up-for-jetpack was found. — itch.io posts (e.g. [itch.io/post/14764385](https://itch.io/post/14764385)), search summary only, not about the target games
- Brawl Stars avoids stick overloading by giving each action its own stick/button (attack, Super, gadget each have a separate coloured joystick or button) while using one stick for tap/drag on each. — [LDShop beginner guide](https://www.ldshop.gg/blog/brawl-stars-gp/brawl-stars-beginner's-guide-2025.html) (third-party; see Section 1). Inference from that description, not a developer statement.

### Inferences
- Up-for-jetpack on the left stick is established by Mini Militia and is in the GDD's own market rationale; the GDD is therefore matching a successful precedent, not inventing it. The new risk in the GDD is that the same stick also carries "down to drop through thin platforms" and "away from wall = wall-jump": a thumb that is meant to run horizontally with a slight upward drift will activate the jetpack by accident, and diagonal up-away inputs near walls are ambiguous. Proposal: use an angular cone for "up" (for example, only count up when the stick angle is within a set cone of vertical) and a larger vertical dead zone for "down" than for "up", with both values in the config resource; verify in phase 1 playtest with timing logs.
- Quick-tap melee on the aim stick is the most overloaded control (aim, fire threshold, charge release, melee). Proposal: the GDD already allows a separate melee button for experienced players; consider showing it by default, because the research found no proof that tap-melee on the fire stick is learnable in a minute.

### Gaps
- No error-rate or playtest data on overloaded sticks in any shooter.
- No reviews specifically evaluating stick-up-for-jump in mobile platform shooters beyond Mini Militia's general reception; no source comparing it against a separate jump button.
- Could not find Mini Militia's official control settings page, Reddit threads or Play Store review text that name specific control complaints.

---

## 4. Aim assist on touch

### Takeaway
Auto-aim is a widely used way to make touch aiming accessible: Brawl Stars via tap-to-quick-fire at the nearest target, Call of Duty Mobile via an optional Aim Assist toggle (documented as helping when aiming down sights). The best developer-sourced fairness data is from War Robots: transparent, tunable and optional auto-aim cut aiming complaints, and was adopted by only 18% at first.

### Cited Findings
- Call of Duty Mobile official wording: "Turning this on will aid in aiming a weapon at an enemy when aiming down sights." Third-party guides recommend leaving it on and say CoD Mobile's assist is stronger than PUBG Mobile's, where many turn it off. The default state is not stated in the official post. — [Activision official post](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls); [GGRecon layout and sensitivity guide](https://www.ggrecon.com/guides/call-of-duty-mobile-layout-and-sensitivity-guide) (search summary only)
- War Robots auto-aim developer account (Game Developer, Kirill Sharikov): scores each target on five 0-to-1 factors (aim, distance, HP, cover, shots fired) with designer-set weights, plus a "sticky" coefficient to hold the current target; only 18% of players enabled the optional new system at first; of those who tried it, 80% did not switch back; community managers reported a significant drop in aiming complaints; experienced players mostly still prefer manual target selection; some hardcore players call auto-aim "cheating". Fairness is defined mainly as transparency and predictability, not measured competitive balance. Targets are robots (3D mobile), not a 2D twin-stick. — [Game Developer: How to create a fair auto-aiming system in a robot shooter](https://gamedeveloper.com/design/how-to-create-a-fair-auto-aiming-system-in-a-robot-shooter-)
- Brawl Stars quick-fire targets the nearest damageable target and is described by third parties as best at close range; no official strength, cone or range number found. — [Fandom / Game8 summaries](https://game8.co/games/Brawl-Stars/archives/316910) (search summary only)

### Inferences
- GDD's "light snapping toward the nearest enemy, on by default for new players and switchable off" matches the CoD Mobile (toggle) and Brawl Stars (tap to auto-aim) precedents in spirit. Proposal from the War Robots account: make the targeting rule simple and predictable (nearest within a cone, with line of sight, with stickiness) and expose strength in config rather than hiding it; keep it identical for human players and bots-as-players per the project rule that bots obey player rules.
- Because the GDD's bots must not have vision through walls, apply the same line-of-sight test to aim assist so it cannot lock through walls (War Robots players valued cover handling).

### Gaps
- No quantitative strength data (snap angle, slowdown factor, magnetism) from Brawl Stars, CoD Mobile, PUBG Mobile, Free Fire, Bullet Echo or Archero-style games.
- No data on whether assist is on by default beyond the GDD's own choice.

---

## 5. Touch targets, safe areas, gesture bar, palm rejection, multi-touch on budget Android

### Takeaway
Android guidance is clear on 48 dp minimum targets, avoiding touch targets under system-gesture insets, and using a gesture-exclusion API for games; research suggests larger (9 to 10 mm) targets for thumbs. I found no source on palm rejection or pointer-count limits on budget Android phones.

### Cited Findings
- Minimum 48 dp for interactive elements (Google/Material accessibility guidance). — [Google Accessibility Help: Touch target size](https://support.google.com/accessibility/android/answer/7101858) (search summary only)
- Parhi et al.: about 9.2 mm (discrete) and 9.6 mm (serial) for one-handed thumb use. — [Microsoft Research](https://www.microsoft.com/en-us/research/?p=155150)
- NN/g: 1 cm minimum, spacing matters, pair actions side by side rather than stacked, fewer elements allow larger targets. — [NN/g](https://www.nngroup.com/articles/touch-target-size/)
- Android system bars guidance: "Avoid adding interactions or touch targets under gesture navigation insets"; use WindowInsets to ensure content is not obscured; display cutouts vary by manufacturer and must be considered for content and controls; if a navigation bar covers a button the user may not be able to press it. — [Android Developers: System bars](https://developer.android.com/design/ui/mobile/guides/foundations/system-bars)
- Gesture navigation (Android 10+): back is an inward swipe from the left or right edge; the bottom home/quick-switch gesture cannot be opted out of by apps; `WindowInsets.getMandatorySystemGestureInsets()` reports the thresholds. Games can call `Window.setSystemGestureExclusionRects()` to exclude edge areas, "only when necessary, such as during gameplay"; a game needing swipes near the home gesture area can request immersive mode, which lets users re-enable gestures by swiping from the bottom. — [Android Developers: Ensure compatibility with gesture navigation](https://developer.android.com/training/gestures/gesturenav)
- Unity forum thread (older) complained Android lacks iOS's "defer system gestures on edges"; not verified to reflect current engine support. — [Unity Discussions](https://discussions.unity.com/t/is-there-another-way-to-get-defer-system-gestures-on-edges-behaviour-on-android-devices/768244) (search summary only)
- Hoober: users touch the screen centre more accurately than edges or corners (author's 2017 correction), which cuts against placing small critical controls at extreme edges. — [UXmatters](https://www.uxmatters.com/mt/archives/2013/02/how-do-users-really-hold-mobile-devices.php)

### Inferences
- Landscape game with sticks in bottom corners: the left stick sits close to the back-gesture edge on a gesture-navigation phone; proposal: inset the left and right controls from the screen edges, keep action buttons out of the bottom inset, and register gesture-exclusion rects for the stick regions during play only.
- Cutouts matter in landscape (notch on the left or right edge); proposal: use safe-area insets as the layout margins and make all control positions relative to them.
- Multi-touch: GDD needs at least four simultaneous touches (left stick, right stick, plus dash and gadget); this is a design inference, not a measured device limit. Test on a budget device that touch count and ghost-touch behaviour hold.

### Gaps
- No source found on palm rejection behaviour in games, on typical simultaneous-touch limits of budget Android panels, or on the touch panels used by popular Indian budget phones.
- No source on how often notch/cutout overlaps game HUD controls in landscape.

---

## 6. Customisable HUD layouts

### Takeaway
Drag-to-reposition and resize is established in the genre (Call of Duty Mobile with size and opacity; Brawl Stars since April 2020). No usage-rate data (what share of players change layouts) was found from any developer.

### Cited Findings
- Call of Duty Mobile: custom layout via mock HUD with drag/drop, size and opacity per element. — [Activision official post](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls)
- Brawl Stars: "Edit Controls" in Settings and Training Cave; added in an optional update (14 April 2020); a "Test your controls" option exists per third-party guide. — [PiunikaWeb](https://piunikaweb.com/2020/04/14/brawl-stars-customizable-controls-update-now-live); [Game8](https://game8.co/games/Brawl-Stars/archives/316910) (search summary only). Supercell's own release-note page exists (title "Additional update: customizable joysticks!", 14 April 2020) but its body did not load, so details are unconfirmed — [Supercell release notes](https://supercell.com/en/games/brawlstars/ru/blog/release-notes/дополнительное-обновление-настраиваемые-джойстики)
- Third-party Brawl Stars guides frame layout editing as an optimisation step for committed players; that hints casual players leave defaults, but it is inference, not data.

### Inferences
- GDD's "button size and position adjustable" matches proven practice. Proposal: include a "test controls" training area as Brawl Stars does so players can see what moving a button does; and store layouts per device orientation and per safe-area.
- Because no usage rates exist, do not assume most players will edit layouts; the defaults must work for a casual friend group on first launch.

### Gaps
- No usage-rate data on layout customisation in any game.
- Whether PUBG Mobile, Free Fire, Bullet Echo, Archero or Brawlhalla mobile allow customisation was not confirmed in this research.

---

## 7. Onboarding: how Brawl Stars, Stumble Guys, Among Us and Mini Militia teach controls; tutorial drop-off

### Takeaway
Brawl Stars uses a mandatory, short scripted tutorial as Shelly, followed by a practice match against bots, per third-party guides. No official data on tutorial drop-off for these games was found; the only measured data are generic analytics case studies from 2017, showing forced, long tutorials with low pass rates hurt retention and that tutorial funnels should be measured per step.

### Cited Findings
- Brawl Stars (third-party guides, not Supercell): tutorial is mandatory, uses Shelly, covers movement, attacking, aiming and using the Super; then a practice match against AI bots. Sources differ on details: one describes a tutorial-only map ("Training Island") that cannot be replayed with reduced-damage tutorial bots; another says the bot match results do not count toward rankings; one review describes control tutorial, then a battle against NPCs, then lobby. — [LDShop beginner guide](https://www.ldshop.gg/blog/brawl-stars-gp/brawl-stars-beginner's-guide-2025.html); [Skycoach guide](https://skycoach.gg/blog/brawl-stars/articles/br-beginners-guide); [Massively OP](https://massivelyop.com/2024/05/13/fight-or-kite-hey-now-youre-brawl-stars-get-your-game-on-go-play/); [Theria Games](https://theriagames.com/?p=158511) (all search summary except LDShop)
- devtodev data (2017, two anonymous games and one customer case): the skippable game's tutorial had about 75% pass rate; the forced one had about 40% pass and much higher churn during the tutorial; the article gives 70 to 80% as the optimal pass rate. A 120-step tutorial with invisible loading steps had the most churn from slow loading, and optimising raised 1-day retention by 10% (relative or absolute not stated); industry 1-day retention is cited as about 30%. Two steepest funnel drops were between step 1 and 2 and between step 15 and 16 (no percentages). — [Game Developer / devtodev: How to optimize the tutorial for your game](https://gamedeveloper.com/business/how-to-optimize-the-tutorial-for-your-game)
- Unity guidance: build a funnel following each tutorial step to find drop-off, track completion rate and time to completion, and extend onboarding past the tutorial with tooltips and loading-screen tips. — [Unity: 10 first-time user experience tips](https://unity.com/how-to/10-first-time-user-experience-tips-games) (search summary only)
- Among Us: a player account says starting without reading instructions left them confused about roles; guides suggest beginners start on smaller maps. This is anecdote and fan-guide material only. Among Us' own tutorial structure was not verified. — [Buzzsprout: Getting Gamers, Among Us beginner's perspective](https://www.buzzsprout.com/1546957/episodes/18930299-18-among-us-a-beginner-s-perspective) (search summary only)
- A blog quoting 73% of players gone within 24 hours and 80% by day 3 has no source; do not use. — [Adrian Crook](https://adriancrook.com/?p=8151)

### Inferences
- The GDD wants "joinable in a minute". Evidence supports a short, optional-skippable guided practice with bots plus in-match hint overlays rather than a long forced tutorial (the forced game in the devtodev data lost more players). Proposal: first run puts the player on a small map against Easy bots with a three-step overlay (move, jetpack, aim and fire), melee and dash hints appear only after the player has fired N times without using them, and the tutorial funnel is instrumented per step.
- Brawl Stars' tutorial-then-bots flow is the closest precedent for a "bot-first" first session and fits the GDD's bots-obey-player-rules design (bots at Easy difficulty).

### Gaps
- No source found describing Stumble Guys' onboarding or Mini Militia's first-session teaching; search for Stumble Guys returned nothing relevant and Mini Militia searches returned only generic descriptions.
- No developer-published tutorial drop-off data for Brawl Stars, Among Us, Stumble Guys or Mini Militia.
- No data specific to India or to friend-group, same-room play.

---

## 8. Haptics and feedback on input

### Takeaway
Android's official guidance is "less is more": reserve vibration for important events, keep frequent events very subtle, avoid buzzy long vibrations, co-design with sound and visuals, and give a way to reduce or turn it off. Game-platform guidance (Xbox, Meta) says haptics should be additional, configurable, and spaced out.

### Cited Findings
- Android: "Too much vibration can be annoying and even numbing to the hands... may lead the user to quickly turn off all haptics"; favour clear and rich haptics over buzzy; "Given the choice of buzzy haptics or no haptics for touch feedback, choose no haptics"; correlate strength with importance and frequency (very frequent events should be very subtle); a good keyclick signal lasts 10 to 20 ms and the actuator can ring 20 to 50 ms after; avoid legacy one-shot vibrations on low-quality actuators; haptics out of sync with visuals and audio can make users think the actuator is broken. — [Android Developers: Haptics design principles](https://developer.android.com/develop/ui/views/haptics/haptics-principles)
- Xbox accessibility guidance: haptics are always additional, never the only signal, and always configurable (off and intensity). Meta's guidelines: avoid long overlapping effects in fast-paced action and use short pauses. — [Xbox XAG 110](https://devdocs.xbox.com/build/game-principles/accessibility/xag-deep-dives/xag-110-haptic-feedback); [Meta haptics best practices](https://developers.meta.com/horizon/design/haptics-best-practices/) (search summary only)
- I did not find which events Brawl Stars, CoD Mobile or other titles vibrate on.

### Inferences
- Budget Android phones often have low-quality vibration motors (inference from the Android doc's low-performance-actuator warning, not a measured Indian-market figure). Proposal: haptics off for continuous input (stick movement, held fire), a short tick only for discrete events (dash, melee hit confirm, taking a heavy hit, entering fire range), with an intensity slider and off toggle; the GDD already has a screen-shake reduction setting, so mirror it.

### Gaps
- No per-game list of haptic events for the games asked about.
- No measurement of haptic hardware quality on budget Android phones in India.

---

### Appendix within this section: GDD controls against evidence (proposals, not decisions)

| GDD element | Evidence status | Assessment |
|---|---|---|
| Two sticks plus buttons, learnable in a minute | Mini Militia twin-stick reviewed as tricky at first but learnable (search summary); Brawl Stars teaches via short tutorial plus bots | Matches precedent; "a minute" is unverified, test it |
| Fixed-position sticks, adjustable size and position | CoD Mobile and Brawl Stars both offer drag-to-reposition layouts | Matches proven practice |
| Left stick up = jetpack | Core of Mini Militia, reviewers praise the jetpack; no complaint data found | Matches precedent; risk is accidental activation and conflict with down-drop and wall-jump, so tune cone and dead zones |
| Left stick down = drop, away from wall = wall-jump | No precedent found in sources | Risky; additional overload on one stick, playtest |
| Right stick aim, fire past outer ring | Standard twin-stick; Brawl Stars uses release-to-fire instead | Matches twin-stick practice; differs from Brawl Stars |
| Quick tap on the right stick = melee | Brawl Stars tap = auto-aimed attack; no precedent for tap = melee found | Risky; players from Brawl Stars may expect a shot; make a melee button visible by default for first sessions |
| Release of a charged weapon fires | Brawl Stars drag-release is familiar | Fine, but two fire semantics on one stick need clear UI |
| Aim assist, light snap, on for new players, switchable off | CoD Mobile toggle; Brawl Stars tap-to-aim; War Robots optional auto-aim reduced complaints | Matches; keep rule simple, tunable, line-of-sight aware |
| Button sizes | NN/g 1 cm, Parhi about 9.2 to 9.6 mm, Android 48 dp | Make action buttons larger than the minimum; derive from physical size |
| Edge placement | Android: no targets under gesture insets; Hoober: centre more accurate than edges | Inset controls from edges; use exclusion rects during play |
| Haptics | Android: less is more | Sparse, optional |

### Appendix within this section: source-reliability notes for the report writer
- Primary and reliable: Activision CoD Mobile controls post (2019, may be outdated), Android Developers pages (system bars, gesture navigation, haptics), Microsoft Research page for Parhi et al., NN/g, UXmatters (Hoober), Game Developer articles (War Robots auto-aim by a developer; devtodev tutorial data from 2017; Mikey Shorts 2013 opinion).
- Secondary or weak: all Brawl Stars control and tutorial details come from fan wikis, commercial guide sites and news write-ups; several are affiliate-driven. No Supercell source explaining control design was retrieved.
- Search summaries marked above were not verified against the full page; one returned page (Cavac wiki mirror) contained an unrelated embedded instruction, which was ignored and not used.
- The Mini Militia Wikipedia page failed to fetch in full; statements about it rest on search summaries.

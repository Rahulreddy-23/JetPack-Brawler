# Netcode practice of shipped action games and Android hotspot / LAN pitfalls (for Jetpack Brawler)

Context read: docs/GDD.md "Tech approach" and "Playing with friends". Our design: Godot 4.7, ENet, netfox, 30 simulation ticks/s, 4 players now / 8 later, playable up to 150 ms ping, phone-as-host over hotspot or via noray relay, host leaving ends the match.

Claim labels: [Official] = official platform or engine documentation; [Dev] = developer statement (talk, author's own article); [Secondary] = third-party summary of a developer talk; [Community] = forum or user report.
Research date: 2026-11-24. Note: two primary Valve wiki pages returned HTTP 403 to the fetcher; Valve figures below come from search-result extracts of those pages, not a full read.

## Prediction, reconciliation, interpolation and lag compensation: the essential rules, interpolation delay, 30 Hz vs 60 Hz

### Takeaway
The proven pattern is: tag every input with a sequence number, predict locally, on each server state snap to it and replay unacknowledged inputs; show remote players a fixed delay in the past (about two to three snapshot intervals plus jitter); and rewind other players by (latency + interpolation delay) when judging hits, with a cap on how far back you rewind. At 30 Hz that implies a remote-entity delay of roughly 67 to 150 ms on top of ping.

### Cited Findings
- [Dev] Client tags each input with a sequence number; server replies include the last processed input number; client keeps unacknowledged inputs, and on each server update sets its state to the server's and reapplies "all the input still not seen by the server". Without that replay the character snaps back and forth. — [Gambetta, Client-Side Prediction and Server Reconciliation](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html)
- [Dev] Prediction requires that "given a game state and a set of inputs, the result is completely predictable" (deterministic movement step). — [Gambetta](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html)
- [Dev] For irreversible effects such as a character's death, the client should wait for server confirmation rather than predict. — [Gambetta](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html)
- [Dev] Remote players are shown "in the past" by interpolating between known past states; lag compensation has the server rebuild the world as the shooter saw it at fire time. — [Gambetta, Lag Compensation](https://www.gabrielgambetta.com/lag-compensation.html)
- [Official] Source default interpolation period is 100 ms (cl_interp 0.1), chosen as 2 x (1 / default cl_updaterate of 20) so that "even if one snapshot is lost, there are always two valid snapshots to interpolate between". Effective interp = min(max(cl_interp, cl_interp_ratio / cl_updaterate), 0.25). — [Valve wiki: Interpolation](https://developer.valvesoftware.com/wiki/Interpolation); [Valve wiki: Source Multiplayer Networking](https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking?ref=blog.hathora.dev) (search extract; page 403 on direct fetch)
- [Official] Source lag compensation factors in both the player's latency and their interpolation amount when checking hits; sv_maxunlag (seconds of stored player positions) default and maximum is 1. A third-party SDK doc gives 0.4 s instead, which conflicts and is unverified. — [Valve wiki: Lag Compensation](https://developer.valvesoftware.com/wiki/Lag_Compensation) (search extract); conflicting: [hw-sdk docs](https://www.mintlify.com/yuriassaf1337/hw-sdk/features/lagcomp)
- [Dev] Snapshot interpolation buffer rule of thumb: enough delay to survive losing two packets in a row, plus one or two frames of jitter. Figures given: 10 pps -> 300 ms (+jitter = 350 ms used); 30 pps -> 150 ms; 60 pps -> 85 ms. Never wait for resends; skip lost snapshots (UDP). Hermite interpolation (sending velocity) removed visible artifacts that linear interpolation showed at low rates. Extrapolation was "just not very good" for physics objects. — [Gaffer on Games, Snapshot Interpolation](https://gafferongames.com/post/snapshot_interpolation/)
- [Secondary] Overwatch: fixed 16 ms command frames (about 60 Hz), 7 ms in tournament mode. Client runs ahead of server by half RTT plus one buffered command frame. Server-side input starvation triggers client "time dilation" (step shortened to about 15.2 ms) to refill the server input buffer, then slows back. Each packet carries every input since the last acknowledged state, so a lost packet's inputs arrive in the next one; when the server has no input it repeats the last known input (causing mispredictions). If the server falls behind it can enter "a death spiral". — [Edgegap deep dive: Overwatch](https://edgegap.com/blog/game-backend-deep-dive-overwatch-2016-netcode-architecture-rollback) (summary of GDC 2017 talk [Overwatch Gameplay Architecture and Netcode](https://gdcvault.com/play/1024001))
- [Dev] Overwatch's April 2016 developer update (Tim Ford, Philip Orwig) states the netcode favours the shooter in non-optimal conditions. — [Destructoid report](https://www.destructoid.com/overwatch-developers-talk-about-exactly-how-their-netcode-works/)
- [Secondary] Rocket League runs physics at a fixed 120 Hz (about 8 ms) to reduce discrete-collision inconsistencies; talk: Jared Cone, GDC 2018 "It IS Rocket Science!". Source is an auto-generated talk summary. — [GDC Vault listing](https://www.gdcvault.com/play/1024972/); [summary](https://glasp.co/youtube/ueEmiDM94IE)

### Inferences
- For our 30 Hz tick: two snapshot intervals = 67 ms (Valve rule), Gaffer's loss-tolerant figure is 150 ms. A starting interpolation delay of about 100 ms (3 ticks) is a reasonable middle; make it a config value and test with 5% loss. Total "remote player is behind" delay at 150 ms ping is then about 75 ms (one-way) + 100 ms = ~175 ms, which the lag-compensation rewind must cover.
- 30 Hz vs 60 Hz: none of the fetched sources say 30 Hz is unacceptable for this genre; Overwatch and Rocket League chose 60 Hz and 120 Hz for twitch 3D/physics games. At 30 Hz the costs are larger interpolation delay and coarser hit windows; fast movers (dash, knockback) move further per tick, so collision for fast projectiles needs swept tests. This is inference, not a sourced statement.
- Overwatch's "send all unacked inputs in every packet" and "server repeats last input when starved" are both directly applicable to a 30 Hz input stream on lossy hotspot Wi-Fi.
- Gambetta's "do not predict death" rule matches our GDD rule that the server decides damage and health; clients should predict only their own movement/jetpack/dash and cosmetic muzzle effects.

### Gaps
- No primary transcript of the Overwatch or Rocket League talks was read; numbers are from secondary summaries.
- No sourced statement found directly comparing 30 Hz and 60 Hz simulation for 2D shooters.
- Halo Reach's hit-registration specifics ("I Shot You First") were not obtained in primary form.

## Player-hosted (listen server) games: host advantage, slow or backgrounded host, host leaving

### Takeaway
Shipped peer-hosted games treat host migration as a major engineering project; dedicated servers avoid it entirely. Mobile OSes kill or suspend sockets of backgrounded apps, so a backgrounded host phone must be treated as a host loss. Our GDD choice (host leaves -> match ends, one-tap Host Rematch) is consistent with the evidence.

### Cited Findings
- [Secondary] Halo Reach switches to a better host mid-session when the host's connection degrades; host migration is described as "a significant engineering undertaking"; dedicated servers avoid it. Reach also hides host round-trip with tricks: grenades predicted in animation, host confirms about one RTT later; armour lock activated early on host offset by measured RTT; ragdolls sync only the initial death state. — [Edgegap deep dive: Halo Reach](https://edgegap.com/blog/game-backend-deep-dive-halo-reach-netcode-host-migration)
- [Community, Godot maintainer] Calinou (Godot): mobile networks usually do not give a publicly reachable IP (carrier-grade NAT) and IPv6 is not always reachable either; "hosting the server directly from a mobile device is a bad idea" unless the game is LAN-only. Thread: Godot 4, phone host failed while PC host worked, phone showed IPv6 address. — [Godot forum: mobile becoming server](https://forum.godotengine.org/t/the-mobile-becoming-server-in-local-multiplayer-games-is-a-chaos/53979)
- [Community] Heroic Labs moderator, on a Godot Android client: the mobile OS closes the socket after the app has been in the background for some time; the client must handle reconnect as part of the normal lifecycle. — [Heroic Labs forum](https://forum.heroiclabs.com/t/not-able-to-find-match-after-keeping-app-in-background/5074)
- [Official] Android Doze restricts network and CPU access; since Android 7.0 a lighter Doze triggers every time the screen turns off, with network only during maintenance windows. Google recommends FCM over persistent app sockets for background messaging. — [Android: Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Dev] Overwatch server "death spiral" when the simulation falls behind real time (relevant to a slow host phone). — [Edgegap deep dive: Overwatch](https://edgegap.com/blog/game-backend-deep-dive-overwatch-2016-netcode-architecture-rollback)

### Inferences
- A host phone that takes a call, opens WhatsApp or turns its screen off should be treated as "host lost" after a short timeout; do not try to keep the server alive in the background (Doze plus OS socket killing make it unreliable). Show clients a "Host paused" state and end the match cleanly after a configurable timeout.
- The host's simulation must have a budget: if a slow phone cannot run 30 ticks/s plus rendering at 60 fps, the server falls behind (death-spiral risk). Measure host tick time on the cheapest target phone in phase 1; the host also renders, so host CPU load is the binding constraint, not bandwidth.
- Host advantage: the host has zero latency to the authority. With favour-the-shooter lag compensation, remote players get their shots honoured too, which partly evens this out; but the host never mispredicts and never gets corrected. Accept this for friend play (GDD already accepts host-unchecked cheating).
- Calinou's warning supports the GDD's decision to route online rooms through noray rather than direct phone IPs; expect some fraction of phone-to-phone NAT punches to fail on CGNAT and fall back to relay (verify in phase 4).

### Gaps
- No primary sources found on how Mini Militia, Among Us local play, Brawlhalla custom rooms, Stick Fight or Duck Game handle host-leave or backgrounding. Not researched in depth within the call budget; these remain open.
- No sourced data on Godot 4.7 Android behaviour when the app is paused (whether the main loop and ENet service stop immediately). Must be tested on device; treat as unknown.

## Hits and projectiles under latency: favour the shooter vs the victim, slow projectiles, melee, knockback

### Takeaway
Hitscan in shipped shooters is server-rewound to what the shooter saw (favour the shooter), accepting "shot behind cover" complaints, with a latency cap beyond which rewind stops. Our game is mostly slow projectiles and knockback, for which the sources give less direct guidance; the fetched evidence points to server-spawned projectiles with client-side cosmetic prediction.

### Cited Findings
- [Dev] Lag compensation favours the shooter; the target "may still be shot up to a few milliseconds after they took cover", which the author calls "somewhat unfair" but better than missing clearly landed shots. — [Gambetta, Lag Compensation](https://www.gabrielgambetta.com/lag-compensation.html)
- [Secondary] Overwatch rewinds to the shooter's frame of reference, pre-filtering with a bounding volume of about the last half-second of movement; above roughly 220 ms RTT hit prediction is disabled and the shooter falls back to extrapolation, a fairness clamp so a target behind cover is not killed by a long rewind. — [Edgegap deep dive: Overwatch](https://edgegap.com/blog/game-backend-deep-dive-overwatch-2016-netcode-architecture-rollback)
- [Secondary] Halo Reach grenades: client plays the throw animation on press, the grenade object is created on host request and confirmed about one RTT later (a slow projectile handled by host spawn plus predicted animation). — [Edgegap deep dive: Halo Reach](https://edgegap.com/blog/game-backend-deep-dive-halo-reach-netcode-host-migration)
- [Official] Source lag compensation includes the shooter's interpolation amount in the rewind. — [Valve wiki: Lag Compensation](https://developer.valvesoftware.com/wiki/Lag_Compensation) (search extract)

### Inferences
- For our design (150 ms ping ceiling), set the max rewind to cover RTT/2 + interpolation delay (about 175 ms) and refuse to rewind beyond a configured cap (Overwatch used ~220 ms RTT; Valve stores up to 1 s). Put the cap in the tuning config.
- Knockback is applied to another player, so the victim's own prediction does not know it is coming. Without care, the victim sees a correction (rubber-band) one RTT later. Common mitigation (inference): the server includes the knockback impulse with the tick it applies, the victim's client reconciles from that tick and replays its inputs, and visual smoothing hides the correction. The fetched sources did not describe this case directly.
- Slow projectiles: spawn authoritatively on the server; the shooter's client may show a cosmetic predicted projectile that is replaced by the server one. Whether to rewind targets for slow projectiles is a design choice not settled by these sources; favouring the victim for slow, visible projectiles (no rewind) reduces "hit behind cover" complaints.
- Melee with rewind should be capped tighter than gunfire, since melee range is small and rewinds feel worse.

### Gaps
- No primary source fetched on slow-projectile lag compensation in shipped games (for example TF2 rockets, Overwatch projectiles).
- No primary source fetched on networked knockback or rubber-banding mitigation.

## Cheating: what Mini Militia trusted the client with, and minimum server-side validation

### Takeaway
No reliable technical analysis of Mini Militia hacking was found; search results are dominated by scam "generator" pages and paid modded APKs. The available, publicly visible signal is that mods advertise unlimited health, ammo and jetpack fuel ("nitro"), which implies the client held those values. The minimum validation set below is derived from the authoritative-server literature rather than from a Mini Militia write-up.

### Cited Findings
- [Community] Third-party mod and "hack" pages for Mini Militia advertise unlimited health, ammo and nitro; these are scam or unverified paid APK listings, not technical analyses. — [example spam page](https://oldwiki.miniscope.org/index.php/Working_Mini_Militia_Hack_Online_Health_Ammo_Nitro_Generator_No_Survey); [itch.io paid mod APK](https://rakibmahmud6514.itch.io/mini-militia-mod-by-sk-shohidullah)
- [Official, publisher] Miniclip (Mini Militia's publisher) has a public "Hacks and Fair Play" statement acknowledging player reports of hackers gaining unfair advantages; policy details were not retrieved. — [Miniclip support](https://support.miniclip.com/hc/en-us/articles/4407948154129-Hacks-and-Fair-Play-our-statement)
- [Dev] Server is authoritative; on mismatch "the client must move the character back" to the server position. — [Gambetta](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html)
- [Secondary] Overwatch's server consumes buffered inputs per command frame and duplicates the last input when none arrives (i.e. the server simulates from inputs; it does not accept client positions). — [Edgegap deep dive: Overwatch](https://edgegap.com/blog/game-backend-deep-dive-overwatch-2016-netcode-architecture-rollback)

### Inferences
- Minimum server validation set for our game (derived): (1) movement: server simulates from inputs only; clamp input axes to [-1, 1]; one input per tick per player, reject or drop extra inputs beyond a small buffer (blocks speed-hack via input flooding); (2) fire rate: server enforces weapon cooldown on its own tick clock; (3) ammo and fuel: server-owned counters, client values only for display; (4) pickups: server checks overlap at its own tick and that the pickup is active; (5) damage, health, score and Chaos Card state: never accepted from clients; (6) shot timestamps used for rewind: clamp to the cap and to the client's measured latency so a client cannot claim an arbitrarily old fire time.
- Mini Militia's advertised hacks (health, ammo, nitro) are exactly the values our GDD keeps on the server, so the design addresses them; the only unchecked party is the host itself, as the GDD already states.

### Gaps
- No reverse-engineering write-up of Mini Militia's network protocol or which values the client sent was found. The claim that Mini Militia trusted the client with health/ammo is an inference from mod advertising, not verified.

## Android hotspot and Wi-Fi LAN play

### Takeaway
The biggest platform fact: from Android 17 (API 37), apps targeting SDK 37+ are blocked from all local-network traffic (TCP and UDP, unicast, broadcast and multicast, inbound and outbound) unless they hold the runtime permission ACCESS_LOCAL_NETWORK (Nearby devices group). This affects ENet gameplay traffic on a hotspot, not only discovery. Also: hotspot subnets are not fixed on Android 11+, 255.255.255.255 broadcast is unreliable from a hotspot host, and some devices need a Wi-Fi MulticastLock to receive broadcast.

### Cited Findings
- [Official] Android 17 (API 37): local network protections enforced for apps targeting 37+; permission ACCESS_LOCAL_NETWORK, part of the NEARBY_DEVICES permission group; local network "blocked by default for all apps that update their target SDK". Requires permission: outgoing TCP, accepting incoming TCP, sending and receiving UDP unicast/multicast/broadcast. Enforced "deep in the networking stack" so it applies to all networking APIs. Apps targeting < 37 with INTERNET get an implicit grant and must not request it. — [Android: Local network permission](https://developer.android.com/privacy-and-security/local-network-permission)
- [Official] Exemptions: connecting to addresses obtained via NsdManager's system picker (DiscoveryRequest FLAG_SHOW_PICKER plus registerServiceInfoCallback / resolveService) does not need ACCESS_LOCAL_NETWORK; DNS to a local resolver on port 53 is exempt. If another Nearby devices permission (for example Bluetooth) is already granted, the user is not re-prompted. A "reset counter" gives apps extra chances to re-request after denial. — [Android: Local network permission](https://developer.android.com/privacy-and-security/local-network-permission)
- [Official] Failure modes: UDP sends fail with EPERM; TCP typically times out; NDK android_getnetworkblockedreason() reports ANDROID_NETWORK_BLOCKED_REASON_LNP. Android 16 had only an opt-in test mode (adb shell am compat enable RESTRICT_LOCAL_NETWORK <pkg>, restored by NEARBY_WIFI_DEVICES), now deprecated. — [Android: Local network permission](https://developer.android.com/privacy-and-security/local-network-permission)
- [Official] Android 13 (API 33): NEARBY_WIFI_DEVICES runtime permission is needed for Wi-Fi management APIs such as startLocalOnlyHotspot, Wi-Fi Aware and all Wi-Fi Direct (WifiP2pManager) calls; declare with usesPermissionFlags="neverForLocation" if no location is derived; ACCESS_FINE_LOCATION still needed for scans, keep it with maxSdkVersion 32 for older devices. Nearby devices group (added Android 12) shows one dialog for Bluetooth/Wi-Fi/UWB. — [Android: Wi-Fi permissions](https://developer.android.com/develop/connectivity/wifi/wifi-permissions)
- [Official] WifiManager.MulticastLock: "Normally the Wifi stack filters out packets not explicitly addressed to this device"; acquiring the lock lets the app receive multicast; "noticeable battery drain", release when not needed; locks are released automatically when the app exits or crashes. — [Android: WifiManager.MulticastLock](https://developer.android.com/reference/android/net/wifi/WifiManager.MulticastLock)
- [Community] Godot developer reports IPv4 broadcast on Android works only with a MulticastLock held, and IPv6 multicast still failed. — [Godot forum: IPv6 multicast problems](https://forum.godotengine.org/t/ipv6-multicast-problems/137300)
- [Community] A developer found 255.255.255.255 does not work when the Android device is itself providing the hotspot; use the interface's directed subnet broadcast (for example x.x.x.255). — [Chainfire: Android UDP broadcast and multicast](https://chainfire.eu/articles/742/_dev_Android_Datagrams_UDP_Broadcast_and_Multicast_...)
- [Community] One-way failures reported: a phone hotspot received broadcasts from a PC but the PC never saw packets from the phone. — [b4x forum](https://www.b4x.com/android/forum/threads/solved-android-blocking-receiving-udp-broadcast.99519/latest)
- [Community] 192.168.43.1 was the traditional Android hotspot gateway; on Android 11 a user reports the last two octets change each time the hotspot is re-enabled, so hard-coded addresses break. No official Google documentation of the randomisation was found. — [GitHub SoftApHelper](https://github.com/zimq/SoftApHelper); [VPNHotspot](https://github.com/nekohasekai/VPNHotspot); [speedtesthq explainer](https://speedtesthq.com/guides/network/192-168-43-1)
- [Official] Doze (Android 6+) and light Doze on screen-off (Android 7+) restrict network access outside maintenance windows. — [Android: Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Community] iPhone hotspots on iOS 18+ reportedly stopped delivering multicast to clients (not Android, but relevant if a host's friends tether off an iPhone later). — [Apple developer forums](https://developer.apple.com/forums/thread/773086)

### Inferences
- FLAG FOR GDD "Tech approach": the Hotspot row says the host is "found by local network broadcast" and the GDD treats discovery as the only risk. Once we target SDK 37 (Google Play's target-API rule normally forces this within about a year of release; verify the exact Play deadline), every LAN packet, including ENet gameplay to the host, needs ACCESS_LOCAL_NETWORK granted at runtime. A denied permission means hotspot play fails entirely with EPERM, not just discovery. The join flow needs a permission rationale screen and a clear failure message. Until we bump to 37, the implicit grant applies and we must not request it.
- The NsdManager picker path avoids the permission for the client-connects-to-host direction, but the host must still accept incoming traffic; whether accepting connections from an NSD-resolved peer is exempt on the host side is not stated. Treat as needing the permission until tested.
- Discovery design: host sends to the directed broadcast of its hotspot interface (computed from the interface address and netmask), never to 255.255.255.255; clients hold a MulticastLock only while browsing and release it on join; also try NSD/mDNS; and always offer QR code / short code encoding the host IP and port (the GDD already plans this fallback; the evidence says it is mandatory, not optional).
- Never hard-code 192.168.43.1. Read the host's actual interface address at hosting time and put it in the QR/code.
- Client/AP isolation on public or venue Wi-Fi (hostels, classrooms) blocks peer-to-peer traffic entirely; no fallback on that network works except switching to a phone hotspot or the online relay. The join error should say so. (Inference; no direct source fetched on AP isolation.)

### Gaps
- No official source on the hotspot subnet randomisation algorithm or per-OEM behaviour (Samsung, Xiaomi, Realme are key for India).
- No source found on whether the Android hotspot host itself applies client isolation between tethered clients (it matters only for client-to-client traffic, which a star topology does not need).
- Nearby Connections API and Wi-Fi Direct as fallbacks for games were not researched in depth; Wi-Fi Direct needs NEARBY_WIFI_DEVICES on Android 13+ (sourced above), Nearby Connections details are not sourced here.
- Android 16 QPR and Android 17 OEM variations not checked.

## Godot-specific: ENet and high-level multiplayer on Android (Godot 4.x), LAN discovery

### Takeaway
Godot 4.7 docs require the INTERNET permission in the Android export preset (otherwise all networking is blocked) and say some Android devices need CHANGE_WIFI_MULTICAST_STATE for broadcast/multicast. Godot does not itself acquire a Wi-Fi MulticastLock in any source found; developers report needing one. Phone-hosting failures in the forum are usually IPv6/CGNAT or wrong-address problems.

### Cited Findings
- [Official, Godot 4.7] PacketPeerUDP: enable INTERNET in the Android export preset, "Otherwise, network communication of any kind will be blocked by Android." set_broadcast_enabled is off by default and must be on before sending to a broadcast address; "Some Android devices might require the CHANGE_WIFI_MULTICAST_STATE permission" for broadcast and multicast. bind("*") binds IPv4 and IPv6; "0.0.0.0" or "::" binds only that family; a specific address binds only that interface. — [Godot 4.7 docs: PacketPeerUDP](https://docs.godotengine.org/en/stable/classes/class_packetpeerudp.html)
- [Official, Godot 4.7] High-level multiplayer uses a modified ENet with full IPv6 support; INTERNET permission warning repeated; unreliable_ordered drops packets that arrive after a newer one and "can cause packet loss if used incorrectly"; channels separate streams; only UDP is used. — [Godot 4.7 docs: High-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- [Community] Godot LAN discovery demo uses PacketPeerUDP.set_broadcast_enabled(true) and says Android exports need CHANGE_WIFI_MULTICAST_STATE. — [Godot asset store: network broadcast discovery demo](https://store.godotengine.org/asset/lucas-campos-achcar/godot-network-broadcast-discovery-demo/)
- [Community] Godot 4 Android-specific UDP failures where desktop works. — [Godot forum: UDP works on desktop but fails on Android](https://forum.godotengine.org/t/title-udp-works-on-desktop-but-fails-on-android-export/130822); [godotforums: UDP packets not leaving Android](https://godotforums.org/d/43023-udp-packets-not-leaving-the-android-kennel)
- [Community] Common Godot LAN fixes: enable INTERNET in the export, connect to the host's LAN address not localhost, set bind IP explicitly so ENet uses the right interface; create_client can return OK yet never connect if peer settings mismatch. Godot 4.2 era. — [Godot forum: no errors but connected_to_server not emitted](https://forum.godotengine.org/t/no-errors-but-connected-to-server-not-emitted/46203); [Godot forum: LAN multiplayer basics](https://forum.godotengine.org/t/lan-multiplayer-basics/56439)
- [Community] Phone-as-host failure: Android host showed an IPv6 address and clients could not reach it (Godot 4). — [Godot forum](https://forum.godotengine.org/t/the-mobile-becoming-server-in-local-multiplayer-games-is-a-chaos/53979)

### Inferences
- Export preset checklist (Godot 4.7, Android): INTERNET; CHANGE_WIFI_MULTICAST_STATE; ACCESS_NETWORK_STATE and ACCESS_WIFI_STATE (likely needed to read interface state; not sourced here); ACCESS_LOCAL_NETWORK only once target SDK is 37. A MulticastLock needs either a small Android plugin (Kotlin) or a Godot Android plugin; GDScript alone cannot acquire it (inference; verify).
- Bind the ENet server on IPv4 (0.0.0.0) for hotspot play and put the IPv4 address in the QR code; dual-stack "*" plus an IPv6 address shown to users is the reported failure pattern.
- Discovery socket and game socket should use different ports; discovery runs only in the lobby.

### Gaps
- No Godot GitHub issue was found confirming an ENet bug specific to Android in 4.x; the reports are configuration-level.
- No sourced information on Godot 4.7 Android lifecycle (NOTIFICATION_APPLICATION_PAUSED timing, whether ENet keeps servicing while paused). Must be device-tested.
- Whether Godot 4.7's Android export template already declares CHANGE_WIFI_MULTICAST_STATE or acquires a MulticastLock automatically was not confirmed.

## Bandwidth: per-player bytes per second for 30 Hz state sync, and ways to keep it low

### Takeaway
Few sources give per-player numbers for small 2D games. The best concrete reference is Halo Reach: 250 kbps for a 16-player match after prioritisation and bit-packing. Proven reductions are send-rate cuts, per-client priority, quantisation and hand-packed input.

### Cited Findings
- [Secondary] Halo Reach: naive approach ~20 Mbps for 16 players; shipped 250 kbps for 16 players against a 384 kbps target; over 80% reduction from Halo 3. Per-client priority scoring (distance, on-screen, threat, recent interaction); low-priority objects update slower rather than stalling; position state example 30 updates/s; control input about 20 bits per player, hand-packed, sent as often as possible. — [Edgegap deep dive: Halo Reach](https://edgegap.com/blog/game-backend-deep-dive-halo-reach-netcode-host-migration)
- [Dev] Gaffer's 900-cube demo: naive 60 pps ~11.6 Mbit/s; 10 pps ~2 Mbit/s; each cube 225 bits (~28 bytes) after quantisation. — [Gaffer on Games, Snapshot Interpolation](https://gafferongames.com/post/snapshot_interpolation/)

### Inferences
- Back-of-envelope for us (inference): 8 players x ~16 bytes quantised state (position, velocity, aim, flags) = ~128 bytes per snapshot + ENet/UDP/IP overhead (~40 to 50 bytes) at 30 Hz is roughly 5 to 6 KB/s downstream per client, about 40 to 50 KB/s total upload from the host for 7 clients, plus projectiles. Well within hotspot Wi-Fi; mobile-data cost for online rooms over a 5-minute match is low single-digit MB. Measure in phase 1 rather than trust this.
- Biggest wins in order: quantise floats (positions to 1/16 pixel or similar in 16-bit ints), send input not state from clients, bundle unacked inputs (tiny), delta against the last acknowledged snapshot, lower rate for far or static objects.

### Gaps
- No sourced per-player bytes/second figures for comparable 2D mobile shooters (Mini Militia, Brawlhalla) were found.

## Testing netcode before real devices

### Takeaway
Sourced material here is thin. Netem (Linux tc) is the documented Android-side approach for latency/loss injection; Gaffer's tests used 5% loss and +/- 2 frames jitter as a standard condition.

### Cited Findings
- [Official] Android Automotive docs use Linux tc/NetEm (needs ifb and netem kernel modules) with a wrapper script taking latency, bandwidth and loss, for example "100ms 1mbit 0%", verified with ping and curl. — [AOSP: Simulate networks in AAOS](https://source.android.com/docs/automotive/tools/network-simulation)
- [Dev] Gaffer's reference test condition: 5% packet loss and +/- 2 frames (60 fps) jitter. — [Gaffer on Games, Snapshot Interpolation](https://gafferongames.com/post/snapshot_interpolation/)
- [Official] Android 16 local-network opt-in test: adb shell am compat enable/disable RESTRICT_LOCAL_NETWORK <package> (deprecated in 17 but still a test lever). — [Android: Local network permission](https://developer.android.com/privacy-and-security/local-network-permission)
- [Dev] Determinism of the movement step is what makes replay reproduce the right state (Overwatch). — [Edgegap deep dive: Overwatch](https://edgegap.com/blog/game-backend-deep-dive-overwatch-2016-netcode-architecture-rollback)

### Inferences
- Cheapest useful setup (inference): run host and N clients as headless Godot instances on the Mac, with an in-game network simulator layer (artificial delay, jitter, loss on the send path) that is a debug-only config. This works the same on macOS and on Android test builds and avoids OS tools. Record server state hash per tick and client reconciled-state hash per tick for the local player; a mismatch after reconciliation flags non-determinism in the movement step. Run a scripted bot soak (8 bots, 20 minutes) per build in CI and fail on errors or hash drift.
- macOS options (known but not sourced in this session): Apple's Network Link Conditioner (Xcode additional tools) and dnctl/pfctl dummynet. Verify before relying on them.
- Test the Android 17 permission-denied path explicitly (expect EPERM on UDP send) and a hotspot host toggled off and on (new subnet).

### Gaps
- No sourced studio postmortem on automated netcode soak tests or state-hash desync detection was obtained within the budget.
- macOS Network Link Conditioner and dnctl/pfctl usage not sourced; Android emulator network delay options not sourced.

## Summary of points where evidence challenges or sharpens the GDD Tech approach

### Takeaway
The GDD is broadly consistent with the evidence. Five items need action or correction.

### Cited Findings
- Android 17 local-network permission gates all LAN traffic for targetSdk 37+ apps. — [Android: Local network permission](https://developer.android.com/privacy-and-security/local-network-permission)
- Hotspot-host broadcast to 255.255.255.255 is reported to fail; directed broadcast works. — [Chainfire](https://chainfire.eu/articles/742/_dev_Android_Datagrams_UDP_Broadcast_and_Multicast_...)
- Backgrounded mobile apps lose sockets; Doze restricts network. — [Heroic Labs forum](https://forum.heroiclabs.com/t/not-able-to-find-match-after-keeping-app-in-background/5074); [Android Doze](https://developer.android.com/training/monitoring-device-state/doze-standby)
- Rewind caps exist in shipped games (Overwatch ~220 ms RTT; Valve 1 s storage). — [Edgegap Overwatch](https://edgegap.com/blog/game-backend-deep-dive-overwatch-2016-netcode-architecture-rollback); [Valve wiki](https://developer.valvesoftware.com/wiki/Lag_Compensation)

### Inferences
1. GDD "Hotspot ... found by local network broadcast": add that hotspot play needs the ACCESS_LOCAL_NETWORK runtime permission once targeting Android 17, for gameplay traffic too, and a permission rationale in the join flow. This is the most important correction.
2. GDD "auto-discovery can be unreliable ... build the QR or code fallback at the same time": confirmed and stronger; the QR/code must carry the actual host IPv4 and port, since the hotspot subnet is not fixed on Android 11+.
3. GDD "If the host leaves: the match ends cleanly": also define host backgrounding or screen-off as host loss after a timeout; it cannot be prevented by the app.
4. GDD "Playable up to 150 ms ping" plus 30 Hz: interpolation delay (~67 to 150 ms) plus one-way latency means lag-compensation rewind of ~175 ms; set an explicit rewind cap and interpolation delay as tuning values in the config resource. Decide favour-the-shooter vs favour-the-victim per weapon type (hitscan vs slow projectile vs knockback); this is a design decision for Rahul.
5. GDD "Hotspot cheating: not a concern": acceptable, but the same server validation must still run in hotspot mode since the code path is shared with online rooms.

### Gaps
- Exact Google Play deadline for target API 37 not checked.

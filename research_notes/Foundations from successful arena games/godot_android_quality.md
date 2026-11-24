# Godot 4.7 Android quality foundation: testing, performance and release practice for a budget-phone 2D arena shooter

Research date: 24 November 2026. Engine baseline: Godot 4.7 stable. Phoronix reported its release on 18 June 2026. 4.7.1 has shipped and a 4.7.2 RC exists. Most Godot docs quoted below are the "4.7 documentation" pages.

Project state observed (read-only) in `project.godot` on this date:
- `config/features` contains "4.7" and "Mobile".
- `renderer/rendering_method="mobile"`.
- `gdscript/warnings/untyped_declaration=2`, which makes it an error.
- `pointing/emulate_mouse_from_touch=false`.
- The only addon is netfox. `tests/` holds only `autopilot_script.gd`.

Source quality: claims taken from fetched official pages are cited directly. Search-summary results are labelled "(search summary)". Community reports are labelled "(community)". Items I know from experience but did not re-verify this session appear only under Inferences or Gaps, marked "unverified".

## Renderer choice: Compatibility versus Mobile for 2D on low-end Android

### Takeaway
The official 4.7-era docs recommend Compatibility for low-end hardware and say it is "usually good enough for 2D". Mobile is described as the default for newer mobile devices and as slower than Compatibility on old or low-end hardware. The project currently uses Mobile, so this should be an early, measured decision on real budget Mali and PowerVR phones.

### Cited Findings
- Official statements on the renderers page:
  - Compatibility "supports the widest range of hardware".
  - It is recommended when "You want the best performance possible on all devices and don't need advanced rendering features".
  - 2D games are listed as a reason to choose it.
  - Mobile is the default on mobile platforms, but in the "Runs on old and low-end hardware" row it is marked slower than Compatibility.
  - Forward+ on mobile is "poorly optimized". Use Mobile or Compatibility instead.

  Source: [Godot docs, Overview of renderers (latest/4.7)](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html)
- Mobile and Forward+ require Vulkan, D3D12 or Metal through the RenderingDevice backend. Compatibility uses OpenGL and runs where RenderingDevice is unavailable. — [Godot renderers doc](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html)
- Since Godot 4.4, Forward+ or Mobile falls back to Compatibility when RenderingDevice is unavailable. The game may then look different from the intended look. This can be disabled with Rendering > Rendering Device > Fallback to OpenGL 3. — [Godot renderers doc](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html)
- Features Compatibility lacks that matter for 2D:
  - particle trails
  - particle SDF collision
  - 2D MSAA
  - 2D HDR viewport
  - compute shaders

  Mobile supports compute shaders but notes "a performance penalty on older devices". — [Godot renderers doc](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html)
- The Godot 4.7 release page says Vulkan Mobile "matches or outperforms" Compatibility in some benchmarks, and Godot now recommends Mobile for new XR projects. This is about XR and higher-end devices, not 2D on budget phones. — [Godot 4.7 release page](https://godotengine.org/releases/4.7/)
- (Community) Forum reports of Vulkan problems:
  - known issues between Godot's Vulkan renderer and Mali GPUs on Android
  - a Godot 4.2.1 Adreno crash that does not happen with gl_compatibility
  - a black screen on Adreno 616
  - one budget phone that still quit silently in Compatibility

  Sources: [Forum: Vulkan crash on some Android devices](https://forum.godotengine.org/t/help-with-a-vulcan-crash-on-some-android-devices/55000); [Forum: Project crashes on Android with Vulkan error](https://forum.godotengine.org/t/project-crashes-on-android-with-following-vulkan-error/50766); [GitHub issue 67430](https://github.com/godotengine/godot/issues/67430); [Forum: Godot 4 app doesn't run on older devices](https://forum.godotengine.org/t/godot-for-mobile-app-doesnt-run-on-older-devices/84692)
- (Community) Compatibility in Godot 4 is "expected to have more bugs" than Godot 3's GLES2. — [Forum: Godot 3 vs Godot 4 mobile games](https://forum.godotengine.org/t/godot-3-vs-godot-4-mobile-games/36251)
- Google and The Forge worked on Godot's Vulkan renderer for Android. Google says the optimizations are not specific to mobile hardware. — [Android Developers story: Godot Engine Vulkan optimization](https://developer.android.com/stories/games/godot-vulkan)

### Inferences
- For a flat-art 2D game, Compatibility gives up nothing the GDD needs. The GDD wants screen shake, freeze frames, muzzle flashes, dust and slow motion. All of these work without trails, compute or 2D HDR. Compatibility also avoids Vulkan driver risk on budget Mali and PowerVR parts. Default recommendation: switch to `gl_compatibility` unless a device A/B test shows Mobile is clearly better.
- If Mobile is kept, leave the OpenGL 3 fallback enabled so phones without Vulkan still run.
- Week-one test: build the same scene with each renderer and log frame time and device temperature over a 20-minute soak on the cheapest target phone.

### Gaps
- I found no published measurement comparing Compatibility and Mobile for frame time, heat or APK size on budget Mali, PowerVR or Adreno phones in Godot 4.4 to 4.7. This must be measured in-house.
- I did not confirm whether a Compatibility-only custom template is meaningfully smaller than one built for both renderers.

## Automated testing: GUT, gdUnit4, headless runs and CI

### Takeaway
Both frameworks support Godot 4.7:
- GUT 9.7.1, on the `godot_4_7` branch.
- gdUnit4 v6.2.x, which supports Godot 4.5 to 4.7.1. Its master branch, v7.0.0, targets 4.7 and 4.8-dev.

The lightest setup that still catches regressions is GUT, or plain `--headless --script` tests, run headlessly in CI. Add gdUnit4 only if the team needs its scene runner for input simulation.

### Cited Findings
- GUT versions by Godot release: 9.7.1 for 4.7.x (`godot_4_7` branch); 9.6.1 or main for 4.6.x; 9.5.0 for 4.5.x; 9.4.0 for 4.3 to 4.4. GUT has a command-line interface. — [GUT repository README](https://github.com/bitwes/Gut)
- gdUnit4 versions: master (v7.0.0) supports Godot 4.7, 4.7.1 and 4.8.dev7; v6.2.x supports 4.5 through 4.7.1. — [gdUnit4 repository](https://github.com/godot-gdunit-labs/gdUnit4)
- gdUnit4 has a command-line tool for CI/CD, HTML and JUnit XML reports, and a GitHub Marketplace action ("gdunit4-action"). — [gdUnit4 repository](https://github.com/godot-gdunit-labs/gdUnit4)
- gdUnit4's scene runner simulates:
  - mouse
  - keyboard
  - touch
  - custom input actions
  - waiting for signals

  It also supports mocking and spying on scenes. — [gdUnit4 repository](https://github.com/godot-gdunit-labs/gdUnit4)
- Godot 4.7 command-line flags for CI (all from the [Godot 4.7 command line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)):
  - `--headless` is the same as `--display-driver headless --audio-driver Dummy`.
  - `--import` imports resources, then quits.
  - `--check-only` with `--script` parses a script for errors and quits.
  - `-s/--script` runs a script.
  - `--quit` and `--quit-after <n>` stop the run.
  - `--fixed-fps <fps>` disables real-time sync, which makes simulation tests deterministic.
  - `--export-release` / `--export-debug <preset> <path>` export a build. The preset must exist in `export_presets.cfg`.
  - `--log-file` writes logs to a path.
  - `--remote-debug <uri>` connects to a remote debugger.
  - `--gpu-profile` and `--print-fps` report rendering cost.

### Inferences
- Minimal CI pipeline:
  1. `godot --headless --import` once, because a fresh checkout has no `.godot/` cache.
  2. Run the GUT CLI headless, or a plain `extends SceneTree` script under `--headless --script res://tests/run_all.gd --fixed-fps 30 --quit-after N` that exits non-zero on failure.
  3. Run `--export-debug` for the Android preset so export breakage shows up early.
- Use `--fixed-fps 30` to match the GDD's 30 ticks per second.
- Most valuable tests for this game:
  - pure-logic unit tests for the config resource, damage, knockback and Chaos Card setting changes
  - one headless server-plus-bot match simulation that runs N ticks and asserts invariants (health never below 0, scores add up, no errors in log)
- The existing `tests/autopilot_script.gd` suggests the second style has already started.
- The `addons/` folder is committed, and both GUT and gdUnit4 are plain GDScript addons. Pin the exact tag, for example GUT 9.7.1.

### Gaps
- I did not verify the exact GUT CLI command line (`addons/gut/gut_cmdln.gd` flags) or the gdUnit4 `runtest` script syntax for 4.7. Both are in the linked repos' docs.
- I did not confirm release dates for GUT 9.7.1 or gdUnit4 6.2.x.
- I found no measured comparison of the two frameworks' headless reliability.

## Static checking: warnings as errors and linters

### Takeaway
Godot 4.7 can turn any GDScript warning into an error under Project Settings > Debug > GDScript, for example `debug/gdscript/warnings/unused_variable`. The project already does this for `untyped_declaration`.

gdtoolkit's latest PyPI release is 4.5.0 (9 October 2025). No release is published for Godot 4.6 or 4.7, so 4.7-only syntax may fail to parse.

### Cited Findings
- Godot 4.7 docs:
  - Warnings can be turned into errors so the game will not run until they are fixed.
  - Setting names match warning names, for example `debug/gdscript/warnings/unused_variable`.
  - `@warning_ignore` suppresses a warning locally, and its autocomplete lists all warnings.

  Source: [Godot 4.7 GDScript warning system](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/warning_system.html)
- gdtoolkit includes:
  - gdlint (linter)
  - gdformat (formatter, which "can cause data loss", so use version control)
  - gdparse
  - gdradon (cyclomatic complexity)

  Install it with `pip install "gdtoolkit==4.*"`. It provides pre-commit hooks. — [gdtoolkit repository](https://github.com/Scony/godot-gdscript-toolkit)
- gdtoolkit release history: 4.5.0 on 9 Oct 2025, 4.3.4 on 29 Jun 2025, 4.3.3 on 2 Nov 2024. It requires Python >= 3.7. — [PyPI gdtoolkit](https://pypi.org/project/gdtoolkit/)

### Inferences
- Unverified warning list to set to Error. I know these names from the Godot 4.x editor but did not confirm them on the docs page this session:
  - `untyped_declaration` (already set)
  - `unsafe_property_access`
  - `unsafe_method_access`
  - `unsafe_cast`
  - `unsafe_call_argument`
  - `return_value_discarded`, as a warning at least
  - `unused_variable`, `unused_parameter`, `unused_signal`
  - `shadowed_variable`, `shadowed_global_identifier`
  - `integer_division`
  - `narrowing_conversion`
  - `inference_on_variant`
  - `confusable_identifier`
- Set `debug/gdscript/warnings/exclude_addons=true`, which I believe is the default, so netfox and the test framework do not fail the build. Confirm both in the editor.
- The cheapest static gate is a CI step that runs `godot --headless --check-only --script <file>` over every `.gd` file, or simply `--import`, and fails on any `SCRIPT ERROR` in the output. It uses the engine's own parser, so it always matches 4.7 syntax.
- Add gdlint as a second layer, but treat a gdtoolkit parse failure on new syntax as a tool gap, not a code bug.

### Gaps
- I found no official, complete list of 4.7 warning names with default levels. Read it from the editor's Project Settings.
- I did not confirm whether gdtoolkit 4.5.0 parses every 4.7 construct.
- I did not find other maintained GDScript linters.

## Common GDScript bug classes and prevention

### Takeaway
The engine documents processing order (priority first, then tree order) and the fact that freeing a node frees its children. The other bug classes below come from engineering practice and are not documented in what I fetched, so treat them as a team checklist.

### Cited Findings
- `_physics_process` runs in order of `process_physics_priority`, and `_process` in order of `process_priority`, lower values first. Ties are processed in tree order, top to bottom. — [Godot 4.7 Node class reference](https://docs.godotengine.org/en/stable/classes/class_node.html)
- Freeing a node with `free()` or `queue_free()` frees all its children. — [Godot 4.7 Node class reference](https://docs.godotengine.org/en/stable/classes/class_node.html)
- `--fixed-fps` disables real-time synchronisation, which is useful for reproducible simulation runs. — [Godot 4.7 command line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)

### Inferences
Prevention checklist (unverified engineering practice):
- **Freed-object access and await after free.** After any `await`, check `is_instance_valid(self)` and the validity of any held node before using it. Prefer `queue_free()` to `free()`.
- **Signals connected twice.** Connect in `_ready()` only. Use `is_connected()` or `CONNECT_ONE_SHOT` where re-entry is possible. Pooled objects must disconnect when returned to the pool.
- **Node-path fragility.** Use `@export var x: NodePath` or typed `@export var node: Node2D`, or `%UniqueName`, instead of long `$A/B/C` paths.
- **Physics versus process.** All gameplay and netfox tick logic goes in netfox's tick callbacks or `_physics_process`, never `_process`. `_process` is for visuals only. Set explicit priorities where order matters.
- **Resource sharing between instances.** Resources loaded from disk are shared. Call `duplicate()` (or `duplicate(true)`) for per-instance state, or enable "Local to Scene". This matters because Chaos Cards change shared match settings: the settings resource must be the single server-owned instance, and per-player state must never write to it.
- **Float determinism.** Do not rely on bit-identical floats across ARM devices. The server-authoritative model handles this: only the host's simulation counts, and clients are reconciled.

### Gaps
- I did not fetch a Godot doc or issue that measures or confirms float non-determinism across Android CPUs.
- I did not fetch documentation of the "await after free" behaviour.

## Android specifics: export settings, Play requirements, lifecycle, input

### Takeaway
Google Play requirements:
- From 31 August 2026, new apps and updates must target API 36 (Android 16). An extension to 1 November 2026 was available, and that date has passed.
- From 1 February 2027, updates that do not support 16 KB page sizes cannot be released.

Godot 4.7's Android toolchain is NDK r28b. Google says NDK r28 or newer builds 16 KB-aligned by default, but verify the exported AAB anyway.

### Cited Findings
- From 31 August 2026:
  - New apps and updates must target API 36 (Android 16) or higher.
  - Existing apps must target API 35 or higher to stay visible to new users on newer Android versions.
  - Extensions to 1 November 2026 could be requested.

  Source: [Android Developers, Meet Google Play's target API level requirement](https://developer.android.com/google/play/requirements/target-sdk)
- 16 KB page sizes:
  - Apps targeting API 35+ must support 16 KB pages on 64-bit devices.
  - From 1 February 2027, non-compliant updates cannot be released.
  - NDK r28+ compiles 16 KB-aligned by default.

  Verification commands:
  - `zipalign -c -P 16 -v 4 app.apk`
  - `bundletool dump config --bundle=app.aab | grep alignment`, which should show `PAGE_ALIGNMENT_16K`
  - `check_elf_alignment.sh app.apk`
  - On a 16 KB emulator image (Android 15+), `adb shell getconf PAGE_SIZE` should return `16384`.

  Source: [Android Developers, Support 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes)
- Godot 4.7 Android toolchain:
  - JDK 17 recommended
  - Platform-Tools 35.0.0+
  - Build-Tools 35.0.1
  - platform android-35
  - NDK r28b (28.1.13356709)
  - CMake 3.10.2

  New Play apps must be AAB, which requires a Gradle build. — [Godot 4.7, Exporting for Android](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)
- Godot 4.7 export options that exist:
  - `gradle_build/min_sdk`, `gradle_build/target_sdk`
  - `architectures/arm64-v8a|armeabi-v7a|x86|x86_64`
  - `screen/immersive_mode`, `screen/edge_to_edge`
  - `permissions/internet`, `permissions/access_network_state`, `permissions/change_wifi_multicast_state`
  - `gradle_build/export_format` (APK or AAB)
  - `gradle_build/compress_native_libraries`. The docs suggest keeping it false for Play Store.

  The fetched text did not show default values for these. — [Godot 4.7 EditorExportPlatformAndroid](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformandroid.html)
- Godot 4.7 Android additions:
  - GABE (Android build environment) is stable.
  - Splash screen export options no longer need a Gradle build.
  - Perfetto is the default tracing tool for Android editor and template builds.
  - A new `VirtualJoystick` node (Fixed, Dynamic and Following modes).
  - A project setting "Ignore Joypad on Unfocused Application".

  Source: [Godot 4.7 release page](https://godotengine.org/releases/4.7/)
- Lifecycle notifications (Godot 4.7):
  - `NOTIFICATION_APPLICATION_PAUSED` and `NOTIFICATION_APPLICATION_RESUMED` are specific to Android and iOS.
  - `NOTIFICATION_APPLICATION_FOCUS_OUT` is sent on mobile too.
  - `NOTIFICATION_WM_GO_BACK_REQUEST` is sent on the Android Back button and is Android-only.

  Source: [Godot 4.7 Node class reference](https://docs.godotengine.org/en/stable/classes/class_node.html)

### Inferences
- Concrete settings to set in week one (unverified exact names and defaults; confirm in the editor):
  - target SDK 36 and min SDK 24 or higher
  - architectures: arm64-v8a only for Play
  - Gradle AAB
  - `screen/immersive_mode=true`
  - `display/window/energy_saving/keep_screen_on=true`
  - landscape orientation via `display/window/handheld/orientation`
  - only the INTERNET, ACCESS_NETWORK_STATE and CHANGE_WIFI_MULTICAST_STATE permissions. Multicast is needed for hotspot LAN broadcast discovery.
  - `application/config/quit_on_go_back=false`, then handle `NOTIFICATION_WM_GO_BACK_REQUEST` with a pause or leave dialog
- On Android, armeabi-v7a matters only for very old 32-bit phones. Whether to keep it is a decision for Rahul.
- Networking on pause. When the host phone is paused, for example by a call or the app switcher, its server stops ticking and clients time out. Handle `NOTIFICATION_APPLICATION_PAUSED` this way:
  - A client tells the host it is away, and the host treats its inputs as idle.
  - If the host pauses, the host broadcasts a pause and clients freeze with a grace timer. If it does not resume within N seconds, end the match cleanly.
  - On resume, resync netfox time before accepting input.
- Touch:
  - The project has `emulate_mouse_from_touch=false`, which is correct for twin-stick input because it avoids duplicate mouse events.
  - Track `InputEventScreenTouch` and `InputEventScreenDrag` by `index` per finger.
  - Evaluate the 4.7 `VirtualJoystick` node before writing custom sticks.

### Gaps
- I did not confirm Godot 4.7's default min and target SDK values, or whether 4.7.x already defaults to target 36.
- I did not verify Android audio latency guidance for Godot. The `audio/driver/output_latency` setting and Android's low-latency path were not researched.
- I did not research the edge-to-edge behaviour change in Android 15+.

## Performance on budget phones

### Takeaway
Official 4.7 guidance is to profile first, on more than one device. Frame time is set by the slower of CPU and GPU. CPUParticles2D "may perform better on low-end systems or in GPU-bottlenecked situations".

Perfetto is now the default Android tracing tool in Godot 4.7. Concrete draw-call, overdraw and thermal budgets were not found in official Godot docs and must be set in-house.

### Cited Findings
- From the Godot 4.7 general optimization page:
  - "Always use profiling and timing to guide your efforts."
  - Measure on more than one device.
  - Total frame time is set by the slower of CPU and GPU.
  - Dynamic memory allocation can cause spikes.

  Source: [Godot 4.7 General optimization tips](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- Particles (search summary):
  - CPUParticles2D may perform better on low-end systems or when the GPU is the bottleneck.
  - GPUParticles2D is recommended otherwise.
  - Since 4.2, CPU particles have been frozen at their current feature set.

  Sources: [Godot docs, 2D particle systems](https://docs.godotengine.org/en/stable/tutorials/2d/particle_systems_2d.html); [Godot blog, Progress report: state of particles](https://godotengine.org/article/progress-report-state-of-particles/)
- Godot 4.7:
  - Perfetto is the default tracing tool for Android builds.
  - AtlasTexture can be tiled in TextureRect, which reduces texture changes.

  Source: [Godot 4.7 release page](https://godotengine.org/releases/4.7/)
- `--gpu-profile` and `--print-fps` report rendering cost from the command line. — [Godot 4.7 command line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)

### Inferences
Practical budget (unverified engineering practice):
- Hold about 12 ms CPU and 12 ms GPU per frame, inside the 16.6 ms budget at 60 fps. The headroom covers thermal throttling during a 20-minute session.
- Profile at the 20-minute mark, not at minute one.
- Use the Godot remote debugger: deploy with "Remote Debug" over USB or Wi-Fi and use the Profiler and Monitors tabs.
- Use Perfetto system traces for frame pacing and CPU frequency.
- Use Android GPU Inspector for GPU counters where the phone supports it. Many budget Mali and PowerVR parts may not.

Other choices:
- Pool bullets, casings and particles.
- Avoid per-frame `Array` and `Dictionary` creation and string building in hot paths.
- Use typed GDScript, which runs faster.
- Use Area2D or raycasts for bullets instead of RigidBody2D.
- Pack sprites into atlases so 2D batching works.
- Keep the three parallax layers opaque where possible to limit overdraw.
- Keep V-Sync on, and consider `Engine.max_fps = 60` so 90 Hz or 120 Hz phones do not burn power.
- For textures, use lossless or VRAM-compressed formats with the ETC2/ASTC import option for mobile. Pixel-flat doodle art often compresses well as lossless WebP.

### Gaps
- I did not fetch Godot's 2D batching documentation, so the details of batching in Compatibility versus RenderingDevice in 4.4 to 4.7 are unconfirmed.
- I found no official draw-call or overdraw limits for budget GPUs.
- I found no published Godot 4 Android postmortem with thermal measurements.
- I did not confirm Android GPU Inspector device support for Mali-G52 or PowerVR GE8320-class GPUs.

## Download size

### Takeaway
The biggest documented savings, from the Godot 4.7 "Optimizing a build for size" page:
- Strip debug symbols: 5 to 10 times smaller binary.
- `lto=full`: high.
- `optimize=size` / `size_extra` (`size_extra` added in 4.5): high.
- Build profile (`build_profile=`): moderate to high.
- Fallback text server: high.
- `disable_3d=yes`: about 15 percent.
- `disable_advanced_gui=yes`: moderate.

Combined with an arm64-only AAB, this should keep the game well under 80 MB. Stock-template size figures are community anecdotes only.

### Cited Findings
- All techniques below are from [Godot 4.7, Optimizing a build for size](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/optimizing_for_size.html):

  | Technique | Flag | Stated savings |
  |---|---|---|
  | Strip debug symbols | `debug_symbols=no` on Android | very high, 5 to 10 times |
  | Link-time optimization | `lto=full` (needs at least 8 GB RAM, 12 to 16 GB recommended) | high |
  | Optimize for size | `optimize=size`, or `optimize=size_extra` (added in 4.5) | high |
  | Build profile | `build_profile=path.gdbuild` | moderate to high |
  | Fallback text server | `module_text_server_adv_enabled=no module_text_server_fb_enabled=yes` | high. Both flags are required or no text renders. |
  | Disable 3D | `disable_3d=yes` | about 15 percent |
  | Disable advanced GUI | `disable_advanced_gui=yes` | moderate |
  | Disable 3D physics | `disable_physics_3d=yes` | low to moderate |
  | Disable modules | `module_<name>_enabled=no` | very low to moderate |

- (Search summary of the translated docs) Build-profile feature detection can be too aggressive and disable features needed at runtime. — [Godot docs, optimizing for size (zh-cn 4.5)](https://docs.godotengine.org/zh-cn/4.5/engine_details/development/compiling/optimizing_for_size.html)
- (Community) Reported sizes:
  - A Godot 4 APK of about 130 MB, against 50 to 60 MB under Godot 3.
  - A custom build of 35 MB APK and about 110 MB installed.
  - Claims that a stock template is about 19 MB and a stripped one about 13 MB.
  - Advice to use one architecture per export preset to strip unused libraries.

  These are anecdotal and not tied to a version. Sources: [Forum: Godot 4 Android build size difference](https://forum.godotengine.org/t/godot-4-android-build-size-difference/58593); [Forum: absurd file size increase on APK](https://forum.godotengine.org/t/absurd-file-size-increase-when-my-project-is-exported-to-apk/130000); [Godot Q&A: optimized size for simple Android build](https://ask.godotengine.org/149365/large-optimized-size-simple-android-build-build-flags-achieve)
- Godot 4.7's export template downloader fetches templates per platform or architecture. — [Godot 4.7 release page](https://godotengine.org/releases/4.7/)

### Inferences
- An AAB already makes Play serve only the device's ABI. The 80 MB target applies to the per-device download, which is mostly engine (one ABI) plus PCK.
- Measure early: export a blank 4.7 project as an arm64 AAB, then check the per-device size with `bundletool get-size total`.
- Keep `disable_physics_2d` off, because the game uses 2D physics.
- Audio: Ogg Vorbis for music loops and short WAV or compressed formats for SFX.
- Custom templates add build complexity. Adopt them only if the stock template plus assets threatens 80 MB.

### Gaps
- I found no official, measured size for a stock Godot 4.7 arm64 Android template, APK or AAB.

## Crash and error capture without a backend

### Takeaway
The Sentry Godot SDK captures native Android crashes and Godot script errors, with GDScript stack traces on Godot 4.5+. It needs a Gradle build and a Sentry account. The zero-backend baseline is `adb logcat`, Godot file logging (`--log-file` or the file-logging project setting), and Play Console Android vitals.

### Cited Findings
- Sentry Godot SDK (search summary):
  - Uses the Android SDK and captures Java, Kotlin, C and C++ crashes plus Godot script and shader errors.
  - GDScript stack traces need Godot 4.5+.
  - Requires the Gradle build.
  - No automatic screenshots on Android, and no attachments on native crashes.
  - GitHub releases list 2.1.1, which fixes missing GDScript line numbers on Android with Godot 4.6+. The docs page may still show an older version.

  Sources: [Sentry docs, Godot](https://docs.sentry.io/platforms/godot/); [Sentry docs, Exporting for Android](https://docs.sentry.io/platforms/godot/configuration/android/); [sentry-godot releases](https://github.com/getsentry/sentry-godot/releases/)
- Godot has an official doc page, "Resolving crashes on Android" (latest branch). Its content was not fetched. — [Godot docs, Resolving crashes on Android](https://docs.godotengine.org/en/latest/tutorials/platform/android/resolving_crashes_on_android.html)
- `--log-file <path>` writes stdout and stderr logs to a file. — [Godot 4.7 command line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)
- Android vitals bad-behaviour thresholds:
  - user-perceived crash rate: 1.09 percent overall, 8 percent per phone model
  - user-perceived ANR rate: 0.47 percent overall, 8 percent per phone model

  Going over them reduces discoverability. Above 8 percent on a model, Play can show a store-listing warning (since 30 Nov 2022). Sources: [Android Developers, Android vitals](https://developer.android.com/games/optimize/vitals); [Android Developers Blog, Raising the bar on technical quality (2022)](https://android-developers.googleblog.com/2022/10/raising-bar-on-technical-quality-on-google-play.html)

### Inferences
- Baseline with no backend:
  - Read `adb logcat -s godot:V` during device tests.
  - Enable `debug/file_logging/enable_file_logging` in release builds (unverified setting name). Logs go to `user://logs`.
  - Add an in-game "copy last log" button so testers can paste it into WhatsApp.
  - Rely on Play Console vitals and its crash stack traces after launch.
- Sentry is a third-party service with a cost tier. Under CLAUDE.md, adopting it is a decision for Rahul.

### Gaps
- I did not fetch the content of Godot's "Resolving crashes on Android" page.
- I did not confirm the Sentry SDK's support for Godot 4.7, its pricing, or its effect on APK size.

## Release checklists and pre-launch testing

### Takeaway
Personal Play developer accounts created after 13 November 2023 must run a closed test with at least 12 testers, opted in continuously for 14 days, before production access. Internal testing (up to 100 testers, no review) does not count. Android vitals thresholds set the post-launch bar.

### Cited Findings
- Closed test rule for personal accounts created after 13 Nov 2023: at least 12 testers, opted in continuously for at least 14 days, before applying for production. — [Play Console Help, App testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465)
- (Third-party) Further claims I could not confirm in Google's own wording:
  - Internal testing allows up to 100 testers, has no review, and does not count toward the closed-test rule.
  - Tester drop-outs can stall or reset the 14-day clock.
  - Organization accounts are exempt.

  Sources: [RevenueCat, Google Play 14-day rule](https://www.revenuecat.com/blog/engineering/google-play-14-day/); [Android Authority](https://www.androidauthority.com/google-play-app-testing-requirement-3510580)
- Popular Indian budget phones in 2026, from editorial picks and not sales data: Galaxy A17 and A07 4G, POCO C71 and C81, Redmi A7 series, Vivo Y19e, Tecno Spark Go 3, Realme Narzo 90X. Listed budget chips include Unisoc T7250 and MediaTek Dimensity 6300. — [Samsung India budget smartphone page](https://www.samsung.com/in/explore/brand/best-features-to-look-for-in-a-budget-smartphone/); [Beebom budget smartphones](https://gadgets.beebom.com/mobile-list/budget-smartphones); [GoDigit, best phones under 10000](https://www.godigit.com/mobile-insurance/find/best-mobile-phones-under-10000)

### Inferences
- Suggested device matrix: at least one phone from each GPU family the market uses.
  - PowerVR or IMG on Unisoc or older Helio phones
  - Mali-G57 or G52 on Dimensity 6300 or Helio G-series
  - Adreno on a Snapdragon 4- or 6-series phone

  Rahul owns real-device testing, so the matrix is his to buy or borrow. Confirm the exact models against Counterpoint or IDC data.
- Release checklist:
  - Target API 36.
  - 16 KB check passes with zipalign and bundletool.
  - arm64 AAB, signed with a keystore stored outside the repo.
  - Per-device size under 80 MB.
  - Headless test suite green.
  - 20-minute thermal soak on the lowest device.
  - Pause/resume and back-button test mid-match as host and as client.
  - Pre-launch report reviewed.
  - 14-day closed test with 12 testers.
  - Vitals dashboard watched after rollout.

### Gaps
- I did not fetch the pre-launch report documentation: device count, robo crawler behaviour with games, and whether it can drive a Godot GL surface.
- I found no Counterpoint or IDC sales ranking by model or GPU for India in 2026.
- I found no Godot 4 Android shipping postmortem with release-process detail.

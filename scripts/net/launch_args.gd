class_name LaunchArgs
extends RefCounted
## Command-line options given after "--", for headless runs and tests.
##   --host              start hosting immediately
##   --join=ADDRESS      join a host immediately
##   --port=N            override the config port
##   --autopilot         drive the local bot with the scripted test input
##   --autopilot-wiggle  with --autopilot: change stick, jetpack and aim every few ticks
##                       (AutopilotScript.wiggle)
##   --trace             print the per-tick position trace of remote-owned bots at exit
##   --quit-after=SEC    quit after this many seconds
##   --touch-ui          show touch controls and accept mouse as touch (desktop check)
##   --sim-latency-ms=N  simulate N ms of one-way latency (round trip about 2N); give it
##                       to the host and to every client, which then joins on port + 1
##   --sim-loss=P        simulate P percent packet loss (same rule as --sim-latency-ms)
##   --sim-jitter-ms=N   add a random 0 to N ms to every packet's delay (same rule)
##   --sim-hold-ms=N     hold every client-to-host packet that arrives in a window an extra N ms,
##                       once; the window starts --sim-hold-at-ms=S after the first client packet
##                       and lasts --sim-hold-window-ms=W (default 100). Later packets overtake
##                       the held ones. Same rule as --sim-latency-ms.
##   --sim-drop-ms=W     drop every client-to-host packet that arrives in a window of W ms, once,
##                       starting --sim-hold-at-ms=S after the first client packet (same rule)
## --autopilot, --trace, --quit-after and the --sim-* options are test support:
## they are ignored in release builds.

var host: bool = false
var join: String = ""
var port: int = 0
var autopilot: bool = false
var autopilot_wiggle: bool = false
var trace: bool = false
var quit_after: float = 0.0
var touch_ui: bool = false
var sim_latency_ms: int = 0
var sim_loss: float = 0.0
var sim_jitter_ms: int = 0
var sim_hold_ms: int = 0
var sim_hold_at_ms: int = 0
var sim_hold_window_ms: int = 100
var sim_drop_ms: int = 0

## True when the flags ask for simulated latency or loss.
func simulates_network() -> bool:
	return sim_latency_ms > 0 or sim_loss > 0.0 or sim_jitter_ms > 0 or sim_hold_ms > 0 or sim_drop_ms > 0

static func parse(args: PackedStringArray) -> LaunchArgs:
	var result: LaunchArgs = LaunchArgs.new()
	var dev: bool = OS.is_debug_build()
	for arg: String in args:
		var key: String = arg.get_slice("=", 0)
		var value: String = arg.get_slice("=", 1) if arg.contains("=") else ""
		if not dev and (key == "--autopilot" or key == "--autopilot-wiggle" or key == "--trace" or key == "--quit-after" or key == "--sim-latency-ms" or key == "--sim-loss" or key == "--sim-jitter-ms" or key == "--sim-hold-ms" or key == "--sim-hold-at-ms" or key == "--sim-hold-window-ms" or key == "--sim-drop-ms"):
			continue
		match key:
			"--host":
				result.host = true
			"--join":
				result.join = value
			"--port":
				result.port = value.to_int()
			"--autopilot":
				result.autopilot = true
			"--autopilot-wiggle":
				result.autopilot_wiggle = true
			"--trace":
				result.trace = true
			"--quit-after":
				result.quit_after = value.to_float()
			"--touch-ui":
				result.touch_ui = true
			"--sim-latency-ms":
				result.sim_latency_ms = maxi(value.to_int(), 0)
			"--sim-loss":
				result.sim_loss = clampf(value.to_float(), 0.0, 100.0)
			"--sim-jitter-ms":
				result.sim_jitter_ms = maxi(value.to_int(), 0)
			"--sim-hold-ms":
				result.sim_hold_ms = maxi(value.to_int(), 0)
			"--sim-hold-at-ms":
				result.sim_hold_at_ms = maxi(value.to_int(), 0)
			"--sim-hold-window-ms":
				result.sim_hold_window_ms = maxi(value.to_int(), 1)
			"--sim-drop-ms":
				result.sim_drop_ms = maxi(value.to_int(), 0)
	return result

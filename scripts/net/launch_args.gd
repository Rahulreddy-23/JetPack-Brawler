class_name LaunchArgs
extends RefCounted
## Command-line options given after "--", for headless runs and tests.
##   --host              start hosting immediately
##   --join=ADDRESS      join a host immediately
##   --port=N            override the config port
##   --autopilot         drive the local bot with the scripted test input
##   --trace             print the per-tick position trace of remote-owned bots at exit
##   --quit-after=SEC    quit after this many seconds
##   --touch-ui          show touch controls and accept mouse as touch (desktop check)
## --autopilot, --trace and --quit-after are test support: they are ignored in
## release builds.

var host: bool = false
var join: String = ""
var port: int = 0
var autopilot: bool = false
var trace: bool = false
var quit_after: float = 0.0
var touch_ui: bool = false

static func parse(args: PackedStringArray) -> LaunchArgs:
	var result: LaunchArgs = LaunchArgs.new()
	var dev: bool = OS.is_debug_build()
	for arg: String in args:
		var key: String = arg.get_slice("=", 0)
		var value: String = arg.get_slice("=", 1) if arg.contains("=") else ""
		if not dev and (key == "--autopilot" or key == "--trace" or key == "--quit-after"):
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
			"--trace":
				result.trace = true
			"--quit-after":
				result.quit_after = value.to_float()
			"--touch-ui":
				result.touch_ui = true
	return result

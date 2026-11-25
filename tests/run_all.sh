#!/usr/bin/env bash
# Runs the whole suite. Any SCRIPT ERROR or Parse Error in any output fails that
# test, whatever its exit code. Exit code 0 only when everything passes; a smoke
# test that is inconclusive (exit 2) is reported and also makes this fail.
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
FAILED=0

run() { # name, command...
	local name="$1"; shift
	"$@" >"$TMP/$name.log" 2>&1
	local status=$?
	if grep -q "SCRIPT ERROR\|Parse Error" "$TMP/$name.log"; then
		echo "FAIL  $name (script error in output)"; grep -m3 "SCRIPT ERROR\|Parse Error" "$TMP/$name.log"; FAILED=1
	elif [ "$status" -eq 0 ]; then
		echo "PASS  $name"
	elif [ "$status" -eq 2 ]; then
		echo "INCONCLUSIVE  $name (not a pass)"; tail -4 "$TMP/$name.log"; FAILED=1
	else
		echo "FAIL  $name (exit $status)"; tail -8 "$TMP/$name.log"; FAILED=1
	fi
}

"$GODOT" --headless --path "$ROOT" --import >"$TMP/import.log" 2>&1
if grep -q "ERROR\|Parse Error" "$TMP/import.log"; then echo "FAIL  import"; grep "ERROR\|Parse Error" "$TMP/import.log" | head; exit 1; fi
echo "PASS  import"

# Network tests take their port from PORT_BASE so several checkouts can run at once.
BASE="${PORT_BASE:-24990}"

run movement   "$GODOT" --headless --path "$ROOT" res://tests/test_movement.tscn
run input_flood env TEST_PORT="$((BASE + 0))" "$GODOT" --headless --path "$ROOT" res://tests/test_input_flood.tscn
run clock_hijack env TEST_PORT="$((BASE + 2))" "$GODOT" --headless --path "$ROOT" res://tests/test_clock_hijack.tscn
run netfox_host "$GODOT" --headless --path "$ROOT" res://tests/test_netfox_handlers.tscn -- --mode=host --port="$((BASE + 1))"
run netfox_client "$GODOT" --headless --path "$ROOT" res://tests/test_netfox_handlers.tscn -- --mode=client --port="$((BASE + 40))"
run host_hitch env PORT="$((BASE + 4))" "$ROOT/tests/net_hitch.sh"
run hole_rule env TEST_PORT="$((BASE + 94))" "$GODOT" --headless --path "$ROOT" res://tests/test_hole_rule.tscn
run late_input_1 env PORT="$((BASE + 84))" HOLD_MS=183 "$ROOT/tests/net_late_input.sh"
run late_input_2 env PORT="$((BASE + 86))" HOLD_MS=217 OBSERVER=1 "$ROOT/tests/net_late_input.sh"
run late_input_refused env PORT="$((BASE + 96))" HOLD_MS=600 EXPECT_REFUSED=1 OBSERVER=1 "$ROOT/tests/net_late_input.sh"
run silent_peer env PORT="$((BASE + 26))" EXPECT_SILENT=1 LATENCY_MS=600 HOLD_MS=0 "$ROOT/tests/net_late_input.sh"
run pause_input env PORT="$((BASE + 24))" HOLD_MS=0 PAUSE_MS=1000 "$ROOT/tests/net_late_input.sh"
run lost_input env PORT="$((BASE + 98))" "$ROOT/tests/net_lost_input.sh"
run slow_frames env TEST_PORT="$((BASE + 15))" "$GODOT" --headless --path "$ROOT" res://tests/test_slow_frames.tscn
run netfox_diffs "$GODOT" --headless --path "$ROOT" res://tests/test_netfox_diffs.tscn -- --port="$((BASE + 41))"
run full_state_coverage env TEST_PORT="$((BASE + 17))" "$GODOT" --headless --path "$ROOT" res://tests/test_full_state_coverage.tscn
run host_diffs env PORT="$((BASE + 18))" "$ROOT/tests/net_diffs.sh"
run menu_touch "$GODOT" --headless --path "$ROOT" --script res://tests/test_menu_touch.gd
run touch_focus "$GODOT" --headless --path "$ROOT" --script res://tests/test_touch_focus.gd
run main_touch "$GODOT" --headless --path "$ROOT" res://tests/test_main_touch.tscn -- --touch-ui --port="$((BASE + 13))"
run touch_input "$GODOT" --headless --path "$ROOT" res://tests/test_touch_input.tscn
run touch_net "$GODOT" --headless --path "$ROOT" res://tests/test_touch_net.tscn -- --touch-ui --port="$((BASE + 16))"
run hud "$GODOT" --headless --path "$ROOT" res://tests/test_hud.tscn
run session_guard "$GODOT" --headless --path "$ROOT" res://tests/test_session_guard.tscn -- --port="$((BASE + 10))"
run session_full "$GODOT" --headless --path "$ROOT" res://tests/test_session_full.tscn -- --port="$((BASE + 12))"
run bot_spawner_exit "$GODOT" --headless --path "$ROOT" res://tests/test_bot_spawner_exit.tscn
run net_relay  env PORT="$((BASE + 14))" "$ROOT/tests/net_relay.sh"
run combat     "$GODOT" --headless --path "$ROOT" --script res://tests/test_combat.gd
run weapons    "$GODOT" --headless --path "$ROOT" res://tests/test_weapons.tscn
run net_fire   env PORT="$((BASE + 40))" "$ROOT/tests/net_fire.sh"
run net_fire_lag env PORT="$((BASE + 50))" SIM_LATENCY_MS=75 "$ROOT/tests/net_fire.sh"
run net_fire_loss env PORT="$((BASE + 60))" SIM_LATENCY_MS=75 SIM_LOSS=5 "$ROOT/tests/net_fire.sh"
run hazard     "$GODOT" --headless --path "$ROOT" --script res://tests/test_hazard.gd
run world_objects "$GODOT" --headless --path "$ROOT" res://tests/test_world_objects.tscn
run net_objects env PORT="$((BASE + 70))" SIM_LATENCY_MS=75 "$ROOT/tests/net_world_objects.sh"
run net_objects_loss env PORT="$((BASE + 72))" SIM_LATENCY_MS=75 SIM_LOSS=5 "$ROOT/tests/net_world_objects.sh"
run net_objects_join env PORT="$((BASE + 74))" SIM_LATENCY_MS=75 "$ROOT/tests/net_world_objects_join.sh"
run net_blast_bomb env PORT="$((BASE + 76))" WEAPON=bomb SIM_LATENCY_MS=75 "$ROOT/tests/net_combat_objects.sh"
run net_blast_bomb_loss env PORT="$((BASE + 78))" WEAPON=bomb SIM_LATENCY_MS=75 SIM_LOSS=5 "$ROOT/tests/net_combat_objects.sh"
run net_blast_rocket env PORT="$((BASE + 80))" WEAPON=rocket SIM_LATENCY_MS=75 "$ROOT/tests/net_combat_objects.sh"
run net_blast_rocket_loss env PORT="$((BASE + 82))" WEAPON=rocket SIM_LATENCY_MS=75 SIM_LOSS=5 "$ROOT/tests/net_combat_objects.sh"
run effects    "$GODOT" --headless --path "$ROOT" --script res://tests/test_effects.gd
run fx_director "$GODOT" --headless --path "$ROOT" res://tests/test_fx_director.tscn
run fx_client  "$GODOT" --headless --path "$ROOT" res://tests/test_fx_client.tscn -- --port="$((BASE + 90))"
run net_fx     env PORT="$((BASE + 92))" "$ROOT/tests/net_fx.sh"
run geometry  "$GODOT" --headless --path "$ROOT" --script res://tests/test_combat_geometry.gd
run foundation "$GODOT" --headless --path "$ROOT" res://tests/test_foundation.tscn
run combat_rules "$GODOT" --headless --path "$ROOT" res://tests/test_combat_rules.tscn
run push_distance "$GODOT" --headless --path "$ROOT" res://tests/test_push_distance.tscn
run net_combat env PORT="$((BASE + 40))" "$ROOT/tests/net_combat.sh"
run net_smoke  env PORT="$((BASE + 9))" "$ROOT/tests/net_smoke.sh"
run net_smoke_lag env PORT="$((BASE + 20))" SIM_LATENCY_MS=75 "$ROOT/tests/net_smoke.sh"
run net_smoke_jitter env PORT="$((BASE + 22))" SIM_JITTER_MS=150 "$ROOT/tests/net_smoke.sh"
run net_rejoin env PORT="$((BASE + 6))" "$ROOT/tests/net_rejoin.sh"
run net_full   env PORT="$((BASE + 8))" "$ROOT/tests/net_full.sh"
run net_reject env PORT="$((BASE + 3))" "$ROOT/tests/net_reject.sh"
run net_ownership env PORT="$((BASE + 30))" "$ROOT/tests/net_ownership.sh"
run export_smoke env PORT="$((BASE + 5))" "$ROOT/tests/export_smoke.sh"
exit "$FAILED"

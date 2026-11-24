extends Node
## Autoload "MatchSettings": the match values that simulation reads by tick. Today
## that is the tuning config (always the default) and the round start tick; later
## Chaos Card entries join here. The host decides these values and sends them ahead
## of time by reliable RPC; every peer reads them by tick, so a re-simulated tick
## sees the same values as the first pass.
##
## Simulation code must read the config only through tuning_at(tick) and never
## through TuningConfig.get_default() or NetworkTime.tick.

## Tick at which the current round (phase 1: the hazard cycle) started, or -1 before
## any round has started.
var round_start_tick: int = -1

## Earliest tick a re-simulation was asked for and not yet handed to netfox, or -1.
var _resim_from: int = -1

func _ready() -> void:
	NetworkTime.after_client_sync.connect(_on_client_synced)
	NetworkEvents.on_server_stop.connect(_reset)
	NetworkEvents.on_client_stop.connect(_reset)

## The tuning config in force at a tick. Chaos Cards will change this; for now it is
## the default config on every tick.
func tuning_at(_tick: int) -> TuningConfig:
	return TuningConfig.get_default()

## Ticks since the current hazard cycle began, or -1 when no round has started or the
## tick is before it. Phase 1 has no rounds, so the hazard repeats every
## hazard_cycle_time seconds: it rises from hazard_start_time to hazard_cap_time and
## then everything starts again.
func hazard_ticks(tick: int) -> int:
	if round_start_tick < 0 or tick < round_start_tick:
		return -1
	var cfg: TuningConfig = tuning_at(tick)
	var cycle: int = roundi(cfg.hazard_cycle_time * float(cfg.tick_rate))
	if cycle <= 0:
		return -1
	return (tick - round_start_tick) % cycle

## Host only. Start a round at this tick and tell every peer that has synced its clock
## (peers that sync later are told when they do).
func start_round(start_tick: int) -> void:
	if not multiplayer.is_server():
		push_error("MatchSettings.start_round called on a client")
		return
	_apply_round_start(start_tick)
	for peer: int in multiplayer.get_peers():
		if NetworkTime.is_client_synced(peer):
			_receive_round_start.rpc_id(peer, start_tick)

# The value arrives as a Variant: it comes from the network, and a wrong type or a
# negative tick must be ignored, not crash. Only the server may send this.
@rpc("authority", "call_remote", "reliable")
func _receive_round_start(value: Variant) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if typeof(value) != TYPE_INT or (value as int) < 0:
		return
	_apply_round_start(value as int)

func _on_client_synced(peer: int) -> void:
	if multiplayer.is_server() and round_start_tick >= 0:
		_receive_round_start.rpc_id(peer, round_start_tick)

func _apply_round_start(start_tick: int) -> void:
	round_start_tick = start_tick
	# A tick that is already past, but still in netfox's history, was simulated with
	# the old value: ask for it to be simulated again.
	if start_tick < NetworkTime.tick and start_tick >= NetworkRollback.history_start:
		if _resim_from < 0:
			NetworkRollback.before_loop.connect(_on_before_loop, CONNECT_ONE_SHOT)
			_resim_from = start_tick
		else:
			_resim_from = mini(_resim_from, start_tick)

func _on_before_loop() -> void:
	NetworkRollback.notify_resimulation_start(_resim_from)
	_resim_from = -1

func _reset() -> void:
	round_start_tick = -1
	# A re-simulation request that was not handed over must not reach the next session.
	if NetworkRollback.before_loop.is_connected(_on_before_loop):
		NetworkRollback.before_loop.disconnect(_on_before_loop)
	_resim_from = -1

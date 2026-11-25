extends Node
## The client side of tests/net_late_input.sh: the real game as a client, which also prints
## where the client's own bot is shown after every rollback loop (DISPLAY lines), and every
## state received for any bot from the host that changed the client's history (RECEIVED lines;
## a state that repeats one already held is not reported), so that they can be compared with the
## host's final states. Takes the launch flags of the game (--join, --port, --autopilot,
## --trace, --quit-after, --sim-*) and quits like the game does.
##   godot --headless --path . res://tests/test_client_display.tscn -- --join=127.0.0.1 --port=N ...

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var _main: Main = null

func _ready() -> void:
	NetworkRollback.after_loop.connect(_on_after_loop)
	NetworkSynchronizationServer._on_state.connect(_on_state)
	# The spawner's node path must match the host's, so Main goes directly under root.
	_main = MAIN_SCENE.instantiate() as Main
	get_tree().root.add_child.call_deferred(_main)

func _own_bot() -> Bot:
	if _main == null:
		return null
	for bot: Bot in _main.get_node("Bots").get_children():
		if bot.peer_id == multiplayer.get_unique_id():
			return bot
	return null

func _on_after_loop() -> void:
	var bot: Bot = _own_bot()
	if bot != null:
		print("DISPLAY peer=%d tick=%d x=%.3f y=%.3f" % [bot.peer_id, NetworkTime.tick, bot.global_position.x, bot.global_position.y])

func _on_state(snapshot: _Snapshot) -> void:
	for subject: Object in snapshot.get_subjects():
		if not subject is Bot:
			continue
		for property: NodePath in snapshot.get_subject_properties(subject):
			if str(property).ends_with("global_position"):
				var position: Vector2 = snapshot.get_property(subject, property)
				print("RECEIVED peer=%d tick=%d now=%d x=%.3f y=%.3f" % [(subject as Bot).peer_id, snapshot.tick, NetworkTime.tick, position.x, position.y])

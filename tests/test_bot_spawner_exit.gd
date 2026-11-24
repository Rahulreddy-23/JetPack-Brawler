extends Node
## A stale bot's exit must not unregister its replacement.
## Run after importing: godot --headless res://tests/test_bot_spawner_exit.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var spawner: BotSpawner = BotSpawner.new()
	spawner.bot_scene = load("res://scenes/bot.tscn") as PackedScene
	spawner.layout = load("res://config/smelter.tres") as ArenaLayout
	get_tree().root.add_child(spawner)
	await get_tree().process_frame
	var old_bot: Bot = spawner._spawn_bot({"peer_id": 1, "slot": 0}) as Bot
	get_tree().root.add_child(old_bot)
	var new_bot: Bot = spawner._spawn_bot({"peer_id": 1, "slot": 0}) as Bot
	get_tree().root.add_child(new_bot)
	await get_tree().process_frame
	var failed: bool = false
	if spawner.get_bots().get(1) != new_bot:
		print("FAIL replacement is not the registered bot")
		failed = true
	old_bot.free()
	await get_tree().process_frame
	if spawner.get_bots().get(1) != new_bot:
		print("FAIL the old bot's exit unregistered its replacement")
		failed = true
	else:
		print("PASS replacement still registered after the old bot was freed")
	new_bot.free()
	await get_tree().process_frame
	if spawner.get_bots().has(1):
		print("FAIL the current bot's exit did not unregister it")
		failed = true
	else:
		print("PASS the current bot's exit unregisters it")
	get_tree().quit(1 if failed else 0)

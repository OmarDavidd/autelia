extends Node
## Stage 1 smoke test. Run: godot --headless --path . tests/smoke_stage1.tscn


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: Array[String] = []

	for action in ["move_up", "move_down", "move_left", "move_right", "shoot", "screenshot"]:
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			failures.append("missing input action: %s" % action)

	var scene: Node = load("res://modes/survival/survival.tscn").instantiate()
	add_child(scene)
	var player: Player = scene.get_node("Player")
	var arena: Arena = scene.get_node("Arena")
	var start_x := player.global_position.x

	Input.action_press("move_right")
	for i in 30:
		await get_tree().physics_frame
	if player.global_position.x <= start_x:
		failures.append("player did not move right (x=%.1f)" % player.global_position.x)

	for i in 300:
		await get_tree().physics_frame
	Input.action_release("move_right")
	var max_x := arena.play_rect().end.x
	if player.global_position.x > max_x:
		failures.append("player passed the right wall (x=%.1f > %.1f)" % [player.global_position.x, max_x])

	if failures.is_empty():
		print("SMOKE OK: player x %.1f -> %.1f (wall at %.1f)" % [start_x, player.global_position.x, max_x])
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)

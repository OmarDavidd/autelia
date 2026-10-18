extends Node
## Game-feel smoke test: death bursts, player death animation, delayed game over, start screen.
## Run: godot --headless --path . tests/smoke_feel.tscn

var failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _bursts(parent: Node) -> int:
	var count := 0
	for child in parent.get_children():
		if child is DeathBurst:
			count += 1
	return count


func _run() -> void:
	await _enemy_death_bursts_and_cleans_up()
	await _player_death_animates()
	await _game_over_waits_for_animation()
	await _start_screen_pauses_until_input()

	get_tree().paused = false
	if failures.is_empty():
		print("SMOKE OK: bursts, death animation, delayed game over and start screen behave")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _enemy_death_bursts_and_cleans_up() -> void:
	var sandbox := Sandbox.create(self)
	var chaser: Enemy = Sandbox.spawn(sandbox.world, "res://core/enemies/chaser.tscn", Vector2(1000, 150))
	chaser.take_hit(1000.0)
	await _frames(2)
	_expect(_bursts(sandbox.world) == 1, "enemy death did not spawn one burst")
	await _frames(40)
	_expect(_bursts(sandbox.world) == 0, "burst did not remove itself")
	sandbox.world.queue_free()
	await _frames(2)


func _player_death_animates() -> void:
	var sandbox := Sandbox.create(self)
	var player: Player = sandbox.player
	player.take_hit(1000.0)
	await _frames(2)
	_expect(_bursts(sandbox.world) == 1, "player death did not spawn a burst")
	await _frames(40)
	_expect(player.look.modulate.a < 0.1, "player did not fade out (alpha %.2f)" % player.look.modulate.a)
	_expect(player.look.scale.x < 0.5, "player did not deflate (scale %.2f)" % player.look.scale.x)
	sandbox.world.queue_free()
	await _frames(2)


func _game_over_waits_for_animation() -> void:
	var mode: SurvivalMode = load("res://modes/survival/survival.tscn").instantiate()
	add_child(mode)
	await _frames(2)
	mode.player.take_hit(1000.0)
	await _frames(2)
	_expect(not mode.hud.game_over_panel.visible, "game over panel covered the death animation")
	await _frames(45)
	_expect(mode.hud.game_over_panel.visible, "game over panel never appeared")
	mode.queue_free()
	await _frames(2)


func _start_screen_pauses_until_input() -> void:
	StartScreen.seen = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	var screen: StartScreen = main.get_node_or_null("StartScreen")
	_expect(screen != null, "start screen missing on first load")
	_expect(get_tree().paused, "game not paused behind the start screen")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	if screen:
		screen._unhandled_input(click)
	await _frames(2)
	_expect(not get_tree().paused, "game still paused after clicking")
	_expect(StartScreen.seen, "start screen not marked as seen")
	main.queue_free()
	await _frames(2)

	# A reload (R) must skip it.
	var again: Node = load("res://main.tscn").instantiate()
	add_child(again)
	await _frames(2)
	_expect(again.get_node_or_null("StartScreen") == null, "start screen shown again after reload")
	_expect(not get_tree().paused, "reload left the game paused")
	again.queue_free()
	await _frames(2)

extends Node
## Stage 5 smoke test: the HUD reflects health, wave state, kills and game over.
## Run: godot --headless --path . tests/smoke_stage5.tscn

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var mode: SurvivalMode = load("res://modes/survival/survival.tscn").instantiate()
	mode.run_seed = 5
	var spawner: WaveSpawner = mode.get_node("Spawner")
	spawner.first_break = 0.5
	spawner.wave_duration = 3.0
	add_child(mode)
	# The difficulty director sets the interval on ready; override it afterwards.
	mode.spawner.spawn_interval = 0.25
	var hud := mode.hud
	var player := mode.player

	await _frames(3)
	_expect(hud.wave_label.text.begins_with("Prepárate"), "break label: '%s'" % hud.wave_label.text)
	_expect(hud.health_bar.value == player.health.max_health, "health bar not full at start")

	await _frames(60)
	_expect(hud.wave_label.text.begins_with("Oleada 1 ·"), "wave label: '%s'" % hud.wave_label.text)

	player.take_hit(10.0)
	await _frames(1)
	_expect(hud.health_bar.value == player.health.current, "health bar %.0f != health %.0f" % [hud.health_bar.value, player.health.current])

	# Wait for an enemy to spawn, then kill it.
	var enemy: Enemy
	for i in 120:
		await _frames(1)
		for child in mode.enemies.get_children():
			if child is Enemy:
				enemy = child
		if enemy:
			break
	_expect(enemy != null, "no enemy spawned to kill")
	if enemy:
		enemy.take_hit(1000.0)
		await _frames(2)
		_expect(hud.kills_label.text == "Eliminaciones: 1", "kills label: '%s'" % hud.kills_label.text)

	_expect(not hud.game_over_panel.visible, "game over visible before death")
	player.health.invulnerable_left = 0.0
	player.take_hit(1000.0)
	await _frames(int(60 * (Hud.GAME_OVER_DELAY + 0.1)))
	_expect(hud.game_over_panel.visible, "game over panel not shown after death")
	_expect(hud.game_over_label.text.contains("Oleada alcanzada: 1"), "game over text: '%s'" % hud.game_over_label.text)

	if failures.is_empty():
		print("SMOKE OK: HUD tracks break/wave, health, kills and game over")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)

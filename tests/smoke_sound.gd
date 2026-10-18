extends Node
## Sound smoke test: each gameplay event triggers its sound, and sound never touches the run's RNG.
## Run: godot --headless --path . tests/smoke_sound.tscn

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var player: Player = load("res://core/player/player.tscn").instantiate()
	var enemy_shooter := Node.new()
	var cases := [
		["shoot", func() -> void: Events.shot_fired.emit(player)],
		["enemy_shoot", func() -> void: Events.shot_fired.emit(enemy_shooter)],
		["enemy_hit", func() -> void: Events.enemy_hit.emit(player, 10.0)],
		["enemy_death", func() -> void: Events.enemy_killed.emit(player)],
		["player_hurt", func() -> void: Events.player_damaged.emit(10.0, 90.0)],
		["wave_start", func() -> void: Events.wave_started.emit(1)],
		["game_over", func() -> void: Events.player_died.emit()],
	]
	for case in cases:
		Sfx.last_played = ""
		case[1].call()
		_expect(Sfx.last_played == case[0], "expected '%s', got '%s'" % [case[0], Sfx.last_played])

	# Playing sounds must not consume a seeded run's random numbers.
	var seeded := RandomNumberGenerator.new()
	seeded.seed = 99
	var expected := seeded.randi()
	seeded.seed = 99
	for i in 20:
		Sfx.play("shoot", 0.1)
	_expect(seeded.randi() == expected, "sound playback changed a seeded RNG sequence")
	player.free()
	enemy_shooter.free()

	if failures.is_empty():
		print("SMOKE OK: every gameplay event plays its sound; seeded RNG untouched")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)

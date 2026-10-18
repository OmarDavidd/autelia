extends Node
## Stage 4 smoke test: wave timing, cleanup between waves, seeded spawns, stop on death.
## Run: godot --headless --path . tests/smoke_stage4.tscn

const SURVIVAL := "res://modes/survival/survival.tscn"

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _waves_start_end_and_clean_up()
	var first := await _record_spawns(1234)
	var again := await _record_spawns(1234)
	var other := await _record_spawns(9876)
	if first.is_empty():
		failures.append("no spawns recorded")
	if first != again:
		failures.append("same seed produced different spawns")
	if first == other:
		failures.append("different seeds produced identical spawns")
	await _death_stops_spawner()

	if failures.is_empty():
		print("SMOKE OK: waves cycle, clean up, replay by seed (%d spawns) and stop on death" % first.size())
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Short waves so the test runs fast. The player is made invulnerable to keep it alive.
func _make_run(seed_value: int) -> SurvivalMode:
	var mode: SurvivalMode = load(SURVIVAL).instantiate()
	mode.run_seed = seed_value
	var spawner: WaveSpawner = mode.get_node("Spawner")
	spawner.first_break = 0.5
	spawner.wave_duration = 2.0
	spawner.break_duration = 0.5
	spawner.spawn_interval = 0.25
	add_child(mode)
	mode.player.health.invulnerability_time = 999.0
	mode.player.health.invulnerable_left = 999.0
	return mode


func _free(mode: Node) -> void:
	mode.queue_free()
	await _frames(2)


func _waves_start_end_and_clean_up() -> void:
	var started: Array[int] = []
	var ended: Array[int] = []
	var on_start := func(index: int) -> void: started.append(index)
	var on_end := func(index: int) -> void: ended.append(index)
	Events.wave_started.connect(on_start)
	Events.wave_ended.connect(on_end)

	var mode := _make_run(42)
	await _frames(int(60 * 1.5))
	if started != [1]:
		failures.append("wave 1 did not start after the first break (started %s)" % [started])
	if mode.spawner.alive_count() == 0:
		failures.append("no enemies during wave 1")
	await _frames(int(60 * 1.1))
	if ended != [1]:
		failures.append("wave 1 did not end on time (ended %s)" % [ended])
	await _frames(2)
	if mode.spawner.alive_count() != 0:
		failures.append("enemies left after wave end: %d" % mode.spawner.alive_count())
	await _frames(int(60 * 0.6))
	if started != [1, 2]:
		failures.append("wave 2 did not start after the break (started %s)" % [started])

	Events.wave_started.disconnect(on_start)
	Events.wave_ended.disconnect(on_end)
	await _free(mode)


func _record_spawns(seed_value: int) -> Array[String]:
	var log: Array[String] = []
	var mode := _make_run(seed_value)
	mode.spawner.spawned.connect(func(path: String, at: Vector2) -> void:
		log.append("%s@%d,%d" % [path.get_file(), roundi(at.x), roundi(at.y)]))
	await _frames(int(60 * 2.4))
	await _free(mode)
	return log


func _death_stops_spawner() -> void:
	var mode := _make_run(7)
	await _frames(int(60 * 0.8))
	mode.player.health.invulnerable_left = 0.0
	mode.player.health.invulnerability_time = 0.0
	mode.player.take_hit(1000.0)
	await _frames(2)
	if mode.spawner.running:
		failures.append("spawner kept running after the player died")
	await _free(mode)

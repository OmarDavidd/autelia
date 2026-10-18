extends Node
## Stage 7 smoke test: difficulty mapping, director -> spawner, per-window CSV telemetry.
## Run: godot --headless --path . tests/smoke_stage7.tscn

const SURVIVAL := "res://modes/survival/survival.tscn"
const OUTPUT_DIR := "user://test_telemetry"

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
	_clean_output()
	_params_map_linearly()
	await _director_tunes_spawner_and_enemies()
	await _telemetry_writes_one_row_per_window()
	await _death_closes_window_early()
	_clean_output()

	if failures.is_empty():
		print("SMOKE OK: difficulty maps and applies; telemetry writes per-window CSV rows")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _make_run(seed_value: int) -> SurvivalMode:
	var mode: SurvivalMode = load(SURVIVAL).instantiate()
	mode.run_seed = seed_value
	var spawner: WaveSpawner = mode.get_node("Spawner")
	spawner.first_break = 0.3
	spawner.wave_duration = 1.5
	var telemetry: TelemetryRecorder = mode.get_node("Telemetry")
	telemetry.output_dir = OUTPUT_DIR
	add_child(mode)
	mode.player.health.invulnerable_left = 999.0
	return mode


func _free(mode: Node) -> void:
	mode.queue_free()
	await _frames(2)


func _params_map_linearly() -> void:
	var easy := DifficultyParams.values(0.0)
	var mid := DifficultyParams.values(0.5)
	var hard := DifficultyParams.values(1.0)
	_expect(is_equal_approx(mid.spawn_interval, 1.4), "d=0.5 spawn interval %.2f" % mid.spawn_interval)
	_expect(is_equal_approx(mid.speed_multiplier, 1.0), "d=0.5 must keep base speed")
	_expect(easy.spawn_interval > hard.spawn_interval, "harder must spawn more often")
	_expect(hard.speed_multiplier > easy.speed_multiplier, "harder must be faster")
	_expect(DifficultyParams.values(3.0) == hard, "difficulty must clamp to 1")


func _director_tunes_spawner_and_enemies() -> void:
	var mode := _make_run(11)
	var director: DifficultyDirector = mode.get_node("Difficulty")
	director.set_difficulty(1.0)
	_expect(is_equal_approx(mode.spawner.spawn_interval, 0.8), "spawner interval not tuned: %.2f" % mode.spawner.spawn_interval)

	var enemy: Enemy
	for i in 120:
		await _frames(1)
		for child in mode.enemies.get_children():
			if child is Enemy:
				enemy = child
		if enemy:
			break
	_expect(enemy != null, "no enemy spawned")
	if enemy:
		var base: Enemy = load(enemy.scene_file_path).instantiate()
		_expect(is_equal_approx(enemy.speed, base.speed * 1.25), "enemy speed %.1f, expected %.1f" % [enemy.speed, base.speed * 1.25])
		var base_health: Health = base.get_node("Health")
		_expect(is_equal_approx(enemy.health.max_health, base_health.max_health * 1.2), "enemy health not scaled")
		base.free()
	await _free(mode)


func _read_rows(telemetry: TelemetryRecorder) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var file := FileAccess.open(telemetry.file_path, FileAccess.READ)
	if file == null:
		return rows
	while not file.eof_reached():
		var line := file.get_line()
		if not line.is_empty():
			rows.append(line.split(","))
	return rows


func _telemetry_writes_one_row_per_window() -> void:
	var mode := _make_run(21)
	var telemetry: TelemetryRecorder = mode.get_node("Telemetry")
	await _frames(30)
	_expect(telemetry.is_window_open(), "window 1 did not open")
	for i in 4:
		Events.shot_fired.emit(mode.player)
	var enemy_shooter := Node.new()
	Events.shot_fired.emit(enemy_shooter)  # an enemy shot must not count
	enemy_shooter.free()
	Events.enemy_hit.emit(mode.player, 10.0)
	Events.enemy_hit.emit(mode.player, 10.0)
	Events.enemy_killed.emit(mode.player)
	Events.player_damaged.emit(5.0, 95.0)
	await _frames(int(60 * 1.6))

	var rows := _read_rows(telemetry)
	_expect(rows.size() == 2, "expected header + 1 row, got %d lines" % rows.size())
	if rows.size() >= 2:
		_expect(rows[0] == PackedStringArray(TelemetryRecorder.COLUMNS), "CSV header mismatch: %s" % [rows[0]])
		var row := {}
		for c in TelemetryRecorder.COLUMNS.size():
			row[TelemetryRecorder.COLUMNS[c]] = rows[1][c]
		_expect(row.condition == "fixed", "condition %s" % row.condition)
		_expect(row.seed == "21", "seed %s" % row.seed)
		_expect(row.window == "1", "window %s" % row.window)
		_expect(row.shots == "4" and row.hits == "2", "shots/hits %s/%s" % [row.shots, row.hits])
		_expect(row.accuracy == "0.5000", "accuracy %s" % row.accuracy)
		_expect(row.damage_dealt == "20.0000" and row.damage_taken == "5.0000", "damage %s/%s" % [row.damage_dealt, row.damage_taken])
		_expect(row.kills == "1" and row.deaths == "0", "kills/deaths %s/%s" % [row.kills, row.deaths])
		_expect(float(row.kills_per_minute) > 0.0, "kills per minute %s" % row.kills_per_minute)
	await _free(mode)


func _death_closes_window_early() -> void:
	var mode := _make_run(31)
	var telemetry: TelemetryRecorder = mode.get_node("Telemetry")
	await _frames(30)
	mode.player.health.invulnerable_left = 0.0
	mode.player.take_hit(1000.0)
	await _frames(2)
	_expect(not telemetry.is_window_open(), "window still open after death")
	var rows := _read_rows(telemetry)
	_expect(rows.size() == 2 and rows[1][TelemetryRecorder.COLUMNS.find("deaths")] == "1", "death row missing or deaths != 1")
	await _free(mode)


func _clean_output() -> void:
	var dir := DirAccess.open(OUTPUT_DIR)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)

class_name TelemetryRecorder
extends Node
## Aggregates gameplay events per wave (one measurement window) and appends one CSV row
## per window. A window also closes early when the player dies.
##
## Participant: `--participant=P01` on the command line (after `--`), default "dev".
## Files: <output_dir>/<participant>_<session>.csv (user:// is git-ignored data, never commit it).

signal window_closed(window: Dictionary)

const COLUMNS := [
	"participant_id", "session_id", "condition", "seed", "window", "timestamp", "difficulty",
	"shots", "hits", "accuracy", "damage_dealt", "damage_taken", "kills", "deaths",
	"active_time", "kills_per_minute",
]

@export var mode_path: NodePath
@export var director_path: NodePath
@export var output_dir := "user://telemetry"

var participant_id := "dev"
var session_id := ""
var file_path := ""
var current := {}

var _open := false

@onready var mode: SurvivalMode = get_node(mode_path)
@onready var director: DifficultyDirector = get_node(director_path)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--participant="):
			participant_id = arg.get_slice("=", 1)
	session_id = Time.get_datetime_string_from_system().replace(":", "-")
	file_path = "%s/%s_%s.csv" % [output_dir, participant_id, session_id]

	Events.wave_started.connect(_on_wave_started)
	Events.wave_ended.connect(_on_wave_ended)
	Events.shot_fired.connect(_on_shot_fired)
	Events.enemy_hit.connect(_on_enemy_hit)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_died.connect(_on_player_died)


func _physics_process(delta: float) -> void:
	if _open:
		current.active_time += delta


func is_window_open() -> bool:
	return _open


func _on_wave_started(index: int) -> void:
	current = {
		"window": index, "difficulty": director.difficulty,
		"shots": 0, "hits": 0, "damage_dealt": 0.0, "damage_taken": 0.0,
		"kills": 0, "deaths": 0, "active_time": 0.0,
	}
	_open = true


func _on_shot_fired(shooter: Node) -> void:
	# Enemy shots also emit this event; only the player's count toward accuracy.
	if _open and shooter is Player:
		current.shots += 1


func _on_enemy_hit(_enemy: Node, damage: float) -> void:
	if _open:
		current.hits += 1
		current.damage_dealt += damage


func _on_enemy_killed(_enemy: Node) -> void:
	if _open:
		current.kills += 1


func _on_player_damaged(amount: float, _health_left: float) -> void:
	if _open:
		current.damage_taken += amount


func _on_player_died() -> void:
	if _open:
		current.deaths = 1
		_close_window()


func _on_wave_ended(_index: int) -> void:
	_close_window()


func _close_window() -> void:
	if not _open:
		return
	_open = false
	var minutes := maxf(current.active_time, 0.001) / 60.0
	var row := current.duplicate()
	row.merge({
		"participant_id": participant_id,
		"session_id": session_id,
		"condition": director.controller.label(),
		"seed": mode.used_seed,
		"timestamp": Time.get_datetime_string_from_system(),
		"accuracy": float(current.hits) / current.shots if current.shots > 0 else 0.0,
		"kills_per_minute": current.kills / minutes,
	})
	_append(row)
	window_closed.emit(row)


func _append(row: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	var exists := FileAccess.file_exists(file_path)
	var file := FileAccess.open(file_path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		push_error("Telemetry: cannot open %s (%s)" % [file_path, error_string(FileAccess.get_open_error())])
		return
	file.seek_end()
	if not exists:
		file.store_line(",".join(COLUMNS))
	var cells: PackedStringArray = []
	for column: String in COLUMNS:
		var value: Variant = row[column]
		cells.append("%.4f" % value if value is float else str(value))
	file.store_line(",".join(cells))
	file.close()

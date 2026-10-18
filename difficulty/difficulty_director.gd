class_name DifficultyDirector
extends Node
## Owns the current difficulty value and pushes it to the spawner.
## After each telemetry window, the active controller picks the next value.
##
## Start value: `--difficulty=0.7` on the command line (after `--`) wins, then `initial_difficulty`.

signal difficulty_changed(value: float)

@export var spawner_path: NodePath
@export var telemetry_path: NodePath
@export_range(0.0, 1.0, 0.01) var initial_difficulty := 0.5

var difficulty := 0.5
var controller: DifficultyController = FixedController.new()

@onready var spawner: WaveSpawner = get_node(spawner_path)
@onready var telemetry: TelemetryRecorder = get_node(telemetry_path)


func _ready() -> void:
	telemetry.window_closed.connect(_on_window_closed)
	set_difficulty(_resolve_initial())


func set_difficulty(value: float) -> void:
	difficulty = clampf(value, 0.0, 1.0)
	DifficultyParams.apply(difficulty, spawner)
	difficulty_changed.emit(difficulty)


func _resolve_initial() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--difficulty="):
			return float(arg.get_slice("=", 1))
	return initial_difficulty


func _on_window_closed(window: Dictionary) -> void:
	set_difficulty(controller.next_difficulty(window, difficulty))

class_name DebugPanel
extends CanvasLayer
## Researcher panel, hidden by default; F3 toggles it.
## Shows the condition, seed and live window stats, and a slider to set difficulty by hand.

@export var mode_path: NodePath
@export var director_path: NodePath
@export var telemetry_path: NodePath

var slider: HSlider
var difficulty_label: Label
var stats_label: Label

@onready var mode: SurvivalMode = get_node(mode_path)
@onready var director: DifficultyDirector = get_node(director_path)
@onready var telemetry: TelemetryRecorder = get_node(telemetry_path)


func _ready() -> void:
	layer = 10
	visible = false
	_build()
	director.difficulty_changed.connect(_on_difficulty_changed)
	_on_difficulty_changed(director.difficulty)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_panel"):
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	var w := telemetry.current
	var lines := ["Condición: %s · Semilla: %d" % [director.controller.label(), mode.used_seed]]
	if telemetry.is_window_open():
		var accuracy: float = float(w.hits) / w.shots if w.shots > 0 else 0.0
		lines.append("Ventana %d · disparos %d · aciertos %d (%.0f %%)" % [w.window, w.shots, w.hits, accuracy * 100.0])
		lines.append("Daño hecho %.0f · recibido %.0f · eliminaciones %d" % [w.damage_dealt, w.damage_taken, w.kills])
	else:
		lines.append("Sin ventana abierta")
	stats_label.text = "\n".join(lines)


func _on_difficulty_changed(value: float) -> void:
	slider.set_value_no_signal(value)
	difficulty_label.text = "Dificultad: %.2f" % value


func _build() -> void:
	var panel := PanelContainer.new()
	panel.theme = UiStyle.theme(500, 18)
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	panel.position = Vector2(40, 470)
	panel.custom_minimum_size = Vector2(520, 0)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	difficulty_label = UiStyle.label(HORIZONTAL_ALIGNMENT_LEFT, 22)
	difficulty_label.add_theme_font_override("font", UiStyle.font(600))
	column.add_child(difficulty_label)

	slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(0, 28)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float) -> void: director.set_difficulty(value))
	column.add_child(slider)

	stats_label = UiStyle.label(HORIZONTAL_ALIGNMENT_LEFT, 18)
	column.add_child(stats_label)

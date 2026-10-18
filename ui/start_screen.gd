class_name StartScreen
extends CanvasLayer
## Title screen shown once per launch. The game stays paused until the first click or key press,
## which is also what lets browsers start audio (they block sound until the user interacts).
## Restarting with R reloads the scene but skips this screen.

signal dismissed

## Survives scene reloads, so the screen only appears on the first load.
static var seen := false

var _prompt: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	if seen:
		queue_free()
		return
	get_tree().paused = true
	_build()


func _unhandled_input(event: InputEvent) -> void:
	var pressed := (event is InputEventMouseButton or event is InputEventKey) \
		and event.is_pressed() and not event.is_echo()
	if pressed:
		get_viewport().set_input_as_handled()
		dismiss()


func dismiss() -> void:
	seen = true
	get_tree().paused = false
	dismissed.emit()
	queue_free()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(Palette.BACKGROUND, 0.94)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var column := VBoxContainer.new()
	column.theme = UiStyle.theme(500, 22)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	var title := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 112)
	title.text = "Autelia"
	title.add_theme_font_override("font", UiStyle.font(700))
	column.add_child(title)

	var subtitle := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 30)
	subtitle.text = "Sobrevive a las oleadas"
	column.add_child(subtitle)

	column.add_child(Lineup.new())

	var controls := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 22)
	controls.text = "WASD o flechas: moverse  ·  Mouse: apuntar y disparar  ·  R: reiniciar"
	controls.add_theme_color_override("font_color", Color(Palette.INK, 0.75))
	column.add_child(controls)

	_prompt = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 30)
	_prompt.text = "Haz clic para jugar"
	_prompt.add_theme_font_override("font", UiStyle.font(600))
	column.add_child(_prompt)

	var pulse := create_tween().set_loops()
	pulse.tween_property(_prompt, "modulate:a", 0.35, 0.7)
	pulse.tween_property(_prompt, "modulate:a", 1.0, 0.7)


## The three characters, drawn with the same functions the game uses.
class Lineup:
	extends Control

	func _init() -> void:
		custom_minimum_size = Vector2(0, 175)

	func _draw() -> void:
		var middle := size.x / 2.0
		var y := 95.0
		Sketch.draw_chaser(self, Vector2.RIGHT, Palette.ENEMY, Vector2(middle - 220, y), 2.2)
		Sketch.draw_player(self, Vector2(0.45, -1).normalized(), Vector2(middle, y), 2.6)
		Sketch.draw_shooter(self, Vector2.LEFT, Vector2.LEFT, Palette.SHOOTER, Vector2(middle + 220, y), 2.2)

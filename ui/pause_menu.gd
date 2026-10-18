class_name PauseMenu
extends CanvasLayer
## Esc or P pauses the run: Continuar, Reiniciar, Menú principal.
## While paused nothing advances, so waves and telemetry do not count paused time.

@export var mode_path: NodePath

var panel: PanelContainer
var resume_button: Button

@onready var mode: SurvivalMode = get_node(mode_path)


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		toggle()


## Pausing is allowed while playing: not during game over, nor while another screen
## (the main menu) already holds the pause.
func can_pause() -> bool:
	return not mode.is_over() and not get_tree().paused


func toggle() -> void:
	if visible:
		resume()
	elif can_pause():
		open()


func open() -> void:
	get_tree().paused = true
	visible = true


func resume() -> void:
	visible = false
	get_tree().paused = false


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func to_main_menu() -> void:
	MainMenu.seen = false
	restart()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(Palette.BACKGROUND, 0.75)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.theme = UiStyle.theme(500, 22)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	panel = UiStyle.menu_panel(420)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 44)
	title.text = "Pausa"
	title.add_theme_font_override("font", UiStyle.font(700))
	column.add_child(title)

	resume_button = UiStyle.button("Continuar")
	resume_button.pressed.connect(resume)
	column.add_child(resume_button)
	var restart_button := UiStyle.button("Reiniciar")
	restart_button.pressed.connect(restart)
	column.add_child(restart_button)
	var menu_button := UiStyle.button("Menú principal")
	menu_button.pressed.connect(to_main_menu)
	column.add_child(menu_button)

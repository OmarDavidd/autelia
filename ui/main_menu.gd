class_name MainMenu
extends CanvasLayer
## Main menu shown once per launch: Jugar, Controles, Acerca de and (on desktop) Salir.
## The game stays paused behind it. Clicking Jugar is also what lets browsers start audio,
## since they block sound until the user interacts with the page.
## Restarting with R reloads the scene but skips the menu.

signal dismissed

const REPO_URL := "https://github.com/OmarDavidd/autelia"

## Survives scene reloads, so the menu only appears when asked for.
static var seen := false

var play_button: Button
var _home: Control
var _controls: Control
var _about: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	if seen:
		queue_free()
		return
	get_tree().paused = true
	_build()
	_show(_home)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _home.visible:
		get_viewport().set_input_as_handled()
		_show(_home)


func play() -> void:
	seen = true
	get_tree().paused = false
	dismissed.emit()
	queue_free()


func show_controls() -> void:
	_show(_controls)


func show_about() -> void:
	_show(_about)


func _show(page: Control) -> void:
	for each in [_home, _controls, _about]:
		each.visible = each == page


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(Palette.BACKGROUND, 0.95)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.theme = UiStyle.theme(500, 22)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_home = _build_home()
	_controls = _build_page("Controles", [
		["Moverse", "WASD o flechas"],
		["Apuntar y disparar", "Mouse y clic izquierdo"],
		["Pausa", "Esc o P"],
		["Reiniciar", "R al terminar la partida"],
	])
	_about = _build_about()
	for page in [_home, _controls, _about]:
		center.add_child(page)


func _build_home() -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)

	var title := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 104)
	title.text = "Autelia"
	title.add_theme_font_override("font", UiStyle.font(700))
	column.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	column.add_child(gap)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(buttons)

	play_button = UiStyle.button("Jugar")
	play_button.pressed.connect(play)
	buttons.add_child(play_button)
	var controls := UiStyle.button("Controles")
	controls.pressed.connect(show_controls)
	buttons.add_child(controls)
	var about := UiStyle.button("Acerca de")
	about.pressed.connect(show_about)
	buttons.add_child(about)
	# Quitting means nothing inside a browser tab.
	if not OS.has_feature("web"):
		var quit := UiStyle.button("Salir")
		quit.pressed.connect(func() -> void: get_tree().quit())
		buttons.add_child(quit)
	return column


## A titled panel with label/value rows and a back button.
func _build_page(heading: String, rows: Array) -> Control:
	var panel := UiStyle.menu_panel(560)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var title := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 40)
	title.text = heading
	title.add_theme_font_override("font", UiStyle.font(700))
	column.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 10)
	for row in rows:
		var key := UiStyle.label(HORIZONTAL_ALIGNMENT_RIGHT, 22)
		key.text = row[0]
		key.add_theme_color_override("font_color", Color(Palette.INK, 0.7))
		grid.add_child(key)
		var value := UiStyle.label(HORIZONTAL_ALIGNMENT_LEFT, 22)
		value.text = row[1]
		value.add_theme_font_override("font", UiStyle.font(600))
		grid.add_child(value)
	column.add_child(grid)
	column.add_child(_back_button())
	return panel


func _build_about() -> Control:
	var panel := UiStyle.menu_panel(640)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var title := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 40)
	title.text = "Acerca de"
	title.add_theme_font_override("font", UiStyle.font(700))
	column.add_child(title)

	var body := UiStyle.label(HORIZONTAL_ALIGNMENT_LEFT, 21)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	body.text = "Autelia es un juego de supervivencia por oleadas hecho en Godot 4 por Omar García.\n\n" \
		+ "También es el entorno experimental de una tesis sobre adaptación dinámica de la dificultad: " \
		+ "cada oleada se puede repetir con una semilla y el reto se controla con un solo valor.\n\n" \
		+ "Arte y sonidos hechos para el juego. Tipografía Fredoka (SIL Open Font License)."
	column.add_child(body)

	var link := LinkButton.new()
	link.text = "Ver el código en GitHub"
	link.uri = REPO_URL
	link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	link.add_theme_font_override("font", UiStyle.font(600))
	link.add_theme_font_size_override("font_size", 21)
	link.add_theme_color_override("font_color", Palette.INK)
	link.add_theme_color_override("font_hover_color", Palette.PLAYER.darkened(0.35))
	column.add_child(link)
	column.add_child(_back_button())
	return panel


func _back_button() -> Button:
	var back := UiStyle.button("Volver", 220)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func() -> void: _show(_home))
	return back


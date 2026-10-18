class_name MainMenu
extends CanvasLayer
## Main menu shown once per launch: Experimento, Modos (Arcade), Controles, Acerca de and
## (on desktop) Salir. Arcade asks for the player's name first.
## The game stays paused behind it. Starting a run is also what lets browsers start audio,
## since they block sound until the user interacts with the page.
## The chosen mode goes to GameSession; main.gd applies it when the menu is dismissed.
## Restarting with R reloads the scene but skips the menu.

signal dismissed

const REPO_URL := "https://github.com/OmarDavidd/autelia"

## Survives scene reloads, so the menu only appears when asked for.
static var seen := false

var experiment_button: Button
var arcade_button: Button
var name_input: LineEdit
var name_error: Label
var _home: Control
var _modes: Control
var _arcade: Control
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


func play_experiment() -> void:
	GameSession.mode = GameSession.Mode.EXPERIMENT
	_start()


## Starts an arcade run with the typed name. Returns false (and shows why) if it is invalid.
func start_arcade() -> bool:
	var player_name := GameSession.clean_name(name_input.text)
	if not GameSession.is_valid_name(player_name):
		name_error.visible = true
		return false
	GameSession.player_name = player_name
	GameSession.save_name(player_name)
	GameSession.mode = GameSession.Mode.ARCADE
	_start()
	return true


func show_modes() -> void:
	_show(_modes)


func show_arcade() -> void:
	name_input.text = GameSession.load_name()
	name_error.visible = false
	_show(_arcade)
	name_input.grab_focus.call_deferred()


func _start() -> void:
	seen = true
	get_tree().paused = false
	dismissed.emit()
	queue_free()


func show_controls() -> void:
	_show(_controls)


func show_about() -> void:
	_show(_about)


func _show(page: Control) -> void:
	for each in [_home, _modes, _arcade, _controls, _about]:
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
	_modes = _build_modes()
	_arcade = _build_arcade()
	_controls = _build_page("Controles", [
		["Moverse", "WASD o flechas"],
		["Apuntar y disparar", "Mouse y clic izquierdo"],
		["Pausa", "Esc o P"],
		["Reiniciar", "R al terminar la partida"],
	])
	_about = _build_about()
	for page in [_home, _modes, _arcade, _controls, _about]:
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

	experiment_button = UiStyle.button("Experimento")
	experiment_button.pressed.connect(play_experiment)
	buttons.add_child(experiment_button)
	var modes := UiStyle.button("Modos")
	modes.pressed.connect(show_modes)
	buttons.add_child(modes)
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


func _build_modes() -> Control:
	var column := _titled_panel("Modos", 420)
	arcade_button = UiStyle.button("Arcade")
	arcade_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	arcade_button.pressed.connect(show_arcade)
	column.add_child(arcade_button)
	column.add_child(_back_button())
	return column.get_parent()


func _build_arcade() -> Control:
	var column := _titled_panel("Arcade", 520)
	var info := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 21)
	info.text = "Cada oleada es más difícil. Suma puntos\ny entra en la tabla de mejores puntajes."
	info.add_theme_color_override("font_color", Color(Palette.INK, 0.7))
	column.add_child(info)

	name_input = LineEdit.new()
	name_input.placeholder_text = "Tu nombre"
	name_input.max_length = GameSession.NAME_MAX
	name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_input.custom_minimum_size = Vector2(320, 52)
	name_input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_input.add_theme_font_override("font", UiStyle.font(600))
	name_input.add_theme_font_size_override("font_size", 24)
	name_input.add_theme_color_override("font_color", Palette.INK)
	name_input.add_theme_color_override("font_placeholder_color", Color(Palette.INK, 0.4))
	name_input.add_theme_color_override("caret_color", Palette.INK)
	for state in ["normal", "focus"]:
		var field := UiStyle.box(Palette.WHITE)
		field.set_border_width_all(3)
		field.border_color = Palette.INK
		field.set_content_margin_all(10)
		name_input.add_theme_stylebox_override(state, field)
	name_input.text_submitted.connect(func(_text: String) -> void: start_arcade())
	name_input.text_changed.connect(func(_text: String) -> void: name_error.visible = false)
	column.add_child(name_input)

	name_error = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 20)
	name_error.text = "El nombre debe tener entre %d y %d caracteres" % [GameSession.NAME_MIN, GameSession.NAME_MAX]
	name_error.add_theme_color_override("font_color", Palette.ENEMY.darkened(0.3))
	name_error.visible = false
	column.add_child(name_error)

	var play := UiStyle.button("Jugar", 220)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.pressed.connect(start_arcade)
	column.add_child(play)
	column.add_child(_back_button())
	return column.get_parent()


## A menu panel with a big title; returns the column to fill.
func _titled_panel(heading: String, min_width: float) -> VBoxContainer:
	var panel := UiStyle.menu_panel(min_width)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var title := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 40)
	title.text = heading
	title.add_theme_font_override("font", UiStyle.font(700))
	column.add_child(title)
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


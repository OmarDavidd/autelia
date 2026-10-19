class_name MainMenu
extends CanvasLayer
## Main menu shown once per launch: Modos (Arcade), Puntajes, Controles, Acerca de, a disabled
## "Próximamente" teaser for the thesis experiment and (on desktop) Salir.
## Arcade asks for the player's name first, next to the global top scores.
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
var daily_button: Button
var coop_button: Button
var coop_name_input: LineEdit
var coop_code_input: LineEdit
var coop_error: Label
var lobby_code_label: Label
var lobby_hint: Label
var lobby_rows: VBoxContainer
var start_button: Button
var _add_bot_button: Button
var run_title: Label
var name_input: LineEdit
var name_error: Label
var board: LeaderboardTable
var scores_board: LeaderboardTable
var daily_board: LeaderboardTable
## The run page serves Arcade and the daily challenge; this says which one it is showing.
var _daily := false
var _run_info: Label
## Recreated on every visit, so a slow answer for the other mode can never fill the board.
var _run_leaderboard: Leaderboard
var _scores_leaderboard: Leaderboard
var _daily_leaderboard: Leaderboard
var _home: Control
var _modes: Control
var _arcade: Control
var _controls: Control
var _about: Control
var _scores: Control
var _coop: Control
var _lobby: Control
## The link to the room server while this menu waits on it or shows a server room;
## null with a local room.
var _client: RoomClient
## Crear is waiting: an unreachable server then opens a local room instead of failing.
var _creating := false


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
	GameSession.mode = GameSession.Mode.DAILY if _daily else GameSession.Mode.ARCADE
	GameSession.challenge_day = GameSession.daily_day() if _daily else ""
	_start()
	return true


func show_coop() -> void:
	coop_name_input.text = GameSession.load_name()
	coop_code_input.text = ""
	coop_error.visible = false
	_show(_coop)


## Asks the server for a room with this player as host; its lobby opens when it answers.
## Without a server it opens a local room, where only bots can join.
func create_room() -> bool:
	var player_name := _coop_name()
	if player_name.is_empty():
		return false
	_creating = true
	coop_error.visible = false
	_use_server().create(player_name)
	return true


## Asks the server to join; the lobby (or the run, if it already started) opens when it answers.
func join_room() -> bool:
	var player_name := _coop_name()
	if player_name.is_empty():
		return false
	if not CoopRoom.is_valid_code(coop_code_input.text):
		_coop_fail("El código tiene %d letras" % CoopRoom.CODE_LENGTH)
		return false
	_creating = false
	coop_error.visible = false
	_use_server().join(CoopRoom.clean_code(coop_code_input.text), player_name)
	return true


func add_bot_to_room() -> void:
	if _client:
		_client.add_bot()
	elif GameSession.coop_room:
		GameSession.coop_room.add_bot()


## The host starts: a local room right away, a server room once the server tells everyone.
func start_coop() -> void:
	if _client:
		_client.start()
	else:
		_enter_coop()


func leave_room() -> void:
	if _client:
		_client.leave()
		_forget_server()
	GameSession.coop_room = null
	show_coop()


## Runs once: the menu frees itself only at the end of the frame, and more started rooms
## (a double tap, a join) can still arrive before then.
func _enter_coop() -> void:
	_forget_server()
	if seen:
		return
	GameSession.mode = GameSession.Mode.COOP
	_start()


func _use_server() -> RoomClient:
	if _client == null:
		_client = RoomClient.shared(get_tree())
		_client.room_changed.connect(_on_server_room)
		_client.failed.connect(_on_server_failed)
		_client.disconnected.connect(_on_server_lost)
	return _client


func _forget_server() -> void:
	if _client:
		_client.room_changed.disconnect(_on_server_room)
		_client.failed.disconnect(_on_server_failed)
		_client.disconnected.disconnect(_on_server_lost)
		_client = null


func _on_server_room(room: CoopRoom) -> void:
	GameSession.coop_room = room
	if room.started:
		_enter_coop()
		return
	_refresh_lobby()
	_show(_lobby)


func _on_server_failed(reason: String) -> void:
	if reason == "unreachable":
		_forget_server()
		if _creating:
			GameSession.coop_room = CoopRoom.create(GameSession.player_name)
			GameSession.coop_room.changed.connect(_refresh_lobby)
			_refresh_lobby()
			_show(_lobby)
			return
	_show(_coop)
	_coop_fail(server_error(reason))


func _on_server_lost() -> void:
	_forget_server()
	GameSession.coop_room = null
	_show(_coop)
	_coop_fail("Se perdió la conexión con el servidor")


static func server_error(reason: String) -> String:
	match reason:
		"unreachable":
			return "No se pudo conectar al servidor"
		"not_found":
			return "No existe una sala con ese código"
		"full":
			return "La sala está llena"
		"busy":
			return "El servidor está lleno, prueba más tarde"
		"bad_name":
			return "El nombre debe tener entre %d y %d caracteres" % [GameSession.NAME_MIN, GameSession.NAME_MAX]
		"bad_code":
			return "El código tiene %d letras" % CoopRoom.CODE_LENGTH
	return "El servidor rechazó la solicitud"


## The validated, remembered name, or "" after showing why it is not valid.
func _coop_name() -> String:
	var player_name := GameSession.clean_name(coop_name_input.text)
	if not GameSession.is_valid_name(player_name):
		_coop_fail("El nombre debe tener entre %d y %d caracteres" % [GameSession.NAME_MIN, GameSession.NAME_MAX])
		return ""
	GameSession.player_name = player_name
	GameSession.save_name(player_name)
	return player_name


func _coop_fail(message: String) -> void:
	coop_error.text = message
	coop_error.visible = true


func _refresh_lobby() -> void:
	var room: CoopRoom = GameSession.coop_room
	if _client:
		lobby_code_label.text = "Código: %s" % room.code
		lobby_hint.text = "Comparte el código para que se unan." if room.is_host() \
			else "Esperando a que el anfitrión empiece."
	else:
		lobby_code_label.text = "Sala local"
		lobby_hint.text = "Sin conexión al servidor: solo puedes sumar bots."
	for child in lobby_rows.get_children():
		child.free()
	for i in room.players.size():
		var entry: Dictionary = room.players[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var swatch := ColorRect.new()
		swatch.color = Palette.PLAYER_COLORS[i]
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var label := UiStyle.label(HORIZONTAL_ALIGNMENT_LEFT, 22)
		label.text = entry.name + (" (anfitrión)" if entry.host else " (bot)" if entry.bot else "") \
			+ (" · tú" if not entry.bot and entry.id == room.you else "")
		row.add_child(label)
		lobby_rows.add_child(row)
	_add_bot_button.disabled = room.is_full()
	_add_bot_button.visible = room.is_host()
	start_button.visible = room.is_host()


func show_modes() -> void:
	_show(_modes)


func show_arcade() -> void:
	_open_run_page(false)


func show_daily() -> void:
	_open_run_page(true)


func _open_run_page(daily: bool) -> void:
	_daily = daily
	var today := GameSession.daily_day()
	run_title.text = "Desafío diario %s" % GameSession.daily_label(today) if daily else "Arcade"
	_run_info.text = "Hoy todos juegan la misma partida.\n¿Quién llega más lejos?" if daily \
		else "Cada oleada es más difícil. Suma puntos\ny entra en la tabla de mejores puntajes."
	name_input.text = GameSession.load_name()
	name_error.visible = false
	_show(_arcade)
	# Phones only open their keyboard when a tap focuses the field; taking focus here would
	# leave it focused with no keyboard, and later taps would not open one either.
	if not TouchControls.wanted():
		name_input.grab_focus.call_deferred()
	board.show_loading()
	if _run_leaderboard:
		_run_leaderboard.queue_free()
	_run_leaderboard = _fetch_into(board, today if daily else "")


## The shared client outlives the menu; drop the menu's listeners with it.
func _exit_tree() -> void:
	_forget_server()


func _start() -> void:
	seen = true
	get_tree().paused = false
	dismissed.emit()
	queue_free()


func show_controls() -> void:
	_show(_controls)


func show_scores() -> void:
	_show(_scores)
	scores_board.show_loading()
	daily_board.show_loading()
	for old in [_scores_leaderboard, _daily_leaderboard]:
		if old:
			old.queue_free()
	_scores_leaderboard = _fetch_into(scores_board, "")
	_daily_leaderboard = _fetch_into(daily_board, GameSession.daily_day())


## Loads one table into one board; no row is highlighted, since only a finished run knows
## which row is its own.
func _fetch_into(table: LeaderboardTable, day: String) -> Leaderboard:
	var source := Leaderboard.new()
	source.day = day
	add_child(source)
	source.top_loaded.connect(func(rows: Array) -> void: table.show_rows(rows, "", -1))
	source.failed.connect(table.show_error)
	source.fetch_top()
	return source


func show_about() -> void:
	_show(_about)


func _show(page: Control) -> void:
	for each in [_home, _modes, _arcade, _scores, _controls, _about, _coop, _lobby]:
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
	# Phones get the touch controls of the Arcade mode, the only mode they can play.
	if TouchControls.wanted():
		_controls = _build_page("Controles", [
			["Moverse", "Joystick izquierdo"],
			["Apuntar y disparar", "Mantén el joystick derecho"],
			["Pausa", "Botón II"],
			["Reiniciar", "Botón Reiniciar al terminar"],
			["Pantalla", "Teléfono en horizontal"],
		])
	else:
		_controls = _build_page("Controles", [
			["Moverse", "WASD o flechas"],
			["Apuntar y disparar", "Mouse y clic izquierdo"],
			["Pausa", "Esc o P"],
			["Reiniciar", "R al terminar la partida"],
		])
	_about = _build_about()
	_scores = _build_scores()
	_coop = _build_coop()
	_lobby = _build_lobby()
	for page in [_home, _modes, _arcade, _scores, _controls, _about, _coop, _lobby]:
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

	var modes := UiStyle.button("Modos")
	modes.pressed.connect(show_modes)
	buttons.add_child(modes)
	var scores := UiStyle.button("Puntajes")
	scores.pressed.connect(show_scores)
	buttons.add_child(scores)
	var controls := UiStyle.button("Controles")
	controls.pressed.connect(show_controls)
	buttons.add_child(controls)
	var about := UiStyle.button("Acerca de")
	about.pressed.connect(show_about)
	buttons.add_child(about)
	# The thesis experiment is not open to players yet: a teaser that cannot be clicked.
	experiment_button = UiStyle.button("Próximamente")
	experiment_button.disabled = true
	experiment_button.focus_mode = Control.FOCUS_NONE
	experiment_button.pressed.connect(play_experiment)
	buttons.add_child(experiment_button)
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
	daily_button = UiStyle.button("Desafío diario")
	daily_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	daily_button.pressed.connect(show_daily)
	coop_button = UiStyle.button("Cooperativo")
	coop_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	coop_button.pressed.connect(show_coop)
	column.add_child(daily_button)
	column.add_child(coop_button)
	column.add_child(_back_button())
	return column.get_parent()


func _build_arcade() -> Control:
	var page := _titled_panel("Arcade", 900)
	run_title = page.get_child(0)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 40)
	page.add_child(sides)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	sides.add_child(column)

	board = LeaderboardTable.new(20)
	board.custom_minimum_size = Vector2(380, 0)
	sides.add_child(board)

	_run_info = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 21)
	_run_info.add_theme_color_override("font_color", Color(Palette.INK, 0.7))
	column.add_child(_run_info)

	name_input = _text_field("Tu nombre", GameSession.NAME_MAX)
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
	return page.get_parent()


func _build_coop() -> Control:
	var column := _titled_panel("Cooperativo", 520)
	var info := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 21)
	info.text = "Juega con amigos: crea una sala y comparte\nel código, o entra con el código de otro."
	info.add_theme_color_override("font_color", Color(Palette.INK, 0.7))
	column.add_child(info)
	coop_name_input = _text_field("Tu nombre", GameSession.NAME_MAX)
	coop_name_input.text_changed.connect(func(_text: String) -> void: coop_error.visible = false)
	column.add_child(coop_name_input)
	var create := UiStyle.button("Crear partida", 320)
	create.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	create.pressed.connect(create_room)
	column.add_child(create)

	var join := HBoxContainer.new()
	join.alignment = BoxContainer.ALIGNMENT_CENTER
	join.add_theme_constant_override("separation", 12)
	column.add_child(join)
	coop_code_input = _text_field("Código", CoopRoom.CODE_LENGTH)
	coop_code_input.custom_minimum_size = Vector2(150, 52)
	coop_code_input.text_changed.connect(func(_text: String) -> void: coop_error.visible = false)
	coop_code_input.text_submitted.connect(func(_text: String) -> void: join_room())
	join.add_child(coop_code_input)
	var join_button := UiStyle.button("Unirse", 158)
	join_button.pressed.connect(join_room)
	join.add_child(join_button)

	coop_error = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 20)
	coop_error.add_theme_color_override("font_color", Palette.ENEMY.darkened(0.3))
	coop_error.visible = false
	column.add_child(coop_error)
	column.add_child(_back_button())
	return column.get_parent()


func _build_lobby() -> Control:
	var column := _titled_panel("Sala", 520)
	lobby_code_label = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 34)
	lobby_code_label.add_theme_font_override("font", UiStyle.font(700))
	column.add_child(lobby_code_label)
	lobby_hint = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 20)
	lobby_hint.add_theme_color_override("font_color", Color(Palette.INK, 0.7))
	column.add_child(lobby_hint)
	lobby_rows = VBoxContainer.new()
	lobby_rows.add_theme_constant_override("separation", 6)
	lobby_rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(lobby_rows)
	_add_bot_button = UiStyle.button("Agregar bot", 320)
	_add_bot_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_add_bot_button.pressed.connect(add_bot_to_room)
	column.add_child(_add_bot_button)
	start_button = UiStyle.button("Empezar", 320)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.pressed.connect(start_coop)
	column.add_child(start_button)
	var leave := UiStyle.button("Salir de la sala", 320)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(leave_room)
	column.add_child(leave)
	return column.get_parent()


## A white outlined text box, centered text, shared by every field in the menu.
func _text_field(placeholder: String, max_length: int) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = max_length
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.custom_minimum_size = Vector2(320, 52)
	field.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	field.add_theme_font_override("font", UiStyle.font(600))
	field.add_theme_font_size_override("font_size", 24)
	field.add_theme_color_override("font_color", Palette.INK)
	field.add_theme_color_override("font_placeholder_color", Color(Palette.INK, 0.4))
	field.add_theme_color_override("caret_color", Palette.INK)
	for state in ["normal", "focus"]:
		var box := UiStyle.box(Palette.WHITE)
		box.set_border_width_all(3)
		box.border_color = Palette.INK
		box.set_content_margin_all(10)
		field.add_theme_stylebox_override(state, box)
	return field


func _build_scores() -> Control:
	var panel := UiStyle.menu_panel(900)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 40)
	sides.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(sides)
	scores_board = LeaderboardTable.new(20, "Arcade")
	scores_board.custom_minimum_size = Vector2(380, 0)
	sides.add_child(scores_board)
	daily_board = LeaderboardTable.new(20, "Desafío de hoy")
	daily_board.custom_minimum_size = Vector2(380, 0)
	sides.add_child(daily_board)
	column.add_child(_back_button())
	return panel


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


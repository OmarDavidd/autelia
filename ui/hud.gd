class_name Hud
extends CanvasLayer
## In-game HUD: health, wave and time, kills, the arcade score, and the game-over panel.
## Updates from Events and the mode's public getters; it never changes game state.
## Copy is in Spanish because the players are Spanish speakers.

## Lets the player's death animation play before the panel covers it.
const GAME_OVER_DELAY := 0.6
## Leaderboard grid: rank, name, points, wave.
const BOARD_COLUMNS := 4

var health_bar: ProgressBar
var wave_label: Label
var kills_label: Label
var score_label: Label
var game_over_panel: PanelContainer
var game_over_label: Label
var board_status: Label
var board_rows: GridContainer
var hint_label: Label

var _mode: SurvivalMode
var _kills := 0
var _score: ScoreKeeper


func _ready() -> void:
	_build()
	Events.player_damaged.connect(_on_player_damaged)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.player_died.connect(_on_player_died)


func bind(mode: SurvivalMode) -> void:
	_mode = mode
	health_bar.max_value = mode.player.health.max_health
	health_bar.value = mode.player.health.current


## Arcade only: shows the score and puts it, with the leaderboard, on the game-over panel.
func show_score(keeper: ScoreKeeper) -> void:
	_score = keeper
	score_label.visible = true
	_on_score_changed(keeper.score)
	keeper.changed.connect(_on_score_changed)


## Fills the leaderboard; the row matching this run is highlighted.
func show_leaderboard(rows: Array, player_name: String, score: int) -> void:
	for child in board_rows.get_children():
		child.free()
	board_status.visible = rows.is_empty()
	board_status.text = "Todavía no hay puntajes"
	var marked := false
	for i in rows.size():
		var row: Dictionary = rows[i]
		var mine: bool = not marked and row.name == player_name and row.score == score
		marked = marked or mine
		var cells := ["%d." % (i + 1), row.name, str(row.score), "Oleada %d" % row.wave]
		for c in BOARD_COLUMNS:
			var cell := UiStyle.label(HORIZONTAL_ALIGNMENT_RIGHT if c != 1 else HORIZONTAL_ALIGNMENT_LEFT, 22)
			cell.text = cells[c]
			cell.add_theme_font_override("font", UiStyle.font(700 if mine else 500))
			if mine:
				cell.add_theme_color_override("font_color", Palette.PLAYER.darkened(0.35))
			board_rows.add_child(cell)


func show_leaderboard_error() -> void:
	board_status.visible = true
	board_status.text = "No se pudo cargar la tabla"


func _process(_delta: float) -> void:
	if _mode == null:
		return
	var spawner := _mode.spawner
	var seconds := ceili(spawner.time_left())
	if spawner.wave == 0:
		wave_label.text = "Prepárate · %d" % seconds
	elif spawner.in_break():
		wave_label.text = "Siguiente oleada en %d" % seconds
	else:
		wave_label.text = "Oleada %d · %d:%02d" % [spawner.wave, seconds / 60, seconds % 60]


func _on_player_damaged(_amount: float, health_left: float) -> void:
	health_bar.value = health_left


func _on_enemy_killed(_enemy: Node) -> void:
	_kills += 1
	kills_label.text = "Eliminaciones: %d" % _kills


func _on_score_changed(score: int) -> void:
	score_label.text = "Puntos: %d" % score


func _on_player_died() -> void:
	# A signal connection (not await) is dropped automatically if the HUD is freed first.
	get_tree().create_timer(GAME_OVER_DELAY).timeout.connect(_show_game_over)


func _show_game_over() -> void:
	var wave := _mode.spawner.wave if _mode else 0
	if _score:
		game_over_label.text = "Fin de la partida\nPuntos: %d · Oleada alcanzada: %d" % [_score.score, wave]
		board_rows.get_parent().visible = true
		hint_label.visible = true
	else:
		game_over_label.text = "Fin de la partida\nOleada alcanzada: %d · Eliminaciones: %d\n\nPresiona R para reiniciar" % [wave, _kills]
	game_over_panel.visible = true


func _build() -> void:
	var root := MarginContainer.new()
	root.theme = UiStyle.theme()
	# Same 1280x720 area as the arena, centered, so wide screens do not push the HUD off it.
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.offset_left = -640.0
	root.offset_right = 640.0
	root.offset_top = -360.0
	root.offset_bottom = 360.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 40)
	add_child(root)

	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(240, 22)
	health_bar.show_percentage = false
	health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	health_bar.add_theme_stylebox_override("background", UiStyle.box(Color(Palette.INK, 0.12)))
	var fill := UiStyle.box(Palette.PLAYER)
	fill.set_border_width_all(3)
	fill.border_color = Palette.INK
	health_bar.add_theme_stylebox_override("fill", fill)
	top.add_child(health_bar)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(middle)
	wave_label = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER)
	middle.add_child(wave_label)
	score_label = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 32)
	score_label.add_theme_font_override("font", UiStyle.font(700))
	score_label.visible = false
	middle.add_child(score_label)

	kills_label = UiStyle.label(HORIZONTAL_ALIGNMENT_RIGHT)
	kills_label.custom_minimum_size = Vector2(240, 0)
	kills_label.add_theme_font_override("font", UiStyle.font(500))
	kills_label.text = "Eliminaciones: 0"
	top.add_child(kills_label)

	game_over_panel = PanelContainer.new()
	game_over_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	game_over_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var panel_box := UiStyle.panel_box()
	panel_box.set_content_margin_all(32)
	game_over_panel.add_theme_stylebox_override("panel", panel_box)
	game_over_panel.visible = false
	root.add_child(game_over_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	game_over_panel.add_child(column)
	game_over_label = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(game_over_label)

	# Arcade only: the global leaderboard, shown while it loads or with its error.
	var board := VBoxContainer.new()
	board.visible = false
	board.add_theme_constant_override("separation", 8)
	column.add_child(board)
	var heading := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 24)
	heading.text = "Mejores puntajes"
	heading.add_theme_font_override("font", UiStyle.font(700))
	board.add_child(heading)
	board_status = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 22)
	board_status.text = "Cargando la tabla…"
	board_status.add_theme_color_override("font_color", Color(Palette.INK, 0.7))
	board.add_child(board_status)
	board_rows = GridContainer.new()
	board_rows.columns = BOARD_COLUMNS
	board_rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	board_rows.add_theme_constant_override("h_separation", 24)
	board_rows.add_theme_constant_override("v_separation", 4)
	board.add_child(board_rows)

	hint_label = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 22)
	hint_label.text = "Presiona R para reiniciar"
	hint_label.visible = false
	column.add_child(hint_label)


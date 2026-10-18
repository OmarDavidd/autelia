class_name Hud
extends CanvasLayer
## In-game HUD: health, wave and time, kills, and the game-over panel.
## Updates from Events and the mode's public getters; it never changes game state.
## Copy is in Spanish because the players are Spanish speakers.

## Lets the player's death animation play before the panel covers it.
const GAME_OVER_DELAY := 0.6

var health_bar: ProgressBar
var wave_label: Label
var kills_label: Label
var game_over_panel: PanelContainer
var game_over_label: Label

var _mode: SurvivalMode
var _kills := 0


func _ready() -> void:
	_build()
	Events.player_damaged.connect(_on_player_damaged)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.player_died.connect(_on_player_died)


func bind(mode: SurvivalMode) -> void:
	_mode = mode
	health_bar.max_value = mode.player.health.max_health
	health_bar.value = mode.player.health.current


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


func _on_player_died() -> void:
	# A signal connection (not await) is dropped automatically if the HUD is freed first.
	get_tree().create_timer(GAME_OVER_DELAY).timeout.connect(_show_game_over)


func _show_game_over() -> void:
	var wave := _mode.spawner.wave if _mode else 0
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

	wave_label = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER)
	wave_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(wave_label)

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

	game_over_label = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER)
	game_over_panel.add_child(game_over_label)


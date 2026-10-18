class_name Hud
extends CanvasLayer
## In-game HUD: health, wave and time, kills, and the game-over panel.
## Updates from Events and the mode's public getters; it never changes game state.
## Copy is in Spanish because the players are Spanish speakers.

const TEXT_SIZE := 22

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
	var wave := _mode.spawner.wave if _mode else 0
	game_over_label.text = "Fin de la partida\nOleada alcanzada: %d · Eliminaciones: %d\n\nPresiona R para reiniciar" % [wave, _kills]
	game_over_panel.visible = true


func _build() -> void:
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 40)
	add_child(root)

	var top := HBoxContainer.new()
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(220, 18)
	health_bar.show_percentage = false
	health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	health_bar.add_theme_stylebox_override("background", _box(Color(Palette.INK, 0.12)))
	health_bar.add_theme_stylebox_override("fill", _box(Palette.PLAYER))
	top.add_child(health_bar)

	wave_label = _label(HORIZONTAL_ALIGNMENT_CENTER)
	wave_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(wave_label)

	kills_label = _label(HORIZONTAL_ALIGNMENT_RIGHT)
	kills_label.custom_minimum_size = Vector2(220, 0)
	kills_label.text = "Eliminaciones: 0"
	top.add_child(kills_label)

	game_over_panel = PanelContainer.new()
	game_over_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	game_over_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var panel_box := _box(Color(Palette.BACKGROUND, 0.95))
	panel_box.set_border_width_all(3)
	panel_box.border_color = Palette.INK
	panel_box.set_content_margin_all(32)
	game_over_panel.add_theme_stylebox_override("panel", panel_box)
	game_over_panel.visible = false
	root.add_child(game_over_panel)

	game_over_label = _label(HORIZONTAL_ALIGNMENT_CENTER)
	game_over_panel.add_child(game_over_label)


func _label(alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.add_theme_color_override("font_color", Palette.INK)
	label.add_theme_font_size_override("font_size", TEXT_SIZE)
	return label


func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(9)
	return box

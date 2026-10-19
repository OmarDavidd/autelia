class_name GunGameHud
extends CanvasLayer
## Minimalist HUD for Gun Game: tracks current weapon, progress pips, live kill feed,
## ranking and victory overlay.

var mode: GunGameMode
var restart_button: Button
var menu_button: Button

var _weapon_name_label: Label
var _weapon_level_label: Label
var _pips_label: Label
var _kill_feed_container: VBoxContainer
var _leaderboard_label: Label
var _victory_panel: PanelContainer
var _victory_title: Label
var _victory_subtitle: Label


func _ready() -> void:
	# The match pauses the tree when someone wins; the victory buttons must still work.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


## The victory buttons leave the match the same way the pause menu does.
func bind(game_mode: GunGameMode, pause: PauseMenu) -> void:
	mode = game_mode
	restart_button.pressed.connect(pause.restart)
	menu_button.pressed.connect(pause.to_main_menu)
	mode.player_leveled.connect(_on_player_leveled)
	mode.kill_logged.connect(_on_kill_logged)
	mode.match_finished.connect(_on_match_finished)
	update_hud()


func update_hud() -> void:
	if mode == null or mode.local_player == null:
		return

	var p := mode.local_player
	var lvl: int = mode.levels.get(p, 1)
	var kills: int = mode.level_kills.get(p, 0)
	var needed := GunGameRules.kills_to_advance(lvl)

	_weapon_name_label.text = GunGameRules.weapon_name(lvl).to_upper()
	_weapon_level_label.text = "Nivel %d / %d" % [lvl, GunGameRules.MAX_LEVEL]

	# Build pips: e.g. "● ○"
	var pips := ""
	for i in needed:
		pips += "● " if i < kills else "○ "
	_pips_label.text = pips.strip_edges()

	# Update live top 3 ranking
	_update_leaderboard()


func _update_leaderboard() -> void:
	if mode == null:
		return
	var sorted_combatants := mode.combatants.duplicate()
	sorted_combatants.sort_custom(func(a: Player, b: Player) -> bool:
		var lvl_a: int = mode.levels.get(a, 1)
		var lvl_b: int = mode.levels.get(b, 1)
		if lvl_a != lvl_b:
			return lvl_a > lvl_b
		return mode.level_kills.get(a, 0) > mode.level_kills.get(b, 0)
	)

	var text := "POSICIONES\n"
	for i in mini(3, sorted_combatants.size()):
		var c: Player = sorted_combatants[i]
		var cname: String = mode.names.get(c, "Jugador")
		var clvl: int = mode.levels.get(c, 1)
		var marker := "▶ " if c == mode.local_player else "  "
		text += "%s%d. %s (Nv. %d)\n" % [marker, i + 1, cname, clvl]
	_leaderboard_label.text = text.strip_edges()


func _on_player_leveled(combatant: Player, _new_level: int) -> void:
	if combatant == mode.local_player:
		update_hud()


func _on_kill_logged(k_name: String, v_name: String, k_color: Color, v_color: Color) -> void:
	update_hud()
	_add_kill_feed(k_name, v_name, k_color, v_color)


func _add_kill_feed(k_name: String, v_name: String, k_color: Color, v_color: Color) -> void:
	var entry := RichTextLabel.new()
	entry.fit_content = true
	entry.bbcode_enabled = true
	entry.autowrap_mode = TextServer.AUTOWRAP_OFF
	entry.custom_minimum_size = Vector2(240, 24)

	var k_hex := k_color.to_html(false)
	var v_hex := v_color.to_html(false)
	entry.text = "[color=#%s]%s[/color] [color=#2b2340]▶[/color] [color=#%s]%s[/color]" % [
		k_hex, k_name, v_hex, v_name
	]
	entry.add_theme_font_override("normal_font", UiStyle.font(600))
	entry.add_theme_font_size_override("normal_font_size", 18)

	_kill_feed_container.add_child(entry)
	if _kill_feed_container.get_child_count() > 4:
		var oldest := _kill_feed_container.get_child(0)
		_kill_feed_container.remove_child(oldest)
		oldest.queue_free()

	# Fade out after 3.5 seconds
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(entry, "modulate:a", 0.0, 0.5)
	tween.tween_callback(entry.queue_free)


func _on_match_finished(winner: Player, winner_name: String, winner_color: Color) -> void:
	_victory_panel.visible = true
	if winner == mode.local_player:
		_victory_title.text = "¡VICTORIA!"
		_victory_subtitle.text = "¡Completaste todos los niveles de armas!"
	else:
		_victory_title.text = "%s GANA" % winner_name.to_upper()
		_victory_subtitle.text = "¡Alcanzó la estocada final antes que nadie!"
	_victory_title.add_theme_color_override("font_color", winner_color)


func _build_ui() -> void:
	# 1. Top Center: Weapon Card
	var top_center := VBoxContainer.new()
	top_center.alignment = BoxContainer.ALIGNMENT_CENTER
	top_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_center.offset_top = 18.0
	top_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(top_center)

	var card := PanelContainer.new()
	var card_box := UiStyle.box(Color(Palette.FLOOR, 0.9), 12)
	card_box.border_color = Palette.INK
	card_box.set_border_width_all(3)
	card_box.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", card_box)
	top_center.add_child(card)

	var card_vbox := VBoxContainer.new()
	card_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(card_vbox)

	_weapon_name_label = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 22)
	_weapon_name_label.add_theme_font_override("font", UiStyle.font(700))
	card_vbox.add_child(_weapon_name_label)

	_weapon_level_label = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 14)
	_weapon_level_label.add_theme_color_override("font_color", Color(Palette.INK, 0.7))
	card_vbox.add_child(_weapon_level_label)

	_pips_label = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 18)
	_pips_label.add_theme_color_override("font_color", Palette.PLAYER)
	card_vbox.add_child(_pips_label)

	# 2. Top Left: Leaderboard
	var top_left := MarginContainer.new()
	top_left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_left.offset_left = 24.0
	top_left.offset_top = 20.0
	add_child(top_left)

	_leaderboard_label = UiStyle.label(HORIZONTAL_ALIGNMENT_LEFT, 15)
	_leaderboard_label.add_theme_font_override("font", UiStyle.font(600))
	_leaderboard_label.add_theme_color_override("font_color", Color(Palette.INK, 0.8))
	top_left.add_child(_leaderboard_label)

	# 3. Top Right: Kill Feed
	var top_right := MarginContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.offset_right = -24.0
	top_right.offset_top = 20.0
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(top_right)

	_kill_feed_container = VBoxContainer.new()
	_kill_feed_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_right.add_child(_kill_feed_container)

	# 4. Victory Overlay
	_victory_panel = PanelContainer.new()
	_victory_panel.set_anchors_preset(Control.PRESET_CENTER)
	_victory_panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	_victory_panel.visible = false
	_victory_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_victory_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_victory_panel)

	var vic_vbox := VBoxContainer.new()
	vic_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vic_vbox.add_theme_constant_override("separation", 16)
	_victory_panel.add_child(vic_vbox)

	_victory_title = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 36)
	_victory_title.add_theme_font_override("font", UiStyle.font(700))
	vic_vbox.add_child(_victory_title)

	_victory_subtitle = UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 20)
	vic_vbox.add_child(_victory_subtitle)

	restart_button = UiStyle.button("Jugar de nuevo", 260)
	vic_vbox.add_child(restart_button)

	menu_button = UiStyle.button("Menú principal", 260)
	vic_vbox.add_child(menu_button)

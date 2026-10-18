class_name TouchControls
extends CanvasLayer
## On-screen controls for touchscreens (Arcade only): a floating move stick on the left half,
## an aim stick on the right half that fires while held, a pause button and, at game over,
## a restart button. Sticks feed the same input actions as the keyboard, and the aim goes
## through Player.aim_override, so the core never knows which device is playing.
##
## Dormant until the first touch, and back to sleep when a real mouse moves: on a touch laptop
## played with the mouse, clicking still fires and the mouse still aims. Every touch also
## arrives as mouse events, and the web build does not tag them as emulated, so only mouse
## input after a quiet spell with no finger down counts as the player switching.

const STICK_RADIUS := 90.0
## Fraction of the radius ignored around the center, so resting thumbs do nothing.
const DEAD_ZONE := 0.2
const MOVE_ACTIONS := ["move_left", "move_right", "move_up", "move_down"]
## How far ahead of the player the aim point sits.
const AIM_REACH := 120.0
## Mouse input this soon after a touch is the touch's own echo, not a real mouse.
const MOUSE_GRACE_MSEC := 500

## Tests and `--touch` on the command line show the controls without a touchscreen.
static var forced := false

var pause_button: Button
var restart_button: Button
## True while the player is using touch; false while dormant or using the mouse.
var active := false
## When a finger last touched or moved; mouse input near it is ignored.
var last_touch_msec := -MOUSE_GRACE_MSEC

var _player: Player
var _pause_menu: PauseMenu
var _hud: Hud
var _mouse_hint := ""
var _canvas: Control
## Per stick: the touch index driving it (-1 when idle), where it started, and its vector.
var _move := {"index": -1, "origin": Vector2.ZERO, "value": Vector2.ZERO}
var _aim := {"index": -1, "origin": Vector2.ZERO, "value": Vector2.ZERO}
var _aim_direction := Vector2.RIGHT
## Mouse clicks taken off "shoot" while touch controls exist (touches also arrive as clicks).
var _removed_shoot_events: Array[InputEvent] = []


static func wanted() -> bool:
	return forced or DisplayServer.is_touchscreen_available() \
		or OS.get_cmdline_user_args().has("--touch")


func _ready() -> void:
	layer = 10
	_build()
	Events.player_died.connect(_on_player_died)


func _exit_tree() -> void:
	_set_active(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_release_all()


func bind(mode: SurvivalMode) -> void:
	_player = mode.player
	_pause_menu = mode.get_node("PauseMenu")
	_hud = mode.hud
	_mouse_hint = _hud.restart_hint


## Touch takes over shooting and aiming; the mouse gets them back when it is used again.
func _set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	_release_all()
	if active:
		for event in InputMap.action_get_events("shoot"):
			if event is InputEventMouseButton:
				_removed_shoot_events.append(event)
				InputMap.action_erase_event("shoot", event)
	else:
		for event in _removed_shoot_events:
			InputMap.action_add_event("shoot", event)
		_removed_shoot_events.clear()
	if _player:
		_player.aim_override = _player.global_position + _aim_direction * AIM_REACH if active else Vector2.INF
	if _hud:
		_hud.restart_hint = "" if active else _mouse_hint
	pause_button.visible = active


func _physics_process(_delta: float) -> void:
	# Keep the aim point ahead of the player as it moves.
	if active and _player and not _player.health.is_dead():
		_player.aim_override = _player.global_position + _aim_direction * AIM_REACH


func _input(event: InputEvent) -> void:
	if _player == null or _player.health.is_dead():
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		last_touch_msec = Time.get_ticks_msec()
	elif event is InputEventMouse:
		var finger_down: bool = _move.index != -1 or _aim.index != -1
		if not finger_down and Time.get_ticks_msec() - last_touch_msec > MOUSE_GRACE_MSEC:
			_set_active(false)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_set_active(true)
			_press(event.index, event.position)
		else:
			_lift(event.index)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)


func _press(index: int, at: Vector2) -> void:
	if pause_button.get_global_rect().grow(16.0).has_point(at):
		return
	var stick := _move if at.x < _canvas.size.x * 0.5 else _aim
	if stick.index != -1:
		return
	stick.index = index
	stick.origin = at
	stick.value = Vector2.ZERO
	_apply()


func _drag(index: int, at: Vector2) -> void:
	for stick in [_move, _aim]:
		if stick.index == index:
			var offset: Vector2 = (at - stick.origin) / STICK_RADIUS
			stick.value = offset.limit_length(1.0)
			_apply()


func _lift(index: int) -> void:
	for stick in [_move, _aim]:
		if stick.index == index:
			stick.index = -1
			stick.value = Vector2.ZERO
			_apply()


## Pushes both sticks into the input actions and the player's aim.
func _apply() -> void:
	var move: Vector2 = _move.value if _move.value.length() >= DEAD_ZONE else Vector2.ZERO
	var strengths := [maxf(-move.x, 0.0), maxf(move.x, 0.0), maxf(-move.y, 0.0), maxf(move.y, 0.0)]
	for i in MOVE_ACTIONS.size():
		if strengths[i] > 0.0:
			Input.action_press(MOVE_ACTIONS[i], strengths[i])
		else:
			Input.action_release(MOVE_ACTIONS[i])

	var aiming: bool = _aim.value.length() >= DEAD_ZONE
	if aiming:
		_aim_direction = _aim.value.normalized()
		Input.action_press("shoot")
	else:
		Input.action_release("shoot")
	if _player:
		_player.aim_override = _player.global_position + _aim_direction * AIM_REACH
	_canvas.queue_redraw()


func _release_all() -> void:
	for stick in [_move, _aim]:
		stick.index = -1
		stick.value = Vector2.ZERO
	for action in MOVE_ACTIONS:
		Input.action_release(action)
	Input.action_release("shoot")
	if _canvas:
		_canvas.queue_redraw()


func _toggle_pause() -> void:
	_release_all()
	_pause_menu.toggle()


func _on_player_died() -> void:
	_release_all()
	pause_button.visible = false
	if not active:
		return
	# Same delay as the game-over panel, so it does not cover the death animation.
	get_tree().create_timer(Hud.GAME_OVER_DELAY).timeout.connect(func() -> void: restart_button.visible = true)


func _draw_sticks() -> void:
	for stick in [_move, _aim]:
		if stick.index == -1:
			continue
		var base: Vector2 = stick.origin
		_canvas.draw_circle(base, STICK_RADIUS, Color(Palette.INK, 0.08))
		_canvas.draw_arc(base, STICK_RADIUS, 0.0, TAU, 48, Color(Palette.INK, 0.35), 4.0, true)
		var knob_color := Palette.PLAYER if is_same(stick, _move) else Palette.SHOOTER
		Sketch.blob(_canvas, base + stick.value * STICK_RADIUS, 34.0, knob_color)


func _build() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_sticks)
	add_child(_canvas)

	pause_button = UiStyle.button("II", 72)
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -112.0
	pause_button.offset_right = -40.0
	pause_button.offset_top = 104.0
	pause_button.offset_bottom = 160.0
	pause_button.pressed.connect(_toggle_pause)
	pause_button.visible = false
	add_child(pause_button)

	restart_button = UiStyle.button("Reiniciar", 260)
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	restart_button.offset_left = -130.0
	restart_button.offset_right = 130.0
	restart_button.offset_top = -96.0
	restart_button.offset_bottom = -40.0
	restart_button.visible = false
	restart_button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	add_child(restart_button)

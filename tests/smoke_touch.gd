extends Node
## Touch controls smoke test: move and aim sticks, pause and restart buttons, arcade-only wiring.
## Run: godot --headless --path . tests/smoke_touch.tscn
## Touches are fed straight to the controls, so no touchscreen is needed.

const PROFILE := "user://test_profile.cfg"

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	GameSession.profile_path = PROFILE
	Leaderboard.enabled = false
	await _experiment_has_no_touch_controls()
	await _sticks_move_aim_and_shoot()
	await _death_offers_restart()
	await _mouse_player_on_touch_device_keeps_r_hint()
	_rotate_hint_only_in_portrait()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	TouchControls.forced = false

	get_tree().paused = false
	if failures.is_empty():
		print("SMOKE OK: touch sticks move, aim and shoot; pause, restart and arcade-only wiring behave")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _touch(controls: TouchControls, index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	controls._input(event)


func _drag(controls: TouchControls, index: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	controls._input(event)


func _start(mode: GameSession.Mode) -> Node:
	MainMenu.seen = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	var menu: MainMenu = main.get_node("MainMenu")
	if mode == GameSession.Mode.ARCADE:
		menu.show_arcade()
		menu.name_input.text = "Ana"
		menu.start_arcade()
	else:
		menu.play_experiment()
	await _frames(2)
	return main


func _experiment_has_no_touch_controls() -> void:
	TouchControls.forced = true
	var main := await _start(GameSession.Mode.EXPERIMENT)
	_expect(main.get_node_or_null("TouchControls") == null, "experiment must not show touch controls")
	main.queue_free()
	await _frames(2)

	TouchControls.forced = false
	main = await _start(GameSession.Mode.ARCADE)
	_expect(main.get_node_or_null("TouchControls") == null, "touch controls shown without a touchscreen")
	main.queue_free()
	GameSession.mode = GameSession.Mode.EXPERIMENT
	await _frames(2)


func _sticks_move_aim_and_shoot() -> void:
	TouchControls.forced = true
	var main := await _start(GameSession.Mode.ARCADE)
	var controls: TouchControls = main.get_node_or_null("TouchControls")
	_expect(controls != null, "arcade on a touchscreen must show touch controls")
	if controls == null:
		main.queue_free()
		await _frames(2)
		return
	var mode: SurvivalMode = main.get_node("Survival")
	var player := mode.player
	player.health.invulnerable_left = 999.0
	# Dormant until the first touch: a touch laptop played with the mouse keeps working.
	_expect(not controls.active, "touch controls active before any touch")
	_expect(_mouse_fires(), "mouse click must keep firing until the screen is touched")
	_expect(not player.aim_override.is_finite(), "mouse must keep aiming until the screen is touched")
	_expect(not controls.pause_button.visible, "pause button shown before any touch")

	# Left half: a floating move stick.
	_touch(controls, 0, Vector2(200, 500), true)
	_expect(controls.active and controls.pause_button.visible, "first touch did not wake the controls")
	_expect(not _mouse_fires(), "a touch must not also fire through the emulated mouse click")
	_expect(player.aim_override.is_finite(), "touch aim not taken over")
	_drag(controls, 0, Vector2(200 + TouchControls.STICK_RADIUS, 500))
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_expect(move.x > 0.9 and absf(move.y) < 0.1, "full right drag must move right, got %s" % move)
	_drag(controls, 0, Vector2(200, 500 - TouchControls.STICK_RADIUS * 3.0))
	move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_expect(move.y < -0.9 and move.length() <= 1.01, "drag past the edge must clamp, got %s" % move)
	var start := player.global_position
	await _frames(20)
	_expect(player.global_position.y < start.y - 10.0, "player did not move up with the stick")
	_touch(controls, 0, Vector2(200, 400), false)
	move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_expect(move == Vector2.ZERO, "releasing the move stick must stop, got %s" % move)

	# Right half: the aim stick aims and fires while held, at the same time as moving.
	_touch(controls, 0, Vector2(200, 500), true)
	_drag(controls, 0, Vector2(250, 500))
	_touch(controls, 1, Vector2(1000, 400), true)
	_drag(controls, 1, Vector2(1000, 400 + TouchControls.STICK_RADIUS))
	_expect(Input.is_action_pressed("shoot"), "holding the aim stick must fire")
	var aim := (player.aim_override - player.global_position).normalized()
	_expect(aim.dot(Vector2.DOWN) > 0.99, "aim stick pointing down must aim down, got %s" % aim)
	_expect(Input.get_vector("move_left", "move_right", "move_up", "move_down").x > 0.3, "aiming dropped the move stick")
	_touch(controls, 1, Vector2(1000, 500), false)
	_expect(not Input.is_action_pressed("shoot"), "releasing the aim stick must stop firing")
	_expect(player.aim_override.is_finite(), "aim must stay where it was, not jump to the mouse")
	_touch(controls, 0, Vector2(250, 500), false)

	# A tiny wobble inside the dead zone does nothing.
	_touch(controls, 1, Vector2(1000, 400), true)
	_drag(controls, 1, Vector2(1004, 400))
	_expect(not Input.is_action_pressed("shoot"), "a wobble inside the dead zone fired")
	_touch(controls, 1, Vector2(1004, 400), false)

	# Pausing lets go of everything, so nothing stays pressed on resume.
	_touch(controls, 0, Vector2(200, 500), true)
	_drag(controls, 0, Vector2(300, 500))
	controls.pause_button.pressed.emit()
	_expect(get_tree().paused, "pause button did not pause")
	_expect(Input.get_vector("move_left", "move_right", "move_up", "move_down") == Vector2.ZERO, "pause left the stick pressed")
	mode.get_node("PauseMenu").resume()

	# A real mouse (not one emulated from touches) hands control back to it.
	var emulated := InputEventMouseMotion.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	controls._input(emulated)
	_expect(controls.active, "emulated mouse motion from a touch put the controls to sleep")
	var real := InputEventMouseMotion.new()
	real.device = 0
	controls._input(real)
	_expect(not controls.active, "real mouse motion did not hand control back to the mouse")
	_expect(_mouse_fires(), "mouse click not restored after switching back to the mouse")
	_expect(not player.aim_override.is_finite(), "mouse aim not restored after switching back")
	_expect(not controls.pause_button.visible, "pause button kept after switching back to the mouse")

	main.queue_free()
	await _frames(2)
	_expect(InputMap.action_get_events("shoot").any(func(e: InputEvent) -> bool: return e is InputEventMouseButton),
		"mouse click not restored to shoot after leaving")
	GameSession.mode = GameSession.Mode.EXPERIMENT


func _mouse_fires() -> bool:
	return InputMap.action_get_events("shoot").any(func(e: InputEvent) -> bool: return e is InputEventMouseButton)


func _death_offers_restart() -> void:
	TouchControls.forced = true
	var main := await _start(GameSession.Mode.ARCADE)
	var controls: TouchControls = main.get_node("TouchControls")
	var mode: SurvivalMode = main.get_node("Survival")
	_expect(not controls.restart_button.visible, "restart shown while alive")
	_touch(controls, 1, Vector2(1000, 400), true)
	_drag(controls, 1, Vector2(1100, 400))
	mode.player.health.take_damage(10000.0)
	await _frames(50)
	_expect(not Input.is_action_pressed("shoot"), "still firing after death")
	_expect(controls.restart_button.visible, "no restart button at game over")
	_expect(not mode.hud.hint_label.text.contains("R para"), "touch game over still asks for the R key")
	_expect(not controls.pause_button.visible, "pause button kept at game over")
	main.queue_free()
	GameSession.mode = GameSession.Mode.EXPERIMENT
	await _frames(2)


func _rotate_hint_only_in_portrait() -> void:
	_expect(RotateHint.needed(Vector2(400, 800), true), "portrait phone must ask to rotate")
	_expect(not RotateHint.needed(Vector2(800, 400), true), "landscape phone asked to rotate")
	_expect(not RotateHint.needed(Vector2(400, 800), false), "portrait window without touch asked to rotate")


func _mouse_player_on_touch_device_keeps_r_hint() -> void:
	TouchControls.forced = true
	var main := await _start(GameSession.Mode.ARCADE)
	var controls: TouchControls = main.get_node("TouchControls")
	var mode: SurvivalMode = main.get_node("Survival")
	mode.player.health.take_damage(10000.0)
	await _frames(50)
	_expect(not controls.restart_button.visible, "restart button shown to a mouse player")
	_expect(mode.hud.hint_label.text.contains("R para"), "mouse player lost the R hint: %s" % mode.hud.hint_label.text)
	main.queue_free()
	GameSession.mode = GameSession.Mode.EXPERIMENT
	await _frames(2)

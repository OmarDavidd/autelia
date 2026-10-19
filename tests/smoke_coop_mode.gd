extends Node
## Co-op mode smoke test (stage 2a, offline): room and invite code, lobby with bots,
## arena sized by players, following camera, teammate markers and crowd scaling.
## The server address points at a closed local port, so Crear falls back to a local room.
## Run: godot --headless --path . tests/smoke_coop_mode.tscn

const PROFILE := "user://test_profile.cfg"
const NO_SERVER := "ws://127.0.0.1:9"

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## Waits until `condition` holds, up to `limit` frames; false if it never did.
func _until(condition: Callable, limit := 240) -> bool:
	for i in limit:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	GameSession.profile_path = PROFILE
	Leaderboard.enabled = false
	RoomClient.url_override = NO_SERVER
	GameSession.save_name("Ana")
	_room_and_codes()
	_rules_scale_with_players()
	await _arena_resizes()
	await _lobby_to_a_running_coop_game()
	await _join_reports_no_server()
	await _coop_without_a_room_and_team_wipe()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	GameSession.mode = GameSession.Mode.EXPERIMENT
	GameSession.coop_room = null
	RoomClient.url_override = ""

	get_tree().paused = false
	if failures.is_empty():
		print("SMOKE OK: co-op rooms, lobby, sized arena, following camera, markers and crowd scaling behave")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _room_and_codes() -> void:
	var room := CoopRoom.create("Ana")
	_expect(room.code.length() == CoopRoom.CODE_LENGTH, "code length: %s" % room.code)
	_expect(CoopRoom.is_valid_code(room.code), "generated code is not valid: %s" % room.code)
	for letter in room.code:
		_expect(letter in CoopRoom.CODE_LETTERS, "code uses an ambiguous letter: %s" % room.code)
	_expect(room.players.size() == 1 and room.players[0].name == "Ana" and room.players[0].host,
		"the creator must be the host: %s" % str(room.players))
	_expect(CoopRoom.is_valid_code("kxqp") and CoopRoom.clean_code(" kxqp ") == "KXQP", "codes are case-insensitive")
	_expect(not CoopRoom.is_valid_code("KXQ") and not CoopRoom.is_valid_code("KX0P"), "bad codes accepted")
	for i in CoopRoom.MAX_PLAYERS - 1:
		_expect(room.add_bot(), "bot %d refused" % (i + 1))
	_expect(room.players.size() == CoopRoom.MAX_PLAYERS and room.is_full(), "a room holds 8 players")
	_expect(not room.add_bot(), "a ninth player must be refused")
	_expect(room.players[1].bot and room.players[1].name == "Bot 1", "bot entry: %s" % str(room.players[1]))


func _rules_scale_with_players() -> void:
	_expect(CoopRules.arena_size(1) == Vector2(1280, 720), "one player keeps the classic arena")
	var last := CoopRules.arena_size(1)
	var last_crowd := CoopRules.crowd(1)
	_expect(is_equal_approx(last_crowd, 1.0), "one player keeps the classic crowd")
	for n in range(2, CoopRoom.MAX_PLAYERS + 1):
		_expect(CoopRules.arena_size(n).x > last.x and CoopRules.arena_size(n).y > last.y, "arena must grow with %d players" % n)
		_expect(CoopRules.crowd(n) > last_crowd, "crowd must grow with %d players" % n)
		last = CoopRules.arena_size(n)
		last_crowd = CoopRules.crowd(n)


func _arena_resizes() -> void:
	var arena := Arena.new()
	add_child(arena)
	await _frames(1)
	arena.resize(Vector2(2000, 1200))
	await _frames(1)
	_expect(arena.size == Vector2(2000, 1200), "arena size not applied")
	_expect(arena.get_children().filter(func(c: Node) -> bool: return c is StaticBody2D).size() == 1,
		"resizing must replace the walls, not add more")
	var walls: StaticBody2D = arena.get_node("Walls")
	var right := 0.0
	for shape: CollisionShape2D in walls.get_children():
		right = maxf(right, shape.position.x)
	_expect(right > 1900.0, "walls not moved to the new size, rightmost at %.0f" % right)
	arena.queue_free()


func _open_main() -> Node:
	MainMenu.seen = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	return main


func _lobby_to_a_running_coop_game() -> void:
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_modes()
	_expect(menu.coop_button.is_visible_in_tree(), "modes page does not offer Cooperativo")
	menu.show_coop()
	_expect(menu.coop_name_input.text == "Ana", "co-op page must reuse the remembered name")
	_expect(menu.create_room(), "creating a room failed")
	_expect(await _until(func() -> bool: return GameSession.coop_room != null), "no local room without a server")
	_expect(menu.lobby_code_label.text == "Sala local", "lobby must say the room is local: %s" % menu.lobby_code_label.text)
	var room: CoopRoom = GameSession.coop_room
	_expect(menu.lobby_rows.get_child_count() == 1, "lobby must list the host")
	_expect(menu.start_button.visible, "the host must be able to start")
	menu.add_bot_to_room()
	menu.add_bot_to_room()
	_expect(menu.lobby_rows.get_child_count() == 3, "lobby rows after two bots: %d" % menu.lobby_rows.get_child_count())

	menu.start_coop()
	await _frames(3)
	_expect(GameSession.mode == GameSession.Mode.COOP, "co-op mode not selected")
	var mode: SurvivalMode = main.get_node("Survival")
	_expect(mode.players.size() == 3, "three players must be in the run, got %d" % mode.players.size())
	_expect(mode.players[1].input is BotInput, "lobby bots must play as bots")
	_expect(mode.arena.size == CoopRules.arena_size(3), "arena not sized for three players: %s" % str(mode.arena.size))
	_expect(mode.player.global_position.distance_to(mode.arena.size / 2.0) < 80.0, "players must start in the middle of the bigger arena")
	_expect(is_equal_approx(mode.spawner.crowd, CoopRules.crowd(3)), "spawner crowd: %.2f" % mode.spawner.crowd)
	_expect(main.leaderboard == null, "co-op does not submit to the solo leaderboards")

	var camera: FollowCamera = main.camera
	_expect(camera != null and camera.is_current(), "co-op needs a camera that follows the player")
	_expect(camera.limit_right == int(mode.arena.size.x) and camera.limit_bottom == int(mode.arena.size.y),
		"camera limits must match the arena")
	mode.player.global_position = Vector2(300, 300)
	await _frames(30)
	# The screen center may stop short of the player at the arena edges (limits), so check the
	# camera itself follows and the visible area never leaves the arena.
	_expect(camera.global_position.distance_to(mode.player.global_position) < 1.0, "camera does not follow the player")
	var half := get_viewport().get_visible_rect().size / 2.0
	var shown := camera.get_screen_center_position()
	# Only along an axis where the arena is bigger than the view; a smaller one is centered.
	for axis in [Vector2.AXIS_X, Vector2.AXIS_Y]:
		if mode.arena.size[axis] >= half[axis] * 2.0:
			_expect(shown[axis] - half[axis] >= -1.0, "camera shows outside the arena on axis %d: %s" % [axis, str(shown)])

	var markers: TeammateMarkers = main.markers
	mode.players[1].global_position = mode.arena.size - Vector2(100, 100)
	mode.players[2].global_position = mode.player.global_position + Vector2(40, 0)
	await _frames(2)
	_expect(markers.offscreen_count() == 1, "one teammate is off screen, markers: %d" % markers.offscreen_count())
	main.queue_free()
	await _frames(2)


func _join_reports_no_server() -> void:
	GameSession.coop_room = null
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_coop()
	menu.coop_code_input.text = "KX"
	_expect(not menu.join_room(), "a short code joined")
	_expect(menu.coop_error.visible and menu.coop_error.text == "El código tiene 4 letras", "short code error: %s" % menu.coop_error.text)
	menu.coop_code_input.text = "kxqp"
	_expect(menu.join_room(), "a valid code must be sent to the server")
	_expect(await _until(func() -> bool: return menu.coop_error.visible), "no error without a server")
	_expect(GameSession.coop_room == null, "joining without a server must not open a room")
	_expect(menu.coop_error.text == "No se pudo conectar al servidor", "offline join error: %s" % menu.coop_error.text)
	main.queue_free()
	await _frames(2)


## A co-op start that somehow lost its room plays alone, and a full team wipe ends the run
## with the game-over panel (co-op has no leaderboard to submit to).
func _coop_without_a_room_and_team_wipe() -> void:
	GameSession.mode = GameSession.Mode.COOP
	GameSession.coop_room = null
	MainMenu.seen = true
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	var mode: SurvivalMode = main.get_node("Survival")
	_expect(GameSession.coop_room != null and mode.players.size() == 1, "co-op without a room must still start")
	GameSession.coop_room.add_bot()
	var mate := mode.add_player(BotInput.new())
	mate.take_hit(10000.0)
	mode.player.take_hit(10000.0)
	await _frames(50)
	_expect(mode.is_over(), "team wipe did not end the co-op run")
	_expect(mode.hud.game_over_panel.visible, "no game-over panel after a co-op wipe")
	_expect(mode.hud.board.status.text == "El cooperativo todavía no tiene tabla", "co-op board note: %s" % mode.hud.board.status.text)
	main.queue_free()
	MainMenu.seen = false
	await _frames(2)

extends Node
## Co-op lobby against the room server (stage 2b): the menu creates and joins rooms on a real
## server on localhost, the roster comes from the server, only the host adds bots and starts,
## the start takes every member into the run, a started room is joined straight into the run,
## server errors are shown and a lost server sends the lobby back.
## Run: godot --headless --path . tests/smoke_coop_online.tscn

const PROFILE := "user://test_profile.cfg"
const PORT := 18912

var failures: Array[String] = []
var server: RoomServer


func _ready() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Waits until `condition` holds, up to `limit` frames; false if it never did.
func _until(condition: Callable, limit := 240) -> bool:
	for i in limit:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


## Waits until the menu closes itself (it frees itself when a run starts).
func _closed(menu: MainMenu) -> bool:
	var ref: WeakRef = weakref(menu)
	return await _until(func() -> bool: return ref.get_ref() == null)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	GameSession.profile_path = PROFILE
	Leaderboard.enabled = false
	GameSession.save_name("Ana")
	server = RoomServer.new()
	add_child(server)
	_expect(server.start(PORT) == OK, "server did not start")
	RoomClient.url_override = "ws://127.0.0.1:%d" % PORT

	await _host_creates_and_starts()
	await _guest_waits_for_the_host()
	await _late_join_and_errors()
	_hostile_room_data()
	await _leave_and_create_again()
	await _lost_server()

	RoomClient.url_override = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	GameSession.mode = GameSession.Mode.EXPERIMENT
	GameSession.coop_room = null
	get_tree().paused = false
	if failures.is_empty():
		print("SMOKE OK: co-op lobby creates, joins, starts and recovers through the room server")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _open_main() -> Node:
	MainMenu.seen = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	return main


## Another machine: a client of its own, not the menu's shared one.
func _other(player_name: String, code := "") -> RoomClient:
	var client := RoomClient.new()
	add_child(client)
	if code.is_empty():
		client.create(player_name)
	else:
		client.join(code, player_name)
	await _until(func() -> bool: return client.room != null)
	_expect(client.room != null, "%s got no room" % player_name)
	return client


func _host_creates_and_starts() -> void:
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_coop()
	_expect(menu.create_room(), "create was refused")
	_expect(await _until(func() -> bool: return menu.lobby_rows.get_child_count() == 1), "lobby did not open")
	var code: String = GameSession.coop_room.code
	_expect(server.rooms.has(code), "the room must live on the server")
	_expect(menu.lobby_code_label.text == "Código: %s" % code, "lobby code: %s" % menu.lobby_code_label.text)
	_expect(menu.start_button.visible, "the host must see Empezar")

	var beto := await _other("Beto", code)
	_expect(await _until(func() -> bool: return menu.lobby_rows.get_child_count() == 2), "the host must see Beto join")
	menu.add_bot_to_room()
	_expect(await _until(func() -> bool: return menu.lobby_rows.get_child_count() == 3), "server bot not listed")
	_expect(server.rooms[code].players[2].bot, "the bot must be added on the server")

	var entries := [0]
	main.get_node("MainMenu").dismissed.connect(func() -> void: entries[0] += 1)
	# A double tap: two started rooms can reach the menu in the same frame.
	menu.start_coop()
	menu.start_coop()
	_expect(await _closed(menu), "the start must close the menu")
	_expect(entries[0] == 1, "the run must start once, started %d times" % entries[0])
	await _frames(3)
	_expect(GameSession.mode == GameSession.Mode.COOP, "co-op mode not selected")
	var mode: SurvivalMode = main.get_node("Survival")
	# Remote humans join the run in stage 2c; the arena already counts them.
	_expect(mode.arena.size == CoopRules.arena_size(3), "arena must count all three members: %s" % str(mode.arena.size))
	_expect(mode.players.size() == 2 and mode.players[1].input is BotInput, "local player and the bot must play")
	_expect(await _until(func() -> bool: return beto.room.started), "the guest must hear the start")
	beto.leave()
	RoomClient.shared(get_tree()).leave()
	main.queue_free()
	await _frames(10)
	_expect(server.rooms.is_empty(), "rooms left behind: %s" % str(server.rooms.keys()))


func _guest_waits_for_the_host() -> void:
	var host := await _other("Caro")
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_coop()
	menu.coop_code_input.text = host.room.code.to_lower()
	_expect(menu.join_room(), "join was refused")
	_expect(await _until(func() -> bool: return menu.lobby_rows.get_child_count() == 2), "guest lobby did not open")
	_expect(not menu.start_button.visible and not menu._add_bot_button.visible, "a guest must not see host buttons")
	_expect(menu.lobby_hint.text == "Esperando a que el anfitrión empiece.", "guest hint: %s" % menu.lobby_hint.text)
	var me: Label = menu.lobby_rows.get_child(1).get_child(1)
	_expect(me.text == "Ana · tú", "own row: %s" % me.text)

	host.start()
	_expect(await _closed(menu), "the host's start must take the guest in")
	await _frames(3)
	_expect(GameSession.mode == GameSession.Mode.COOP, "guest is not in co-op")
	host.leave()
	RoomClient.shared(get_tree()).leave()
	main.queue_free()
	await _frames(10)


func _late_join_and_errors() -> void:
	var host := await _other("Dani")
	host.start()
	await _until(func() -> bool: return host.room.started)
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_coop()

	menu.coop_code_input.text = "ZZZZ" if host.room.code != "ZZZZ" else "YYYY"
	menu.join_room()
	_expect(await _until(func() -> bool: return menu.coop_error.visible), "no error for an unknown code")
	_expect(menu.coop_error.text == "No existe una sala con ese código", "unknown code: %s" % menu.coop_error.text)

	menu.coop_code_input.text = host.room.code
	menu.join_room()
	_expect(await _closed(menu), "joining a started room must enter the run")
	await _frames(3)
	_expect(GameSession.coop_room.started and GameSession.coop_room.players.size() == 2, "late joiner room: %s" % str(GameSession.coop_room.to_dict()))
	host.leave()
	RoomClient.shared(get_tree()).leave()
	main.queue_free()
	await _frames(10)


## A broken or hostile server copy is refused or bounded, never trusted.
func _hostile_room_data() -> void:
	_expect(CoopRoom.from_dict({"code": "ABCD", "started": "true", "players": [{"id": 2, "name": "A", "host": "yes"}]}, 2) != null,
		"wrong-typed flags must not break parsing")
	var room := CoopRoom.from_dict({"code": "ABCD", "started": "true", "players": [{"id": 2, "name": "A", "host": "yes"}]}, 2)
	_expect(room != null and not room.started and not room.players[0].host, "only real booleans count")
	var many := []
	for i in 50:
		many.append({"id": i, "name": "x".repeat(500), "host": false, "bot": true})
	var big := CoopRoom.from_dict({"code": "ABCD", "players": many}, 1)
	_expect(big == null, "a roster over the player cap must be refused")
	var long_name := CoopRoom.from_dict({"code": "ABCD", "players": [{"id": 1, "name": "x".repeat(500), "host": true}]}, 1)
	_expect(long_name != null and long_name.players[0].name.length() == GameSession.NAME_MAX, "names must be cut to the limit")


## Leaving and creating again must not stack the menu's listeners on the shared client.
func _leave_and_create_again() -> void:
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_coop()
	menu.create_room()
	await _until(func() -> bool: return menu.lobby_rows.get_child_count() == 1)
	menu.leave_room()
	var client := RoomClient.shared(get_tree())
	_expect(client.room_changed.get_connections().is_empty(), "leaving must drop the menu's listeners")
	menu.create_room()
	_expect(await _until(func() -> bool: return menu.lobby_rows.get_child_count() == 1 and GameSession.coop_room != null),
		"creating again after leaving failed")
	_expect(client.room_changed.get_connections().size() == 1, "listeners stacked: %d" % client.room_changed.get_connections().size())
	client.leave()
	main.queue_free()
	await _frames(10)


func _lost_server() -> void:
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_coop()
	menu.create_room()
	_expect(await _until(func() -> bool: return menu.lobby_rows.get_child_count() == 1), "lobby did not open")
	server.stop()
	_expect(await _until(func() -> bool: return menu.coop_error.visible), "a lost server must be reported")
	_expect(menu.coop_error.text == "Se perdió la conexión con el servidor", "lost server: %s" % menu.coop_error.text)
	_expect(GameSession.coop_room == null, "the room must be dropped with the server")
	main.queue_free()
	await _frames(2)

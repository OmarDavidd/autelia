extends Node
## Co-op room server smoke test (stage 2b): create and join by code, the shared roster,
## host-only actions, joining a started run, the host role passing on, rooms closing,
## and malformed messages answered without breaking the server. Real sockets on localhost.
## Run: godot --headless --path . tests/smoke_room_server.tscn

const PORT := 18910

var failures: Array[String] = []
var server: RoomServer
var _clients: Array[WebSocketPeer] = []
## Socket → messages received so far (parsed).
var _inbox := {}


func _ready() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _process(_delta: float) -> void:
	for ws in _clients:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			_inbox[ws].append(JSON.parse_string(ws.get_packet().get_string_from_utf8()))


func _connect() -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % PORT)
	_clients.append(ws)
	_inbox[ws] = []
	for i in 120:
		await _frames(1)
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			break
	_expect(ws.get_ready_state() == WebSocketPeer.STATE_OPEN, "client could not connect")
	return ws


## Sends one message and waits for the next answer to that socket.
func _ask(ws: WebSocketPeer, message: Variant) -> Variant:
	var before: int = _inbox[ws].size()
	ws.send_text(message if message is String else JSON.stringify(message))
	return await _next(ws, before)


func _next(ws: WebSocketPeer, before: int) -> Variant:
	for i in 60:
		await _frames(1)
		if _inbox[ws].size() > before:
			return _inbox[ws][before]
	return null


func _last(ws: WebSocketPeer) -> Variant:
	return _inbox[ws].back() if not _inbox[ws].is_empty() else null


func _run() -> void:
	server = RoomServer.new()
	add_child(server)
	_expect(server.start(PORT) == OK, "server did not start")

	await _create_join_and_roster()
	await _bad_requests()
	await _full_room()

	server.stop()
	if failures.is_empty():
		print("SMOKE OK: room server creates, joins, starts, hands over and refuses bad messages")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _create_join_and_roster() -> void:
	var ana := await _connect()
	var created: Variant = await _ask(ana, {"t": "create", "name": "Ana"})
	_expect(created is Dictionary and created.t == "room", "create answer: %s" % str(created))
	var code: String = created.room.code
	_expect(CoopRoom.is_valid_code(code), "invalid room code: %s" % code)
	var room := CoopRoom.from_dict(created.room, int(created.you))
	_expect(room.players.size() == 1 and room.is_host(), "creator must be the only member and host")

	var beto := await _connect()
	var before: int = _inbox[ana].size()
	var joined: Variant = await _ask(beto, {"t": "join", "code": code.to_lower(), "name": " Beto "})
	_expect(joined is Dictionary and joined.t == "room", "join answer: %s" % str(joined))
	var as_beto := CoopRoom.from_dict(joined.room, int(joined.you))
	_expect(as_beto.players.size() == 2 and not as_beto.is_host(), "joiner must see two members and not be host")
	_expect(as_beto.players[1].name == "Beto", "names are trimmed: '%s'" % as_beto.players[1].name)
	var seen_by_ana: Variant = await _next(ana, before)
	_expect(seen_by_ana is Dictionary and seen_by_ana.room.players.size() == 2, "host must get the new roster")

	# Only the host adds bots and starts.
	before = _inbox[ana].size()
	beto.send_text(JSON.stringify({"t": "start"}))
	beto.send_text(JSON.stringify({"t": "add_bot"}))
	await _frames(10)
	_expect(_inbox[ana].size() == before, "a non-host changed the room")
	var with_bot: Variant = await _ask(ana, {"t": "add_bot"})
	_expect(with_bot.room.players.size() == 3 and with_bot.room.players[2].bot, "host add_bot: %s" % str(with_bot))
	var started: Variant = await _ask(ana, {"t": "start"})
	_expect(started.room.started == true, "start must mark the room started")
	await _frames(5)
	_expect(_last(beto).room.started == true, "every member must hear the start")

	# Joining is allowed mid-game.
	var caro := await _connect()
	var late: Variant = await _ask(caro, {"t": "join", "code": code, "name": "Caro"})
	_expect(late.t == "room" and late.room.started == true and late.room.players.size() == 4,
		"late join must enter the started room: %s" % str(late))

	# The host leaving hands the role to the next human; bots never host.
	before = _inbox[beto].size()
	ana.send_text(JSON.stringify({"t": "leave"}))
	var after_leave: Variant = await _next(beto, before)
	var handed := CoopRoom.from_dict(after_leave.room, int(after_leave.you))
	_expect(handed.players.size() == 3 and handed.is_host(), "Beto must become host: %s" % str(after_leave))

	# A dropped connection leaves the room too; the last human out closes it.
	before = _inbox[caro].size()
	beto.close()
	var after_drop: Variant = await _next(caro, before)
	_expect(after_drop != null and CoopRoom.from_dict(after_drop.room, int(after_drop.you)).is_host(),
		"Caro must be host after Beto drops: %s" % str(after_drop))
	caro.send_text(JSON.stringify({"t": "leave"}))
	await _frames(10)
	_expect(not server.rooms.has(code), "an empty room must close")
	var gone: Variant = await _ask(ana, {"t": "join", "code": code, "name": "Ana"})
	_expect(gone.t == "error" and gone.reason == "not_found", "joining a closed room: %s" % str(gone))
	ana.close()
	caro.close()
	await _frames(10)
	_expect(server.peer_count() == 0, "closed sockets must be forgotten, %d left" % server.peer_count())


func _bad_requests() -> void:
	var ws := await _connect()
	var cases := [
		["not json", "bad_request"],
		["[1, 2]", "bad_request"],
		[{"t": 7}, "bad_request"],
		[{"t": "fly"}, "bad_request"],
		[{"t": "create"}, "bad_name"],
		[{"t": "create", "name": "Al"}, "bad_name"],
		[{"t": "create", "name": "Ana\nBot"}, "bad_name"],
		[{"t": "create", "name": 12345}, "bad_name"],
		[{"t": "join", "code": "KX0P", "name": "Ana"}, "bad_code"],
		[{"t": "join", "code": ["KXQP"], "name": "Ana"}, "bad_code"],
		[{"t": "join", "code": "KXQP", "name": "Ana"}, "not_found"],
	]
	for each in cases:
		var answer: Variant = await _ask(ws, each[0])
		_expect(answer is Dictionary and answer.t == "error" and answer.reason == each[1],
			"%s → %s, expected %s" % [str(each[0]), str(answer), each[1]])
	var before: int = _inbox[ws].size()
	ws.send(PackedByteArray([1, 2, 3]))
	var binary: Variant = await _next(ws, before)
	_expect(binary is Dictionary and binary.reason == "bad_request", "binary message: %s" % str(binary))
	# Actions outside a room do nothing.
	before = _inbox[ws].size()
	for t in ["leave", "start", "add_bot"]:
		ws.send_text(JSON.stringify({"t": t}))
	await _frames(10)
	_expect(_inbox[ws].size() == before, "actions without a room must be ignored")

	# A message over the size bound costs that socket its connection, not the server.
	ws.send_text(JSON.stringify({"t": "create", "name": "x".repeat(RoomServer.MAX_MESSAGE * 2)}))
	await _frames(30)
	_expect(ws.get_ready_state() != WebSocketPeer.STATE_OPEN, "an oversized message must close the socket")
	var other := await _connect()
	var still: Variant = await _ask(other, {"t": "create", "name": "Dani"})
	_expect(still is Dictionary and still.t == "room", "server must keep serving after bad input")
	other.close()
	await _frames(10)


func _full_room() -> void:
	var host := await _connect()
	var created: Variant = await _ask(host, {"t": "create", "name": "Host"})
	var code: String = created.room.code
	for i in CoopRoom.MAX_PLAYERS - 2:
		await _ask(host, {"t": "add_bot"})
	var seventh := await _connect()
	var ok: Variant = await _ask(seventh, {"t": "join", "code": code, "name": "Siete"})
	_expect(ok.t == "room" and ok.room.players.size() == CoopRoom.MAX_PLAYERS, "eighth seat: %s" % str(ok))
	var extra := await _connect()
	var refused: Variant = await _ask(extra, {"t": "join", "code": code, "name": "Nueve"})
	_expect(refused.t == "error" and refused.reason == "full", "a ninth player must be refused: %s" % str(refused))
	var bot: Variant = await _ask(host, {"t": "add_bot"})
	_expect(bot == null, "a full room must not take another bot")
	for ws in [host, seventh, extra]:
		ws.close()
	await _frames(10)

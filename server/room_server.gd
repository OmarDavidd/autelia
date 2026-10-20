class_name RoomServer
extends Node
## The co-op game server: holds the rooms and tells every member who is in theirs.
## Plain WebSocket with one JSON object per message, so one process serves many rooms.
## It is reached from the internet through the tunnel, so every message is checked and
## anything malformed is answered with an error or dropped, never trusted.
##
## Client → server: {"t": "create", "name"} · {"t": "join", "code", "name"} · {"t": "leave"}
##                  {"t": "add_bot"} · {"t": "start"} (host only)
## Server → client: {"t": "room", "you", "room"} after every change · {"t": "error", "reason"}
##
## In a started room (stage 2c, the host simulates the run):
## guest → host:   {"t": "in", "q", "p": [x, y], "a": [x, y], "s"}, relayed with "from" added
## host → guests:  {"t": "snap", "d": {…}}, relayed as it came
## The server checks only a snapshot's envelope and passes it on as the host wrote it; the
## guests check its contents.

const DEFAULT_PORT := 8910
const MAX_PEERS := 256
const MAX_ROOMS := 128
## Bigger messages are refused by the socket itself. Lobby messages are tiny; the host's
## snapshot of a crowded wave is the largest one.
const MAX_MESSAGE := 32768
## Guests send their input about 30 times a second and the host 20 snapshots; anything
## beyond these is dropped.
const MAX_INPUTS_PER_SECOND := 45
const MAX_SNAPSHOTS_PER_SECOND := 30
## A connection that never finishes the WebSocket handshake is dropped after this.
const HANDSHAKE_SECONDS := 5.0

var _tcp := TCPServer.new()
## Connection id → {"ws": WebSocketPeer, "code": String, "since": float,
## "window": float, "inputs": int, "snapshots": int} (the last three count this second's relays).
var _peers := {}
## Invite code → CoopRoom.
var rooms := {}
var _next_id := 2
var _clock := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start(port := DEFAULT_PORT, bind_address := "127.0.0.1") -> Error:
	return _tcp.listen(port, bind_address)


func stop() -> void:
	for id in _peers.keys():
		_peers[id].ws.close()
	_peers.clear()
	rooms.clear()
	_tcp.stop()


func peer_count() -> int:
	return _peers.size()


func _process(delta: float) -> void:
	_clock += delta
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		if _peers.size() >= MAX_PEERS:
			stream.disconnect_from_host()
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = MAX_MESSAGE
		# Room for a few snapshots queued for a slow guest before they start being dropped.
		ws.outbound_buffer_size = MAX_MESSAGE * 8
		ws.accept_stream(stream)
		_peers[_next_id] = {"ws": ws, "code": "", "since": _clock, "window": _clock, "inputs": 0, "snapshots": 0}
		_next_id += 1
	for id: int in _peers.keys():
		_poll(id)


func _poll(id: int) -> void:
	var peer: Dictionary = _peers[id]
	var ws: WebSocketPeer = peer.ws
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if _clock - peer.since > HANDSHAKE_SECONDS:
				ws.close()
				_drop(id)
		WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0 and _peers.has(id):
				var packet := ws.get_packet()
				if ws.was_string_packet():
					var text := packet.get_string_from_utf8()
					_handle(id, _parse(text), text)
				else:
					_send(id, {"t": "error", "reason": "bad_request"})
		WebSocketPeer.STATE_CLOSED:
			_drop(id)


## JSON.parse_string logs every failure; strangers could fill the log with garbage.
func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


## `text` is the message as it arrived; a snapshot is passed on in it unchanged.
func _handle(id: int, message: Variant, text := "") -> void:
	if not message is Dictionary or not message.get("t") is String:
		_send(id, {"t": "error", "reason": "bad_request"})
		return
	var code: String = _peers[id].code
	match message.t:
		"create":
			_create(id, message.get("name"))
		"join":
			_join(id, message.get("code"), message.get("name"))
		"leave":
			_leave(id)
		"add_bot":
			if _is_host(id) and rooms[code].add_bot():
				_broadcast(code)
		"start":
			if _is_host(id):
				rooms[code].started = true
				_broadcast(code)
		# Game traffic is dropped quietly when it does not fit: a guest sends it many
		# times a second and an error for each would only add to the flood.
		"in":
			if _in_started_room(id) and not _is_host(id) and _valid_input(message) and _allow(id, "inputs"):
				message["from"] = id
				_send(rooms[code].host_id(), message)
		"snap":
			if _in_started_room(id) and _is_host(id) and _valid_snapshot(message) and _allow(id, "snapshots"):
				for entry in rooms[code].players:
					if not entry.bot and entry.id != id:
						_send_text(entry.id, text)
		_:
			_send(id, {"t": "error", "reason": "bad_request"})


func _create(id: int, player_name: Variant) -> void:
	if not _valid_name(player_name):
		_send(id, {"t": "error", "reason": "bad_name"})
		return
	# Leaving first lets a sole host re-create even when the server is at its room cap.
	_leave(id)
	if rooms.size() >= MAX_ROOMS:
		_send(id, {"t": "error", "reason": "busy"})
		return
	var code := CoopRoom.random_code()
	while rooms.has(code):
		code = CoopRoom.random_code()
	var room := CoopRoom.create(GameSession.clean_name(player_name), null, id)
	room.code = code
	rooms[code] = room
	_peers[id].code = code
	_broadcast(code)


func _join(id: int, raw_code: Variant, player_name: Variant) -> void:
	if not _valid_name(player_name):
		_send(id, {"t": "error", "reason": "bad_name"})
		return
	if not raw_code is String or not CoopRoom.is_valid_code(raw_code):
		_send(id, {"t": "error", "reason": "bad_code"})
		return
	var code := CoopRoom.clean_code(raw_code)
	if not rooms.has(code):
		_send(id, {"t": "error", "reason": "not_found"})
		return
	if _peers[id].code == code:
		_broadcast(code)
		return
	if rooms[code].is_full():
		_send(id, {"t": "error", "reason": "full"})
		return
	_leave(id)
	rooms[code].add_player(GameSession.clean_name(player_name), id)
	_peers[id].code = code
	_broadcast(code)


func _leave(id: int) -> void:
	var code: String = _peers[id].code
	if code.is_empty():
		return
	_peers[id].code = ""
	var room: CoopRoom = rooms[code]
	room.remove_player(id)
	if room.humans() == 0:
		rooms.erase(code)
	else:
		_broadcast(code)


func _drop(id: int) -> void:
	if _peers.has(id):
		_leave(id)
		_peers.erase(id)


func _in_started_room(id: int) -> bool:
	var code: String = _peers[id].code
	return not code.is_empty() and rooms[code].started


## A guest's input: a sequence number, its position and aim as two finite numbers each,
## and whether it shoots. Nothing else is relayed.
static func _valid_input(message: Dictionary) -> bool:
	if not _finite(message.get("q")) or not message.get("s") is bool:
		return false
	for key in ["p", "a"]:
		var pair: Variant = message.get(key)
		if not pair is Array or pair.size() != 2 or not _finite(pair[0]) or not _finite(pair[1]):
			return false
	for key: Variant in message.keys():
		if not key in ["t", "q", "p", "a", "s"]:
			return false
	return true


static func _valid_snapshot(message: Dictionary) -> bool:
	return message.get("d") is Dictionary and message.size() == 2


static func _finite(value: Variant) -> bool:
	return value is float and is_finite(value)


## Counts one relay of `kind` for this peer and says whether this second still has room.
func _allow(id: int, kind: String) -> bool:
	var peer: Dictionary = _peers[id]
	if _clock - peer.window >= 1.0:
		peer.window = _clock
		peer.inputs = 0
		peer.snapshots = 0
	var cap := MAX_INPUTS_PER_SECOND if kind == "inputs" else MAX_SNAPSHOTS_PER_SECOND
	if peer[kind] >= cap:
		return false
	peer[kind] += 1
	return true


func _is_host(id: int) -> bool:
	var code: String = _peers[id].code
	return not code.is_empty() and rooms[code].host_id() == id


## Names reach every member's screen, so anything that breaks a line, hides or reorders text
## is refused: a name could otherwise fake extra roster rows.
func _valid_name(value: Variant) -> bool:
	if not value is String or not GameSession.is_valid_name(value):
		return false
	for letter: String in value:
		if _hidden_or_breaking(letter.unicode_at(0)):
			return false
	return true


static func _hidden_or_breaking(c: int) -> bool:
	return c < 32 or (c >= 127 and c <= 159) \
		or (c >= 0x200B and c <= 0x200F) \
		or (c >= 0x2028 and c <= 0x202E) \
		or (c >= 0x2060 and c <= 0x206F) \
		or c == 0xFEFF or c == 0xFFFD


func _broadcast(code: String) -> void:
	var room: CoopRoom = rooms[code]
	var data := room.to_dict()
	for entry in room.players:
		if not entry.bot:
			_send(entry.id, {"t": "room", "you": entry.id, "room": data})


func _send(id: int, message: Dictionary) -> void:
	_send_text(id, JSON.stringify(message))


## A guest that stops reading fills its outbound buffer; what does not fit is dropped here
## quietly (the socket would log an error for every message).
func _send_text(id: int, text: String) -> void:
	var ws: WebSocketPeer = _peers[id].ws
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if ws.get_current_outbound_buffered_amount() + text.to_utf8_buffer().size() > ws.outbound_buffer_size:
		return
	ws.send_text(text)

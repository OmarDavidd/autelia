class_name RoomClient
extends Node
## This machine's link to the co-op room server (server/room_server.gd).
## Lives under the tree root, so it survives the menu closing and the scene reloading.
## Every answer from the server ends in `room_changed` or `failed`; a lost connection
## ends in `disconnected`. The server's copy is checked before it is used.

signal room_changed(room: CoopRoom)
## "unreachable" when the server cannot be reached, otherwise the server's reason
## (not_found, full, bad_name, bad_code, busy, bad_request).
signal failed(reason: String)
signal disconnected
## In a started room (stage 2c). The host gets its guests' inputs, with "from" set by the
## server; the guests get the host's snapshots.
signal input_received(message: Dictionary)
signal snapshot_received(data: Dictionary)

const DEFAULT_URL := "wss://juego.omard.space"
const CONNECT_SECONDS := 6.0

## Tests point this at a local server; `--server=ws://…` does the same in development.
static var url_override := ""

var room: CoopRoom
var _ws: WebSocketPeer
var _pending: Array[Dictionary] = []
var _waited := 0.0
var _was_open := false
## Leaving: the socket keeps being polled until the goodbye is out, but says nothing more.
var _closing: WebSocketPeer


## The one client of this launch, created on first use.
static func shared(tree: SceneTree) -> RoomClient:
	var existing := tree.root.get_node_or_null("RoomClient")
	if existing:
		return existing
	var client := RoomClient.new()
	client.name = "RoomClient"
	tree.root.add_child(client)
	return client


static func server_url() -> String:
	if not url_override.is_empty():
		return url_override
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			return arg.get_slice("=", 1)
	return DEFAULT_URL


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func create(player_name: String) -> void:
	_request({"t": "create", "name": player_name})


func join(code: String, player_name: String) -> void:
	_request({"t": "join", "code": code, "name": player_name})


func add_bot() -> void:
	_request({"t": "add_bot"})


func start() -> void:
	_request({"t": "start"})


## Game traffic is sent only while connected and never queued: a late input or snapshot is
## worth less than the next one.
func send_input(seq: int, at: Vector2, aim: Vector2, shoot: bool) -> void:
	if is_connected_to_server():
		_ws.send_text(JSON.stringify({"t": "in", "q": seq, "p": [at.x, at.y], "a": [aim.x, aim.y], "s": shoot}))


func send_snapshot(data: Dictionary) -> void:
	if is_connected_to_server():
		_ws.send_text(JSON.stringify({"t": "snap", "d": data}))


func leave() -> void:
	if is_connected_to_server():
		_ws.send_text(JSON.stringify({"t": "leave"}))
		_closing = _ws
		_ws = null
	_close()


func is_connected_to_server() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func _request(message: Dictionary) -> void:
	if _ws == null:
		_ws = WebSocketPeer.new()
		_waited = 0.0
		_was_open = false
		if _ws.connect_to_url(server_url()) != OK:
			_ws = null
			failed.emit("unreachable")
			return
	_pending.append(message)
	_flush()


func _flush() -> void:
	if not is_connected_to_server():
		return
	for message in _pending:
		_ws.send_text(JSON.stringify(message))
	_pending.clear()


func _process(delta: float) -> void:
	if _closing:
		_closing.poll()
		if _closing.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_closing.close()
		elif _closing.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_closing = null
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_waited += delta
			if _waited > CONNECT_SECONDS:
				_close()
				failed.emit("unreachable")
		WebSocketPeer.STATE_OPEN:
			_was_open = true
			_flush()
			while _ws and _ws.get_available_packet_count() > 0:
				_receive(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var was_open := _was_open
			_close()
			if was_open:
				disconnected.emit()
			else:
				failed.emit("unreachable")


func _receive(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return
	var message: Dictionary = json.data
	match message.get("t"):
		"room":
			var you: Variant = message.get("you")
			var copy := CoopRoom.from_dict(message.get("room"), int(you) if you is float else 0)
			if copy:
				room = copy
				room_changed.emit(room)
		"error":
			failed.emit(str(message.get("reason", "bad_request")))
		"in":
			if message.get("from") is float:
				input_received.emit(message)
		"snap":
			if message.get("d") is Dictionary:
				snapshot_received.emit(message.d)


func _close() -> void:
	if _ws:
		_ws.close()
	_ws = null
	_pending.clear()
	room = null

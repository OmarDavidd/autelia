extends Node
## Co-op network play (stage 2c), host side: the host's run takes the room's guests in as
## players driven by their relayed input and sends snapshots of the run to the guests.
## The guest is a raw socket here, so the host's tree holds only the host's run.
## Run: godot --headless --path . tests/smoke_coop_net.tscn

const PROFILE := "user://test_profile_net.cfg"
const PORT := 18914

var failures: Array[String] = []
var server: RoomServer
var guest: WebSocketPeer
## Every message the raw guest received, parsed.
var guest_inbox: Array = []
## Other raw members; their messages are read and dropped.
var others: Array[WebSocketPeer] = []


func _ready() -> void:
	_run.call_deferred()


func _process(_delta: float) -> void:
	for other in others:
		other.poll()
		while other.get_available_packet_count() > 0:
			other.get_packet()
	if guest == null:
		return
	guest.poll()
	while guest.get_available_packet_count() > 0:
		guest_inbox.append(JSON.parse_string(guest.get_packet().get_string_from_utf8()))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _physics(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _until(condition: Callable, limit := 600) -> bool:
	for i in limit:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _seconds(value: float) -> void:
	await get_tree().create_timer(value).timeout


func _snapshots() -> Array:
	return guest_inbox.filter(func(m: Variant) -> bool: return m is Dictionary and m.get("t") == "snap")


func _send_input(seq: int, at: Vector2, aim: Vector2, shoot: bool) -> void:
	guest.send_text(JSON.stringify({"t": "in", "q": seq, "p": [at.x, at.y], "a": [aim.x, aim.y], "s": shoot}))


func _run() -> void:
	GameSession.profile_path = PROFILE
	Leaderboard.enabled = false
	server = RoomServer.new()
	add_child(server)
	_expect(server.start(PORT) == OK, "server did not start")
	RoomClient.url_override = "ws://127.0.0.1:%d" % PORT

	await _host_runs_the_guest()
	_snapshots_fit_the_server()

	RoomClient.url_override = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	GameSession.mode = GameSession.Mode.EXPERIMENT
	GameSession.coop_room = null
	MainMenu.seen = false
	server.stop()
	if failures.is_empty():
		print("SMOKE OK: the host runs its guests from their input and sends them snapshots")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _host_runs_the_guest() -> void:
	var client := RoomClient.shared(get_tree())
	client.create("Ana")
	_expect(await _until(func() -> bool: return client.room != null), "host could not create a room")
	var code := client.room.code

	guest = WebSocketPeer.new()
	guest.connect_to_url(RoomClient.server_url())
	_expect(await _until(func() -> bool: return guest.get_ready_state() == WebSocketPeer.STATE_OPEN), "guest could not connect")
	guest.send_text(JSON.stringify({"t": "join", "code": code, "name": "Beto"}))
	_expect(await _until(func() -> bool: return client.room.players.size() == 2), "host never saw the guest")
	var beto_id: int = client.room.players[1].id
	client.start()
	_expect(await _until(func() -> bool: return client.room.started), "room never started")

	GameSession.mode = GameSession.Mode.COOP
	GameSession.coop_room = client.room
	MainMenu.seen = true
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _physics(2)
	var survival: SurvivalMode = main.survival
	_expect(main.get_node_or_null("CoopHost") != null, "an online host must run a CoopHost")
	_expect(survival.players.size() == 2, "the guest must play in the host's run, players: %d" % survival.players.size())
	if survival.players.size() < 2:
		main.queue_free()
		return
	var remote: Player = survival.players[1]
	_expect(not remote.input.is_local(), "the guest's player is not this machine's")
	_expect(remote.color == Palette.PLAYER_COLORS[1], "the guest gets the second color")

	# The guest's reported position moves its player on the host.
	var target := remote.global_position + Vector2(120, 0)
	_send_input(1, target, Vector2.UP, false)
	await _physics(40)
	_expect(remote.global_position.distance_to(target) < 2.0, "guest player should reach %s, is at %s" % [target, remote.global_position])
	_expect(remote.body.rotation == Vector2.UP.angle(), "the guest's aim must turn its player: %f" % remote.body.rotation)

	# Never faster than its speed allows, whatever the guest reports.
	var before := remote.global_position
	_send_input(2, before + Vector2(0, 300), Vector2.UP, false)
	var per_frame := remote.speed * NetworkInput.SPEED_SLACK / Engine.physics_ticks_per_second
	var steps := []
	for i in 120:
		await get_tree().physics_frame
		var moved := remote.global_position.distance_to(before)
		if moved > 0.0:
			steps.append(moved)
			if steps.size() == 4:
				break
	_expect(steps.size() == 4, "the far report never moved the guest player")
	for i in steps.size():
		_expect(steps[i] <= per_frame * (i + 1) + 0.5,
			"a far report must not teleport: %f px after %d frames, limit %f" % [steps[i], i + 1, per_frame * (i + 1)])

	# An older input arriving late changes nothing.
	var far := before + Vector2(0, 300)
	_expect(await _until(func() -> bool: return remote.global_position.distance_to(far) < 2.0, 600), "guest player never reached the far report")
	var settled := remote.global_position
	_send_input(1, target, Vector2.UP, false)
	await _physics(20)
	_expect(remote.global_position.distance_to(far) < 1.0, "a stale input moved the player from %s to %s" % [far, remote.global_position])

	# Shooting comes from the guest too.
	_send_input(3, settled, Vector2.RIGHT, true)
	var fired := await _until(func() -> bool:
		return survival.get_children().any(func(n: Node) -> bool: return n is Bullet and n.source == remote), 240)
	_expect(fired, "the guest's shot must fire on the host")
	# A guest that goes quiet stops shooting instead of firing forever.
	await _seconds(NetworkInput.QUIET_SECONDS + 0.2)
	var shots_before := survival.get_children().filter(func(n: Node) -> bool: return n is Bullet and n.source == remote).size()
	await _seconds(0.3)
	var shots_after := survival.get_children().filter(func(n: Node) -> bool: return n is Bullet and n.source == remote).size()
	_expect(shots_after <= shots_before and not remote.input.wants_to_shoot(remote), "a quiet guest must stop shooting")
	_send_input(4, settled, Vector2.RIGHT, false)

	# Snapshots reach the guest about 20 times a second, with both players.
	var counted := _snapshots().size()
	await _seconds(1.0)
	var per_second := _snapshots().size() - counted
	_expect(per_second >= 14 and per_second <= 26, "about 20 snapshots a second, got %d" % per_second)
	var last: Dictionary = _snapshots().back().d if not _snapshots().is_empty() else {}
	var rows: Array = last.get("pl", [])
	_expect(rows.size() == 2, "the snapshot lists both players: %s" % str(rows))
	var guest_row: Variant = null
	for row: Array in rows:
		if int(row[NetSnapshot.P_ID]) == beto_id:
			guest_row = row
	_expect(guest_row != null, "the guest finds its own row by id")
	if guest_row != null:
		var shown := Vector2(guest_row[NetSnapshot.P_X], guest_row[NetSnapshot.P_Y])
		_expect(shown.distance_to(remote.global_position) < 20.0, "the snapshot shows where the guest is: %s" % shown)
		_expect(int(guest_row[NetSnapshot.P_SLOT]) == 1, "the guest's slot picks its color")

	# Enemies the host spawns appear in the snapshots.
	var spawned := await _until(func() -> bool:
		return survival.enemies.get_children().any(func(n: Node) -> bool: return n is Enemy), 600)
	_expect(spawned, "the host's run must spawn enemies")
	await _seconds(0.2)
	var enemies: Array = _snapshots().back().d.get("en", [])
	_expect(enemies.any(func(row: Array) -> bool: return int(row[NetSnapshot.E_KIND]) != NetSnapshot.KIND_MARKER),
		"the snapshot lists the enemies: %s" % str(enemies))
	_expect(int(_snapshots().back().d.get("w", 0)) == survival.spawner.wave, "the snapshot carries the wave")

	# A late joiner appears next to a living teammate, protected for a moment (S21).
	var caro := WebSocketPeer.new()
	caro.connect_to_url(RoomClient.server_url())
	others.append(caro)
	_expect(await _until(func() -> bool: return caro.get_ready_state() == WebSocketPeer.STATE_OPEN), "Caro could not connect")
	caro.send_text(JSON.stringify({"t": "join", "code": code, "name": "Caro"}))
	_expect(await _until(func() -> bool: return survival.players.size() == 3, 240), "a late joiner must enter the running game")
	if survival.players.size() == 3:
		var newcomer: Player = survival.players[2]
		var nearest := INF
		for mate in survival.players:
			if mate != newcomer and not mate.health.is_dead():
				nearest = minf(nearest, mate.global_position.distance_to(newcomer.global_position))
		_expect(nearest <= CoopHost.JOIN_DISTANCE + 1.0, "the late joiner appears next to a teammate, %f px away" % nearest)
		_expect(newcomer.health.is_invulnerable(), "the late joiner is protected on arrival")
		_expect(newcomer.color == Palette.PLAYER_COLORS[2], "the late joiner takes the next color")

		# Beto leaves: his player goes and Caro keeps her color.
		guest.send_text(JSON.stringify({"t": "leave"}))
		_expect(await _until(func() -> bool: return survival.players.size() == 2, 240), "a guest who leaves must leave the run")
		_expect(not is_instance_valid(remote) or remote.is_queued_for_deletion(), "the leaver's player is removed")
		# Beto no longer gets snapshots, so the host's own view is checked.
		var host_side: CoopHost = main.get_node("CoopHost")
		_expect(host_side.slots == [0, 2], "colors stay with their players after someone leaves: %s" % str(host_side.slots))
		_expect(newcomer.color == Palette.PLAYER_COLORS[2], "Caro keeps her color")

	# Online, opening the pause menu does not stop the run for everyone.
	var pause: PauseMenu = survival.get_node("PauseMenu")
	pause.open()
	_expect(not get_tree().paused and pause.visible, "an online pause menu must not pause the game")
	pause.resume()

	# Leaving the run leaves the room.
	var ana_id := client.room.you
	main.queue_free()
	_expect(await _until(func() -> bool: return client.room == null and server.rooms.has(code) \
		and not server.rooms[code].players.any(func(p: Dictionary) -> bool: return p.id == ana_id), 240),
		"leaving the run must leave the room")
	MainMenu.seen = true
	client.leave()
	guest.close()
	caro.close()
	await _physics(5)


## The server closes any socket that sends more than its bound, so the host trims the
## least important rows (bullets, then enemies) rather than lose its connection.
func _snapshots_fit_the_server() -> void:
	var data := {"k": 1, "w": 3, "pl": [[0, 1, 1.0, 2.0, 0.0, 100, false, false]], "en": [], "bu": []}
	for i in 900:
		data.bu.append([i, 1234.5, 678.9, 1.57, false])
		data.en.append([i, 0, 1234.5, 678.9, 1.57, false])
	var fitted := NetSnapshot.fit(data, RoomServer.MAX_MESSAGE)
	var size := JSON.stringify({"t": "snap", "d": fitted}).to_utf8_buffer().size()
	_expect(size <= RoomServer.MAX_MESSAGE, "a crowded snapshot must fit the server bound: %d bytes" % size)
	_expect(fitted.pl.size() == 1 and fitted.w == 3, "trimming keeps players and the wave")
	_expect(fitted.en.size() > 0, "enemies are kept while bullets can go")
	var small := {"k": 2, "pl": [], "en": [[1, 0, 1.0, 1.0, 0.0, false]], "bu": [[1, 1.0, 1.0, 0.0, false]]}
	_expect(NetSnapshot.fit(small, RoomServer.MAX_MESSAGE) == small, "a snapshot that fits is sent whole")

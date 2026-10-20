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


func _ready() -> void:
	_run.call_deferred()


func _process(_delta: float) -> void:
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

	main.queue_free()
	client.leave()
	guest.close()
	await _physics(5)

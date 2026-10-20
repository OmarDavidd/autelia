extends Node
## Co-op network play (stage 2c), guest side: the guest's run simulates nothing; it shows
## the host's snapshots (teammates, enemies, markers, bullets, health, wave, score, kills),
## sends its own player's position, aim and trigger, and drops snapshots it cannot trust.
## The host is a raw socket here, so the guest's tree holds only the guest's run.
## Run: godot --headless --path . tests/smoke_coop_guest.tscn

const PROFILE := "user://test_profile_guest.cfg"
const PORT := 18916

var failures: Array[String] = []
var server: RoomServer
var host: WebSocketPeer
var host_inbox: Array = []
## A second guest for the host migration; polled here, its messages kept.
var dani: WebSocketPeer
var dani_inbox: Array = []
var _tick := 0


func _ready() -> void:
	_run.call_deferred()


func _process(_delta: float) -> void:
	if dani:
		dani.poll()
		while dani.get_available_packet_count() > 0:
			dani_inbox.append(JSON.parse_string(dani.get_packet().get_string_from_utf8()))
	if host == null:
		return
	host.poll()
	while host.get_available_packet_count() > 0:
		host_inbox.append(JSON.parse_string(host.get_packet().get_string_from_utf8()))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _until(condition: Callable, limit := 600) -> bool:
	for i in limit:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _seconds(value: float) -> void:
	await get_tree().create_timer(value).timeout


func _inputs() -> Array:
	return host_inbox.filter(func(m: Variant) -> bool: return m is Dictionary and m.get("t") == "in")


## One snapshot from the fake host, with the next tick; `extra` overrides fields.
func _snap(players: Array, enemies := [], bullets := [], events := [], extra := {}) -> void:
	# Ticks follow real time, 20 a second, as a host's do.
	_tick = maxi(_tick + 1, Time.get_ticks_msec() / 50)
	var data := {"k": _tick, "w": 1, "br": false, "tl": 25.0, "sc": 0, "pl": players, "en": enemies, "bu": bullets, "ev": events}
	data.merge(extra, true)
	host.send_text(JSON.stringify({"t": "snap", "d": data}))


## Sends the same snapshot content every 50 ms for `seconds`, like a host would.
func _stream(seconds: float, players: Array, enemies := [], bullets := [], extra := {}) -> void:
	var steps := ceili(seconds * 20.0)
	for i in steps:
		_snap(players, enemies, bullets, [], extra)
		await _seconds(0.05)


func _run() -> void:
	GameSession.profile_path = PROFILE
	Leaderboard.enabled = false
	server = RoomServer.new()
	add_child(server)
	_expect(server.start(PORT) == OK, "server did not start")
	RoomClient.url_override = "ws://127.0.0.1:%d" % PORT

	await _guest_shows_the_host_run()

	RoomClient.url_override = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	GameSession.mode = GameSession.Mode.EXPERIMENT
	GameSession.coop_room = null
	MainMenu.seen = false
	server.stop()
	if failures.is_empty():
		print("SMOKE OK: the guest shows the host's run and sends its own player")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _guest_shows_the_host_run() -> void:
	host = WebSocketPeer.new()
	host.connect_to_url(RoomClient.server_url())
	_expect(await _until(func() -> bool: return host.get_ready_state() == WebSocketPeer.STATE_OPEN), "host could not connect")
	host.send_text(JSON.stringify({"t": "create", "name": "Ana"}))
	_expect(await _until(func() -> bool: return not host_inbox.is_empty()), "no room for the host")
	var code: String = host_inbox.back().room.code
	var host_id := int(host_inbox.back().you)

	var client := RoomClient.shared(get_tree())
	client.join(code, "Beto")
	_expect(await _until(func() -> bool: return client.room != null), "guest could not join")
	var you := client.room.you
	host.send_text(JSON.stringify({"t": "start"}))
	_expect(await _until(func() -> bool: return client.room.started), "room never started")

	GameSession.mode = GameSession.Mode.COOP
	GameSession.coop_room = client.room
	MainMenu.seen = true
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().physics_frame
	var survival: SurvivalMode = main.survival
	_expect(main.get_node_or_null("CoopGuest") != null, "an online guest must run a CoopGuest")
	_expect(main.get_node_or_null("CoopHost") == null, "a guest must not host")
	var me := survival.player

	# Nothing spawns on its own: the first break passes with no enemies of the guest's own.
	await _seconds(survival.spawner.first_break + survival.spawner.telegraph_time + 0.4)
	_expect(survival.enemies.get_child_count() == 0, "a guest must not spawn enemies")

	# The host's run appears: teammate, enemies, a marker and a bullet.
	var ana_row := [0, host_id, 300.0, 300.0, 0.0, 100.0, false, false]
	var beto_row := [1, you, 500.0, 400.0, 0.0, 100.0, false, false]
	var chaser := [7, NetSnapshot.KIND_CHASER, 700.0, 300.0, 3.14, false]
	var shooter := [8, NetSnapshot.KIND_SHOOTER, 800.0, 500.0, 1.57, false]
	var marker := [9, NetSnapshot.KIND_MARKER, 900.0, 600.0, 0.5, false]
	var bullet := [20, 320.0, 300.0, 0.0, false]
	await _stream(0.4, [ana_row, beto_row], [chaser, shooter, marker], [bullet])
	_expect(survival.players.size() == 2, "the guest sees the host as a teammate: %d players" % survival.players.size())
	var ana: Player = survival.players[1] if survival.players.size() > 1 else null
	if ana:
		_expect(ana.global_position.distance_to(Vector2(300, 300)) < 1.0, "teammate at the host's position: %s" % ana.global_position)
		_expect(ana.color == Palette.PLAYER_COLORS[0], "the teammate keeps the host's color")
		_expect(not ana.input.is_local(), "a teammate is not this machine's player")
	_expect(me.global_position.distance_to(Vector2(500, 400)) < 1.0, "the guest starts where the host put it: %s" % me.global_position)
	var shown := survival.enemies.get_children()
	_expect(shown.filter(func(n: Node) -> bool: return n is Chaser).size() == 1, "one chaser shown")
	_expect(shown.filter(func(n: Node) -> bool: return n is Shooter).size() == 1, "one shooter shown")
	_expect(shown.filter(func(n: Node) -> bool: return n is SpawnMarker).size() == 1, "one spawn marker shown")
	var puppets := survival.get_children().filter(func(n: Node) -> bool: return n is Bullet)
	_expect(puppets.size() == 1 and puppets[0].global_position.distance_to(Vector2(320, 300)) < 1.0, "the host's bullet is shown")

	# Puppets never act: the chaser stands still next to nobody and hurts no one.
	var still: Node2D = shown.filter(func(n: Node) -> bool: return n is Chaser)[0]
	await _seconds(0.3)
	_expect(still.global_position.distance_to(Vector2(700, 300)) < 1.0, "a puppet enemy must not move on its own")

	# Movement is drawn between snapshots: halfway, the chaser is between both points.
	_snap([ana_row, beto_row], [[7, 0, 700.0, 300.0, 3.14, false]])
	await _seconds(0.05)
	_snap([ana_row, beto_row], [[7, 0, 900.0, 300.0, 3.14, false]])
	var between := false
	var until := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		if still.global_position.x > 705.0 and still.global_position.x < 895.0:
			between = true
	_expect(between, "the chaser must glide between snapshots, not jump")
	await _stream(0.3, [ana_row, beto_row], [[7, 0, 900.0, 300.0, 3.14, false]])
	_expect(survival.enemies.get_children().filter(func(n: Node) -> bool: return n is SpawnMarker).is_empty(),
		"what the host no longer lists goes away")

	# The guest's own player moves here and is reported; its trigger goes to the host.
	host_inbox.clear()
	Input.action_press("move_right")
	await _seconds(0.3)
	Input.action_release("move_right")
	_expect(me.global_position.x > 520.0, "the guest's player moves at once on its screen: %s" % me.global_position)
	var inputs := _inputs()
	_expect(inputs.size() >= 6 and inputs.size() <= 12, "about 30 inputs a second, got %d in 0.3 s" % inputs.size())
	if not inputs.is_empty():
		var last: Dictionary = inputs.back()
		_expect(Vector2(last.p[0], last.p[1]).distance_to(me.global_position) < 20.0, "the input reports where the player is")
		_expect(last.s == false, "not shooting yet")
	var own_bullets := survival.get_children().filter(func(n: Node) -> bool: return n is Bullet and n.source == me).size()
	Input.action_press("shoot")
	await _seconds(0.2)
	_expect(_inputs().back().s == true, "holding fire must reach the host")
	_expect(survival.get_children().filter(func(n: Node) -> bool: return n is Bullet and n.source == me).size() == own_bullets,
		"the guest's shots are fired by the host, not here")
	Input.action_release("shoot")

	# Health, hits, kills, wave and score come from the host.
	var hurt := [0]
	Events.player_damaged.connect(func(_a: float, _l: float) -> void: hurt[0] += 1)
	var kills := [0]
	Events.enemy_killed.connect(func(_e: Node) -> void: kills[0] += 1)
	var at := me.global_position
	beto_row = [1, you, at.x, at.y, 0.0, 60.0, false, false]
	_snap([ana_row, beto_row], [[7, 0, 900.0, 300.0, 3.14, false]], [], [["h", 7]], {"w": 2, "sc": 150})
	await _seconds(0.1)
	_expect(me.health.current == 60.0, "the guest's health follows the host: %f" % me.health.current)
	_expect(hurt[0] == 1, "a hit from the host plays the hurt sound once, got %d" % hurt[0])
	_expect(survival.spawner.wave == 2, "the wave follows the host")
	var keeper := survival.get_node_or_null("Score") as ScoreKeeper
	_expect(keeper != null and keeper.score == 150, "the score follows the host")
	# A steady stream first, so the drawing runs its usual 100 ms behind the newest snapshot.
	await _stream(0.4, [ana_row, beto_row], [[7, 0, 900.0, 300.0, 3.14, false]], [], {"w": 2, "sc": 150})
	_snap([ana_row, beto_row], [], [], [["k", 7, 900.0, 300.0, 0]], {"w": 2, "sc": 160})
	_expect(await _until(func() -> bool: return kills[0] > 0, 240), "the kill never arrived")
	# The snapshot being drawn is still older than the kill and lists the chaser.
	var drawn_again := false
	var watch_until := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < watch_until:
		await get_tree().process_frame
		if survival.enemies.get_children().any(func(n: Node) -> bool: return n is Enemy and not n.is_queued_for_deletion()):
			drawn_again = true
	_expect(kills[0] == 1, "a kill on the host counts here once")
	_expect(not drawn_again, "a killed enemy must not be drawn again from an older snapshot")

	beto_row = [1, you, at.x, at.y, 0.0, 0.0, true, false]
	_snap([ana_row, beto_row], [], [], [], {"w": 2})
	await _seconds(0.1)
	_expect(me.health.is_dead(), "the host's down is the guest's down")
	beto_row = [1, you, at.x, at.y, 0.0, 50.0, false, true]
	_snap([ana_row, beto_row], [], [], [], {"w": 3})
	await _seconds(0.1)
	_expect(not me.health.is_dead() and me.health.current == 50.0, "revived with the host's health")

	# Snapshots that are not what a host sends are dropped whole.
	var before := survival.players.size()
	for bad in [
		{"k": 999, "w": 1, "br": false, "tl": 1.0, "sc": 0, "pl": [[3, 0, "x", 1.0, 0.0, 1.0, false, false]], "en": [], "bu": [], "ev": []},
		{"k": 999, "w": 1, "br": false, "tl": 1.0, "sc": 0, "pl": [[9, 0, 1.0, 1.0, 0.0, 1.0, false, false]], "en": [], "bu": [], "ev": []},
		{"k": 999, "w": 1, "br": false, "tl": 1.0, "sc": 0, "pl": [], "en": [[1, 0, 1.0]], "bu": [], "ev": []},
		{"k": 999, "w": 1, "br": false, "tl": 1.0, "sc": 0, "pl": [], "en": [], "bu": [], "ev": [["k", 1]]},
		{"k": 999, "w": "1", "br": false, "tl": 1.0, "sc": 0, "pl": [], "en": [], "bu": [], "ev": []},
	]:
		host.send_text(JSON.stringify({"t": "snap", "d": bad}))
	host.send_text('{"t":"snap","d":{"k":999,"w":1,"br":false,"tl":1e999,"sc":0,"pl":[],"en":[],"bu":[],"ev":[]}}')
	await _seconds(0.2)
	_expect(survival.players.size() == before, "a bad snapshot must change nothing")
	_expect(not me.health.is_dead() and survival.spawner.wave == 3, "a bad snapshot must not reach the run")

	# A teammate the host no longer lists has left the run.
	var ana_puppet: Player = survival.players[1] if survival.players.size() > 1 else null
	await _stream(0.3, [beto_row], [], [], {"w": 3})
	_expect(survival.players.size() == 1, "a teammate who left must go: %d players" % survival.players.size())
	_expect(ana_puppet == null or not is_instance_valid(ana_puppet) or ana_puppet.is_queued_for_deletion(), "the puppet is removed")

	# The host leaves mid-run: this guest is next in line and takes the run over (S23).
	dani = WebSocketPeer.new()
	dani.connect_to_url(RoomClient.server_url())
	_expect(await _until(func() -> bool: return dani.get_ready_state() == WebSocketPeer.STATE_OPEN), "Dani could not connect")
	dani.send_text(JSON.stringify({"t": "join", "code": code, "name": "Dani"}))
	_expect(await _until(func() -> bool: return client.room.players.size() == 3), "Dani never joined")
	var chaser_row := [30, NetSnapshot.KIND_CHASER, 600.0, 500.0, 0.0, false]
	await _stream(0.4, [beto_row], [chaser_row], [], {"w": 4, "br": false, "tl": 12.0, "sc": 300})
	var last_tick := _tick
	host.send_text(JSON.stringify({"t": "leave"}))
	_expect(await _until(func() -> bool: return main.get_node_or_null("CoopHost") != null, 240), "the next host must take the run over")
	_expect(main.get_node_or_null("CoopGuest") == null, "the new host stops being a guest")
	_expect(me.input is LocalInput and not me.input is GuestInput, "the new host's own shots are real now")
	_expect(survival.spawner.running and survival.spawner.wave == 4 and not survival.spawner.in_break(),
		"the run goes on from the wave it was in: wave %d running %s" % [survival.spawner.wave, survival.spawner.running])
	var taken := survival.enemies.get_children().filter(func(n: Node) -> bool: return n is Enemy and not n.is_queued_for_deletion())
	_expect(taken.size() == 1 and taken[0].is_physics_processing() and taken[0].collision_layer != 0,
		"the enemy that was shown becomes a real one")
	_expect(await _until(func() -> bool: return survival.players.size() == 2, 240), "Dani joins the new host's run")
	dani_inbox.clear()
	await _seconds(0.6)
	var dani_snaps := dani_inbox.filter(func(m: Variant) -> bool: return m is Dictionary and m.get("t") == "snap")
	_expect(not dani_snaps.is_empty(), "the other guests get snapshots from the new host")
	if not dani_snaps.is_empty():
		_expect(int(dani_snaps[0].d.k) > last_tick, "the new host's ticks go on after the old host's: %d after %d" % [int(dani_snaps[0].d.k), last_tick])
		_expect(int(dani_snaps[0].d.sc) == 300, "the score carries over")

	# A lost connection says so instead of leaving a frozen run.
	server.stop()
	_expect(await _until(func() -> bool: return main.get("lost_connection") == true, 600), "the guest must notice the lost connection")
	_expect(survival.hud.notice_label.visible and survival.hud.notice_label.text.contains("conexión"),
		"the guest is told the connection was lost: %s" % survival.hud.notice_label.text)

	main.queue_free()
	MainMenu.seen = true
	client.leave()
	host.close()
	dani.close()
	await _seconds(0.1)

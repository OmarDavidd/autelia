class_name CoopGuest
extends Node
## A guest's side of an online co-op run (the host simulates; the server only relays).
## Nothing is simulated here: teammates, enemies, spawn markers and bullets are puppets
## placed where the host's snapshots say, drawn a little in the past (DELAY) so they move
## smoothly between snapshots. The guest's own player moves here at once and its position,
## aim and trigger go to the host; its health, downs and revives come back from the host.
## When the host leaves and this machine is next in line, `promoted` fires and `take_over`
## turns what is shown into a real run for the new host.

const INPUTS_PER_SECOND := 30.0
## How far behind the newest snapshot puppets are drawn: two snapshots at 20 a second, so
## one late packet does not stop them.
const DELAY := 0.1
## Snapshots kept for interpolation; older ones are dropped.
const BUFFER := 12
## Share of the gap the offset follows per snapshot when packets arrive later than before.
const OFFSET_CREEP := 0.05
## When the host's view of this player drifts this far from the local one (the host could
## not follow, or put the player somewhere), the host's position wins.
const CORRECTION_DISTANCE := 160.0

## The host left and this machine is the room's host now.
signal promoted

const CHASER := preload("res://core/enemies/chaser.tscn")
const SHOOTER := preload("res://core/enemies/shooter.tscn")
const BULLET := preload("res://core/combat/bullet.tscn")

var mode: SurvivalMode
var client: RoomClient
## This machine's room id; its row in each snapshot is its own player.
var you := 0

## Validated snapshots, oldest first, each with "at" = host seconds.
var _buffer: Array[Dictionary] = []
## Local clock − host clock for the least delayed packet. A quicker packet lowers it at
## once; it also creeps up when packets keep arriving later (a host running behind), so
## drawing never runs ahead of the snapshots for long.
var _offset := INF
var _clock := 0.0
var _seq := 0
var _since_input := 0.0
var _placed := false
var _wave := 0
var _breaking := true
## slot → Player puppet; enemy/marker id → node; bullet id → node.
var _mates := {}
var _enemies := {}
var _bullets := {}
## Enemies already killed: the snapshot being drawn is older than the kill and still has them.
var _killed := {}


func _init() -> void:
	name = "CoopGuest"


## Call once the run's local player exists and before anything spawns.
func bind(run: SurvivalMode, room_client: RoomClient, room: CoopRoom) -> void:
	mode = run
	client = room_client
	you = room.you
	mode.spawner.stop()
	mode.player.input = GuestInput.new()
	client.snapshot_received.connect(_on_snapshot)
	client.room_changed.connect(_on_room_changed)


func _on_room_changed(room: CoopRoom) -> void:
	if room.is_host() and not _buffer.is_empty():
		promoted.emit()


## Turns this guest's view into the new host's run: puppet enemies become real, markers and
## bullets in flight are dropped, teammates get inputs again (people over the network, bots
## here), and the waves go on from the last snapshot. Returns what the new CoopHost needs:
## {"ids", "slots" (parallel to mode.players), "tick" (where the old host's ticks would be now)}.
func take_over() -> Dictionary:
	var last: Dictionary = _buffer.back()
	client.snapshot_received.disconnect(_on_snapshot)
	client.room_changed.disconnect(_on_room_changed)
	for id: int in _enemies.keys():
		var node: Node = _enemies[id]
		if node is Enemy:
			node.become_real()
		elif is_instance_valid(node):
			node.queue_free()
	_enemies.clear()
	_drop_missing(_bullets, {})
	mode.player.input = LocalInput.new()

	var rows := _by(last.pl, NetSnapshot.P_SLOT)
	var ids: Array[int] = []
	var slots: Array[int] = []
	for each in mode.players:
		var slot := -1
		if each == mode.player:
			for row: Array in last.pl:
				if int(row[NetSnapshot.P_ID]) == you:
					slot = int(row[NetSnapshot.P_SLOT])
		else:
			slot = _mates.find_key(each)
		var row: Array = rows.get(slot, [])
		ids.append(int(row[NetSnapshot.P_ID]) if not row.is_empty() else 0)
		slots.append(maxi(slot, 0))

	mode.rng.randomize()
	mode.spawner.resume(mode.rng, mode.arena, mode.players, mode.enemies, int(last.w), last.br, last.tl)
	var since_last := maxf(_clock - _offset - last.at, 0.0)
	set_physics_process(false)
	set_process(false)
	return {"ids": ids, "slots": slots, "tick": int(last.k) + 1 + roundi(since_last * CoopHost.SNAPSHOTS_PER_SECOND)}


func _physics_process(delta: float) -> void:
	if mode == null:
		return
	_clock += delta
	_since_input += delta
	if _since_input >= 1.0 / INPUTS_PER_SECOND:
		_since_input = fmod(_since_input, 1.0 / INPUTS_PER_SECOND)
		_send_input()


func _process(_delta: float) -> void:
	if mode == null or _buffer.is_empty():
		return
	# The two snapshots around the moment being drawn; past the newest one, it stays put.
	var render_at := _clock - _offset - DELAY
	var after := _buffer.size() - 1
	for i in _buffer.size():
		if _buffer[i].at > render_at:
			after = i
			break
	var later: Dictionary = _buffer[after]
	var earlier: Dictionary = _buffer[maxi(after - 1, 0)] if later.at > render_at else later
	var span: float = later.at - earlier.at
	var t := clampf((render_at - earlier.at) / span, 0.0, 1.0) if span > 0.0 else 1.0
	_place_mates(earlier, later, t)
	_place_enemies(earlier, later, t)
	_place_bullets(earlier, later, t)


func _send_input() -> void:
	var player := mode.player
	var input := player.input as GuestInput
	var shooting := input != null and input.shooting() and not player.health.is_dead()
	_seq += 1
	client.send_input(_seq, player.global_position, Vector2.RIGHT.rotated(player.body.rotation), shooting)


func _on_snapshot(data: Dictionary) -> void:
	var snapshot := NetSnapshot.read(data)
	if snapshot.is_empty():
		return
	if not _buffer.is_empty() and snapshot.k <= _buffer.back().k:
		return
	snapshot.at = snapshot.k / CoopHost.SNAPSHOTS_PER_SECOND
	var gap: float = _clock - snapshot.at
	_offset = gap if gap < _offset else _offset + (gap - _offset) * OFFSET_CREEP
	_buffer.append(snapshot)
	if _buffer.size() > BUFFER:
		_buffer.pop_front()
		_forget_killed()
	# Health, events, wave and score show as soon as they arrive; only movement waits.
	_mirror_players(snapshot)
	_play_events(snapshot)
	_show_wave(snapshot)
	var keeper := mode.get_node_or_null("Score") as ScoreKeeper
	if keeper and keeper.score != int(snapshot.sc):
		keeper.score = int(snapshot.sc)
		keeper.changed.emit(keeper.score)


func _mirror_players(snapshot: Dictionary) -> void:
	var listed := {}
	for row: Array in snapshot.pl:
		listed[int(row[NetSnapshot.P_SLOT])] = true
	# A teammate the host no longer lists left the room.
	for slot: int in _mates.keys():
		if not listed.has(slot):
			mode.remove_player(_mates[slot])
			_mates.erase(slot)
	for row: Array in snapshot.pl:
		var player := _player_for(row)
		if player == null:
			continue
		if player == mode.player:
			var reported := Vector2(row[NetSnapshot.P_X], row[NetSnapshot.P_Y])
			if not _placed or player.global_position.distance_to(reported) > CORRECTION_DISTANCE:
				player.global_position = reported
				_placed = true
		player.mirror_health(row[NetSnapshot.P_HP], row[NetSnapshot.P_DOWN], row[NetSnapshot.P_SHIELDED])


## This machine's player for its own row; a teammate puppet (made on first sight) otherwise.
func _player_for(row: Array) -> Player:
	if int(row[NetSnapshot.P_ID]) == you and you != 0:
		return mode.player
	var slot := int(row[NetSnapshot.P_SLOT])
	if not _mates.has(slot):
		var mate := mode.add_player(PuppetInput.new(), slot)
		if mate == null:
			return null
		mate.global_position = Vector2(row[NetSnapshot.P_X], row[NetSnapshot.P_Y])
		_mates[slot] = mate
	return _mates[slot]


func _place_mates(earlier: Dictionary, later: Dictionary, t: float) -> void:
	var before := _by(earlier.pl, NetSnapshot.P_SLOT)
	for row: Array in later.pl:
		var mate: Player = _mates.get(int(row[NetSnapshot.P_SLOT]))
		if mate == null:
			continue
		var from: Array = before.get(int(row[NetSnapshot.P_SLOT]), row)
		mate.global_position = _lerp_at(from, row, NetSnapshot.P_X, t)
		(mate.input as PuppetInput).aim = Vector2.RIGHT.rotated(lerp_angle(from[NetSnapshot.P_AIM], row[NetSnapshot.P_AIM], t))


func _place_enemies(earlier: Dictionary, later: Dictionary, t: float) -> void:
	var before := _by(earlier.en, NetSnapshot.E_ID)
	var seen := {}
	for row: Array in later.en:
		var id := int(row[NetSnapshot.E_ID])
		if _killed.has(id):
			continue
		seen[id] = true
		var kind := int(row[NetSnapshot.E_KIND])
		var node: Node2D = _enemies.get(id)
		if node != null and _kind_of_node(node) != kind:
			# The spawn marker became its enemy on the host.
			node.queue_free()
			node = null
		if node == null:
			node = _make_enemy(kind)
			_enemies[id] = node
		var from: Array = before.get(id, row)
		if int(from[NetSnapshot.E_KIND]) != kind:
			from = row
		node.global_position = _lerp_at(from, row, NetSnapshot.E_X, t)
		if node is SpawnMarker:
			node.show_progress(lerpf(from[NetSnapshot.E_LOOK], row[NetSnapshot.E_LOOK], t))
		else:
			var enemy := node as Enemy
			enemy.look_override = Vector2.RIGHT.rotated(lerp_angle(from[NetSnapshot.E_LOOK], row[NetSnapshot.E_LOOK], t))
			if enemy is Shooter:
				enemy.pivot.rotation = enemy.look_override.angle()
			if row[NetSnapshot.E_FLASH]:
				enemy.flash = 0.08
			enemy.flash = maxf(enemy.flash - get_process_delta_time(), 0.0)
			enemy.queue_redraw()
	_drop_missing(_enemies, seen)


func _place_bullets(earlier: Dictionary, later: Dictionary, t: float) -> void:
	var before := _by(earlier.bu, NetSnapshot.B_ID)
	var seen := {}
	for row: Array in later.bu:
		var id := int(row[NetSnapshot.B_ID])
		seen[id] = true
		var bullet: Bullet = _bullets.get(id)
		if bullet == null:
			bullet = _make_bullet(row[NetSnapshot.B_ENEMY], row[NetSnapshot.B_DIR])
			_bullets[id] = bullet
		bullet.global_position = _lerp_at(before.get(id, row), row, NetSnapshot.B_X, t)
	_drop_missing(_bullets, seen)


func _play_events(snapshot: Dictionary) -> void:
	for event: Array in snapshot.ev:
		var node: Node2D = _enemies.get(int(event[1]))
		var enemy := node as Enemy
		if event[0] == NetSnapshot.EV_HIT:
			if enemy:
				enemy.flash = 0.08
			Events.enemy_hit.emit(enemy, 0.0)
		elif event[0] == NetSnapshot.EV_KILL:
			if enemy:
				enemy.global_position = Vector2(event[2], event[3])
				DeathBurst.spawn(enemy, enemy.burst_color())
				_enemies.erase(int(event[1]))
				enemy.queue_free()
			_killed[int(event[1])] = true
			Events.enemy_killed.emit(enemy)


## The host's wave timer and banner; a wave starting revives fallen players here as there.
func _show_wave(snapshot: Dictionary) -> void:
	var wave := int(snapshot.w)
	mode.spawner.show_state(wave, snapshot.br, snapshot.tl)
	if wave > _wave:
		_wave = wave
		_breaking = false
		Events.wave_started.emit(wave)
	elif snapshot.br and not _breaking and wave > 0:
		_breaking = true
		Events.wave_ended.emit(wave)


## A killed enemy is remembered only while a buffered snapshot still lists it.
func _forget_killed() -> void:
	var listed := {}
	for snapshot in _buffer:
		for row: Array in snapshot.en:
			listed[int(row[NetSnapshot.E_ID])] = true
	for id: int in _killed.keys():
		if not listed.has(id):
			_killed.erase(id)


func _make_enemy(kind: int) -> Node2D:
	var node: Node2D
	if kind == NetSnapshot.KIND_MARKER:
		var marker := SpawnMarker.new()
		mode.enemies.add_child(marker)
		marker.show_progress(0.0)
		node = marker
	else:
		var enemy: Enemy = (SHOOTER if kind == NetSnapshot.KIND_SHOOTER else CHASER).instantiate()
		mode.enemies.add_child(enemy)
		enemy.become_puppet()
		node = enemy
	return node


func _make_bullet(fired_by_enemy: bool, angle: float) -> Bullet:
	var bullet: Bullet = BULLET.instantiate()
	bullet.direction = Vector2.RIGHT.rotated(angle)
	bullet.rotation = angle
	bullet.color = Palette.ENEMY if fired_by_enemy else Palette.INK
	bullet.outlined = fired_by_enemy
	mode.add_child(bullet)
	bullet.become_puppet()
	return bullet


static func _kind_of_node(node: Node) -> int:
	if node is SpawnMarker:
		return NetSnapshot.KIND_MARKER
	return NetSnapshot.kind_of(node)


static func _by(rows: Array, column: int) -> Dictionary:
	var result := {}
	for row: Array in rows:
		result[int(row[column])] = row
	return result


static func _lerp_at(from: Array, to: Array, x_column: int, t: float) -> Vector2:
	return Vector2(from[x_column], from[x_column + 1]).lerp(Vector2(to[x_column], to[x_column + 1]), t)


static func _drop_missing(nodes: Dictionary, seen: Dictionary) -> void:
	for id: int in nodes.keys():
		if not seen.has(id):
			var node: Node = nodes[id]
			if is_instance_valid(node):
				node.queue_free()
			nodes.erase(id)

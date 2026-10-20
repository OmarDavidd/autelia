class_name CoopHost
extends Node
## The host's side of an online co-op run (the host simulates; the server only relays).
## Puts every other member of the room into the run: bots run here, guests are players
## driven by their relayed input. A guest who joins later appears next to a living
## teammate, protected for a moment; one who leaves is taken out. Each player keeps its
## color slot for the whole run. Sends a snapshot of the run about 20 times a second.

const SNAPSHOTS_PER_SECOND := 20.0
## A late joiner appears this far from a living teammate.
const JOIN_DISTANCE := 60.0
## How long a late joiner cannot be hurt after appearing.
const JOIN_GRACE := 2.0

var mode: SurvivalMode
var client: RoomClient
## Room id of each player in `mode.players`, in the same order (0 for bots).
var ids: Array[int] = []
## Color slot of each player in `mode.players`, in the same order.
var slots: Array[int] = []

## Guest's room id → the input that drives their player.
var _inputs := {}
var _snapshot := NetSnapshot.new()
var _tick := 0
var _since_snapshot := 0.0
var _events := []


func _init() -> void:
	name = "CoopHost"


## Call once the run's local player exists and before anything spawns.
func bind(run: SurvivalMode, room_client: RoomClient, room: CoopRoom) -> void:
	mode = run
	client = room_client
	ids = [room.you]
	slots = [0]
	var center := mode.arena.size / 2.0
	for i in room.players.size():
		var entry: Dictionary = room.players[i]
		if entry.id == room.you and not entry.bot:
			continue
		var input: PlayerInput
		if entry.bot:
			input = BotInput.new(center, mode.used_seed + i)
		else:
			input = NetworkInput.new()
			_inputs[entry.id] = input
		if mode.add_player(input):
			ids.append(entry.id)
			slots.append(mode.players.size() - 1)
	client.input_received.connect(_on_input)
	client.room_changed.connect(_on_room_changed)
	Events.enemy_hit.connect(_on_enemy_hit)
	Events.enemy_killed.connect(_on_enemy_killed)


func _physics_process(delta: float) -> void:
	if mode == null:
		return
	_since_snapshot += delta
	if _since_snapshot < 1.0 / SNAPSHOTS_PER_SECOND:
		return
	_since_snapshot = fmod(_since_snapshot, 1.0 / SNAPSHOTS_PER_SECOND)
	_tick += 1
	var keeper := mode.get_node_or_null("Score") as ScoreKeeper
	var data := _snapshot.capture(mode, ids, slots, _tick, keeper.score if keeper else 0, _events)
	client.send_snapshot(NetSnapshot.fit(data, RoomServer.MAX_MESSAGE))
	_events = []


func _on_room_changed(room: CoopRoom) -> void:
	var present := {}
	for entry in room.players:
		if not entry.bot:
			present[entry.id] = true
	for i in range(ids.size() - 1, 0, -1):
		if ids[i] != 0 and not present.has(ids[i]):
			_inputs.erase(ids[i])
			mode.remove_player(mode.players[i])
			ids.remove_at(i)
			slots.remove_at(i)
	for entry in room.players:
		if not entry.bot and entry.id != room.you and not ids.has(entry.id):
			_join(entry.id)


func _join(id: int) -> void:
	var slot := 0
	while slots.has(slot):
		slot += 1
	var input := NetworkInput.new()
	var mate := mode.add_player(input, slot)
	if mate == null:
		return
	_inputs[id] = input
	ids.append(id)
	slots.append(slot)
	var living := mode.living_players().filter(func(each: Player) -> bool: return each != mate)
	var anchor: Player = living[0] if not living.is_empty() else mode.player
	var spot := anchor.global_position + Vector2.RIGHT.rotated(TAU * slot / SurvivalMode.MAX_PLAYERS) * JOIN_DISTANCE
	var area := mode.arena.play_rect().grow(-Player.RADIUS)
	mate.global_position = spot.clamp(area.position, area.end)
	mate.health.invulnerable_left = JOIN_GRACE


func _on_input(message: Dictionary) -> void:
	var input: NetworkInput = _inputs.get(int(message.from))
	if input:
		input.report(message)


func _on_enemy_hit(enemy: Node, _damage: float) -> void:
	if enemy is Node2D and _events.size() < NetSnapshot.MAX_EVENTS:
		_events.append([NetSnapshot.EV_HIT, _snapshot.id_of(enemy)])


func _on_enemy_killed(enemy: Node) -> void:
	if enemy is Node2D and _events.size() < NetSnapshot.MAX_EVENTS:
		_events.append([NetSnapshot.EV_KILL, _snapshot.id_of(enemy), snappedf(enemy.global_position.x, 0.1),
			snappedf(enemy.global_position.y, 0.1), NetSnapshot.kind_of(enemy)])

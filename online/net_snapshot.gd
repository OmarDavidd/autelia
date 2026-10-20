class_name NetSnapshot
extends RefCounted
## What the host sends its guests about the run, about 20 times a second. Rows are plain
## arrays to keep messages small; the indices below name their columns. Positions are
## rounded to a tenth of a pixel. Enemies, spawn markers and bullets carry an id that stays
## the same from one snapshot to the next, so a guest can follow each one smoothly.
##
## {"k": tick, "w": wave, "br": in break, "tl": seconds left, "sc": score,
##  "pl": players, "en": enemies and spawn markers, "bu": bullets, "ev": hits and kills}

## Players: [slot, room id (0 for bots), x, y, aim angle, health, down, invulnerable].
const P_SLOT := 0
const P_ID := 1
const P_X := 2
const P_Y := 3
const P_AIM := 4
const P_HP := 5
const P_DOWN := 6
const P_SHIELDED := 7

## Enemies: [id, kind, x, y, look angle (markers: spawn progress 0-1), flashing].
const E_ID := 0
const E_KIND := 1
const E_X := 2
const E_Y := 3
const E_LOOK := 4
const E_FLASH := 5
const KIND_CHASER := 0
const KIND_SHOOTER := 1
const KIND_MARKER := 2

## Bullets: [id, x, y, direction angle, fired by an enemy].
const B_ID := 0
const B_X := 1
const B_Y := 2
const B_DIR := 3
const B_ENEMY := 4

## Events since the last snapshot: ["h", x, y] an enemy was hit, ["k", x, y, kind] killed.
const EV_HIT := "h"
const EV_KILL := "k"

var _next_id := 1


## `ids[i]` is the room id of `mode.players[i]`.
func capture(mode: SurvivalMode, ids: Array[int], tick: int, score: int, events: Array) -> Dictionary:
	var players := []
	for i in mode.players.size():
		var each: Player = mode.players[i]
		players.append([i, ids[i], _r(each.global_position.x), _r(each.global_position.y),
			_r(each.body.rotation, 0.01), roundi(each.health.current), each.health.is_dead(),
			each.health.is_invulnerable()])

	var enemies := []
	var bullets := []
	for node in mode.enemies.get_children() + mode.get_children():
		if node is Enemy:
			var look: Vector2 = node.look_direction()
			enemies.append([_id(node), kind_of(node), _r(node.global_position.x), _r(node.global_position.y),
				_r(look.angle(), 0.01), node.flash > 0.0])
		elif node is SpawnMarker:
			enemies.append([_id(node), KIND_MARKER, _r(node.global_position.x), _r(node.global_position.y),
				_r(node.progress(), 0.01), false])
		elif node is Bullet and not node.is_queued_for_deletion():
			bullets.append([_id(node), _r(node.global_position.x), _r(node.global_position.y),
				_r(node.direction.angle(), 0.01), node.outlined])

	var spawner := mode.spawner
	return {"k": tick, "w": spawner.wave, "br": spawner.in_break(), "tl": _r(spawner.time_left()),
		"sc": score, "pl": players, "en": enemies, "bu": bullets, "ev": events}


## The server closes a socket that sends more than its bound, so a snapshot that would not
## fit loses its least important rows first: bullets, then enemies, never the players.
## Halving keeps the number of retries small for a crowded wave.
static func fit(data: Dictionary, limit: int) -> Dictionary:
	# Room for the {"t":"snap","d":…} envelope around the data.
	var budget := limit - 32
	if JSON.stringify(data).to_utf8_buffer().size() <= budget:
		return data
	var trimmed := data.duplicate()
	for key in ["bu", "en"]:
		while JSON.stringify(trimmed).to_utf8_buffer().size() > budget and not trimmed.get(key, []).is_empty():
			var rows: Array = trimmed[key]
			trimmed[key] = rows.slice(0, rows.size() / 2)
	return trimmed


static func kind_of(enemy: Node) -> int:
	return KIND_SHOOTER if enemy is Shooter else KIND_CHASER


func _id(node: Node) -> int:
	if not node.has_meta("net_id"):
		node.set_meta("net_id", _next_id)
		_next_id += 1
	return node.get_meta("net_id")


static func _r(value: float, step := 0.1) -> float:
	return snappedf(value, step)

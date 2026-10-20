class_name NetworkInput
extends PlayerInput
## A guest's player on the host. The guest's machine moves that player itself and reports
## where it is, where it aims and whether it shoots; the host follows the report at no more
## than the player's speed (with some slack for bursty packets), so a report can never
## teleport it through walls or across the arena.

## How much faster than its speed the host may move a guest's player to catch up.
const SPEED_SLACK := 1.5
## A guest that has sent nothing for this long stops shooting (its last input said "fire").
const QUIET_SECONDS := 0.5

var _target := Vector2.INF
var _aim := Vector2.RIGHT
var _shooting := false
var _last_seq := -INF
## Physics time since the last report, counted in reported_velocity (called every frame).
var _quiet := 0.0


## Takes one relayed input message (already checked by the server); older ones are ignored.
func report(message: Dictionary) -> void:
	var seq: float = message.q
	if seq <= _last_seq:
		return
	_last_seq = seq
	_quiet = 0.0
	_target = Vector2(message.p[0], message.p[1])
	var aim := Vector2(message.a[0], message.a[1])
	if aim.length() > 0.001:
		_aim = aim.normalized()
	_shooting = message.s


func reports_position() -> bool:
	return true


func reported_velocity(player: Player, delta: float) -> Vector2:
	_quiet += delta
	if not _target.is_finite() or delta <= 0.0:
		return Vector2.ZERO
	var step := (_target - player.global_position).limit_length(player.speed * SPEED_SLACK * delta)
	return step / delta


func aim_point(player: Player) -> Vector2:
	return player.global_position + _aim * 100.0


func wants_to_shoot(_player: Player) -> bool:
	return _shooting and _quiet < QUIET_SECONDS


func is_local() -> bool:
	return false

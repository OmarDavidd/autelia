class_name BotInput
extends PlayerInput
## A teammate for trying co-op without a network. It plays like a person rather than a
## machine: it notices enemies with a reaction delay, aims with a small error and fires in
## bursts. It backs away from enemies that get close, keeps some room from teammates
## (players do not collide, so identical bots would stack) and drifts back to the middle.
## Its randomness comes from its own seed, never from the run's RNG.

const KEEP_AWAY := 220.0
const PERSONAL_SPACE := 90.0
## How often (physics frames) the bot looks again for the nearest enemy.
const REACTION_FRAMES := 24
## Largest aiming error, picked again for every new look.
const AIM_ERROR_DEGREES := 6.0
## Firing pattern: shoot for a while, then rest.
const BURST_FRAMES := 48
const REST_FRAMES := 12

## Where the bot drifts back to: the middle of its arena.
var home := Vector2(640, 360)
## The enemy it is engaging; kept until the next look, even if a closer one appears.
var target: Node2D
## Direction to step away when standing exactly on a teammate.
var split_direction := Vector2.RIGHT

var _rng := RandomNumberGenerator.new()
var _frame := 0
var _aim_error := 0.0


func _init(center := Vector2(640, 360), seed_value := 0) -> void:
	home = center
	_rng.seed = seed_value
	split_direction = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	# Start each bot at a different point of its burst, so a team does not fire in unison.
	_frame = _rng.randi_range(0, BURST_FRAMES + REST_FRAMES)


## Called first every physics frame by the player, so it also advances the bot's clock.
func move_vector(player: Player) -> Vector2:
	_frame += 1
	if _frame % REACTION_FRAMES == 0 or not is_instance_valid(target):
		target = _nearest_enemy(player)
		_aim_error = deg_to_rad(_rng.randf_range(-AIM_ERROR_DEGREES, AIM_ERROR_DEGREES))

	var push := (home - player.global_position) * 0.004
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		var away: Vector2 = player.global_position - enemy.global_position
		if away.length() < KEEP_AWAY:
			push += away.normalized() * (1.0 - away.length() / KEEP_AWAY) * 2.0
	for mate: Player in player.get_tree().get_nodes_in_group("player"):
		var gap: Vector2 = player.global_position - mate.global_position
		if mate != player and not mate.health.is_dead() and gap.length() < PERSONAL_SPACE:
			var side := gap.normalized() if gap.length() > 1.0 else split_direction
			push += side * (1.0 - gap.length() / PERSONAL_SPACE) * 1.5
	return push.limit_length(1.0)


func aim_point(player: Player) -> Vector2:
	if not is_instance_valid(target):
		return super.aim_point(player)
	return player.global_position + (target.global_position - player.global_position).rotated(_aim_error)


func wants_to_shoot(_player: Player) -> bool:
	return is_instance_valid(target) and _frame % (BURST_FRAMES + REST_FRAMES) < BURST_FRAMES


func _nearest_enemy(player: Player) -> Node2D:
	var best: Node2D
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if best == null or player.global_position.distance_squared_to(enemy.global_position) \
				< player.global_position.distance_squared_to(best.global_position):
			best = enemy
	return best

class_name GunGameBotInput
extends PlayerInput
## AI bot for Gun Game. Competes in FFA: selects the nearest living opponent, adapts
## engagement distance to its current weapon (rushes with melee, keeps distance with rifles)
## and shoots with simulated human reaction time and aim error.

const REACTION_FRAMES := 20
const AIM_ERROR_DEGREES := 6.5
const BURST_FRAMES := 42
const REST_FRAMES := 10

var home := Vector2(680, 380)
var target: Player
var split_direction := Vector2.RIGHT

var _rng := RandomNumberGenerator.new()
var _frame := 0
var _aim_error := 0.0


var _current_move := Vector2.ZERO


func _init(center := Vector2(680, 380), seed_value := 0) -> void:
	home = center
	_rng.seed = seed_value
	split_direction = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	_frame = _rng.randi_range(0, BURST_FRAMES + REST_FRAMES)


func move_vector(player: Player) -> Vector2:
	_frame += 1
	if _frame % REACTION_FRAMES == 0 or not is_instance_valid(target) or target.health.is_dead():
		target = _nearest_opponent(player)
		_aim_error = deg_to_rad(_rng.randf_range(-AIM_ERROR_DEGREES, AIM_ERROR_DEGREES))

	# Target engagement distance depends on weapon type
	var is_melee := player.weapon.is_melee
	var desired_distance := 0.0 if is_melee else (160.0 if player.weapon.bullet_count > 1 else 280.0)

	var push := Vector2.ZERO
	if is_instance_valid(target):
		var to_target: Vector2 = target.global_position - player.global_position
		var dist := to_target.length()
		if is_melee:
			# Charge target directly for melee kill
			push += to_target.normalized() * 1.0
		elif dist < desired_distance * 0.7:
			# Too close, back away
			push -= to_target.normalized() * 0.75
		elif dist > desired_distance * 1.3:
			# Too far, advance
			push += to_target.normalized() * 0.8
		else:
			# Strafe around target
			push += to_target.orthogonal().normalized() * 0.65
	else:
		# Drift toward center when seeking targets
		push = (home - player.global_position) * 0.002

	# Keep personal space from other players
	for node in player.get_tree().get_nodes_in_group("player"):
		if node == player or not (node is Player):
			continue
		var other: Player = node
		if other.health.is_dead():
			continue
		var gap := player.global_position - other.global_position
		if gap.length() < 80.0:
			var side := gap.normalized() if gap.length() > 1.0 else split_direction
			push += side * (1.0 - gap.length() / 80.0) * 1.5

	_current_move = _current_move.move_toward(push.limit_length(0.9), 0.1)
	return _current_move


func aim_point(player: Player) -> Vector2:
	if not is_instance_valid(target) or target.health.is_dead():
		return super.aim_point(player)
	var dir := (target.global_position - player.global_position).rotated(_aim_error)
	return player.global_position + dir


const MAX_SIGHT_RANGE := 620.0


func wants_to_shoot(player: Player) -> bool:
	if not is_instance_valid(target) or target.health.is_dead():
		return false

	var dist := player.global_position.distance_to(target.global_position)
	if dist > _max_fire_range(player):
		return false

	# Never shoot into solid walls
	if not _has_line_of_sight(player, target):
		return false

	if player.weapon.is_melee:
		return dist < 65.0

	return _frame % (BURST_FRAMES + REST_FRAMES) < BURST_FRAMES


func _max_fire_range(player: Player) -> float:
	if player.weapon.is_melee:
		return 65.0
	if player.weapon.bullet_count > 1:
		return 280.0 # Escopeta
	if player.weapon.bounces > 0:
		return 380.0 # Rebote
	if player.weapon.pierces > 0:
		return 480.0 # Perforador
	return 380.0 # Pistola


func _has_line_of_sight(player: Player, target_player: Player) -> bool:
	var space := player.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		player.global_position,
		target_player.global_position,
		1 # Mask 1: world / walls
	)
	var hit := space.intersect_ray(query)
	return hit.is_empty()


func _nearest_opponent(player: Player) -> Player:
	var best: Player = null
	var best_dist := INF
	for node in player.get_tree().get_nodes_in_group("player"):
		if node == player or not (node is Player):
			continue
		var other: Player = node
		if other.health.is_dead():
			continue
		var d := player.global_position.distance_to(other.global_position)
		if d < MAX_SIGHT_RANGE and d < best_dist:
			best_dist = d
			best = other
	return best


func is_local() -> bool:
	return false

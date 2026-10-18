class_name BotInput
extends PlayerInput
## A simple teammate for trying co-op without a network: shoots the nearest enemy, backs
## away from enemies that get close and drifts back toward the middle of the arena.

const KEEP_AWAY := 220.0
const ARENA_CENTER := Vector2(640, 360)


func move_vector(player: Player) -> Vector2:
	var push := (ARENA_CENTER - player.global_position) * 0.004
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		var away: Vector2 = player.global_position - enemy.global_position
		if away.length() < KEEP_AWAY:
			push += away.normalized() * (1.0 - away.length() / KEEP_AWAY) * 2.0
	return push.limit_length(1.0)


func aim_point(player: Player) -> Vector2:
	var enemy := _nearest_enemy(player)
	return enemy.global_position if enemy else super.aim_point(player)


func wants_to_shoot(player: Player) -> bool:
	return _nearest_enemy(player) != null


func _nearest_enemy(player: Player) -> Node2D:
	var best: Node2D
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		if best == null or player.global_position.distance_squared_to(enemy.global_position) \
				< player.global_position.distance_squared_to(best.global_position):
			best = enemy
	return best

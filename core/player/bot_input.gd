class_name BotInput
extends PlayerInput
## A simple teammate for trying co-op without a network: shoots the nearest enemy, backs
## away from enemies that get close, keeps some room from teammates (players do not collide,
## so identical bots would stack) and drifts back toward the middle of the arena.

const KEEP_AWAY := 220.0
const PERSONAL_SPACE := 90.0

## Where the bot drifts back to: the middle of its arena.
var home := Vector2(640, 360)


func _init(center := Vector2(640, 360)) -> void:
	home = center


func move_vector(player: Player) -> Vector2:
	var push := (home - player.global_position) * 0.004
	for enemy in player.get_tree().get_nodes_in_group("enemies"):
		var away: Vector2 = player.global_position - enemy.global_position
		if away.length() < KEEP_AWAY:
			push += away.normalized() * (1.0 - away.length() / KEEP_AWAY) * 2.0
	for mate: Player in player.get_tree().get_nodes_in_group("player"):
		var gap: Vector2 = player.global_position - mate.global_position
		if mate != player and not mate.health.is_dead() and gap.length() < PERSONAL_SPACE:
			# Same spot: split along a direction that differs per player.
			var side := gap.normalized() if gap.length() > 1.0 else Vector2.RIGHT.rotated(player.get_instance_id() % 628 / 100.0)
			push += side * (1.0 - gap.length() / PERSONAL_SPACE) * 1.5
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

class_name ScriptedInput
extends PlayerInput
## Intentions set from outside: tests now, network messages later.

var move := Vector2.ZERO
## World point to aim at; INF keeps the default aim.
var aim := Vector2.INF
var shoot := false


func move_vector(_player: Player) -> Vector2:
	return move.limit_length(1.0)


func aim_point(player: Player) -> Vector2:
	return aim if aim.is_finite() else super.aim_point(player)


func wants_to_shoot(_player: Player) -> bool:
	return shoot

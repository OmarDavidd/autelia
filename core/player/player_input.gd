class_name PlayerInput
extends RefCounted
## Where a player's intentions come from: this machine's keyboard and mouse, a script, a bot
## and, later, the network. The player only asks; it never reads devices itself.


## Desired movement, length 0 to 1.
func move_vector(_player: Player) -> Vector2:
	return Vector2.ZERO


## World point to aim at.
func aim_point(player: Player) -> Vector2:
	return player.global_position + Vector2.RIGHT


func wants_to_shoot(_player: Player) -> bool:
	return false


## Whether a person at this machine plays through it: only that player's damage makes the
## hurt sound and reaches telemetry. Bots (and, later, remote players) say no.
func is_local() -> bool:
	return true

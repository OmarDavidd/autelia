class_name PuppetInput
extends PlayerInput
## A teammate on a guest's screen: the guest moves it where the host's snapshots say and
## only turns it toward the reported aim. It never moves, shoots or plays by itself.

var aim := Vector2.RIGHT


func reports_position() -> bool:
	return true


func aim_point(player: Player) -> Vector2:
	return player.global_position + aim * 100.0


func is_local() -> bool:
	return false

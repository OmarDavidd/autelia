class_name FollowCamera
extends Camera2D
## Keeps a player centered, stopping at the arena edges. Used when the arena is bigger than
## the screen (co-op); the classic arena keeps its fixed camera.

var target: Node2D


func follow(who: Node2D, bounds: Rect2) -> void:
	target = who
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	global_position = who.global_position
	reset_smoothing()


func _process(_delta: float) -> void:
	if is_instance_valid(target):
		global_position = target.global_position

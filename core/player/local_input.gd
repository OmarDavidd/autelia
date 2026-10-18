class_name LocalInput
extends PlayerInput
## The player at this machine: movement and shooting actions (keyboard, touch sticks) and
## the mouse to aim.


func move_vector(_player: Player) -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func aim_point(player: Player) -> Vector2:
	return player.get_global_mouse_position()


func wants_to_shoot(_player: Player) -> bool:
	return Input.is_action_pressed("shoot")

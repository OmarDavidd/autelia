class_name GuestInput
extends LocalInput
## The guest's own player: it moves and aims here at once, but its shots are fired by the
## host (the host decides every hit), so the local weapon stays quiet and the press is sent.


func wants_to_shoot(_player: Player) -> bool:
	return false


## Whether the person here holds fire; sent to the host with every input.
func shooting() -> bool:
	return Input.is_action_pressed("shoot")

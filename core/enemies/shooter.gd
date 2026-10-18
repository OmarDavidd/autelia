class_name Shooter
extends Enemy
## Keeps a preferred distance from the player, strafes, and shoots at it.

@export var preferred_distance := 280.0
@export var distance_tolerance := 40.0
@export var fire_range := 480.0

@onready var pivot: Node2D = $Pivot
@onready var weapon: Weapon = $Pivot/Weapon

var _strafe_sign := 1.0


func desired_velocity(delta: float) -> Vector2:
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	var direction := to_target / maxf(distance, 0.001)
	pivot.rotation = direction.angle()

	var move := Vector2.ZERO
	if distance > preferred_distance + distance_tolerance:
		move = direction
	elif distance < preferred_distance - distance_tolerance:
		move = -direction
	else:
		if is_on_wall():
			_strafe_sign = -_strafe_sign
		move = direction.orthogonal() * _strafe_sign * 0.6

	if distance <= fire_range:
		weapon.try_fire()
	return velocity.move_toward(move * speed, acceleration * delta)


func burst_color() -> Color:
	return Palette.SHOOTER


func _draw() -> void:
	Sketch.draw_shooter(self, Vector2.RIGHT.rotated(pivot.rotation), look_direction(),
		fill_color(Palette.SHOOTER), Vector2.ZERO, 1.0, pop_scale())

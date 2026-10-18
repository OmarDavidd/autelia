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


func _draw() -> void:
	var r := Palette.ART_RADIUS
	Sketch.hatch_shadow(self, Vector2(0.0, r + 8.0), r)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * pop_scale())
	var aim := Vector2.RIGHT.rotated(pivot.rotation)
	Sketch.capsule(self, aim * (r - 4.0), aim * (r + 12.0), 9.0, Palette.INK)
	draw_set_transform(Vector2.ZERO)
	Sketch.rounded_diamond(self, r * 0.82 * pop_scale(), fill_color(Palette.SHOOTER))
	# One big eye that follows the player.
	draw_circle(Vector2.ZERO, 7.5, Palette.WHITE)
	draw_arc(Vector2.ZERO, 7.5, 0.0, TAU, 24, Palette.INK, 2.5, true)
	draw_circle(look_direction() * 2.5, 3.0, Palette.INK)

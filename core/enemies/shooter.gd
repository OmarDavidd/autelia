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
	var r := radius
	var shape := PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
	var barrel_end := Vector2.RIGHT.rotated(pivot.rotation) * (r + 8.0)
	draw_line(Vector2.ZERO, barrel_end, Palette.INK, 6.0)
	draw_colored_polygon(shape, fill_color(Palette.SHOOTER))
	shape.append(shape[0])
	draw_polyline(shape, Palette.INK, Palette.OUTLINE_WIDTH, true)

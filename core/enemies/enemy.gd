class_name Enemy
extends CharacterBody2D
## Base enemy: health, contact damage, hit flash and death.
## Subclasses only decide how to move by overriding `desired_velocity`.

@export var speed := 140.0
@export var acceleration := 900.0
@export var contact_damage := 10.0
@export var radius := 16.0

@onready var health: Health = $Health

var target: Player
var flash := 0.0


func _ready() -> void:
	add_to_group("enemies")
	# Deferred so a killing blow reports `enemy_hit` before `enemy_killed`.
	health.died.connect(_on_died, CONNECT_DEFERRED)


func _physics_process(delta: float) -> void:
	flash = maxf(flash - delta, 0.0)
	if not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Player

	if target and not target.health.is_dead():
		velocity = desired_velocity(delta)
		_apply_contact_damage()
	else:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
	move_and_slide()
	queue_redraw()


## Override in subclasses. Called only while there is a living target.
func desired_velocity(_delta: float) -> Vector2:
	return Vector2.ZERO


func take_hit(damage: float, _source: Node = null) -> void:
	if health.take_damage(damage):
		flash = 0.08
		Events.enemy_hit.emit(self, damage)


func fill_color(base: Color) -> Color:
	return Palette.WHITE if flash > 0.0 else base


## Brief swell when hit, as visual feedback.
func pop_scale() -> float:
	return 1.0 + flash * 2.0


func look_direction() -> Vector2:
	if is_instance_valid(target):
		return global_position.direction_to(target.global_position)
	return Vector2.DOWN


func _apply_contact_damage() -> void:
	if global_position.distance_to(target.global_position) <= radius + Player.RADIUS + 2.0:
		target.take_hit(contact_damage, self)


func _on_died() -> void:
	Events.enemy_killed.emit(self)
	queue_free()

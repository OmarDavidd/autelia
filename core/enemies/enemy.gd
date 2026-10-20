class_name Enemy
extends CharacterBody2D
## Base enemy: health, contact damage, hit flash and death.
## Subclasses only decide how to move by overriding `desired_velocity`.

@export var speed := 140.0
@export var acceleration := 900.0
@export var contact_damage := 10.0
@export var radius := 16.0

## How often (in physics frames) an enemy looks again for the nearest living player.
const RETARGET_FRAMES := 15

@onready var health: Health = $Health

var target: Player
var flash := 0.0
## Online co-op guests: where the host says this enemy looks (it has no target here).
var look_override := Vector2.ZERO

var _retarget_in := 0


func _ready() -> void:
	add_to_group("enemies")
	# Deferred so a killing blow reports `enemy_hit` before `enemy_killed`.
	health.died.connect(_on_died, CONNECT_DEFERRED)


func _physics_process(delta: float) -> void:
	flash = maxf(flash - delta, 0.0)
	_retarget_in -= 1
	if _retarget_in <= 0 or not is_instance_valid(target) or target.health.is_dead():
		target = _nearest_player()
		_retarget_in = RETARGET_FRAMES

	if target and not target.health.is_dead():
		velocity = desired_velocity(delta)
		_apply_contact_damage()
	else:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
	move_and_slide()
	queue_redraw()


## The closest player still standing, or null when the whole team is down.
func _nearest_player() -> Player:
	var best: Player
	for player: Player in get_tree().get_nodes_in_group("player"):
		if player.health.is_dead():
			continue
		if best == null or global_position.distance_squared_to(player.global_position) \
				< global_position.distance_squared_to(best.global_position):
			best = player
	return best


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
	if look_override != Vector2.ZERO:
		return look_override
	if is_instance_valid(target):
		return global_position.direction_to(target.global_position)
	return Vector2.DOWN


func _apply_contact_damage() -> void:
	if global_position.distance_to(target.global_position) <= radius + Player.RADIUS + 2.0:
		target.take_hit(contact_damage, self)


## Online co-op guests: only shows where the host's enemy is; it neither moves, hits nor
## blocks anyone here.
func become_puppet() -> void:
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0


## Color of the death burst; subclasses use their body color.
func burst_color() -> Color:
	return Palette.ENEMY


func _on_died() -> void:
	Events.enemy_killed.emit(self)
	DeathBurst.spawn(self, burst_color())
	queue_free()

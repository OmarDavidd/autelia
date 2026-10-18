class_name Weapon
extends Node2D
## Fires bullets along its global +X axis, limited by `fire_rate`.

enum Team { PLAYER, ENEMY }

const BULLET_SCENE := preload("res://core/combat/bullet.tscn")
# Physics layer bits: 1 world, 2 player, 4 enemies, 8 player bullets, 16 enemy bullets.
const TEAM_LAYERS := {
	Team.PLAYER: {"layer": 8, "mask": 1 | 4, "color": Palette.INK},
	Team.ENEMY: {"layer": 16, "mask": 1 | 2, "color": Palette.ENEMY},
}

@export var team := Team.PLAYER
@export var fire_rate := 8.0
@export var bullet_speed := 900.0
@export var damage := 10.0

var _cooldown := 0.0


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func can_fire() -> bool:
	return _cooldown <= 0.0


## Returns true when a bullet was fired.
func try_fire() -> bool:
	if not can_fire():
		return false
	_cooldown = 1.0 / fire_rate

	var settings: Dictionary = TEAM_LAYERS[team]
	var bullet: Bullet = BULLET_SCENE.instantiate()
	bullet.direction = Vector2.RIGHT.rotated(global_rotation)
	bullet.speed = bullet_speed
	bullet.damage = damage
	bullet.source = owner
	bullet.color = settings.color
	bullet.collision_layer = settings.layer
	bullet.collision_mask = settings.mask

	# Bullets live next to the shooter so they share its physics world.
	var shooter: Node = owner if owner else self
	shooter.get_parent().add_child(bullet)
	bullet.global_position = global_position
	Events.shot_fired.emit(owner)
	return true

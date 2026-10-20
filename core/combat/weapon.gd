class_name Weapon
extends Node2D
## Fires bullets along its global +X axis, limited by `fire_rate`.

enum Team { PLAYER, ENEMY, FFA }

const BULLET_SCENE := preload("res://core/combat/bullet.tscn")
# Physics layer bits: 1 world, 2 player, 4 enemies, 8 player bullets, 16 enemy bullets.
const TEAM_LAYERS := {
	Team.PLAYER: {"layer": 8, "mask": 1 | 4, "color": Palette.INK, "outlined": false},
	Team.ENEMY: {"layer": 16, "mask": 1 | 2, "color": Palette.ENEMY, "outlined": true},
	Team.FFA: {"layer": 8, "mask": 1 | 2, "color": Palette.INK, "outlined": false},
}

@export var team := Team.PLAYER
@export var fire_rate := 8.0
@export var bullet_speed := 900.0
@export var damage := 10.0
@export var bullet_count := 1
@export var spread_degrees := 0.0
@export var bounces := 0
@export var pierces := 0
@export var bullet_radius := 5.0
@export var bullet_lifetime := 1.2
@export var is_melee := false
@export var recoil := 0.0
@export var lunge := 0.0
@export var sound_pitch := 1.0

var _cooldown := 0.0


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func can_fire() -> bool:
	return _cooldown <= 0.0


func apply_profile(profile: Dictionary) -> void:
	fire_rate = profile.get("fire_rate", 8.0)
	bullet_speed = profile.get("bullet_speed", 900.0)
	damage = profile.get("damage", 10.0)
	bullet_count = profile.get("bullet_count", 1)
	spread_degrees = profile.get("spread_degrees", 0.0)
	bounces = profile.get("bounces", 0)
	pierces = profile.get("pierces", 0)
	bullet_radius = profile.get("bullet_radius", 5.0)
	bullet_lifetime = profile.get("bullet_lifetime", 1.2)
	is_melee = profile.get("is_melee", false)
	recoil = profile.get("recoil", 0.0)
	lunge = profile.get("lunge", 0.0)
	sound_pitch = profile.get("sound_pitch", 1.0)


## Returns true when a bullet was fired.
func try_fire() -> bool:
	if not can_fire():
		return false
	_cooldown = 1.0 / fire_rate

	var settings: Dictionary = TEAM_LAYERS[team]
	var shooter: Node = owner if owner else self

	var base_angle := global_rotation
	if shooter is CharacterBody2D:
		var dir := Vector2.RIGHT.rotated(base_angle)
		if recoil > 0.0:
			shooter.velocity -= dir * recoil
		if lunge > 0.0:
			shooter.velocity += dir * lunge

	var angles: Array[float] = []
	if bullet_count <= 1:
		angles.append(base_angle)
	elif spread_degrees <= 0.0:
		for i in bullet_count:
			angles.append(base_angle)
	else:
		var half_spread := deg_to_rad(spread_degrees) / 2.0
		var step := deg_to_rad(spread_degrees) / float(bullet_count - 1)
		for i in bullet_count:
			angles.append(base_angle - half_spread + step * i)

	for angle in angles:
		var bullet: Bullet = BULLET_SCENE.instantiate()
		bullet.direction = Vector2.RIGHT.rotated(angle)
		bullet.rotation = angle
		bullet.speed = bullet_speed
		bullet.damage = damage
		bullet.lifetime = bullet_lifetime
		bullet.radius = bullet_radius
		bullet.bounces = bounces
		bullet.pierces = pierces
		bullet.is_melee = is_melee
		bullet.source = shooter
		bullet.color = settings.color
		bullet.outlined = settings.outlined
		bullet.collision_layer = settings.layer
		bullet.collision_mask = settings.mask

		# Bullets live next to the shooter so they share its physics world.
		shooter.get_parent().add_child(bullet)
		bullet.global_position = global_position

	Events.shot_fired.emit(owner)
	return true

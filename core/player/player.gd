class_name Player
extends CharacterBody2D
## Top-down player: free movement with acceleration, aims at the mouse, holds to shoot.

const RADIUS := 16.0

@export var speed := 260.0
@export var acceleration := 2200.0
@export var friction := 2600.0

## When finite, the player aims here instead of at the mouse (scripted captures, bots).
var aim_override := Vector2.INF

## Invisible aim pivot: rotates toward the aim and carries the weapon.
@onready var body: Node2D = $Body
@onready var look: Node2D = $Look
@onready var weapon: Weapon = $Body/Weapon
@onready var health: Health = $Health


func _ready() -> void:
	add_to_group("player")
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var rate := acceleration if input != Vector2.ZERO else friction
	velocity = velocity.move_toward(input * speed, rate * delta)
	move_and_slide()

	var aim_at := aim_override if aim_override.is_finite() else get_global_mouse_position()
	body.rotation = (aim_at - global_position).angle()
	look.set_aim(Vector2.RIGHT.rotated(body.rotation))
	if Input.is_action_pressed("shoot"):
		weapon.try_fire()

	# Blink while invulnerable so the player can read the grace period.
	var blinking := health.is_invulnerable() and int(health.invulnerable_left * 20.0) % 2 == 0
	look.modulate.a = 0.35 if blinking else 1.0


func take_hit(damage: float, _source: Node = null) -> void:
	health.take_damage(damage)


func _on_damaged(amount: float, current: float) -> void:
	Events.player_damaged.emit(amount, current)


func _on_died() -> void:
	Events.player_died.emit()
	set_physics_process(false)
	velocity = Vector2.ZERO
	look.modulate.a = 1.0
	DeathBurst.spawn(self, Palette.PLAYER)
	# Squash, then deflate and fade out.
	var tween := create_tween()
	tween.tween_property(look, "scale", Vector2(1.45, 0.55), 0.12)
	tween.tween_property(look, "scale", Vector2(0.2, 0.2), 0.35).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(look, "modulate:a", 0.0, 0.35)

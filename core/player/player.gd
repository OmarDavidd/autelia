class_name Player
extends CharacterBody2D
## Top-down player: free movement with acceleration, aims and holds to shoot.
## Intentions come from `input` (keyboard and mouse by default, a bot, a guest over the network).

const RADIUS := 16.0
## Invulnerability after reviving, so the player is not knocked down again on arrival.
const REVIVE_GRACE := 1.5

@export var speed := 260.0
@export var acceleration := 2200.0
@export var friction := 2600.0

## When finite, the player aims here instead of where its input says (captures, touch sticks).
var aim_override := Vector2.INF
var input: PlayerInput = LocalInput.new()
## Body color; co-op players each get their own.
var color := Palette.PLAYER

## Attacker who dealt the most recent hit; used for kill attribution in versus modes.
var last_attacker: Node = null

var _collision_layer := 0
var _death_tween: Tween

## Invisible aim pivot: rotates toward the aim and carries the weapon.
@onready var body: Node2D = $Body
@onready var look: Node2D = $Look
@onready var weapon: Weapon = $Body/Weapon
@onready var health: Health = $Health


func _ready() -> void:
	add_to_group("player")
	look.color = color
	_collision_layer = collision_layer
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if input.reports_position():
		velocity = input.reported_velocity(self, delta)
	else:
		var move := input.move_vector(self)
		var rate := acceleration if move != Vector2.ZERO else friction
		velocity = velocity.move_toward(move * speed, rate * delta)
	move_and_slide()

	var aim_at := aim_override if aim_override.is_finite() else input.aim_point(self)
	body.rotation = (aim_at - global_position).angle()
	look.set_aim(Vector2.RIGHT.rotated(body.rotation))
	if input.wants_to_shoot(self):
		weapon.try_fire()

	# Blink while invulnerable so the player can read the grace period.
	var blinking := health.is_invulnerable() and int(health.invulnerable_left * 20.0) % 2 == 0
	look.modulate.a = 0.35 if blinking else 1.0


func take_hit(damage: float, source: Node = null) -> void:
	if source != null:
		last_attacker = source
	health.take_damage(damage)


func _on_damaged(amount: float, current: float) -> void:
	if input.is_local():
		Events.player_damaged.emit(amount, current)


## Back from being down with part of the health (co-op: at the start of the next wave).
func revive(fraction := 0.5) -> void:
	if _death_tween:
		_death_tween.kill()
	last_attacker = null
	health.current = health.max_health * fraction
	health.invulnerable_left = REVIVE_GRACE
	collision_layer = _collision_layer
	look.scale = Vector2.ONE
	look.modulate.a = 1.0
	set_physics_process(true)
	Events.player_revived.emit(self)


func _on_died() -> void:
	Events.player_down.emit(self)
	Events.player_killed.emit(last_attacker, self)
	# The run is over only when nobody else is standing.
	var team_standing := get_tree().get_nodes_in_group("player").any(
		func(other: Player) -> bool: return other != self and not other.health.is_dead())
	if not team_standing:
		Events.player_died.emit()
	set_physics_process(false)
	# Down players neither block enemies nor get hit.
	collision_layer = 0
	velocity = Vector2.ZERO
	look.modulate.a = 1.0
	DeathBurst.spawn(self, color)
	# Squash, then deflate and fade out.
	_death_tween = create_tween()
	_death_tween.tween_property(look, "scale", Vector2(1.45, 0.55), 0.12)
	_death_tween.tween_property(look, "scale", Vector2(0.2, 0.2), 0.35).set_ease(Tween.EASE_IN)
	_death_tween.parallel().tween_property(look, "modulate:a", 0.0, 0.35)

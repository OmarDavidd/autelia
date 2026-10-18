class_name Health
extends Node
## Hit points with optional invulnerability after each hit.
## Uses physics time, not wall-clock time, so behavior is the same in tests and replays.

signal damaged(amount: float, current: float)
signal died

@export var max_health := 100.0
@export var invulnerability_time := 0.0

var current: float
var invulnerable_left := 0.0


func _ready() -> void:
	reset()


func _physics_process(delta: float) -> void:
	invulnerable_left = maxf(invulnerable_left - delta, 0.0)


func reset() -> void:
	current = max_health
	invulnerable_left = 0.0


func is_dead() -> bool:
	return current <= 0.0


func is_invulnerable() -> bool:
	return invulnerable_left > 0.0


## Returns true when the damage was applied.
func take_damage(amount: float) -> bool:
	if amount <= 0.0 or is_dead() or is_invulnerable():
		return false
	current = maxf(current - amount, 0.0)
	invulnerable_left = invulnerability_time
	damaged.emit(amount, current)
	if is_dead():
		died.emit()
	return true

class_name ScoreKeeper
extends Node
## Arcade scoring: points per kill by enemy type, plus a bonus for each wave survived.
## The score freezes when the player dies, so stray bullets cannot add to it afterwards.

signal changed(score: int)

const CHASER_POINTS := 10
const SHOOTER_POINTS := 20
## Surviving wave N gives N times this.
const WAVE_BONUS := 50

var score := 0

var _over := false


func _ready() -> void:
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.wave_ended.connect(_on_wave_ended)
	Events.player_died.connect(_on_player_died)


static func points_for(enemy: Node) -> int:
	if enemy is Shooter:
		return SHOOTER_POINTS
	if enemy is Chaser:
		return CHASER_POINTS
	return 0


func add(points: int) -> void:
	if _over or points == 0:
		return
	score += points
	changed.emit(score)


func _on_enemy_killed(enemy: Node) -> void:
	add(points_for(enemy))


func _on_wave_ended(index: int) -> void:
	add(WAVE_BONUS * index)


func _on_player_died() -> void:
	_over = true

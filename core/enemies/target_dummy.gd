class_name TargetDummy
extends StaticBody2D
## Practice target: takes hits, shows remaining health, respawns after dying.
## Temporary in the arena until real enemies exist; later reused for the tutorial.

@export var radius := 18.0
@export var respawn_time := 1.0

@onready var health: Health = $Health

var _flash := 0.0
var _respawn_left := 0.0


func _ready() -> void:
	add_to_group("enemies")
	health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	if _respawn_left > 0.0:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			health.reset()
	queue_redraw()


func take_hit(damage: float, _source: Node = null) -> void:
	if health.take_damage(damage):
		_flash = 0.08
		Events.enemy_hit.emit(self, damage)


func _on_died() -> void:
	Events.enemy_killed.emit(self)
	_respawn_left = respawn_time


func _draw() -> void:
	if health.is_dead():
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Palette.INK, 1.5, true)
		return
	var fill := Color.WHITE if _flash > 0.0 else Palette.ENEMY
	draw_circle(Vector2.ZERO, radius, fill)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Palette.INK, Palette.OUTLINE_WIDTH, true)
	var ratio := health.current / health.max_health
	draw_arc(Vector2.ZERO, radius + 7.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 32, Palette.INK, 2.0, true)

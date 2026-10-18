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
	DeathBurst.spawn(self, Palette.ENEMY)
	_respawn_left = respawn_time


func _draw() -> void:
	var r := Palette.ART_RADIUS
	if health.is_dead():
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Palette.INK_SOFT, 2.0, true)
		return
	Sketch.hatch_shadow(self, Vector2(0.0, r + 6.0), r - 2.0)
	Sketch.blob(self, Vector2.ZERO, r, Palette.WHITE if _flash > 0.0 else Palette.ENEMY)
	draw_circle(Vector2.ZERO, 6.0, Palette.WHITE)
	draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 20, Palette.INK, 2.5, true)
	var ratio := health.current / health.max_health
	draw_arc(Vector2.ZERO, r + 8.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 32, Palette.INK, 3.0, true)

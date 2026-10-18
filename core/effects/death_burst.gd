class_name DeathBurst
extends Node2D
## Pop effect when something dies: pieces fly out and fade while a ring expands.
## Directions are fixed (evenly spaced), never random, so it cannot touch a seeded run.

const DURATION := 0.45
const PIECES := 9

var color := Palette.ENEMY
var radius := Palette.ART_RADIUS

var _elapsed := 0.0


## Adds a burst next to `origin` (same parent, same position).
static func spawn(origin: Node2D, burst_color: Color) -> DeathBurst:
	var burst := DeathBurst.new()
	burst.color = burst_color
	origin.get_parent().add_child(burst)
	burst.global_position = origin.global_position
	return burst


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var t := clampf(_elapsed / DURATION, 0.0, 1.0)
	var fade := 1.0 - t
	# Ease-out: fast at first, then slowing down.
	var travel := 1.0 - (1.0 - t) * (1.0 - t)

	draw_arc(Vector2.ZERO, lerpf(radius, radius * 2.6, travel), 0.0, TAU, 32,
		Color(Palette.INK, 0.5 * fade), 2.0, true)

	for i in PIECES:
		var angle := TAU * i / PIECES + 0.35 * (i % 2)
		var distance := lerpf(radius * 0.5, radius * (2.2 + 0.4 * (i % 3)), travel)
		var center := Vector2.RIGHT.rotated(angle) * distance
		var size := lerpf(7.0, 2.0, t)
		draw_circle(center, size, Color(color, fade))
		draw_arc(center, size, 0.0, TAU, 12, Color(Palette.INK, fade), 1.5, true)

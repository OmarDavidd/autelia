class_name SpawnMarker
extends Node2D
## Telegraphs a spawn with a shrinking ring, then replaces itself with the enemy.
## Gives the player a fair warning instead of enemies popping in on top of them.

var scene: PackedScene
var duration := 0.6
## Optional hook to adjust the enemy before it enters the tree.
var on_spawn: Callable

var _elapsed := 0.0


func _physics_process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		var enemy: Node2D = scene.instantiate()
		if on_spawn.is_valid():
			on_spawn.call(enemy)
		get_parent().add_child(enemy)
		enemy.global_position = global_position
		queue_free()


func _draw() -> void:
	var t := clampf(_elapsed / duration, 0.0, 1.0)
	var radius := lerpf(30.0, 16.0, t)
	var dashes := 10
	for i in dashes:
		var from := TAU * i / dashes + t * PI
		draw_arc(Vector2.ZERO, radius, from, from + TAU / dashes * 0.55, 6, Palette.ENEMY, 3.0, true)
	draw_circle(Vector2.ZERO, 6.0, Color(Palette.ENEMY, 0.5))

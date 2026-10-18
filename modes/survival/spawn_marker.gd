class_name SpawnMarker
extends Node2D
## Telegraphs a spawn with a shrinking ring, then replaces itself with the enemy.
## Gives the player a fair warning instead of enemies popping in on top of them.

var scene: PackedScene
var duration := 0.6

var _elapsed := 0.0


func _physics_process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		var enemy: Node2D = scene.instantiate()
		get_parent().add_child(enemy)
		enemy.global_position = global_position
		queue_free()


func _draw() -> void:
	var t := clampf(_elapsed / duration, 0.0, 1.0)
	draw_arc(Vector2.ZERO, lerpf(34.0, 14.0, t), 0.0, TAU, 32, Palette.ENEMY, 2.0, true)

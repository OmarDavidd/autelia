class_name TeammateMarkers
extends CanvasLayer
## Arrows at the screen edge pointing to teammates that are off screen, in their colors.
## Only living teammates get one; the local player never does.

const EDGE := 36.0
const SIZE := 16.0

var _mode: SurvivalMode
var _canvas: Control


func bind(mode: SurvivalMode) -> void:
	_mode = mode


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_markers)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


## Each marker: {"at": screen position on the edge, "dir": direction to the teammate, "color"}.
func markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _mode == null:
		return result
	var view := get_viewport().get_visible_rect()
	var inner := view.grow(-EDGE)
	var to_screen := get_viewport().get_canvas_transform()
	for mate in _mode.players:
		if mate == _mode.player or mate.health.is_dead():
			continue
		var on_screen: Vector2 = to_screen * mate.global_position
		if view.has_point(on_screen):
			continue
		var center := inner.get_center()
		var dir := (on_screen - center).normalized()
		# Walk from the center toward the teammate until the edge of the inner rect.
		var reach := INF
		if dir.x != 0.0:
			reach = minf(reach, (inner.size.x * 0.5) / absf(dir.x))
		if dir.y != 0.0:
			reach = minf(reach, (inner.size.y * 0.5) / absf(dir.y))
		result.append({"at": center + dir * reach, "dir": dir, "color": mate.color})
	return result


func offscreen_count() -> int:
	return markers().size()


func _draw_markers() -> void:
	for marker in markers():
		var tip: Vector2 = marker.at + marker.dir * SIZE
		var side: Vector2 = marker.dir.orthogonal() * SIZE * 0.7
		var points := PackedVector2Array([tip, marker.at - side, marker.at + side])
		_canvas.draw_colored_polygon(points, marker.color)
		points.append(tip)
		_canvas.draw_polyline(points, Palette.INK, 3.0, true)

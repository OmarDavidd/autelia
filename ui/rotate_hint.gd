class_name RotateHint
extends CanvasLayer
## Asks phone players to turn the screen sideways: the arena is landscape and would be tiny
## in portrait. Only shown on touchscreens, above everything, and gone once rotated.


static func needed(window_size: Vector2, touchscreen: bool) -> bool:
	return touchscreen and window_size.y > window_size.x


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_tree().root.size_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	visible = needed(Vector2(get_window().size), TouchControls.wanted())


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Palette.BACKGROUND
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var label := UiStyle.label(HORIZONTAL_ALIGNMENT_CENTER, 40)
	label.text = "Gira tu teléfono\npara jugar"
	label.add_theme_font_override("font", UiStyle.font(700))
	center.add_child(label)

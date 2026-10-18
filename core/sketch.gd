class_name Sketch
## Drawing helpers shared by every character so the style stays consistent:
## ink outlines, hatched shadows, eyes that look somewhere, and motion lines.

static var _diamond_boxes := {}


static func blob(ci: CanvasItem, center: Vector2, radius: float, fill: Color) -> void:
	ci.draw_circle(center, radius, fill)
	ci.draw_arc(center, radius, 0.0, TAU, 40, Palette.INK, Palette.OUTLINE_WIDTH, true)


## Diagonal strokes under a character, like a pen-drawn shadow.
static func hatch_shadow(ci: CanvasItem, center: Vector2, half_width: float) -> void:
	var x := center.x - half_width
	while x <= center.x + half_width - 5.0:
		ci.draw_line(Vector2(x, center.y + 5.0), Vector2(x + 5.0, center.y), Palette.INK_SOFT, 1.6, true)
		x += 7.0


static func ellipse(ci: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * i / 20.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	ci.draw_colored_polygon(points, color)


## Two white eyes whose pupils shift toward `look` (a unit vector).
static func eyes(ci: CanvasItem, center: Vector2, look: Vector2, spacing: float, size: Vector2) -> void:
	for side in [-1.0, 1.0]:
		var eye := center + Vector2(side * spacing, 0.0)
		ellipse(ci, eye, size, Palette.WHITE)
		ci.draw_circle(eye + look * size.x * 0.45, size.x * 0.55, Palette.INK)


## A rounded bar from `from` to `to`, used for guns.
static func capsule(ci: CanvasItem, from: Vector2, to: Vector2, width: float, color: Color) -> void:
	ci.draw_line(from, to, color, width)
	ci.draw_circle(from, width * 0.5, color)
	ci.draw_circle(to, width * 0.5, color)


## Short parallel strokes behind something moving along `direction`.
static func motion_lines(ci: CanvasItem, direction: Vector2, radius: float) -> void:
	var side := direction.orthogonal() * radius * 0.6
	var start := -direction * (radius + 3.0)
	var end := -direction * (radius + 13.0)
	for offset in [side, -side]:
		ci.draw_line(start + offset, end + offset, Palette.INK_SOFT, 2.0, true)


## Rounded square outline for the shooter, cached per fill color (its size never changes;
## callers scale the drawing transform instead).
static func _diamond_box(fill: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = _diamond_boxes.get(fill)
	if box == null:
		box = StyleBoxFlat.new()
		box.bg_color = fill
		box.border_color = Palette.INK
		box.set_border_width_all(int(Palette.OUTLINE_WIDTH))
		box.set_corner_radius_all(int(Palette.ART_RADIUS * 0.41))
		box.anti_aliasing = true
		_diamond_boxes[fill] = box
	return box


# Character art. Each function draws around `at`, scaled by `size`; `pop` swells the body
# (hit feedback) but not the shadow. They all leave the identity transform when done.

static func draw_player(ci: CanvasItem, aim: Vector2, at := Vector2.ZERO, size := 1.0,
		fill := Palette.PLAYER) -> void:
	var r := Palette.ART_RADIUS
	ci.draw_set_transform(at, 0.0, Vector2.ONE * size)
	hatch_shadow(ci, Vector2(0.0, r + 6.0), r - 2.0)
	capsule(ci, aim * (r - 6.0), aim * (r + 12.0), 11.0, Palette.INK)
	blob(ci, Vector2.ZERO, r, fill)
	eyes(ci, Vector2(0.0, -4.0), aim, 6.0, Vector2(4.0, 5.5))
	var blush := Color(Palette.ENEMY, 0.45)
	ellipse(ci, Vector2(-10.0, 5.0), Vector2(3.2, 2.0), blush)
	ellipse(ci, Vector2(10.0, 5.0), Vector2(3.2, 2.0), blush)
	ci.draw_set_transform(Vector2.ZERO)


static func draw_chaser(ci: CanvasItem, look: Vector2, fill: Color, at := Vector2.ZERO,
		size := 1.0, pop := 1.0) -> void:
	var r := Palette.ART_RADIUS
	ci.draw_set_transform(at, 0.0, Vector2.ONE * size)
	hatch_shadow(ci, Vector2(0.0, r + 6.0), r - 2.0)
	ci.draw_set_transform(at, 0.0, Vector2.ONE * size * pop)
	blob(ci, Vector2.ZERO, r, fill)
	# Angry brows, eyes that track the target, small frown.
	ci.draw_line(Vector2(-10, -9), Vector2(-3, -5), Palette.INK, 3.0, true)
	ci.draw_line(Vector2(10, -9), Vector2(3, -5), Palette.INK, 3.0, true)
	ci.draw_circle(Vector2(-6, 0) + look * 1.5, 3.2, Palette.INK)
	ci.draw_circle(Vector2(6, 0) + look * 1.5, 3.2, Palette.INK)
	ci.draw_arc(Vector2(0, 12), 5.0, PI * 1.2, PI * 1.8, 8, Palette.INK, 2.5, true)
	ci.draw_set_transform(Vector2.ZERO)


static func draw_shooter(ci: CanvasItem, aim: Vector2, look: Vector2, fill: Color,
		at := Vector2.ZERO, size := 1.0, pop := 1.0) -> void:
	var r := Palette.ART_RADIUS
	var half := r * 0.82
	ci.draw_set_transform(at, 0.0, Vector2.ONE * size)
	hatch_shadow(ci, Vector2(0.0, r + 8.0), r)
	ci.draw_set_transform(at, 0.0, Vector2.ONE * size * pop)
	capsule(ci, aim * (r - 4.0), aim * (r + 12.0), 9.0, Palette.INK)
	ci.draw_set_transform(at, PI / 4.0, Vector2.ONE * size * pop)
	ci.draw_style_box(_diamond_box(fill), Rect2(-half, -half, half * 2.0, half * 2.0))
	# One big eye that follows the target.
	ci.draw_set_transform(at, 0.0, Vector2.ONE * size * pop)
	ci.draw_circle(Vector2.ZERO, 7.5, Palette.WHITE)
	ci.draw_arc(Vector2.ZERO, 7.5, 0.0, TAU, 24, Palette.INK, 2.5, true)
	ci.draw_circle(look * 2.5, 3.0, Palette.INK)
	ci.draw_set_transform(Vector2.ZERO)

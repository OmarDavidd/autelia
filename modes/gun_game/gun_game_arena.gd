class_name GunGameArena
extends Node2D
## Symmetrical arena for Gun Game. Uses a seed to place ink covers with 180-degree
## rotational symmetry so no spawn corner has an unfair advantage.

@export var size := Vector2(2160, 1260)
@export var margin := 32.0
@export var wall_thickness := 64.0

var arena_seed := 0
var obstacles: Array[Rect2] = []
var _walls_body: StaticBody2D


func _init(seed_value := 0) -> void:
	arena_seed = seed_value


func _ready() -> void:
	_generate_obstacles()
	_build_physics()


func play_rect() -> Rect2:
	return Rect2(Vector2(margin, margin), size - Vector2(margin, margin) * 2.0)


## Safe spawn points distributed around the arena corners and flanks.
func get_spawn_points() -> Array[Vector2]:
	var r := play_rect()
	var inset := 100.0
	return [
		Vector2(r.position.x + inset, r.position.y + inset),
		Vector2(r.end.x - inset, r.position.y + inset),
		Vector2(r.end.x - inset, r.end.y - inset),
		Vector2(r.position.x + inset, r.end.y - inset),
		Vector2(size.x * 0.5, r.position.y + inset),
		Vector2(size.x * 0.5, r.end.y - inset),
		Vector2(r.position.x + inset, size.y * 0.5),
		Vector2(r.end.x - inset, size.y * 0.5),
		Vector2(size.x * 0.28, size.y * 0.3),
		Vector2(size.x * 0.72, size.y * 0.3),
		Vector2(size.x * 0.28, size.y * 0.7),
		Vector2(size.x * 0.72, size.y * 0.7),
	]


## Picks the spawn point furthest from any living opponent to avoid spawn camping.
func find_safest_spawn(opponents: Array) -> Vector2:
	var spawns := get_spawn_points()
	var active := opponents.filter(func(p: Variant) -> bool:
		if p is Player:
			return not p.health.is_dead()
		return is_instance_valid(p)
	)
	if active.is_empty():
		return spawns[0]

	var best_spawn := spawns[0]
	var largest_min_distance := -1.0
	for spawn in spawns:
		var min_dist := INF
		for opponent in active:
			var dist := spawn.distance_to(opponent.global_position)
			if dist < min_dist:
				min_dist = dist
		if min_dist > largest_min_distance:
			largest_min_distance = min_dist
			best_spawn = spawn
	return best_spawn


func _generate_obstacles() -> void:
	obstacles.clear()
	var noise := FastNoiseLite.new()
	noise.seed = arena_seed
	noise.frequency = 0.32

	var center := size * 0.5
	var center_safe_radius := 260.0
	var spawn_safe_radius := 160.0
	var spawns := get_spawn_points()

	var cols := 15
	var rows := 9
	var cell_w := (size.x - margin * 4.0) / float(cols)
	var cell_h := (size.y - margin * 4.0) / float(rows)

	# Central courtyard pillars to break long cross-map sniper sightlines
	var cp_size := Vector2(80.0, 80.0)
	var cp_offsets := [
		Vector2(-140.0, -95.0),
		Vector2(140.0, -95.0),
		Vector2(-140.0, 95.0),
		Vector2(140.0, 95.0),
	]
	for off in cp_offsets:
		obstacles.append(Rect2(center + off - cp_size * 0.5, cp_size))

	# Only iterate through top half to guarantee 180-degree rotational symmetry
	for r in range(rows / 2 + 1):
		for c in cols:
			var cx := margin * 2.0 + cell_w * (c + 0.5)
			var cy := margin * 2.0 + cell_h * (r + 0.5)
			var pos := Vector2(cx, cy)

			# Leave courtyard transit space open
			if pos.distance_to(center) < 220.0:
				continue

			# Leave spawn zones completely clear
			var near_spawn := spawns.any(func(s: Vector2) -> bool: return s.distance_to(pos) < spawn_safe_radius)
			if near_spawn:
				continue

			if noise.get_noise_2d(float(c * 10), float(r * 10)) > 0.16:
				var obs_size := Vector2(80.0, 80.0)
				var rect1 := Rect2(pos - obs_size * 0.5, obs_size)
				var mirror_pos := size - pos
				var rect2 := Rect2(mirror_pos - obs_size * 0.5, obs_size)

				if not _overlaps_any(rect1):
					obstacles.append(rect1)
				if not _overlaps_any(rect2):
					obstacles.append(rect2)


func _overlaps_any(new_rect: Rect2) -> bool:
	for existing in obstacles:
		if existing.grow(30.0).intersects(new_rect):
			return true
	return false


func _build_physics() -> void:
	_walls_body = StaticBody2D.new()
	_walls_body.name = "Walls"
	_walls_body.collision_layer = 1
	_walls_body.collision_mask = 0
	add_child(_walls_body)

	# 1. Outer boundary walls
	var rect := play_rect()
	var t := wall_thickness
	var sides := [
		Rect2(rect.position.x - t, rect.position.y - t, rect.size.x + t * 2.0, t),
		Rect2(rect.position.x - t, rect.end.y, rect.size.x + t * 2.0, t),
		Rect2(rect.position.x - t, rect.position.y, t, rect.size.y),
		Rect2(rect.end.x, rect.position.y, t, rect.size.y),
	]
	for side: Rect2 in sides:
		var shape := RectangleShape2D.new()
		shape.size = side.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = side.get_center()
		_walls_body.add_child(collider)

	# 2. Symmetric interior cover pillars
	for obs in obstacles:
		var shape := RectangleShape2D.new()
		shape.size = obs.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = obs.get_center()
		_walls_body.add_child(collider)


func _draw() -> void:
	var rect := play_rect()
	var floor_box := StyleBoxFlat.new()
	floor_box.bg_color = Palette.FLOOR
	floor_box.border_color = Palette.INK
	floor_box.set_border_width_all(5)
	floor_box.set_corner_radius_all(24)
	floor_box.anti_aliasing = true
	draw_style_box(floor_box, rect.grow(5.0))

	# Floor dot pattern
	var dot := Color(Palette.INK, 0.08)
	var y := rect.position.y + 20.0
	while y < rect.end.y:
		var x := rect.position.x + 20.0
		while x < rect.end.x:
			draw_circle(Vector2(x, y), 2.5, dot)
			x += 40.0
		y += 40.0

	# Draw obstacles with ink borders and hatched shadows
	for obs in obstacles:
		var obs_box := StyleBoxFlat.new()
		obs_box.bg_color = Palette.BACKGROUND
		obs_box.border_color = Palette.INK
		obs_box.set_border_width_all(4)
		obs_box.set_corner_radius_all(10)
		obs_box.anti_aliasing = true
		draw_style_box(obs_box, obs)

		# Subtle interior cross hatch
		var inset := 8.0
		draw_line(obs.position + Vector2(inset, inset), obs.end - Vector2(inset, inset), Palette.INK_SOFT, 1.5)
		draw_line(Vector2(obs.end.x - inset, obs.position.y + inset), Vector2(obs.position.x + inset, obs.end.y - inset), Palette.INK_SOFT, 1.5)

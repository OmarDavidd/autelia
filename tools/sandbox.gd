class_name Sandbox
## Minimal world (arena + player, no mode rules or enemies) for tests and scripted captures.

const PLAYER_SCENE := preload("res://core/player/player.tscn")


static func create(parent: Node, player_position := Vector2(640, 360)) -> Dictionary:
	var world := Node2D.new()
	world.name = "Sandbox"
	parent.add_child(world)
	var arena := Arena.new()
	world.add_child(arena)
	var player: Player = PLAYER_SCENE.instantiate()
	world.add_child(player)
	player.global_position = player_position
	return {"world": world, "arena": arena, "player": player}


static func spawn(world: Node, scene_path: String, at: Vector2) -> Node2D:
	var node: Node2D = load(scene_path).instantiate()
	world.add_child(node)
	node.global_position = at
	return node

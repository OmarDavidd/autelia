extends Node
## Stage 2 smoke test: shooting, hits, invulnerability, death.
## Run: godot --headless --path . tests/smoke_stage2.tscn

const PHYSICS_FPS := 60

var shots := 0
var hits := 0
var player_damage_events := 0
var player_deaths := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: Array[String] = []
	Events.shot_fired.connect(func(_shooter: Node) -> void: shots += 1)
	Events.enemy_hit.connect(func(_enemy: Node, _damage: float) -> void: hits += 1)
	Events.player_damaged.connect(func(_amount: float, _left: float) -> void: player_damage_events += 1)
	Events.player_died.connect(func() -> void: player_deaths += 1)

	var sandbox := Sandbox.create(self)
	var player: Player = sandbox.player
	await get_tree().physics_frame

	# Headless has no real mouse, so put a target on the line the player is aiming at.
	await get_tree().physics_frame
	var aim := Vector2.RIGHT.rotated(player.body.rotation)
	var dummy: TargetDummy = Sandbox.spawn(sandbox.world, "res://core/enemies/target_dummy.tscn",
		player.global_position + aim * 180.0)

	# 1 second of holding fire at 8 shots/s.
	Input.action_press("shoot")
	for i in PHYSICS_FPS:
		await get_tree().physics_frame
	Input.action_release("shoot")
	for i in 20:
		await get_tree().physics_frame
	if shots < 7 or shots > 9:
		failures.append("expected ~8 shots in 1 s, got %d" % shots)
	if hits == 0:
		failures.append("no bullet hit the target")
	if dummy.health.current >= dummy.health.max_health and not dummy.health.is_dead():
		failures.append("target health did not drop")

	# Invulnerability: a second hit right away is ignored, a hit after 0.6 s lands.
	player.take_hit(10.0)
	player.take_hit(10.0)
	if player.health.current != 90.0:
		failures.append("second hit during invulnerability applied (health %.1f)" % player.health.current)
	for i in int(PHYSICS_FPS * 0.7):
		await get_tree().physics_frame
	player.take_hit(10.0)
	if player.health.current != 80.0:
		failures.append("hit after invulnerability not applied (health %.1f)" % player.health.current)
	if player_damage_events != 2:
		failures.append("expected 2 player_damaged events, got %d" % player_damage_events)

	for i in int(PHYSICS_FPS * 0.7):
		await get_tree().physics_frame
	player.take_hit(1000.0)
	if player_deaths != 1 or not player.health.is_dead():
		failures.append("player did not die")

	if failures.is_empty():
		print("SMOKE OK: shots=%d hits=%d target=%.0f/%.0f player=%.0f dead=%s" % [
			shots, hits, dummy.health.current, dummy.health.max_health,
			player.health.current, player.health.is_dead()])
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)

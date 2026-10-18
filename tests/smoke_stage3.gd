extends Node
## Stage 3 smoke test: chaser and shooter behavior, enemy death events.
## Run: godot --headless --path . tests/smoke_stage3.tscn

const CHASER := "res://core/enemies/chaser.tscn"
const SHOOTER := "res://core/enemies/shooter.tscn"

var failures: Array[String] = []
var event_log: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Events.enemy_hit.connect(func(_enemy: Node, _damage: float) -> void: event_log.append("hit"))
	Events.enemy_killed.connect(func(_enemy: Node) -> void: event_log.append("killed"))

	await _chaser_approaches_and_hurts()
	await _shooter_keeps_distance_and_hits()
	await _killing_blow_reports_hit_then_death()

	if failures.is_empty():
		print("SMOKE OK: chaser, shooter and death events behave as expected")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _chaser_approaches_and_hurts() -> void:
	var sandbox := Sandbox.create(self)
	var player: Player = sandbox.player
	var chaser := Sandbox.spawn(sandbox.world, CHASER, Vector2(900, 360))
	var start := chaser.global_position.distance_to(player.global_position)
	await _frames(60)
	var after := chaser.global_position.distance_to(player.global_position)
	if after >= start:
		failures.append("chaser did not approach (%.0f -> %.0f)" % [start, after])
	await _frames(120)
	if player.health.current >= player.health.max_health:
		failures.append("chaser contact did not damage the player")
	sandbox.world.queue_free()
	await _frames(2)


func _shooter_keeps_distance_and_hits() -> void:
	var sandbox := Sandbox.create(self)
	var player: Player = sandbox.player
	var shooter: Shooter = Sandbox.spawn(sandbox.world, SHOOTER, Vector2(700, 360))
	await _frames(150)
	var distance := shooter.global_position.distance_to(player.global_position)
	if distance < shooter.preferred_distance - shooter.distance_tolerance - 20.0:
		failures.append("shooter did not back off (distance %.0f)" % distance)
	await _frames(150)
	if player.health.current >= player.health.max_health:
		failures.append("shooter bullets did not damage the player")
	sandbox.world.queue_free()
	await _frames(2)


func _killing_blow_reports_hit_then_death() -> void:
	var sandbox := Sandbox.create(self)
	var chaser: Enemy = Sandbox.spawn(sandbox.world, CHASER, Vector2(1000, 120))
	event_log.clear()
	chaser.take_hit(1000.0)
	await _frames(2)
	if event_log != ["hit", "killed"]:
		failures.append("expected [hit, killed], got %s" % [event_log])
	if is_instance_valid(chaser):
		failures.append("dead enemy was not removed")
	sandbox.world.queue_free()
	await _frames(2)

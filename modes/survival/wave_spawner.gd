class_name WaveSpawner
extends Node
## Runs fixed-length waves separated by short breaks and spawns enemies during each wave.
## Every random choice goes through the injected RNG, so a seed reproduces the same
## sequence of enemy types and spawn points.

signal spawned(scene_path: String, at: Vector2)

const CHASER := preload("res://core/enemies/chaser.tscn")
const SHOOTER := preload("res://core/enemies/shooter.tscn")

@export var wave_duration := 30.0
@export var break_duration := 3.0
@export var first_break := 2.0
## Overwritten by a difficulty director when the scene has one (see DifficultyParams).
@export var spawn_interval := 1.4
@export var max_alive := 12
@export var shooter_chance := 0.3
@export var min_player_distance := 220.0
@export var telegraph_time := 0.6

## Set by whoever controls difficulty. Applied to enemies as they spawn.
var speed_multiplier := 1.0
var fire_rate_multiplier := 1.0
var health_multiplier := 1.0

## Co-op: more players, more enemies. Divides the spawn interval and multiplies the cap.
var crowd := 1.0

var wave := 0
var running := false

var _rng: RandomNumberGenerator
var _arena: Arena
var _players: Array[Player]
var _container: Node2D
var _time_left := 0.0
var _spawn_timer := 0.0
var _in_break := true


## `players` is kept by reference, so teammates added later are seen too.
func start(rng: RandomNumberGenerator, arena: Arena, players: Array[Player], container: Node2D) -> void:
	_rng = rng
	_arena = arena
	_players = players
	_container = container
	wave = 0
	_in_break = true
	_time_left = first_break
	running = true


func stop() -> void:
	running = false


func in_break() -> bool:
	return _in_break


func time_left() -> float:
	return maxf(_time_left, 0.0)


## Enemies plus pending spawns. Enemy bullets share the container and are not counted.
func alive_count() -> int:
	var count := 0
	for child in _container.get_children():
		if child is Enemy or child is SpawnMarker:
			count += 1
	return count


func _physics_process(delta: float) -> void:
	if not running:
		return
	_time_left -= delta
	if _in_break:
		if _time_left <= 0.0:
			_begin_wave()
		return

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer += spawn_interval / crowd
		if alive_count() < roundi(max_alive * crowd):
			_spawn_one()
	if _time_left <= 0.0:
		_end_wave()


func _begin_wave() -> void:
	wave += 1
	_in_break = false
	_time_left = wave_duration
	_spawn_timer = 0.0
	Events.wave_started.emit(wave)


func _end_wave() -> void:
	Events.wave_ended.emit(wave)
	# Leftover enemies are removed, not killed: they do not count as player kills.
	for child in _container.get_children():
		child.queue_free()
	_in_break = true
	_time_left = break_duration


func _spawn_one() -> void:
	var scene := SHOOTER if _rng.randf() < shooter_chance else CHASER
	var at := _pick_position()
	var marker := SpawnMarker.new()
	marker.scene = scene
	marker.duration = telegraph_time
	marker.on_spawn = _tune
	_container.add_child(marker)
	marker.global_position = at
	spawned.emit(scene.resource_path, at)


## Scales a freshly instantiated enemy before it enters the tree (Health resets on ready).
func _tune(enemy: Node) -> void:
	if enemy is Enemy:
		enemy.speed *= speed_multiplier
		var health: Health = enemy.get_node("Health")
		health.max_health *= health_multiplier
	if enemy is Shooter:
		var weapon: Weapon = enemy.get_node("Pivot/Weapon")
		weapon.fire_rate *= fire_rate_multiplier


## Always uses exactly two RNG draws, so the random sequence does not depend on
## where the players are. A point too close to a living player is mirrored across the arena.
func _pick_position() -> Vector2:
	var rect := _arena.play_rect().grow(-40.0)
	var at := Vector2(
		_rng.randf_range(rect.position.x, rect.end.x),
		_rng.randf_range(rect.position.y, rect.end.y))
	for player in _players:
		if not player.health.is_dead() and at.distance_to(player.global_position) < min_player_distance:
			at = rect.get_center() * 2.0 - at
			break
	return at

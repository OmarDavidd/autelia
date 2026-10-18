class_name SurvivalMode
extends Node2D
## Wave survival rules: owns the run's RNG, starts the spawner, ends the run when every
## player is down. In co-op, a fallen player revives at the start of the next wave.
##
## Seed: `--seed=N` on the command line (after `--`) wins, then `run_seed`; 0 means random.
## The seed actually used is printed and kept in `used_seed` so any run can be replayed.

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const MAX_PLAYERS := 8
const REVIVE_HEALTH := 0.5
## Where teammates appear, around the first player.
const TEAMMATE_OFFSETS: Array[Vector2] = [
	Vector2.ZERO, Vector2(60, 0), Vector2(-60, 0), Vector2(0, 60),
	Vector2(0, -60), Vector2(60, 60), Vector2(-60, 60), Vector2(60, -60),
]

@export var run_seed := 0

@onready var arena: Arena = $Arena
@onready var player: Player = $Player
@onready var enemies: Node2D = $Enemies
@onready var spawner: WaveSpawner = $Spawner
@onready var hud: Hud = $Hud

var rng := RandomNumberGenerator.new()
var used_seed := 0
## Every player in the arena; the first one is this machine's.
var players: Array[Player] = []


func _ready() -> void:
	used_seed = _resolve_seed()
	rng.seed = used_seed
	print("Run seed: ", used_seed)
	players.append(player)
	Events.player_died.connect(_on_player_died)
	Events.wave_started.connect(_on_wave_started)
	spawner.start(rng, arena, players, enemies)
	hud.bind(self)


## Adds a teammate driven by `input`, in the next free color. Returns null when full.
func add_player(input: PlayerInput) -> Player:
	if players.size() >= MAX_PLAYERS:
		return null
	var mate: Player = PLAYER_SCENE.instantiate()
	mate.input = input
	mate.color = Palette.PLAYER_COLORS[players.size()]
	mate.position = player.position + TEAMMATE_OFFSETS[players.size()]
	add_child(mate)
	players.append(mate)
	return mate


func living_players() -> Array[Player]:
	return players.filter(func(each: Player) -> bool: return not each.health.is_dead())


func is_over() -> bool:
	return living_players().is_empty()


## Replays a chosen seed instead (the daily challenge). Only valid before anything spawns.
func reseed(value: int) -> void:
	used_seed = value
	rng.seed = used_seed
	print("Run seed: ", used_seed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and is_over():
		get_tree().reload_current_scene()


func _resolve_seed() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			return int(arg.get_slice("=", 1))
	if run_seed != 0:
		return run_seed
	var random := RandomNumberGenerator.new()
	random.randomize()
	return random.randi()


func _on_wave_started(_index: int) -> void:
	if is_over():
		return
	for each in players:
		if each.health.is_dead():
			each.revive(REVIVE_HEALTH)


func _on_player_died() -> void:
	spawner.stop()

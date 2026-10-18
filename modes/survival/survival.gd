class_name SurvivalMode
extends Node2D
## Wave survival rules: owns the run's RNG, starts the spawner, ends the run when the player dies.
##
## Seed: `--seed=N` on the command line (after `--`) wins, then `run_seed`; 0 means random.
## The seed actually used is printed and kept in `used_seed` so any run can be replayed.

@export var run_seed := 0

@onready var arena: Arena = $Arena
@onready var player: Player = $Player
@onready var enemies: Node2D = $Enemies
@onready var spawner: WaveSpawner = $Spawner
@onready var hud: Hud = $Hud

var rng := RandomNumberGenerator.new()
var used_seed := 0


func _ready() -> void:
	used_seed = _resolve_seed()
	rng.seed = used_seed
	print("Run seed: ", used_seed)
	Events.player_died.connect(_on_player_died)
	spawner.start(rng, arena, player, enemies)
	hud.bind(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and player.health.is_dead():
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


func _on_player_died() -> void:
	spawner.stop()

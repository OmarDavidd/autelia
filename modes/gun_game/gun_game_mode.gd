class_name GunGameMode
extends Node2D
## Orchestrator for the Gun Game mode.
## Spawns the symmetric arena, local player, and bot opponents.
## Tracks weapon progression, respawns fallen combatants in safe spots, and detects the winner.

signal player_leveled(combatant: Player, new_level: int)
signal kill_logged(killer_name: String, victim_name: String, killer_color: Color, victim_color: Color)
signal match_finished(winner: Player, winner_name: String, winner_color: Color)

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const RESPAWN_DELAY := 2.6

const BOT_NAMES: Array[String] = [
	"Echo", "Vortex", "Cipher", "Nova", "Atlas", "Pixel", "Shadow"
]

@export var mode_seed := 0

var arena: GunGameArena
var local_player: Player
var combatants: Array[Player] = []
var levels: Dictionary = {} # Player -> int
var level_kills: Dictionary = {} # Player -> int
var total_kills: Dictionary = {} # Player -> int
var names: Dictionary = {} # Player -> String

var winner: Player = null
var is_finished := false


func _ready() -> void:
	if mode_seed == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		mode_seed = rng.randi()

	Events.player_killed.connect(_on_player_killed)


func setup_match(human_name: String, bot_count := 7) -> void:
	# 1. Spawn Symmetrical Arena
	arena = GunGameArena.new(mode_seed)
	arena.name = "Arena"
	add_child(arena)

	var spawns := arena.get_spawn_points()

	# 2. Spawn Local Player
	local_player = PLAYER_SCENE.instantiate()
	local_player.name = "LocalPlayer"
	local_player.input = LocalInput.new()
	local_player.color = Palette.PLAYER_COLORS[0]
	local_player.position = spawns[0]
	add_child(local_player)
	_register_combatant(local_player, "Tú" if human_name.is_empty() else human_name)

	# 3. Spawn Bot Competitors
	var bot_limit := mini(bot_count, 7)
	for i in bot_limit:
		var bot: Player = PLAYER_SCENE.instantiate()
		bot.name = "Bot%d" % (i + 1)
		bot.color = Palette.PLAYER_COLORS[i + 1]
		bot.input = GunGameBotInput.new(arena.size * 0.5, mode_seed + i + 101)
		bot.position = spawns[(i + 1) % spawns.size()]
		add_child(bot)
		var bname := BOT_NAMES[i % BOT_NAMES.size()]
		_register_combatant(bot, bname)


func _register_combatant(combatant: Player, display_name: String) -> void:
	combatants.append(combatant)
	names[combatant] = display_name
	levels[combatant] = 1
	level_kills[combatant] = 0
	# Movement speed restored to standard fluid speed
	combatant.speed = 260.0
	combatant.acceleration = 2200.0
	combatant.friction = 2600.0

	# Gun Game health tuning: fast, lethal combat without hit invulnerability delays
	combatant.health.max_health = GunGameRules.COMBATANT_MAX_HEALTH
	combatant.health.current = GunGameRules.COMBATANT_MAX_HEALTH
	combatant.health.invulnerability_time = 0.0

	# Configure weapon for FFA combat with starting weapon
	combatant.weapon.team = Weapon.Team.FFA
	combatant.weapon.apply_profile(GunGameRules.weapon_profile(1))


## The pause menu asks this: no pausing once someone has won.
func is_over() -> bool:
	return is_finished


func living_combatants() -> Array[Player]:
	return combatants.filter(func(p: Player) -> bool: return not p.health.is_dead())


func _on_player_killed(killer: Node, victim: Node) -> void:
	if is_finished or not (victim is Player):
		return

	var v_player: Player = victim
	var v_name: String = names.get(v_player, "Jugador")
	var v_color: Color = v_player.color

	var k_name := "Ambiente"
	var k_color := Palette.INK

	if killer is Player and killer in combatants:
		var k_player: Player = killer
		k_name = names.get(k_player, "Jugador")
		k_color = k_player.color

		if k_player != v_player:
			total_kills[k_player] = total_kills.get(k_player, 0) + 1
			level_kills[k_player] = level_kills.get(k_player, 0) + 1

			var cur_level: int = levels.get(k_player, 1)
			var needed := GunGameRules.kills_to_advance(cur_level)

			if level_kills[k_player] >= needed:
				if cur_level >= GunGameRules.MAX_LEVEL:
					# Winner crowned!
					_crown_winner(k_player)
				else:
					# Level up!
					var next_level := cur_level + 1
					levels[k_player] = next_level
					level_kills[k_player] = 0
					k_player.weapon.apply_profile(GunGameRules.weapon_profile(next_level))
					player_leveled.emit(k_player, next_level)

	kill_logged.emit(k_name, v_name, k_color, v_color)

	# Schedule safe respawn for victim. A child timer stops while paused and goes away with
	# the match, so a restart never fires a respawn into a freed mode.
	if not is_finished:
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = RESPAWN_DELAY
		add_child(timer)
		timer.timeout.connect(func() -> void:
			timer.queue_free()
			if is_instance_valid(v_player) and not is_finished:
				_respawn_player(v_player)
		)
		timer.start()


func _respawn_player(p: Player) -> void:
	var safe_pos := arena.find_safest_spawn(living_combatants())
	p.global_position = safe_pos
	p.revive(1.0)


func _crown_winner(p: Player) -> void:
	is_finished = true
	winner = p
	# Everything stops behind the victory panel; its buttons keep working (the HUD always runs).
	get_tree().paused = true
	match_finished.emit(winner, names.get(winner, "Jugador"), winner.color)

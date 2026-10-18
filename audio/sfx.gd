extends Node
## Plays sound effects in response to gameplay events. Purely presentational: it never
## changes game state, and its pitch variation uses its own RNG so it cannot alter a seeded run.
## `--mute` on the command line (after `--`) silences it, and so does headless mode, which has
## no audio output (and would otherwise report voices still playing at quit as leaks).

const SOUNDS := {
	"shoot": preload("res://assets/audio/shoot.wav"),
	"enemy_shoot": preload("res://assets/audio/enemy_shoot.wav"),
	"enemy_hit": preload("res://assets/audio/enemy_hit.wav"),
	"enemy_death": preload("res://assets/audio/enemy_death.wav"),
	"player_hurt": preload("res://assets/audio/player_hurt.wav"),
	"wave_start": preload("res://assets/audio/wave_start.wav"),
	"game_over": preload("res://assets/audio/game_over.wav"),
}
const VOLUME_DB := {
	"shoot": -16.0,
	"enemy_shoot": -12.0,
	"enemy_hit": -9.0,
	"enemy_death": -6.0,
	"player_hurt": -4.0,
	"wave_start": -6.0,
	"game_over": -4.0,
}

var muted := false
## Last sound requested, for tests and debugging.
var last_played := ""

var _players := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	muted = "--mute" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless"
	for sound: String in SOUNDS:
		var player := AudioStreamPlayer.new()
		player.stream = SOUNDS[sound]
		player.volume_db = VOLUME_DB[sound]
		player.max_polyphony = 6
		add_child(player)
		_players[sound] = player

	Events.shot_fired.connect(func(shooter: Node) -> void:
		play("shoot" if shooter is Player else "enemy_shoot", 0.06))
	Events.enemy_hit.connect(func(_enemy: Node, _damage: float) -> void: play("enemy_hit", 0.1))
	Events.enemy_killed.connect(func(_enemy: Node) -> void: play("enemy_death", 0.08))
	Events.player_damaged.connect(func(_amount: float, _left: float) -> void: play("player_hurt"))
	Events.wave_started.connect(func(_index: int) -> void: play("wave_start"))
	Events.player_died.connect(func() -> void: play("game_over"))


func play(sound: String, pitch_jitter := 0.0) -> void:
	last_played = sound
	if muted:
		return
	var player: AudioStreamPlayer = _players[sound]
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	player.play()


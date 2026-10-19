extends Node
## Co-op smoke test (stage 1, no network): input sources, several players, nearest-player
## targeting, down and revive at the next wave, team wipe, HUD team state and bot teammates.
## Run: godot --headless --path . tests/smoke_coop.tscn

const SURVIVAL := "res://modes/survival/survival.tscn"
const CHASER := "res://core/enemies/chaser.tscn"
const PROFILE := "user://test_profile.cfg"

var failures: Array[String] = []
var downs: Array[Player] = []
var revives: Array[Player] = []
var wipes := 0


func _ready() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## The HUD writes its labels in _process. A slow first frame runs several physics steps
## before any process frame, and process_frame fires before nodes process, so wait two.
func _hud_updated() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	GameSession.profile_path = PROFILE
	Leaderboard.enabled = false
	Events.player_down.connect(func(player: Player) -> void: downs.append(player))
	Events.player_revived.connect(func(player: Player) -> void: revives.append(player))
	Events.player_died.connect(func() -> void: wipes += 1)

	await _scripted_input_drives_the_player()
	await _players_get_colors_and_enemies_chase_the_nearest()
	await _down_revive_and_wipe()
	await _spawn_point_uses_two_draws()
	await _bots_join_arcade_without_the_leaderboard()
	await _bots_play_like_people()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	GameSession.mode = GameSession.Mode.EXPERIMENT
	GameSession.bots_override = -1

	get_tree().paused = false
	if failures.is_empty():
		print("SMOKE OK: co-op players move on their own input, share the arena, revive and wipe as a team")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _make_run() -> SurvivalMode:
	var mode: SurvivalMode = load(SURVIVAL).instantiate()
	mode.run_seed = 7
	var spawner: WaveSpawner = mode.get_node("Spawner")
	spawner.first_break = 999.0
	mode.get_node("Telemetry").output_dir = "user://test_telemetry"
	add_child(mode)
	return mode


func _free(node: Node) -> void:
	node.queue_free()
	await _frames(2)


func _scripted_input_drives_the_player() -> void:
	var mode := _make_run()
	await _frames(1)
	_expect(mode.player.input is LocalInput, "the first player must use the keyboard and mouse")
	_expect(mode.players.size() == 1 and mode.players[0] == mode.player, "a run starts with one player")

	var input := ScriptedInput.new()
	var mate := mode.add_player(input)
	await _frames(1)
	var start := mate.global_position
	var local_start := mode.player.global_position
	input.move = Vector2.RIGHT
	input.aim = mate.global_position + Vector2.DOWN * 10000.0
	await _frames(20)
	_expect(mate.global_position.x > start.x + 20.0, "scripted input did not move its player")
	_expect(mode.player.global_position.distance_to(local_start) < 1.0, "the local player moved with someone else's input")
	_expect(Vector2.RIGHT.rotated(mate.body.rotation).dot(Vector2.DOWN) > 0.9, "scripted aim not followed")

	var shots := [0]
	var count := func(shooter: Node) -> void:
		if shooter == mate:
			shots[0] += 1
	Events.shot_fired.connect(count)
	input.shoot = true
	await _frames(20)
	Events.shot_fired.disconnect(count)
	_expect(shots[0] > 0, "scripted shooting did not fire")
	await _free(mode)


func _players_get_colors_and_enemies_chase_the_nearest() -> void:
	var mode := _make_run()
	await _frames(1)
	var colors := {mode.player.color: true}
	for i in SurvivalMode.MAX_PLAYERS - 1:
		var extra := mode.add_player(ScriptedInput.new())
		colors[extra.color] = true
	_expect(mode.players.size() == 8, "up to eight players must fit, got %d" % mode.players.size())
	_expect(colors.size() == 8, "each player needs its own color")
	_expect(mode.add_player(ScriptedInput.new()) == null and mode.players.size() == 8, "a ninth player must be refused")
	_expect(mode.player.color == Palette.PLAYER, "the first player keeps the classic green")
	await _free(mode)

	mode = _make_run()
	await _frames(1)
	var far := mode.add_player(ScriptedInput.new())
	mode.player.global_position = Vector2(200, 360)
	far.global_position = Vector2(1080, 360)
	var chaser: Enemy = load(CHASER).instantiate()
	chaser.position = Vector2(1000, 360)
	mode.enemies.add_child(chaser)
	await _frames(3)
	_expect(chaser.target == far, "the chaser must go for the nearest player")
	far.health.invulnerable_left = 0.0
	far.take_hit(10000.0)
	await _frames(Enemy.RETARGET_FRAMES + 2)
	_expect(chaser.target == mode.player, "the chaser must switch to a living player when its target falls")
	await _free(mode)


func _down_revive_and_wipe() -> void:
	var mode := _make_run()
	await _frames(1)
	var mate := mode.add_player(ScriptedInput.new())
	downs.clear()
	revives.clear()
	wipes = 0

	mate.take_hit(10000.0)
	await _frames(2)
	_expect(downs == [mate], "a fallen player must report player_down")
	_expect(wipes == 0, "one fallen player out of two must not end the run")
	_expect(not mode.is_over(), "run over with a teammate standing")
	_expect(mate.collision_layer == 0, "a fallen player must not block or be hit")
	_expect(mode.living_players() == [mode.player], "living players: %s" % str(mode.living_players()))

	Events.wave_started.emit(2)
	await _frames(1)
	_expect(revives == [mate], "the fallen player must revive when the next wave starts")
	_expect(not mate.health.is_dead() and is_equal_approx(mate.health.current, mate.health.max_health * 0.5),
		"revive must give half health, got %.1f" % mate.health.current)
	_expect(mate.collision_layer != 0, "a revived player must collide again")
	_expect(mate.health.is_invulnerable(), "a revived player needs a moment of invulnerability")

	mate.health.invulnerable_left = 0.0
	mode.player.take_hit(10000.0)
	await _frames(1)
	_expect(wipes == 0, "run ended with the revived teammate standing")
	mate.take_hit(10000.0)
	await _frames(2)
	_expect(wipes == 1, "the run must end once when everybody is down, got %d" % wipes)
	_expect(mode.is_over(), "run not over with everybody down")
	revives.clear()
	Events.wave_started.emit(3)
	await _frames(1)
	_expect(revives.is_empty(), "nobody revives after the team is wiped")
	await _free(mode)


func _spawn_point_uses_two_draws() -> void:
	var mode: SurvivalMode = load(SURVIVAL).instantiate()
	add_child(mode)
	var extra := mode.add_player(ScriptedInput.new())
	extra.global_position = Vector2(300, 300)
	var spawner := mode.spawner
	var reference := RandomNumberGenerator.new()
	reference.seed = 99
	reference.randf()
	reference.randf()
	mode.rng.seed = 99
	spawner._pick_position()
	_expect(mode.rng.state == reference.state, "a spawn point must use exactly two RNG draws with several players")

	# A point too close to one player, whose mirror lands on another, must avoid both.
	var rect := mode.arena.play_rect().grow(-40.0)
	var raw_rng := RandomNumberGenerator.new()
	raw_rng.seed = 1234
	var raw := Vector2(raw_rng.randf_range(rect.position.x, rect.end.x), raw_rng.randf_range(rect.position.y, rect.end.y))
	mode.player.global_position = raw
	extra.global_position = rect.get_center() * 2.0 - raw
	mode.rng.seed = 1234
	var at := spawner._pick_position()
	var nearest := minf(at.distance_to(mode.player.global_position), at.distance_to(extra.global_position))
	_expect(nearest >= spawner.min_player_distance,
		"spawn landed %.0f px from a player (min %.0f)" % [nearest, spawner.min_player_distance])
	mode.queue_free()
	await _frames(2)


func _bots_join_arcade_without_the_leaderboard() -> void:
	GameSession.bots_override = 2
	GameSession.save_name("Ana")
	MainMenu.seen = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_arcade()
	menu.start_arcade()
	await _frames(2)
	var mode: SurvivalMode = main.get_node("Survival")
	_expect(mode.players.size() == 3, "two bots must join, got %d players" % mode.players.size())
	_expect(mode.players[1].input is BotInput and mode.players[2].input is BotInput, "teammates must be bots")
	_expect(main.leaderboard == null, "a run with bots must not submit to the leaderboard")
	_expect(mode.hud.board.status.text == "Partida con bots: no entra en la tabla", "bots note: %s" % mode.hud.board.status.text)
	await _hud_updated()
	_expect(mode.hud.team_label.visible and mode.hud.team_label.text == "Equipo: 3/3 en pie", "team label: %s" % mode.hud.team_label.text)

	# The HUD follows the local player's health, not a teammate's.
	var before := mode.hud.health_bar.value
	mode.players[1].take_hit(30.0)
	await _frames(1)
	_expect(is_equal_approx(mode.hud.health_bar.value, before), "a teammate's damage moved the local health bar")
	mode.players[1].health.invulnerable_left = 0.0
	mode.players[1].take_hit(10000.0)
	await _hud_updated()
	_expect(mode.hud.team_label.text == "Equipo: 2/3 en pie", "team label after a fall: %s" % mode.hud.team_label.text)
	mode.player.take_hit(10000.0)
	await _hud_updated()
	_expect(mode.hud.down_label.visible, "the local player must be told they will revive")
	_expect(not mode.hud.game_over_panel.visible, "game over shown while a bot stands")
	Events.wave_started.emit(2)
	await _frames(1)
	_expect(is_equal_approx(mode.hud.health_bar.value, mode.player.health.max_health * 0.5),
		"the health bar must show half health after reviving, got %.0f" % mode.hud.health_bar.value)
	_expect(not mode.hud.down_label.visible, "the revive message must go away")

	# A bot aims at and shoots the nearest enemy.
	var bot: Player = mode.players[2]
	var chaser: Enemy = load(CHASER).instantiate()
	chaser.position = bot.global_position + Vector2(250, 0)
	mode.enemies.add_child(chaser)
	chaser.health.invulnerable_left = 99999.0
	var fired := false
	for i in BotInput.BURST_FRAMES + BotInput.REST_FRAMES:
		await _frames(1)
		fired = fired or bot.input.wants_to_shoot(bot)
	_expect(fired, "a bot with an enemy in sight must shoot")
	var aim := (bot.input.aim_point(bot) - bot.global_position).normalized()
	_expect(aim.dot((chaser.global_position - bot.global_position).normalized()) > 0.95, "a bot must aim at the nearest enemy")

	# Two bots on the same spot move apart instead of stacking.
	chaser.queue_free()
	mode.players[1].revive(1.0)
	var a: Player = mode.players[1]
	a.global_position = Vector2(640, 360)
	bot.global_position = Vector2(640, 360)
	await _frames(40)
	_expect(a.global_position.distance_to(bot.global_position) > 40.0,
		"bots stacked on each other: %.1f apart" % a.global_position.distance_to(bot.global_position))
	main.queue_free()
	await _frames(2)


## Bots react late, miss a little and fire in bursts, so they help without carrying the team.
func _bots_play_like_people() -> void:
	var a := BotInput.new(Vector2(640, 360), 7)
	var b := BotInput.new(Vector2(640, 360), 7)
	_expect(a.split_direction == b.split_direction, "the same seed must give the same bot")
	_expect(a.split_direction != BotInput.new(Vector2(640, 360), 8).split_direction, "different seeds must give different bots")

	var mode := _make_run()
	await _frames(1)
	mode.player.global_position = Vector2(100, 650)
	var bot := mode.add_player(BotInput.new(Vector2(640, 360), 3))
	bot.global_position = Vector2(400, 360)
	bot.health.invulnerable_left = 999.0
	var far: Enemy = load(CHASER).instantiate()
	far.position = Vector2(1100, 360)
	mode.enemies.add_child(far)
	far.set_physics_process(false)
	far.health.invulnerable_left = 99999.0
	await _frames(BotInput.REACTION_FRAMES + 2)

	var shooting := 0
	var total_error := 0.0
	var samples := 120
	for i in samples:
		await _frames(1)
		bot.global_position = Vector2(400, 360)
		if bot.input.wants_to_shoot(bot):
			shooting += 1
		var aim := (bot.input.aim_point(bot) - bot.global_position).normalized()
		total_error += absf(rad_to_deg(aim.angle_to(far.global_position - bot.global_position)))
	var ratio := float(shooting) / samples
	_expect(ratio > 0.4 and ratio < 0.85, "bots must fire in bursts, fired %.0f%% of the time" % (ratio * 100.0))
	var mean_error := total_error / samples
	_expect(mean_error > 1.0 and mean_error <= BotInput.AIM_ERROR_DEGREES, "bot aim error %.1f deg" % mean_error)

	# A closer enemy is noticed only after the reaction time.
	var near: Enemy = load(CHASER).instantiate()
	near.position = Vector2(480, 360)
	mode.enemies.add_child(near)
	near.set_physics_process(false)
	near.health.invulnerable_left = 99999.0
	await _frames(2)
	_expect(bot.input.target == far, "a bot must not switch targets instantly")
	await _frames(BotInput.REACTION_FRAMES + 2)
	_expect(bot.input.target == near, "a bot must switch to the nearer enemy after reacting")
	await _free(mode)

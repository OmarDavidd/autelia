extends Node
## Composition root: applies the mode chosen in the main menu to the survival run.
## Experiment keeps the run as it is (fixed difficulty, the thesis control condition).
## Arcade adds the difficulty ramp, the score and the global leaderboard, wired here so
## modes/ stays unaware of how difficulty is chosen.

## Submits the finished run and loads the final table.
var leaderboard: Leaderboard
## Loads the table at the start, for the next place to beat. A separate instance so a
## slow answer arriving after death is told apart from the final table and dropped.
var preview: Leaderboard
## Co-op only: the camera that follows this machine's player and the teammate markers.
var camera: FollowCamera
var markers: TeammateMarkers

@onready var survival: SurvivalMode = $Survival


func _ready() -> void:
	add_child(RotateHint.new())
	# The game stays paused behind the menu, so nothing has spawned when the mode is applied.
	if MainMenu.seen:
		_apply_mode()
	else:
		$MainMenu.dismissed.connect(_apply_mode)


func _apply_mode() -> void:
	if GameSession.mode == GameSession.Mode.EXPERIMENT:
		return
	if GameSession.mode == GameSession.Mode.COOP:
		_apply_coop()
		return
	if GameSession.mode == GameSession.Mode.GUN_GAME:
		_apply_gun_game()
		return
	# Arcade and the daily challenge share every rule; the challenge fixes the seed and table.
	var day := GameSession.challenge_day if GameSession.mode == GameSession.Mode.DAILY else ""
	if not day.is_empty():
		survival.reseed(GameSession.daily_seed(day))
		survival.hud.run_title = "Desafío diario %s" % GameSession.daily_label(day)
	var director: DifficultyDirector = survival.get_node("Difficulty")
	director.controller = RampController.new()
	director.set_difficulty(RampController.START)

	var keeper := ScoreKeeper.new()
	keeper.name = "Score"
	survival.add_child(keeper)
	survival.hud.show_score(keeper)

	# Development only: bot teammates to try co-op without a network. Such runs are not
	# comparable, so they never reach the leaderboard.
	var bots := GameSession.bot_count()
	for i in bots:
		survival.add_player(BotInput.new(Vector2(640, 360), survival.used_seed + i + 1))
	if bots > 0:
		survival.hud.board.show_note("Partida con bots: no entra en la tabla")
	else:
		_connect_leaderboard(day)

	if TouchControls.wanted():
		var touch := TouchControls.new()
		touch.name = "TouchControls"
		add_child(touch)
		touch.bind(survival)


## Co-op: an arena and an enemy crowd sized for the room, everybody starting in the middle,
## and a camera that follows this machine's player. No leaderboard yet.
func _apply_coop() -> void:
	var room: CoopRoom = GameSession.coop_room
	if room == null:
		# Never left without a room: play alone rather than fail.
		room = CoopRoom.create(GameSession.player_name)
		GameSession.coop_room = room
	var count := room.players.size()
	survival.arena.resize(CoopRules.arena_size(count))
	var center := survival.arena.size / 2.0
	survival.player.global_position = center
	survival.spawner.crowd = CoopRules.crowd(count)
	var director: DifficultyDirector = survival.get_node("Difficulty")
	director.controller = RampController.new()
	director.set_difficulty(RampController.START)

	var keeper := ScoreKeeper.new()
	keeper.name = "Score"
	survival.add_child(keeper)
	survival.hud.show_score(keeper)
	survival.hud.board.show_note("El cooperativo todavía no tiene tabla")
	for i in range(1, count):
		if room.players[i].bot:
			survival.add_player(BotInput.new(center, survival.used_seed + i))

	survival.get_node("Camera").enabled = false
	camera = FollowCamera.new()
	survival.add_child(camera)
	camera.follow(survival.player, Rect2(Vector2.ZERO, survival.arena.size))
	camera.make_current()
	markers = TeammateMarkers.new()
	add_child(markers)
	markers.bind(survival)

	if TouchControls.wanted():
		var touch := TouchControls.new()
		touch.name = "TouchControls"
		add_child(touch)
		touch.bind(survival)


func _apply_gun_game() -> void:
	survival.process_mode = Node.PROCESS_MODE_DISABLED
	survival.visible = false
	remove_child(survival)
	survival.queue_free()

	var gun_game := GunGameMode.new()
	gun_game.name = "GunGame"
	add_child(gun_game)
	gun_game.setup_match(GameSession.player_name, 7)

	# The run's pause menu went away with Survival; the match gets its own.
	var pause := PauseMenu.new()
	pause.name = "PauseMenu"
	pause.mode_path = NodePath("../GunGame")
	add_child(pause)

	var hud := GunGameHud.new()
	hud.name = "GunGameHud"
	add_child(hud)
	hud.bind(gun_game, pause)

	if TouchControls.wanted():
		var touch := TouchControls.new()
		touch.name = "TouchControls"
		add_child(touch)
		touch.bind_player(gun_game.local_player, pause)
		hud.move_kill_feed_below(touch.pause_button.offset_bottom + 16.0)

	camera = FollowCamera.new()
	add_child(camera)
	camera.follow(gun_game.local_player, Rect2(Vector2.ZERO, gun_game.arena.size))
	camera.make_current()

	markers = TeammateMarkers.new()
	add_child(markers)
	markers.bind(gun_game)


func _connect_leaderboard(day: String) -> void:
	leaderboard = Leaderboard.new()
	leaderboard.day = day
	add_child(leaderboard)
	leaderboard.top_loaded.connect(_on_top_loaded)
	leaderboard.failed.connect(survival.hud.show_leaderboard_error)
	Events.player_died.connect(_on_player_died)

	preview = Leaderboard.new()
	preview.day = day
	add_child(preview)
	preview.top_loaded.connect(_on_preview_loaded)
	preview.failed.connect(_on_preview_failed)
	preview.fetch_top()


func _on_player_died() -> void:
	var keeper: ScoreKeeper = survival.get_node("Score")
	leaderboard.submit_and_fetch(GameSession.player_name, keeper.score, survival.spawner.wave)


func _on_preview_loaded(rows: Array) -> void:
	if not survival.is_over():
		_on_top_loaded(rows)


func _on_preview_failed() -> void:
	if not survival.is_over():
		survival.hud.show_leaderboard_error()


func _on_top_loaded(rows: Array) -> void:
	var keeper: ScoreKeeper = survival.get_node("Score")
	survival.hud.show_leaderboard(rows, GameSession.player_name, keeper.score)

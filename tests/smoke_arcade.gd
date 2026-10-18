extends Node
## Arcade smoke test: menu split, player name, difficulty ramp, score, leaderboard client, game over.
## Run: godot --headless --path . tests/smoke_arcade.tscn
## Never touches the network: Leaderboard.enabled is off, which is the offline path.

const PROFILE := "user://test_profile.cfg"

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	GameSession.profile_path = PROFILE
	Leaderboard.enabled = false
	_ramp_rises_and_caps()
	_next_target_line()
	_names_are_cleaned_validated_and_remembered()
	await _score_counts_kills_and_waves()
	await _leaderboard_requests_and_parsing()
	await _experiment_keeps_fixed_difficulty()
	await _arcade_from_menu_to_game_over()
	await _arcade_page_shows_the_table()
	await _home_teases_experiment_and_shows_scores()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))

	get_tree().paused = false
	if failures.is_empty():
		print("SMOKE OK: arcade ramps, scores, remembers the name and shows the leaderboard")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _ramp_rises_and_caps() -> void:
	var ramp := RampController.new()
	_expect(ramp.label() == "ramp", "ramp label: %s" % ramp.label())
	_expect(is_equal_approx(RampController.START, 0.3), "ramp must start at 0.3")
	_expect(is_equal_approx(ramp.next_difficulty({}, 0.3), 0.37), "ramp must add 0.07 per wave")
	_expect(is_equal_approx(ramp.next_difficulty({}, 0.98), 1.0), "ramp must cap at 1.0")


func _next_target_line() -> void:
	var rows := [
		{"name": "Lucía", "score": 2480, "wave": 9},
		{"name": "Omar", "score": 1240, "wave": 6},
		{"name": "Mateo", "score": 980, "wave": 5},
	]
	_expect(Hud.next_text(rows, 640) == "Próximo: #3 Mateo · 980 (faltan 341)", "below: %s" % Hud.next_text(rows, 640))
	# A tie does not pass: the older score stays ahead.
	_expect(Hud.next_text(rows, 980) == "Próximo: #3 Mateo · 980 (faltan 1)", "tie: %s" % Hud.next_text(rows, 980))
	_expect(Hud.next_text(rows, 1000) == "Próximo: #2 Omar · 1240 (faltan 241)", "passed one: %s" % Hud.next_text(rows, 1000))
	_expect(Hud.next_text(rows, 2481) == "¡Récord! Vas primero", "record: %s" % Hud.next_text(rows, 2481))
	_expect(Hud.next_text([], 0) == "Tabla vacía: ¡sé el primero!", "empty: %s" % Hud.next_text([], 0))


func _names_are_cleaned_validated_and_remembered() -> void:
	_expect(GameSession.clean_name("  Omar  ") == "Omar", "name not trimmed")
	_expect(not GameSession.is_valid_name("ab"), "2-char name accepted")
	_expect(GameSession.is_valid_name("abc"), "3-char name rejected")
	_expect(GameSession.is_valid_name("a".repeat(16)), "16-char name rejected")
	_expect(not GameSession.is_valid_name("a".repeat(17)), "17-char name accepted")
	_expect(not GameSession.is_valid_name("   "), "blank name accepted")
	GameSession.save_name("Tester")
	_expect(GameSession.load_name() == "Tester", "name not remembered: %s" % GameSession.load_name())


func _score_counts_kills_and_waves() -> void:
	var keeper := ScoreKeeper.new()
	add_child(keeper)
	var chaser: Node = load("res://core/enemies/chaser.tscn").instantiate()
	var shooter: Node = load("res://core/enemies/shooter.tscn").instantiate()
	Events.enemy_killed.emit(chaser)
	_expect(keeper.score == 10, "chaser must give 10, got %d" % keeper.score)
	Events.enemy_killed.emit(shooter)
	_expect(keeper.score == 30, "shooter must give 20, got %d" % (keeper.score - 10))
	Events.wave_ended.emit(2)
	_expect(keeper.score == 130, "surviving wave 2 must give 100, got %d" % (keeper.score - 30))
	Events.player_died.emit()
	Events.enemy_killed.emit(chaser)
	_expect(keeper.score == 130, "score changed after the player died")
	chaser.free()
	shooter.free()
	keeper.queue_free()
	await _frames(2)


func _leaderboard_requests_and_parsing() -> void:
	var legacy := Leaderboard.headers("eyJhbGciOi.test")
	_expect(legacy.has("apikey: eyJhbGciOi.test"), "apikey header missing")
	_expect(legacy.has("Authorization: Bearer eyJhbGciOi.test"), "legacy JWT key needs a bearer header")
	var publishable := Leaderboard.headers("sb_publishable_test")
	_expect(publishable.has("apikey: sb_publishable_test"), "publishable apikey header missing")
	_expect(not "\n".join(publishable).contains("Authorization"),
		"publishable key is not a JWT and must not be sent as bearer")

	var body: Dictionary = JSON.parse_string(Leaderboard.insert_body("Tester", 130, 2))
	_expect(body == {"name": "Tester", "score": 130.0, "wave": 2.0}, "insert body: %s" % str(body))
	_expect(Leaderboard.top_query() == "/rest/v1/scores?select=name,score,wave&order=score.desc,created_at.asc&limit=10",
		"top query: %s" % Leaderboard.top_query())

	var rows := Leaderboard.parse_rows('[{"name":"A","score":300,"wave":4},{"name":"B","score":120,"wave":2}]'.to_utf8_buffer())
	_expect(rows.size() == 2 and rows[0].name == "A" and rows[0].score == 300 and rows[1].wave == 2,
		"rows not parsed: %s" % str(rows))
	_expect(Leaderboard.parse_rows("not json".to_utf8_buffer()).is_empty(), "garbage must parse to no rows")
	_expect(Leaderboard.parse_rows('[{"name":"A"}]'.to_utf8_buffer()).is_empty(), "rows without score must be dropped")

	# On the web the browser already decompresses; Godot decompressing again fails (result 8).
	var http := Leaderboard.make_request()
	_expect(not http.accept_gzip, "requests must not ask for gzip: the web build cannot decode it twice")
	_expect(is_equal_approx(http.timeout, Leaderboard.TIMEOUT), "request timeout not set")
	http.free()

	var board := Leaderboard.new()
	add_child(board)
	var failed := [0]
	board.failed.connect(func() -> void: failed[0] += 1)
	board.submit_and_fetch("Tester", 130, 2)
	board.fetch_top()
	await _frames(2)
	_expect(failed[0] == 2, "disabled leaderboard must fail instead of hanging (%d)" % failed[0])
	board.queue_free()
	await _frames(2)


func _open_main() -> Node:
	MainMenu.seen = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	return main


func _experiment_keeps_fixed_difficulty() -> void:
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.play_experiment()
	await _frames(2)
	var mode: SurvivalMode = main.get_node("Survival")
	var director: DifficultyDirector = mode.get_node("Difficulty")
	_expect(GameSession.mode == GameSession.Mode.EXPERIMENT, "experiment not selected")
	_expect(director.controller is FixedController, "experiment must keep fixed difficulty")
	_expect(not mode.hud.score_label.visible, "experiment must not show a score")
	_expect(mode.get_node_or_null("Score") == null, "experiment must not keep score")
	main.queue_free()
	await _frames(2)


func _arcade_from_menu_to_game_over() -> void:
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_modes()
	_expect(menu.arcade_button.is_visible_in_tree(), "modes page does not show Arcade")
	menu.show_arcade()
	_expect(menu.name_input.text == "Tester", "name field must start with the remembered name")

	menu.name_input.text = "ab"
	_expect(not menu.start_arcade(), "short name started the run")
	_expect(menu.name_error.visible, "short name shows no error")
	_expect(get_tree().paused, "game unpaused with an invalid name")

	menu.name_input.text = "  Ana  "
	_expect(menu.start_arcade(), "valid name did not start the run")
	await _frames(2)
	_expect(not get_tree().paused, "arcade still paused after starting")
	_expect(GameSession.player_name == "Ana", "player name not kept: %s" % GameSession.player_name)
	_expect(GameSession.load_name() == "Ana", "new name not remembered")

	var mode: SurvivalMode = main.get_node("Survival")
	var director: DifficultyDirector = mode.get_node("Difficulty")
	_expect(director.controller is RampController, "arcade must ramp difficulty")
	_expect(is_equal_approx(director.difficulty, RampController.START), "arcade must start at 0.3, got %.2f" % director.difficulty)
	_expect(mode.hud.score_label.visible, "arcade must show the score")
	_expect(mode.hud.score_label.text == "Puntos: 0", "score label: %s" % mode.hud.score_label.text)

	var keeper: ScoreKeeper = mode.get_node("Score")
	keeper.add(40)
	_expect(mode.hud.score_label.text == "Puntos: 40", "score label not updated: %s" % mode.hud.score_label.text)

	_expect(not mode.hud.next_label.visible, "next line shown without a loaded table")
	var table := [{"name": "Bo", "score": 60, "wave": 2}, {"name": "Cy", "score": 30, "wave": 1}]
	mode.hud.show_leaderboard(table, "Ana", keeper.score)
	_expect(mode.hud.next_label.visible, "next line hidden with a loaded table")
	_expect(mode.hud.next_label.text == "Próximo: #1 Bo · 60 (faltan 21)", "next line: %s" % mode.hud.next_label.text)
	keeper.add(30)
	_expect(mode.hud.next_label.text == "¡Récord! Vas primero", "next line not updated: %s" % mode.hud.next_label.text)

	mode.player.health.take_damage(10000.0)
	await _frames(50)
	_expect(mode.hud.game_over_panel.visible, "arcade game over never appeared")
	_expect(mode.hud.game_over_label.text.contains("Puntos: 70"), "game over misses the score: %s" % mode.hud.game_over_label.text)
	_expect(mode.hud.board.status.text == "No se pudo cargar la tabla", "offline status: %s" % mode.hud.board.status.text)
	_expect(not mode.hud.next_label.visible, "next line kept after the table failed")

	# A slow start-of-run load that arrives after death must not replace the final table.
	main.preview.top_loaded.emit([{"name": "Old", "score": 999, "wave": 9}])
	main.preview.failed.emit()
	_expect(mode.hud.board.status.text == "No se pudo cargar la tabla", "late preview replaced the final table: %s" % mode.hud.board.status.text)
	_expect(mode.hud.board.rows.get_child_count() == 0, "late preview rows shown after death")

	mode.hud.show_leaderboard([{"name": "Ana", "score": 40, "wave": 1}, {"name": "Bo", "score": 20, "wave": 1}], "Ana", 40)
	_expect(not mode.hud.board.status.visible, "status still shown with rows")
	_expect(mode.hud.board.rows.get_child_count() == 2 * LeaderboardTable.COLUMNS, "board rows: %d" % mode.hud.board.rows.get_child_count())

	main.queue_free()
	GameSession.mode = GameSession.Mode.EXPERIMENT
	await _frames(2)


func _arcade_page_shows_the_table() -> void:
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_arcade()
	await _frames(2)
	_expect(menu.board.is_visible_in_tree(), "arcade page does not show the table")
	_expect(menu.board.status.text == "No se pudo cargar la tabla", "arcade page offline status: %s" % menu.board.status.text)
	menu.board.show_rows([{"name": "Bo", "score": 60, "wave": 2}], "Ana", -1)
	_expect(menu.board.rows.get_child_count() == LeaderboardTable.COLUMNS, "arcade page rows: %d" % menu.board.rows.get_child_count())
	main.queue_free()
	await _frames(2)


func _home_teases_experiment_and_shows_scores() -> void:
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	var teaser := menu.experiment_button
	_expect(teaser.disabled, "experiment must not be clickable yet")
	_expect(teaser.text == "Próximamente", "experiment teaser text: %s" % teaser.text)
	_expect(teaser.focus_mode == Control.FOCUS_NONE, "keyboard focus must skip the teaser")
	var buttons := teaser.get_parent()
	var last_index := buttons.get_child_count() - (1 if OS.has_feature("web") else 2)
	_expect(teaser.get_index() == last_index, "teaser must sit at the bottom, above Salir")
	_expect(buttons.get_child(0).text == "Modos", "first home button: %s" % buttons.get_child(0).text)

	menu.show_scores()
	await _frames(2)
	_expect(menu.scores_board.is_visible_in_tree(), "scores page does not show the table")
	_expect(menu.scores_board.status.text == "No se pudo cargar la tabla", "scores page offline status: %s" % menu.scores_board.status.text)
	main.queue_free()
	await _frames(2)

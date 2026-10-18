extends Node
## Daily challenge smoke test: date and seed, daily leaderboard queries, menu, run wiring.
## Run: godot --headless --path . tests/smoke_daily.tscn
## Never touches the network: Leaderboard.enabled is off.

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
	GameSession.save_name("Ana")
	_day_and_seed()
	_daily_leaderboard_requests()
	_best_score_per_player()
	await _daily_run_from_menu()
	await _restart_keeps_the_same_challenge()
	await _scores_page_shows_both_tables()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	GameSession.mode = GameSession.Mode.EXPERIMENT

	get_tree().paused = false
	if failures.is_empty():
		print("SMOKE OK: daily challenge shares a seed per day, ranks best per player and wires the run")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		get_tree().quit(1)


func _day_and_seed() -> void:
	var day := GameSession.daily_day({"year": 2026, "month": 3, "day": 7})
	_expect(day == "2026-03-07", "day format: %s" % day)
	var seed_a := GameSession.daily_seed("2026-03-07")
	_expect(seed_a == GameSession.daily_seed("2026-03-07"), "same day must give the same seed")
	_expect(seed_a != GameSession.daily_seed("2026-03-08"), "different days must give different seeds")
	_expect(seed_a > 0, "seed must be positive, got %d" % seed_a)
	_expect(GameSession.daily_label("2026-03-07") == "7/3", "short label: %s" % GameSession.daily_label("2026-03-07"))


func _daily_leaderboard_requests() -> void:
	_expect(Leaderboard.top_query() == "/rest/v1/scores?select=name,score,wave&order=score.desc,created_at.asc&limit=10",
		"arcade query changed: %s" % Leaderboard.top_query())
	var daily := Leaderboard.top_query("2026-03-07")
	_expect(daily == "/rest/v1/daily_scores?select=name,score,wave&day=eq.2026-03-07&order=score.desc,created_at.asc&limit=%d" % Leaderboard.DAILY_FETCH,
		"daily query: %s" % daily)
	var body: Dictionary = JSON.parse_string(Leaderboard.insert_body("Ana", 90, 3, "2026-03-07"))
	_expect(body == {"name": "Ana", "score": 90.0, "wave": 3.0, "day": "2026-03-07"}, "daily insert body: %s" % str(body))
	var arcade_body: Dictionary = JSON.parse_string(Leaderboard.insert_body("Ana", 90, 3))
	_expect(not arcade_body.has("day"), "arcade insert must not send a day")
	_expect(Leaderboard.table_path("") == "/rest/v1/scores", "arcade table path")
	_expect(Leaderboard.table_path("2026-03-07") == "/rest/v1/daily_scores", "daily table path")


func _best_score_per_player() -> void:
	var rows := [
		{"name": "Ana", "score": 300, "wave": 5},
		{"name": "Ana", "score": 200, "wave": 4},
		{"name": "Bo", "score": 150, "wave": 3},
		{"name": "Ana", "score": 100, "wave": 2},
	]
	var best := Leaderboard.best_per_player(rows)
	_expect(best.size() == 2 and best[0].name == "Ana" and best[0].score == 300 and best[1].name == "Bo",
		"best per player: %s" % str(best))
	var many := []
	for i in 30:
		many.append({"name": "P%d" % i, "score": 1000 - i, "wave": 1})
	_expect(Leaderboard.best_per_player(many).size() == Leaderboard.TOP_SIZE, "daily table must cap at the top size")


func _open_main() -> Node:
	MainMenu.seen = false
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	return main


func _daily_run_from_menu() -> void:
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_modes()
	_expect(menu.daily_button.is_visible_in_tree(), "modes page does not offer the daily challenge")
	menu.show_daily()
	_expect(menu.run_title.text.begins_with("Desafío diario"), "daily page title: %s" % menu.run_title.text)
	_expect(menu.name_input.text == "Ana", "daily page must reuse the remembered name")
	_expect(menu.start_arcade(), "daily run did not start")
	await _frames(2)

	var today := GameSession.daily_day()
	_expect(GameSession.mode == GameSession.Mode.DAILY, "daily mode not selected")
	_expect(GameSession.challenge_day == today, "challenge day: %s" % GameSession.challenge_day)
	var mode: SurvivalMode = main.get_node("Survival")
	_expect(mode.used_seed == GameSession.daily_seed(today), "run seed %d is not today's" % mode.used_seed)
	var director: DifficultyDirector = mode.get_node("Difficulty")
	_expect(director.controller is RampController, "daily must ramp like arcade")
	_expect(mode.get_node_or_null("Score") != null, "daily must keep score")
	_expect(main.leaderboard.day == today and main.preview.day == today, "daily scores must go to today's table")
	main.queue_free()
	await _frames(2)

	# Arcade afterwards is back to a random seed and the all-time table.
	main = await _open_main()
	menu = main.get_node("MainMenu")
	menu.show_arcade()
	_expect(menu.run_title.text == "Arcade", "arcade page title: %s" % menu.run_title.text)
	menu.start_arcade()
	await _frames(2)
	_expect(GameSession.mode == GameSession.Mode.ARCADE, "arcade not selected after daily")
	_expect(main.leaderboard.day == "", "arcade must use the all-time table")
	main.queue_free()
	await _frames(2)


func _restart_keeps_the_same_challenge() -> void:
	GameSession.mode = GameSession.Mode.DAILY
	GameSession.challenge_day = "2026-03-07"
	MainMenu.seen = true
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await _frames(2)
	var mode: SurvivalMode = main.get_node("Survival")
	_expect(mode.used_seed == GameSession.daily_seed("2026-03-07"), "restart must replay the same challenge")
	main.queue_free()
	await _frames(2)


func _scores_page_shows_both_tables() -> void:
	var main := await _open_main()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_scores()
	await _frames(2)
	_expect(menu.scores_board.is_visible_in_tree() and menu.daily_board.is_visible_in_tree(),
		"scores page must show the arcade and the daily tables")
	_expect(menu.daily_board.status.text == "No se pudo cargar la tabla", "daily table offline status: %s" % menu.daily_board.status.text)
	main.queue_free()
	await _frames(2)

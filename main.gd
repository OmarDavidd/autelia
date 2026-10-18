extends Node
## Composition root: applies the mode chosen in the main menu to the survival run.
## Experiment keeps the run as it is (fixed difficulty, the thesis control condition).
## Arcade adds the difficulty ramp, the score and the global leaderboard, wired here so
## modes/ stays unaware of how difficulty is chosen.

var leaderboard: Leaderboard

@onready var survival: SurvivalMode = $Survival


func _ready() -> void:
	# The game stays paused behind the menu, so nothing has spawned when the mode is applied.
	if MainMenu.seen:
		_apply_mode()
	else:
		$MainMenu.dismissed.connect(_apply_mode)


func _apply_mode() -> void:
	if GameSession.mode != GameSession.Mode.ARCADE:
		return
	var director: DifficultyDirector = survival.get_node("Difficulty")
	director.controller = RampController.new()
	director.set_difficulty(RampController.START)

	var keeper := ScoreKeeper.new()
	keeper.name = "Score"
	survival.add_child(keeper)
	survival.hud.show_score(keeper)

	leaderboard = Leaderboard.new()
	add_child(leaderboard)
	leaderboard.top_loaded.connect(_on_top_loaded)
	leaderboard.failed.connect(survival.hud.show_leaderboard_error)
	Events.player_died.connect(_on_player_died)
	# Loaded up front so the HUD can show the next place to beat during the run.
	leaderboard.fetch_top()


func _on_player_died() -> void:
	var keeper: ScoreKeeper = survival.get_node("Score")
	leaderboard.submit_and_fetch(GameSession.player_name, keeper.score, survival.spawner.wave)


func _on_top_loaded(rows: Array) -> void:
	var keeper: ScoreKeeper = survival.get_node("Score")
	survival.hud.show_leaderboard(rows, GameSession.player_name, keeper.score)

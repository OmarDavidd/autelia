extends Node
## Plays a scripted scenario and saves a screenshot for the thesis log.
## The scenario renders in an offscreen 1280x720 SubViewport, so the image size
## does not depend on the monitor or its scaling.
## Run (needs a window, not --headless):
##   godot --path . tools/capture/capture.tscn -- <scenario>
## Output: docs/tesis/capturas/<scenario>.png

const OUTPUT_DIR := "res://docs/tesis/capturas"
const SIZE := Vector2i(1280, 720)

var stage: SubViewport

var scenarios := {
	"etapa2-disparo": _stage2_shooting,
	"etapa3-enemigos": _stage3_enemies,
	"etapa4-oleada": _stage4_wave,
	"etapa5-hud": _stage5_hud,
	"etapa5-fin": _stage5_game_over,
	"etapa6-oleada": _stage5_hud,
	"etapa6-personajes": _stage6_lineup,
	"etapa7-baja": _stage7_low,
	"etapa7-alta": _stage7_high,
	"etapa7-panel": _stage7_panel,
	"etapa7-bot": _stage7_bot_session,
	"feel-inicio": _feel_main_menu,
	"feel-muerte": _feel_death_burst,
	"menu-acerca": _menu_about,
	"pausa": _pause_screen,
	"arcade-modos": _arcade_modes,
	"arcade-nombre": _arcade_name,
	"arcade-partida": _arcade_run,
	"arcade-fin": _arcade_game_over,
	"menu-puntajes": _menu_scores,
	"arcade-tactil": _arcade_touch,
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var name: String = args[0] if args.size() > 0 else ""
	if not scenarios.has(name):
		printerr("Unknown scenario '%s'. Available: %s" % [name, ", ".join(scenarios.keys())])
		get_tree().quit(1)
		return

	Sfx.muted = true
	stage = SubViewport.new()
	stage.size = SIZE
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.transparent_bg = false
	add_child(stage)
	RenderingServer.set_default_clear_color(Palette.BACKGROUND)

	await scenarios[name].call()
	# Let the last frame render before reading the viewport.
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [OUTPUT_DIR, name]
	var error := stage.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		printerr("Could not save %s: %s" % [path, error_string(error)])
		get_tree().quit(1)
		return
	print("Captured: ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)


func _sandbox() -> Dictionary:
	return Sandbox.create(stage)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _stage2_shooting() -> void:
	var sandbox := _sandbox()
	var player: Player = sandbox.player
	var target := Sandbox.spawn(sandbox.world, "res://core/enemies/target_dummy.tscn", Vector2(960, 250))
	Sandbox.spawn(sandbox.world, "res://core/enemies/target_dummy.tscn", Vector2(960, 470))
	player.aim_override = target.global_position
	Input.action_press("shoot")
	await _frames(34)
	Input.action_release("shoot")


func _stage3_enemies() -> void:
	var sandbox := _sandbox()
	var player: Player = sandbox.player
	var chaser := Sandbox.spawn(sandbox.world, "res://core/enemies/chaser.tscn", Vector2(1060, 200))
	Sandbox.spawn(sandbox.world, "res://core/enemies/chaser.tscn", Vector2(1060, 540))
	Sandbox.spawn(sandbox.world, "res://core/enemies/shooter.tscn", Vector2(220, 300))
	Input.action_press("shoot")
	for i in 55:
		if is_instance_valid(chaser):
			player.aim_override = chaser.global_position
		await get_tree().physics_frame
	Input.action_release("shoot")


## Aims at the closest enemy, like a simple bot.
func _aim_nearest(player: Player, enemies: Node) -> void:
	var best: Node2D
	for enemy in enemies.get_children():
		if enemy is Enemy and (best == null or player.global_position.distance_to(enemy.global_position) < player.global_position.distance_to(best.global_position)):
			best = enemy
	if best:
		player.aim_override = best.global_position


func _stage4_wave() -> void:
	var mode: SurvivalMode = load("res://modes/survival/survival.tscn").instantiate()
	mode.run_seed = 2026
	stage.add_child(mode)
	# Keep the player alive and let enemies build up, then fire for the last moment.
	mode.player.health.invulnerable_left = 999.0
	for i in int(60 * 9.5):
		_aim_nearest(mode.player, mode.enemies)
		if i == int(60 * 9.0):
			Input.action_press("shoot")
		await get_tree().physics_frame
	Input.action_release("shoot")


func _survival(seed_value: int) -> SurvivalMode:
	var mode: SurvivalMode = load("res://modes/survival/survival.tscn").instantiate()
	mode.run_seed = seed_value
	stage.add_child(mode)
	return mode


func _stage5_hud() -> void:
	var mode := _survival(2026)
	Input.action_press("shoot")
	for i in int(60 * 9.5):
		_aim_nearest(mode.player, mode.enemies)
		await get_tree().physics_frame
	Input.action_release("shoot")


func _stage5_game_over() -> void:
	var mode := _survival(2026)
	for i in 60 * 40:
		if mode.player.health.is_dead():
			break
		await get_tree().physics_frame
	await _frames(20)


## Static lineup of every character and effect, for the style section of the thesis.
func _stage6_lineup() -> void:
	var sandbox := _sandbox()
	var world: Node2D = sandbox.world
	var player: Player = sandbox.player
	player.global_position = Vector2(300, 360)
	player.aim_override = Vector2(1000, 300)
	var still := func(node: Node) -> void:
		node.set_physics_process(false)
	var chaser := Sandbox.spawn(world, "res://core/enemies/chaser.tscn", Vector2(500, 360))
	var shooter := Sandbox.spawn(world, "res://core/enemies/shooter.tscn", Vector2(680, 360))
	Sandbox.spawn(world, "res://core/enemies/target_dummy.tscn", Vector2(860, 360))
	var marker := SpawnMarker.new()
	world.add_child(marker)
	marker.global_position = Vector2(1020, 360)
	marker._elapsed = 0.25
	await _frames(2)
	for node in [chaser, shooter, marker]:
		still.call(node)
		node.queue_redraw()
	for spec in [[Vector2(380, 300), Vector2.RIGHT, false], [Vector2(1150, 300), Vector2.LEFT, true]]:
		var bullet: Bullet = load("res://core/combat/bullet.tscn").instantiate()
		bullet.direction = spec[1]
		bullet.outlined = spec[2]
		bullet.color = Palette.ENEMY if spec[2] else Palette.INK
		world.add_child(bullet)
		bullet.global_position = spec[0]
		still.call(bullet)
	await _frames(2)


func _stage7_wave_at(difficulty: float) -> SurvivalMode:
	var mode: SurvivalMode = load("res://modes/survival/survival.tscn").instantiate()
	mode.run_seed = 2026
	mode.get_node("Telemetry").output_dir = "user://capture_telemetry"
	stage.add_child(mode)
	mode.get_node("Difficulty").set_difficulty(difficulty)
	mode.player.health.invulnerable_left = 999.0
	for i in int(60 * 10.0):
		_aim_nearest(mode.player, mode.enemies)
		await get_tree().physics_frame
	return mode


func _stage7_low() -> void:
	await _stage7_wave_at(0.1)


func _stage7_high() -> void:
	await _stage7_wave_at(0.9)


func _stage7_panel() -> void:
	var mode: SurvivalMode = load("res://modes/survival/survival.tscn").instantiate()
	mode.run_seed = 2026
	mode.get_node("Telemetry").output_dir = "user://capture_telemetry"
	stage.add_child(mode)
	mode.get_node("DebugPanel").visible = true
	mode.get_node("Difficulty").set_difficulty(0.65)
	Input.action_press("shoot")
	for i in int(60 * 6.0):
		_aim_nearest(mode.player, mode.enemies)
		await get_tree().physics_frame
	Input.action_release("shoot")


## A simple bot (shoots the nearest enemy, steps away from threats) plays three short
## waves at d = 0.5 and leaves its telemetry in docs/tesis/ejemplos/ as a sample file.
func _stage7_bot_session() -> void:
	var out_dir := ProjectSettings.globalize_path("res://docs/tesis/ejemplos")
	var mode: SurvivalMode = load("res://modes/survival/survival.tscn").instantiate()
	mode.run_seed = 2026
	var spawner: WaveSpawner = mode.get_node("Spawner")
	spawner.wave_duration = 15.0
	var telemetry: TelemetryRecorder = mode.get_node("Telemetry")
	telemetry.output_dir = out_dir
	stage.add_child(mode)
	Input.action_press("shoot")
	var frames := 0
	while spawner.wave < 4 and not mode.player.health.is_dead() and frames < 60 * 70:
		_aim_nearest(mode.player, mode.enemies)
		_dodge(mode.player, mode.enemies, mode.arena)
		await get_tree().physics_frame
		frames += 1
	for action in ["shoot", "move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
	var target := out_dir + "/telemetria-ejemplo.csv"
	DirAccess.remove_absolute(target)
	DirAccess.rename_absolute(telemetry.file_path, target)
	print("Sample telemetry: ", target)


func _dodge(player: Player, enemies: Node, arena: Arena) -> void:
	var push := Vector2.ZERO
	for enemy in enemies.get_children():
		if enemy is Enemy:
			var away: Vector2 = player.global_position - enemy.global_position
			push += away / maxf(away.length_squared(), 400.0) * 400.0
	push += (arena.play_rect().get_center() - player.global_position) * 0.004
	for pair in [["move_right", push.x], ["move_left", -push.x], ["move_down", push.y], ["move_up", -push.y]]:
		if pair[1] > 0.3:
			Input.action_press(pair[0])
		else:
			Input.action_release(pair[0])


func _feel_main_menu() -> void:
	MainMenu.seen = false
	stage.add_child(load("res://main.tscn").instantiate())
	await _frames(20)


func _feel_death_burst() -> void:
	var sandbox := _sandbox()
	var player: Player = sandbox.player
	var chaser: Enemy = Sandbox.spawn(sandbox.world, "res://core/enemies/chaser.tscn", Vector2(820, 300))
	var shooter: Enemy = Sandbox.spawn(sandbox.world, "res://core/enemies/shooter.tscn", Vector2(960, 470))
	for node in [chaser, shooter]:
		node.set_physics_process(false)
	player.aim_override = chaser.global_position
	await _frames(3)
	chaser.take_hit(1000.0)
	shooter.take_hit(1000.0)
	await _frames(7)


func _menu_about() -> void:
	MainMenu.seen = false
	var main: Node = load("res://main.tscn").instantiate()
	stage.add_child(main)
	await _frames(3)
	main.get_node("MainMenu").show_about()
	await _frames(10)


func _pause_screen() -> void:
	var mode: SurvivalMode = load("res://modes/survival/survival.tscn").instantiate()
	mode.run_seed = 2026
	stage.add_child(mode)
	mode.player.health.invulnerable_left = 999.0
	for i in int(60 * 6.0):
		_aim_nearest(mode.player, mode.enemies)
		await get_tree().physics_frame
	mode.get_node("PauseMenu").open()
	await _frames(10)
	get_tree().paused = false


const SAMPLE_TOP := [
	{"name": "Lucía", "score": 2480, "wave": 9},
	{"name": "Omar", "score": 1240, "wave": 6},
	{"name": "Mateo", "score": 980, "wave": 5},
	{"name": "Sofi", "score": 410, "wave": 3},
]


## Opens the main menu with a throwaway profile, so captures never touch the saved name.
func _arcade_menu() -> Node:
	Leaderboard.enabled = false
	GameSession.profile_path = "user://capture_profile.cfg"
	GameSession.save_name("Omar")
	MainMenu.seen = false
	var main: Node = load("res://main.tscn").instantiate()
	stage.add_child(main)
	await _frames(3)
	return main


func _arcade_modes() -> void:
	var main: Node = await _arcade_menu()
	main.get_node("MainMenu").show_modes()
	await _frames(10)


func _arcade_name() -> void:
	var main: Node = await _arcade_menu()
	main.get_node("MainMenu").show_arcade()
	await _frames(2)
	main.get_node("MainMenu").board.show_rows(SAMPLE_TOP, "Omar", -1)
	await _frames(8)


## Starts an arcade run from the menu, offline, and plays it with an auto-aiming player.
func _arcade_start(seed_value: int) -> Node:
	var main: Node = await _arcade_menu()
	var mode: SurvivalMode = main.get_node("Survival")
	mode.run_seed = seed_value
	main.get_node("MainMenu").show_arcade()
	main.get_node("MainMenu").start_arcade()
	return main


func _arcade_run() -> void:
	var main: Node = await _arcade_start(2026)
	var mode: SurvivalMode = main.get_node("Survival")
	await _frames(2)
	mode.hud.show_leaderboard(SAMPLE_TOP, "Omar", 0)
	mode.player.health.invulnerable_left = 999.0
	Input.action_press("shoot")
	for i in int(60 * 12.0):
		_aim_nearest(mode.player, mode.enemies)
		await get_tree().physics_frame
	Input.action_release("shoot")


func _arcade_game_over() -> void:
	var main: Node = await _arcade_start(2026)
	var mode: SurvivalMode = main.get_node("Survival")
	main.get_node("Survival/Score").add(1240)
	mode.player.health.take_damage(10000.0)
	await _frames(50)
	mode.hud.show_leaderboard(SAMPLE_TOP, "Omar", 1240)
	await _frames(5)


func _menu_scores() -> void:
	var main: Node = await _arcade_menu()
	var menu: MainMenu = main.get_node("MainMenu")
	menu.show_scores()
	await _frames(2)
	menu.scores_board.show_rows(SAMPLE_TOP, "", -1)
	await _frames(8)


## Arcade with the touch controls, both thumbs down: moving up-left and firing right.
func _arcade_touch() -> void:
	TouchControls.forced = true
	var main: Node = await _arcade_start(2026)
	var mode: SurvivalMode = main.get_node("Survival")
	var controls: TouchControls = main.get_node("TouchControls")
	await _frames(2)
	mode.hud.show_leaderboard(SAMPLE_TOP, "Omar", 0)
	mode.player.health.invulnerable_left = 999.0
	for i in int(60 * 8.0):
		var target := mode.player.global_position + Vector2.RIGHT
		for enemy in mode.enemies.get_children():
			if enemy is Enemy:
				target = enemy.global_position
				break
		var aim := (target - mode.player.global_position).normalized() * TouchControls.STICK_RADIUS * 0.8
		for pair in [[0, Vector2(220, 540), Vector2(220, 540) + Vector2(-0.4, -0.5) * TouchControls.STICK_RADIUS],
				[1, Vector2(1040, 520), Vector2(1040, 520) + aim]]:
			if i == 0:
				var touch := InputEventScreenTouch.new()
				touch.index = pair[0]
				touch.position = pair[1]
				touch.pressed = true
				controls._input(touch)
			var drag := InputEventScreenDrag.new()
			drag.index = pair[0]
			drag.position = pair[2]
			controls._input(drag)
		await get_tree().physics_frame

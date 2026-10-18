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

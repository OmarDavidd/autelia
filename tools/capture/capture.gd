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


func _load_survival() -> Node:
	var scene: Node = load("res://modes/survival/survival.tscn").instantiate()
	stage.add_child(scene)
	return scene


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _stage2_shooting() -> void:
	var scene := _load_survival()
	var player: Player = scene.get_node("Player")
	var target: Node2D = scene.get_node("TargetDummyA")
	player.aim_override = target.global_position
	Input.action_press("shoot")
	await _frames(34)
	Input.action_release("shoot")

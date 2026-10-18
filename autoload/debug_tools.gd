extends Node
## Development helpers. F12 saves a screenshot to user://screenshots/
## (on Linux: ~/.local/share/godot/app_userdata/Autelia/screenshots/).

const SCREENSHOT_DIR := "user://screenshots"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot"):
		save_screenshot()


func save_screenshot() -> String:
	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/autelia_%s.png" % [SCREENSHOT_DIR, stamp]
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Screenshot failed (%s): %s" % [error_string(error), path])
		return ""
	print("Screenshot saved: ", ProjectSettings.globalize_path(path))
	return path

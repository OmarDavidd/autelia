class_name GameSession
extends RefCounted
## What the main menu chose for this launch: the mode and the arcade player's name.
## Static, so it survives scene reloads (R and Reiniciar keep the same mode).
## The name is also saved to disk so the next launch suggests it.

enum Mode { EXPERIMENT, ARCADE }

const NAME_MIN := 3
const NAME_MAX := 16

static var mode := Mode.EXPERIMENT
static var player_name := ""
## Tests point this elsewhere so they never overwrite the player's saved name.
static var profile_path := "user://profile.cfg"


static func clean_name(raw: String) -> String:
	return raw.strip_edges()


static func is_valid_name(raw: String) -> bool:
	var length := clean_name(raw).length()
	return length >= NAME_MIN and length <= NAME_MAX


static func load_name() -> String:
	var config := ConfigFile.new()
	if config.load(profile_path) != OK:
		return ""
	return str(config.get_value("arcade", "name", ""))


static func save_name(value: String) -> void:
	var config := ConfigFile.new()
	config.set_value("arcade", "name", value)
	config.save(profile_path)

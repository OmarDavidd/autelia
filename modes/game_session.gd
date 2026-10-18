class_name GameSession
extends RefCounted
## What the main menu chose for this launch: the mode, the player's name and, for the daily
## challenge, which day is being played.
## Static, so it survives scene reloads (R and Reiniciar keep the same mode).
## The name is also saved to disk so the next launch suggests it.

enum Mode { EXPERIMENT, ARCADE, DAILY }

const NAME_MIN := 3
const NAME_MAX := 16

static var mode := Mode.EXPERIMENT
static var player_name := ""
## The daily challenge being played, as "YYYY-MM-DD". Kept across restarts, so a run that
## crosses midnight replays the same challenge.
static var challenge_day := ""
## Tests point this elsewhere so they never overwrite the player's saved name.
static var profile_path := "user://profile.cfg"


## The player's local date: like Wordle, the challenge changes at each player's midnight.
static func daily_day(date := {}) -> String:
	if date.is_empty():
		date = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [date.year, date.month, date.day]


## Everybody playing the same day gets the same seed, so the same enemies in the same places.
static func daily_seed(day: String) -> int:
	return absi(("autelia-daily-" + day).hash()) + 1


## "7/3" for "2026-03-07".
static func daily_label(day: String) -> String:
	var parts := day.split("-")
	return "%d/%d" % [int(parts[2]), int(parts[1])]


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

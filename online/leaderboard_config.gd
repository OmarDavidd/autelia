class_name LeaderboardConfig
extends RefCounted
## Supabase project behind the global Arcade leaderboard (see docs/leaderboard.sql).
## Read from online/leaderboard.cfg, which git ignores so the values stay out of the
## repository; copy online/leaderboard.example.cfg to create it. The export includes it.
## The publishable key still ships inside the game: that is what it is for, and Row Level
## Security only lets it read scores and insert new ones. Never use the secret key here.
## A missing file keeps the game offline: runs work and the table shows an error.

const PATH := "res://online/leaderboard.cfg"


static func value(field: String) -> String:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return ""
	return str(config.get_value("supabase", field, ""))

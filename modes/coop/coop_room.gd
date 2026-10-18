class_name CoopRoom
extends RefCounted
## A co-op room as the lobby sees it: its invite code and who is in it.
## Offline for now (the host can add bots); the game server will own rooms later.

signal changed

const MAX_PLAYERS := 8
const CODE_LENGTH := 4
## No I or O, so a code read aloud or typed on a phone is never mistaken for 1 or 0.
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"

var code := ""
## Each entry: {"name": String, "host": bool, "bot": bool}.
var players: Array[Dictionary] = []


static func create(host_name: String, rng: RandomNumberGenerator = null) -> CoopRoom:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var room := CoopRoom.new()
	for i in CODE_LENGTH:
		room.code += CODE_LETTERS[rng.randi_range(0, CODE_LETTERS.length() - 1)]
	room.players.append({"name": host_name, "host": true, "bot": false})
	return room


static func clean_code(raw: String) -> String:
	return raw.strip_edges().to_upper()


static func is_valid_code(raw: String) -> bool:
	var text := clean_code(raw)
	if text.length() != CODE_LENGTH:
		return false
	for letter in text:
		if not letter in CODE_LETTERS:
			return false
	return true


func is_full() -> bool:
	return players.size() >= MAX_PLAYERS


func add_bot() -> bool:
	if is_full():
		return false
	var bots := players.filter(func(p: Dictionary) -> bool: return p.bot).size()
	players.append({"name": "Bot %d" % (bots + 1), "host": false, "bot": true})
	changed.emit()
	return true

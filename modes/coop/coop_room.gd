class_name CoopRoom
extends RefCounted
## A co-op room as the lobby sees it: its invite code and who is in it.
## The game server owns the real rooms and sends each member a copy (to_dict/from_dict);
## without a server the lobby keeps a local one, where only bots can join.

signal changed

const MAX_PLAYERS := 8
const CODE_LENGTH := 4
## No I or O, so a code read aloud or typed on a phone is never mistaken for 1 or 0.
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"

var code := ""
## Each entry: {"id": int, "name": String, "host": bool, "bot": bool}. Humans carry their
## connection id on the server (the local host is 1); bots carry 0.
var players: Array[Dictionary] = []
## The host started the run; later joiners go straight into it.
var started := false
## This machine's player id; 1 in a local room, set by the server copy otherwise.
var you := 1


static func create(host_name: String, rng: RandomNumberGenerator = null, host_id := 1) -> CoopRoom:
	var room := CoopRoom.new()
	room.code = random_code(rng)
	room.players.append({"id": host_id, "name": host_name, "host": true, "bot": false})
	room.you = host_id
	return room


static func random_code(rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var text := ""
	for i in CODE_LENGTH:
		text += CODE_LETTERS[rng.randi_range(0, CODE_LETTERS.length() - 1)]
	return text


## The copy the server sends; `you` is filled in per member.
func to_dict() -> Dictionary:
	return {"code": code, "started": started, "players": players.duplicate(true)}


## Null when the data is not a room (the client never trusts it blindly).
static func from_dict(data: Variant, you_id: int) -> CoopRoom:
	if not data is Dictionary or not data.get("players") is Array or not data.get("code") is String:
		return null
	var room := CoopRoom.new()
	room.code = data.code
	room.started = data.get("started", false) == true
	room.you = you_id
	for entry: Variant in data.players:
		if not entry is Dictionary:
			return null
		room.players.append({"id": int(entry.get("id", 0)), "name": str(entry.get("name", "")),
			"host": entry.get("host", false) == true, "bot": entry.get("bot", false) == true})
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


func host_id() -> int:
	for entry in players:
		if entry.host:
			return entry.id
	return 0


func is_host() -> bool:
	return host_id() == you


func humans() -> int:
	return players.filter(func(p: Dictionary) -> bool: return not p.bot).size()


func add_player(player_name: String, id: int) -> bool:
	if is_full():
		return false
	players.append({"id": id, "name": player_name, "host": false, "bot": false})
	changed.emit()
	return true


## Removes a human; the next human (in joining order) becomes host. Bots stay.
func remove_player(id: int) -> void:
	var was_host := false
	for i in players.size():
		if players[i].id == id and not players[i].bot:
			was_host = players[i].host
			players.remove_at(i)
			break
	if was_host:
		for entry in players:
			if not entry.bot:
				entry.host = true
				break
	changed.emit()


func add_bot() -> bool:
	if is_full():
		return false
	var bots := players.filter(func(p: Dictionary) -> bool: return p.bot).size()
	players.append({"id": 0, "name": "Bot %d" % (bots + 1), "host": false, "bot": true})
	changed.emit()
	return true

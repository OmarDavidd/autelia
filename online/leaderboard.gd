class_name Leaderboard
extends Node
## Global Arcade leaderboard on Supabase, through its REST API.
## Submits a finished run, then loads the top scores. Any failure (offline, not configured,
## server error) ends in `failed`: the game never waits on the network to keep playing.

signal top_loaded(rows: Array)
signal failed

const TOP_SIZE := 10
const TIMEOUT := 8.0
## Daily rows fetched before keeping each player's best, so repeat players still leave
## room for ten names.
const DAILY_FETCH := 50

## Tests and scripted captures turn this off so they never reach the network.
static var enabled := true

var url := LeaderboardConfig.value("url")
var key := LeaderboardConfig.value("key")
## Empty for the all-time Arcade table; a "YYYY-MM-DD" day for that daily challenge.
var day := ""


static func headers(api_key: String) -> PackedStringArray:
	var result := PackedStringArray(["apikey: " + api_key, "Content-Type: application/json"])
	# Legacy anon keys are JWTs and also go as bearer; new publishable keys must not.
	if api_key.begins_with("eyJ"):
		result.append("Authorization: Bearer " + api_key)
	return result


static func insert_body(player_name: String, score: int, wave: int, challenge_day := "") -> String:
	var body := {"name": player_name, "score": score, "wave": wave}
	if not challenge_day.is_empty():
		body.day = challenge_day
	return JSON.stringify(body)


static func table_path(challenge_day: String) -> String:
	return "/rest/v1/scores" if challenge_day.is_empty() else "/rest/v1/daily_scores"


static func top_query(challenge_day := "") -> String:
	if challenge_day.is_empty():
		return "/rest/v1/scores?select=name,score,wave&order=score.desc,created_at.asc&limit=%d" % TOP_SIZE
	return "/rest/v1/daily_scores?select=name,score,wave&day=eq.%s&order=score.desc,created_at.asc&limit=%d" \
		% [challenge_day, DAILY_FETCH]


## Rows sorted best first; keeps each name's first (best) row, up to the top size.
static func best_per_player(rows: Array) -> Array:
	var seen := {}
	var best := []
	for row in rows:
		if seen.has(row.name):
			continue
		seen[row.name] = true
		best.append(row)
		if best.size() == TOP_SIZE:
			break
	return best


## Keeps only well-formed rows; anything else parses to an empty list.
static func parse_rows(body: PackedByteArray) -> Array:
	var json := JSON.new()
	var rows := []
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Array:
		return rows
	for item in json.data:
		if item is Dictionary and item.get("name") is String \
				and item.get("score") is float and item.get("wave") is float:
			rows.append({"name": item.name, "score": int(item.score), "wave": int(item.wave)})
	return rows


## No gzip: in the web build the browser already decompresses the answer, and Godot trying
## again fails with RESULT_BODY_DECOMPRESS_FAILED once Supabase starts compressing.
static func make_request() -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.accept_gzip = false
	return http


func is_configured() -> bool:
	return enabled and not url.is_empty() and not key.is_empty()


## Runs with no points are not stored, but the table is still loaded.
func submit_and_fetch(player_name: String, score: int, wave: int) -> void:
	if not is_configured():
		failed.emit.call_deferred()
		return
	if score > 0:
		var sent := await _request(HTTPClient.METHOD_POST, table_path(day),
			insert_body(player_name, score, wave, day), ["Prefer: return=minimal"])
		if sent.is_empty():
			failed.emit()
			return
	await fetch_top()


## Loads the top scores without submitting anything.
func fetch_top() -> void:
	if not is_configured():
		failed.emit.call_deferred()
		return
	var top := await _request(HTTPClient.METHOD_GET, top_query(day))
	if top.is_empty():
		failed.emit()
		return
	var rows := parse_rows(top.body)
	top_loaded.emit(rows if day.is_empty() else best_per_player(rows))


## Returns {"body": PackedByteArray} on a 2xx answer, or an empty dictionary on any failure.
func _request(method: HTTPClient.Method, path: String, body := "", extra: Array = []) -> Dictionary:
	var http := make_request()
	add_child(http)
	var request_headers := headers(key)
	request_headers.append_array(extra)
	if http.request(url.trim_suffix("/") + path, request_headers, method, body) != OK:
		http.queue_free()
		return {}
	var answer: Array = await http.request_completed
	http.queue_free()
	var code: int = answer[1]
	if answer[0] != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		push_warning("Leaderboard request failed: result %d, HTTP %d" % [answer[0], code])
		return {}
	return {"body": answer[3]}

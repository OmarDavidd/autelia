extends Node
## Headless entry point of the co-op game server:
##   godot --headless --path . server/server.tscn -- --port=8910 --bind=127.0.0.1
## It only listens on this machine by default; the tunnel brings players in.


func _ready() -> void:
	var port := RoomServer.DEFAULT_PORT
	var bind_address := "127.0.0.1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--bind="):
			bind_address = arg.get_slice("=", 1)
	var server := RoomServer.new()
	add_child(server)
	var error := server.start(port, bind_address)
	if error != OK:
		printerr("Room server could not listen on %s:%d (%s)" % [bind_address, port, error_string(error)])
		get_tree().quit(1)
		return
	print("Room server listening on %s:%d" % [bind_address, port])

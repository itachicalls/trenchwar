extends Node
## Headless / dedicated lobby+match host.
## Run:
##   tools/Godot_v4.3-stable_win64_console.exe --headless --path . res://server/ServerMain.tscn
##
## Clients join with:  ws://YOUR_IP:9080
## Behind HTTPS (Vercel), put nginx/caddy TLS in front and use wss://YOUR_DOMAIN

func _ready() -> void:
	print("[Trenchwar Server] starting on port %d…" % Net.DEFAULT_PORT)
	var err := Net.host_game(Net.DEFAULT_PORT, "skirmish")
	if err != OK:
		push_error("[Trenchwar Server] bind failed: %s" % error_string(err))
		get_tree().quit()
		return
	print("[Trenchwar Server] listening. Share: %s" % Net.host_address_hint())
	print("[Trenchwar Server] Web clients on HTTPS pages need wss:// via a TLS reverse-proxy.")
	Net.match_starting.connect(_on_match_starting)

func _on_match_starting(mode_id: String) -> void:
	print("[Trenchwar Server] match start requested: ", mode_id)
	# Dedicated server stays in lobby authority role; the host peer that clicked
	# Start runs the arena scene. Pure headless can be extended to simulate later.

extends Node
## Throwaway harness: connects to a local dedicated server and pushes one of
## every combat RPC across the wire. Arg-count mismatches in @rpc functions
## only blow up at runtime, so this is the cheapest way to prove the PvP
## replication path before shipping a build people wager on.
##   godot --headless --path . res://server/NetSmoke.tscn

func _ready() -> void:
	Net.connection_succeeded.connect(_on_connected)
	Net.connection_failed.connect(func(reason): _fail("connect failed: " + reason))
	var port := Net.DEFAULT_PORT
	var env_port := OS.get_environment("TRENCHWAR_PORT").strip_edges()
	if env_port.is_valid_int():
		port = env_port.to_int()
	var url := OS.get_environment("TRENCHWAR_SMOKE_URL").strip_edges()
	if url == "":
		url = "ws://127.0.0.1:%d" % port
	print("[smoke] dialing ", url)
	var err := Net.join_game(url)
	if err != OK:
		_fail("join_game error %s" % error_string(err))
		return
	await get_tree().create_timer(12.0).timeout
	_fail("timed out")

func _on_connected() -> void:
	await get_tree().create_timer(1.0).timeout
	print("[smoke] connected as peer %d" % Net.my_id())
	Net.broadcast_pose(Vector3(1, 0, 2), 0.5, Vector3(1, 0, 0))
	Net.broadcast_shot(Vector3(1, 1, 2), Vector3(0, 0, -1), "res://data/weapons/plastic_rifle.tres")
	Net.broadcast_health(140.0, 200.0, true)
	Net.report_hit(1, 25.0)
	Net.confirm_hit(1, 25.0, false)
	Net.announce_down(1)
	Net.report_bot_hit(1, 10.0)
	await get_tree().create_timer(1.5).timeout
	print("[smoke] all combat RPCs sent without error")
	get_tree().quit(0)

func _fail(msg: String) -> void:
	printerr("[smoke] FAILED: ", msg)
	get_tree().quit(1)

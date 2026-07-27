extends Node
## Throwaway harness: drives a real client against a real dedicated server.
## RPC arg mismatches and protocol deadlocks only surface at runtime, so this
## is the cheapest way to prove the PvP paths before shipping a build people
## wager on.
##
##   TRENCHWAR_SMOKE_ROLE=rpc     one client, fires every combat RPC
##   TRENCHWAR_SMOKE_ROLE=caller  asks for a match timeout, then resumes it
##   TRENCHWAR_SMOKE_ROLE=voter   agrees to the timeout
##
##   godot --headless --path . res://server/NetSmoke.tscn

var _role := "rpc"
var _started := false
var _saw_pause := false

func _ready() -> void:
	_role = OS.get_environment("TRENCHWAR_SMOKE_ROLE").strip_edges()
	if _role == "":
		_role = "rpc"
	Net.connection_succeeded.connect(_on_connected)
	Net.connection_failed.connect(func(reason): _fail("connect failed: " + reason))
	Net.match_starting.connect(_on_match_starting)
	Net.pause_vote_opened.connect(_on_vote_opened)
	Net.pause_vote_closed.connect(func(ok: bool, why: String):
		print("[smoke:%s] vote closed accepted=%s %s" % [_role, ok, why])
		if not ok and OS.get_environment("TRENCHWAR_SMOKE_DENY") == "1":
			_after_denial())
	Net.pause_started.connect(_on_pause_started)
	Net.pause_ended.connect(_on_pause_ended)
	Net.pause_refused.connect(func(why: String):
		if OS.get_environment("TRENCHWAR_SMOKE_DENY") == "1":
			print("[smoke:%s] server refused the repeat request: %s" % [_role, why])
		else:
			_fail("pause refused: " + why))
	var port := Net.DEFAULT_PORT
	var env_port := OS.get_environment("TRENCHWAR_PORT").strip_edges()
	if env_port.is_valid_int():
		port = env_port.to_int()
	var url := OS.get_environment("TRENCHWAR_SMOKE_URL").strip_edges()
	if url == "":
		url = "ws://127.0.0.1:%d" % port
	print("[smoke:%s] dialing %s" % [_role, url])
	var err := Net.join_game(url)
	if err != OK:
		_fail("join_game error %s" % error_string(err))
		return
	await get_tree().create_timer(150.0, true).timeout
	_fail("timed out (saw_pause=%s)" % _saw_pause)

func _on_connected() -> void:
	await get_tree().create_timer(1.0).timeout
	print("[smoke:%s] connected as peer %d" % [_role, Net.my_id()])
	if _role == "rpc":
		_fire_combat_rpcs()
		return
	if _role == "caller":
		# Give the voter time to land in the room before starting the match.
		await get_tree().create_timer(4.0).timeout
		if Net.peer_count() < 2:
			_fail("voter never joined (peers=%d)" % Net.peer_count())
			return
		print("[smoke:caller] starting match with %d peers" % Net.peer_count())
		Net.request_start_match()

func _fire_combat_rpcs() -> void:
	Net.broadcast_pose(Vector3(1, 0, 2), 0.5, Vector3(1, 0, 0))
	Net.broadcast_shot(Vector3(1, 1, 2), Vector3(0, 0, -1), "res://data/weapons/plastic_rifle.tres")
	Net.broadcast_health(140.0, 200.0, true)
	Net.report_hit(1, 25.0)
	Net.confirm_hit(1, 25.0, false)
	Net.announce_down(1)
	Net.report_bot_hit(1, 10.0)
	await get_tree().create_timer(1.5).timeout
	print("[smoke:rpc] all combat RPCs sent without error")
	get_tree().quit(0)

func _on_match_starting(mode_id: String) -> void:
	if _started:
		return
	_started = true
	print("[smoke:%s] match starting: %s" % [_role, mode_id])
	if _role != "caller":
		return
	await get_tree().create_timer(2.0).timeout
	print("[smoke:caller] requesting timeout")
	Net.request_pause()

func _on_vote_opened(requester_id: int, seconds: float) -> void:
	print("[smoke:%s] vote opened by %d (%.0fs)" % [_role, requester_id, seconds])
	if _role != "voter":
		return
	await get_tree().create_timer(1.0).timeout
	if OS.get_environment("TRENCHWAR_SMOKE_DENY") == "1":
		print("[smoke:voter] refusing the timeout")
		Net.answer_pause(false)
		return
	print("[smoke:voter] agreeing to the timeout")
	Net.answer_pause(true)

func _on_pause_started(requester_id: int, seconds: float) -> void:
	_saw_pause = true
	print("[smoke:%s] PAUSE STARTED by %d for %.0fs (tree paused=%s)"
		% [_role, requester_id, seconds, get_tree().paused])
	if _role != "caller":
		return
	if OS.get_environment("TRENCHWAR_SMOKE_NORESUME") == "1":
		print("[smoke:caller] camping the pause — server must time it out")
		return
	# SceneTreeTimer with process_always so the harness can act while frozen,
	# exactly like the real pause menu's resume button.
	await get_tree().create_timer(3.0, true).timeout
	print("[smoke:caller] pause clock now %.1fs — resuming" % Net.pause_seconds_left)
	Net.resume_pause()

func _on_pause_ended(reason: String) -> void:
	if not _saw_pause:
		return
	print("[smoke:%s] PAUSE ENDED (%s)" % [_role, reason])
	await get_tree().create_timer(1.0, true).timeout
	print("[smoke:%s] OK" % _role)
	get_tree().quit(0)

## After a refusal nobody may be frozen, and the requester must be held off by
## the cooldown rather than allowed to spam the prompt again immediately.
func _after_denial() -> void:
	await get_tree().create_timer(1.0, true).timeout
	if Net.pause_active or get_tree().paused:
		_fail("denied vote still froze the match")
		return
	if _role == "caller":
		print("[smoke:caller] denied — asking again immediately (must be refused)")
		Net.request_pause()
		await get_tree().create_timer(2.0, true).timeout
		if Net.pause_active or Net.pause_vote_open:
			_fail("cooldown did not block a repeat request")
			return
	print("[smoke:%s] OK (denial handled, match still live)" % _role)
	get_tree().quit(0)

func _fail(msg: String) -> void:
	printerr("[smoke:%s] FAILED: %s" % [_role, msg])
	get_tree().quit(1)

extends Node
## Headless dedicated lobby + match authority.
##   godot --headless --path . res://server/ServerMain.tscn
## Public wss:// via Caddy / Fly — see server/README.md

const MODES := {
	"skirmish": preload("res://scripts/rooms/SkirmishMode.gd"),
	"royale": preload("res://scripts/rooms/RoyaleMode.gd"),
	"tank_battle": preload("res://scripts/rooms/TankBattleMode.gd"),
	"plane_race": preload("res://scripts/rooms/PlaneRaceMode.gd"),
	"hold_dune": preload("res://scripts/rooms/HoldDuneMode.gd"),
}

var _arena: Node3D = null

func _ready() -> void:
	var port := Net.DEFAULT_PORT
	var env_port := OS.get_environment("TRENCHWAR_PORT").strip_edges()
	if env_port.is_valid_int():
		port = env_port.to_int()
	print("[Trenchwar Server] starting dedicated host on port %d…" % port)
	var err := Net.host_game(port, "skirmish", true)
	if err != OK:
		push_error("[Trenchwar Server] bind failed: %s" % error_string(err))
		get_tree().quit()
		return
	print("[Trenchwar Server] room code: %s" % Net.room_code)
	print("[Trenchwar Server] LAN: ws://<ip>:%d" % port)
	print("[Trenchwar Server] Public clients need wss:// via Caddy/Fly (see server/README.md).")
	Net.match_starting.connect(_on_match_starting)
	Net.match_ended.connect(_on_match_ended)
	Events.mission_completed.connect(_on_mission_done)
	Events.mission_failed.connect(_on_mission_done)

func _on_match_starting(mode_id: String) -> void:
	print("[Trenchwar Server] match start: ", mode_id)
	_clear_arena()
	if not MODES.has(mode_id):
		push_error("[Trenchwar Server] unknown mode " + mode_id)
		return
	Game.state = Game.State.PLAYING
	Game.squad.clear()
	Game.plastic_parts = 0
	Game.kills = 0
	_arena = MODES[mode_id].new()
	add_child(_arena)

func _on_match_ended(_green_won: bool, _win_title: String, _lose_reason: String) -> void:
	print("[Trenchwar Server] match ended — returning to lobby. New code: ", Net.room_code)
	await get_tree().create_timer(2.0).timeout
	_clear_arena()
	Game.state = Game.State.MENU

func _on_mission_done(_msg: String = "") -> void:
	# Mode scripts emit Events; dedicated already gets Net.match_ended from resolve.
	if Net.is_match_authority() and Net.match_active:
		# Fallback if a mode called win/lose without broadcast_match_end.
		pass

func _clear_arena() -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	Game.mode_respawns = false

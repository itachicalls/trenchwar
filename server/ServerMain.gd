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
	# The authority simulates the bots, so it has to freeze with the players or
	# the arena would keep fighting through a timeout.
	Net.pause_started.connect(func(_id: int, _secs: float): get_tree().paused = true)
	Net.pause_ended.connect(func(_reason: String): get_tree().paused = false)
	Net.squad_match_ended.connect(_on_squad_ended)
	Net.race_won.connect(_on_race_ended)
	Net.match_abandoned.connect(_on_match_abandoned)
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
	await _return_to_lobby("team match")

func _on_squad_ended(winner_squad: String, _win_title: String) -> void:
	await _return_to_lobby("royale %s" % winner_squad)

func _on_race_ended(peer_id: int) -> void:
	await _return_to_lobby("race peer %d" % peer_id)

func _on_match_abandoned() -> void:
	await _return_to_lobby("all players left")

func _return_to_lobby(reason: String) -> void:
	print("[Trenchwar Server] match ended (%s) — lobby code: %s" % [reason, Net.room_code])
	await get_tree().create_timer(2.0).timeout
	_clear_arena()
	Game.state = Game.State.MENU

func _on_mission_done(_msg: String = "") -> void:
	# Mode scripts emit Events; dedicated already tears down via Net end signals.
	pass

func _clear_arena() -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
	Game.mode_respawns = false

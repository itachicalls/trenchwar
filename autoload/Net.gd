extends Node
## Online multiplayer: desktop hosts a WebSocket listen-server; everyone joins
## with a room address. Web clients cannot host (browser limit) — they join a
## desktop host or a dedicated headless server.
##
## Protocol: Godot high-level multiplayer over WebSocketMultiplayerPeer
## (works on HTML5 + desktop). Match authority = peer 1 (host).

signal lobby_changed
signal match_starting(mode_id: String)
signal peer_list_changed
signal connection_failed(reason: String)
signal connection_succeeded
signal peer_pose(peer_id: int, pos: Vector3, yaw: float, vel: Vector3)
signal peer_hurt(peer_id: int, amount: float)
signal peer_down(peer_id: int)
signal race_won(peer_id: int)

const DEFAULT_PORT := 9080
const MAX_PLAYERS := 8
const FACTION_PATHS := {
	"green_army": "res://data/factions/green_army.tres",
	"chrome_legion": "res://data/factions/chrome_legion.tres",
	"brick_kingdom": "res://data/factions/brick_kingdom.tres",
	"wind_up_empire": "res://data/factions/wind_up_empire.tres",
}

## green_army / chrome_legion / brick_kingdom / wind_up_empire
var local_team: String = "green_army"
var selected_mode: String = "skirmish"
var room_code: String = ""
var status_text: String = "Offline"
var is_online: bool = false
var is_host: bool = false
var peers: Dictionary = {}   # peer_id -> {name, team, ready}
var pending_mode: String = ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func reset() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_online = false
	is_host = false
	peers.clear()
	room_code = ""
	status_text = "Offline"
	pending_mode = ""
	lobby_changed.emit()
	peer_list_changed.emit()

func my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0

func peer_count() -> int:
	return peers.size()

func can_host() -> bool:
	return not OS.has_feature("web")

func humans_on_team(team: String) -> int:
	var n := 0
	for p in peers.values():
		if str(p.get("team", "")) == team:
			n += 1
	return n

func faction_path(team: String = "") -> String:
	var t := team if team != "" else local_team
	return FACTION_PATHS.get(t, FACTION_PATHS["green_army"])

## Desktop listen-server. Web cannot bind sockets — use join instead.
func host_game(port: int = DEFAULT_PORT, mode_id: String = "skirmish") -> Error:
	if not can_host():
		connection_failed.emit("Browsers can't host. Join a desktop host, or run the dedicated server.")
		return ERR_UNAVAILABLE
	reset()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		connection_failed.emit("Could not open port %d (is it in use?)." % port)
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	is_host = true
	selected_mode = mode_id
	room_code = _make_room_code(port)
	status_text = "Hosting — share %s" % room_code
	_register_self()
	lobby_changed.emit()
	connection_succeeded.emit()
	return OK

## Join via ws://host:port  (use wss:// behind TLS reverse-proxy for HTTPS sites).
func join_game(address: String) -> Error:
	reset()
	var url := address.strip_edges()
	if url.is_empty():
		connection_failed.emit("Enter a host address.")
		return ERR_INVALID_PARAMETER
	if not url.contains("://"):
		url = "ws://%s" % url
	if not url.contains(":" + str(DEFAULT_PORT)) and url.count(":") < 2:
		if url.begins_with("ws://") or url.begins_with("wss://"):
			var bare := url.split("://")[1]
			if not bare.contains(":"):
				url = "%s:%d" % [url, DEFAULT_PORT]
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		connection_failed.emit("Join failed (%s)." % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	status_text = "Connecting to %s…" % url
	lobby_changed.emit()
	return OK

func set_mode(mode_id: String) -> void:
	selected_mode = mode_id
	if is_host and is_online:
		_sync_lobby.rpc(peers, selected_mode, room_code)
		lobby_changed.emit()

func set_ready(ready: bool) -> void:
	if not is_online:
		return
	if is_host:
		if peers.has(my_id()):
			peers[my_id()].ready = ready
			_sync_lobby.rpc(peers, selected_mode, room_code)
			peer_list_changed.emit()
	else:
		rpc_id(1, "_rpc_set_ready", ready)

func set_team(team: String) -> void:
	local_team = team
	if not is_online:
		return
	if is_host:
		_apply_team(my_id(), team)
	else:
		rpc_id(1, "_rpc_set_team", team)

func host_start_match() -> void:
	if not is_host or not is_online:
		return
	pending_mode = selected_mode
	_rpc_start_match.rpc(selected_mode)

@rpc("authority", "call_local", "reliable")
func _rpc_start_match(mode_id: String) -> void:
	pending_mode = mode_id
	selected_mode = mode_id
	status_text = "Starting %s…" % mode_id
	match_starting.emit(mode_id)

@rpc("any_peer", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if peers.has(id):
		peers[id].ready = ready
		_sync_lobby.rpc(peers, selected_mode, room_code)
		peer_list_changed.emit()

@rpc("any_peer", "reliable")
func _rpc_set_team(team: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_apply_team(id, team)

func _apply_team(id: int, team: String) -> void:
	if not peers.has(id):
		return
	peers[id].team = team
	_sync_lobby.rpc(peers, selected_mode, room_code)
	peer_list_changed.emit()

@rpc("authority", "call_local", "reliable")
func _sync_lobby(peer_map: Dictionary, mode_id: String, code: String) -> void:
	peers = peer_map
	selected_mode = mode_id
	room_code = code
	is_online = true
	status_text = "In lobby — %d player(s)" % peers.size()
	lobby_changed.emit()
	peer_list_changed.emit()

@rpc("any_peer", "reliable")
func _rpc_hello(player_name: String, team: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	peers[id] = {"name": player_name, "team": team, "ready": false}
	_sync_lobby.rpc(peers, selected_mode, room_code)
	peer_list_changed.emit()

func _register_self() -> void:
	var nm := "Host" if is_host else ("Soldier-%d" % my_id())
	peers[my_id()] = {"name": nm, "team": local_team, "ready": is_host, "id": my_id()}
	peer_list_changed.emit()

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		peers[id] = {"name": "Soldier-%d" % id, "team": _auto_team(), "ready": false}
		_sync_lobby.rpc(peers, selected_mode, room_code)
	peer_list_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	if multiplayer.is_server():
		_sync_lobby.rpc(peers, selected_mode, room_code)
	peer_list_changed.emit()

func _on_connected_ok() -> void:
	is_online = true
	is_host = false
	status_text = "Connected"
	rpc_id(1, "_rpc_hello", "Soldier-%d" % my_id(), local_team)
	connection_succeeded.emit()
	lobby_changed.emit()

func _on_connected_fail() -> void:
	reset()
	connection_failed.emit("Could not reach host. Check address / firewall / server running.")

func _on_server_disconnected() -> void:
	reset()
	connection_failed.emit("Host disconnected.")
	status_text = "Disconnected"

func _auto_team() -> String:
	var green := 0
	var chrome := 0
	for p in peers.values():
		if p.team == "green_army":
			green += 1
		elif p.team == "chrome_legion":
			chrome += 1
	return "chrome_legion" if green > chrome else "green_army"

func _make_room_code(port: int) -> String:
	var ips := IP.get_local_addresses()
	var pick := "127.0.0.1"
	for ip in ips:
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			pick = ip
			break
	return "%s:%d" % [pick, port]

func host_address_hint() -> String:
	return room_code if room_code != "" else ("127.0.0.1:%d" % DEFAULT_PORT)

func team_for_peer(peer_id: int) -> String:
	if peers.has(peer_id):
		return str(peers[peer_id].get("team", "green_army"))
	return "green_army"

func name_for_peer(peer_id: int) -> String:
	if peers.has(peer_id):
		return str(peers[peer_id].get("name", "Soldier-%d" % peer_id))
	return "Soldier-%d" % peer_id

func is_match_authority() -> bool:
	return (not is_online) or multiplayer.is_server()

## ---- in-match sync --------------------------------------------------------

func broadcast_pose(pos: Vector3, yaw: float, vel: Vector3) -> void:
	if not is_online:
		return
	_rpc_pose.rpc(my_id(), pos, yaw, vel)

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_pose(id: int, pos: Vector3, yaw: float, vel: Vector3) -> void:
	peer_pose.emit(id, pos, yaw, vel)

func report_hit(victim_peer_id: int, amount: float) -> void:
	if not is_online or amount <= 0.0:
		return
	_rpc_hit.rpc(victim_peer_id, amount)

@rpc("any_peer", "reliable", "call_local")
func _rpc_hit(victim_id: int, amount: float) -> void:
	peer_hurt.emit(victim_id, amount)

func announce_down() -> void:
	if not is_online:
		return
	_rpc_down.rpc(my_id())

@rpc("any_peer", "reliable", "call_local")
func _rpc_down(id: int) -> void:
	peer_down.emit(id)

func announce_race_win() -> void:
	if not is_online:
		return
	_rpc_race_win.rpc(my_id())

@rpc("any_peer", "reliable", "call_local")
func _rpc_race_win(id: int) -> void:
	race_won.emit(id)

extends Node
## Online multiplayer over WebSocketMultiplayerPeer.
## Desktop can listen-host; web/mobile join only.
## Public play: join DEFAULT_WSS_URL (wss:// behind TLS) — see server/README.md.

signal lobby_changed
signal match_starting(mode_id: String)
signal peer_list_changed
signal connection_failed(reason: String)
signal connection_succeeded
signal peer_pose(peer_id: int, pos: Vector3, yaw: float, vel: Vector3)
signal peer_hurt(peer_id: int, amount: float, attacker_id: int)
signal peer_down(peer_id: int)
signal peer_shot(peer_id: int, origin: Vector3, dir: Vector3, weapon_path: String)
signal peer_health(peer_id: int, hp: float, max_hp: float)
signal hit_landed(victim_id: int, amount: float, killed: bool)
signal kill_feed(killer_id: int, victim_id: int)
signal race_won(peer_id: int)
signal bot_spawned(bot_id: int, team: String, pos: Vector3, variant: String)
signal bot_pose(bot_id: int, pos: Vector3, yaw: float, hp_ratio: float)
signal bot_shot(bot_id: int, origin: Vector3, dir: Vector3, weapon_path: String)
signal bot_hurt(bot_id: int, amount: float)
signal bot_died(bot_id: int)
signal match_ended(winner_is_green: bool, win_title: String, lose_reason: String)
signal squad_match_ended(winner_squad: String, win_title: String)
signal score_synced(green_score: int, chrome_score: int)
signal hold_synced(hold_amount: float, wave: int, time_left: float)
signal hull_lost(victim_team: String)

const DEFAULT_PORT := 9080
const MAX_PLAYERS := 8
## Fallback only — live URL comes from web/net_config.json (Cloudflare tunnel).
const DEFAULT_WSS_URL := ""
const FACTION_PATHS := {
	"green_army": "res://data/factions/green_army.tres",
	"chrome_legion": "res://data/factions/chrome_legion.tres",
	"brick_kingdom": "res://data/factions/brick_kingdom.tres",
	"wind_up_empire": "res://data/factions/wind_up_empire.tres",
}

var local_team: String = "green_army"
var selected_mode: String = "skirmish"
var room_code: String = ""
var status_text: String = "Offline"
var is_online: bool = false
var is_host: bool = false
## Headless dedicated authority — not a playable soldier.
var is_dedicated: bool = false
var peers: Dictionary = {}   # peer_id -> {name, team, ready}
var pending_mode: String = ""
var match_active: bool = false
var _wanted_room_code: String = ""
var _config_wss: String = ""
var _config_wager_api: String = ""
var _config_cluster: String = "devnet"
var stake_sol: float = 0.0
var local_wallet: String = ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_load_net_config()

func public_ws_url() -> String:
	var env := OS.get_environment("TRENCHWAR_WS_URL").strip_edges()
	if env != "":
		return env
	if _config_wss != "":
		return _config_wss
	return DEFAULT_WSS_URL

func wager_api_url() -> String:
	var env := OS.get_environment("TRENCHWAR_WAGER_API").strip_edges()
	if env != "":
		return env
	# Dedicated/listen host settles via local gateway (Cloudflare fronts clients only).
	if is_dedicated or (is_online and multiplayer.is_server()):
		return "http://127.0.0.1:9081"
	return _config_wager_api

func solana_cluster() -> String:
	return _config_cluster

func _load_net_config() -> void:
	# Prefer static file next to index.html (Vercel) so tunnel URL updates without re-export.
	if OS.has_feature("web"):
		var h := HTTPRequest.new()
		add_child(h)
		h.request_completed.connect(func(result, code, _h, body):
			h.queue_free()
			if result == HTTPRequest.RESULT_SUCCESS and code == 200:
				_apply_net_config(body.get_string_from_utf8())
		, CONNECT_ONE_SHOT)
		var origin := str(JavaScriptBridge.eval("window.location.origin", true))
		var url := "net_config.json"
		if origin.begins_with("http"):
			url = "%s/net_config.json" % origin
		h.request(url)
		return
	if FileAccess.file_exists("res://web/net_config.json"):
		var f := FileAccess.open("res://web/net_config.json", FileAccess.READ)
		if f:
			_apply_net_config(f.get_as_text())

func _apply_net_config(text: String) -> void:
	# Strip UTF-8 BOM if present (PowerShell Set-Content often adds it).
	if text.length() > 0 and text.unicode_at(0) == 0xFEFF:
		text = text.substr(1)
	text = text.strip_edges()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_config_wss = str(data.get("wss", "")).strip_edges()
	_config_wager_api = str(data.get("wager_api", "")).strip_edges()
	_config_cluster = str(data.get("solana_cluster", "devnet"))
	if _config_wager_api != "":
		Wager.configure(_config_wager_api, _config_cluster)
	lobby_changed.emit()

func reset() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_online = false
	is_host = false
	# Keep is_dedicated if this process is the dedicated server binary.
	if not OS.get_environment("TRENCHWAR_DEDICATED") in ["1", "true", "TRUE"]:
		is_dedicated = false
	peers.clear()
	room_code = ""
	status_text = "Offline"
	pending_mode = ""
	match_active = false
	_wanted_room_code = ""
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

func is_match_authority() -> bool:
	return (not is_online) or multiplayer.is_server()

func is_lobby_leader() -> bool:
	if not is_online:
		return false
	# Dedicated process is never a playable lobby leader.
	if is_dedicated:
		return false
	if is_host:
		return true
	var lowest := _lowest_human_id()
	return lowest > 0 and lowest == my_id()

func _lowest_human_id() -> int:
	# Skip peer id 1 when a dedicated server owns it — humans start at 2+.
	var best := 999999
	for id in peers.keys():
		var pid := int(id)
		if pid <= 0:
			continue
		if is_dedicated and pid == 1:
			continue
		if pid < best:
			best = pid
	return best if best < 999999 else 0

func can_request_start() -> bool:
	if not is_online or match_active:
		return false
	if peers.is_empty():
		return false
	# Free play: anyone in the room can start. Staked: need funded pot.
	if stake_sol > 0.0:
		return Wager.pot_ready or Wager.status == "funded"
	return true

## ---- host / join ----------------------------------------------------------

func host_game(port: int = DEFAULT_PORT, mode_id: String = "skirmish", dedicated: bool = false) -> Error:
	if not can_host():
		connection_failed.emit("Browsers can't host. Use Quick Play / Join on the public server.")
		return ERR_UNAVAILABLE
	reset()
	is_dedicated = dedicated or OS.get_environment("TRENCHWAR_DEDICATED") in ["1", "true", "TRUE"]
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		connection_failed.emit("Could not open port %d (is it in use?)." % port)
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	is_host = true
	selected_mode = mode_id
	room_code = _generate_room_code()
	status_text = "Hosting room %s" % room_code
	_register_self()
	lobby_changed.emit()
	connection_succeeded.emit()
	return OK

func join_game(address: String, code: String = "") -> Error:
	reset()
	_wanted_room_code = code.strip_edges().to_upper()
	var url := address.strip_edges()
	if url.is_empty():
		connection_failed.emit("Enter a host address.")
		return ERR_INVALID_PARAMETER
	if not url.contains("://"):
		# Prefer wss for bare hostnames (public); ws for raw IPs.
		if url.begins_with("127.") or url.begins_with("192.168.") or url.begins_with("10.") \
				or url.begins_with("localhost"):
			url = "ws://%s" % url
		else:
			url = "wss://%s" % url
	if url.begins_with("ws://") or url.begins_with("wss://"):
		var bare := url.split("://")[1]
		if not bare.contains("/") and not bare.contains(":"):
			if url.begins_with("ws://"):
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

func quick_play(mode_id: String = "") -> Error:
	if mode_id != "":
		selected_mode = mode_id
	return join_game(public_ws_url(), "")

func join_room_code(code: String) -> Error:
	return join_game(public_ws_url(), code)

func create_public_room(mode_id: String = "skirmish") -> Error:
	selected_mode = mode_id
	# Join public dedicated server; first human becomes lobby leader.
	return join_game(public_ws_url(), "")

func set_mode(mode_id: String) -> void:
	selected_mode = mode_id
	if not is_online:
		return
	if multiplayer.is_server():
		_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)
		lobby_changed.emit()
	elif is_lobby_leader():
		rpc_id(1, "_rpc_request_mode", mode_id)

@rpc("any_peer", "reliable")
func _rpc_request_mode(mode_id: String) -> void:
	if not multiplayer.is_server():
		return
	selected_mode = mode_id
	_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)

func set_ready(ready: bool) -> void:
	if not is_online:
		return
	if multiplayer.is_server() and not is_dedicated:
		if peers.has(my_id()):
			peers[my_id()].ready = ready
			_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)
			peer_list_changed.emit()
	else:
		rpc_id(1, "_rpc_set_ready", ready)

func set_stake(sol: float) -> void:
	stake_sol = sol
	Wager.set_stake(sol)
	if not is_online:
		return
	if multiplayer.is_server():
		_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)
		lobby_changed.emit()
	elif is_lobby_leader():
		rpc_id(1, "_rpc_request_stake", sol)

@rpc("any_peer", "reliable")
func _rpc_request_stake(sol: float) -> void:
	if not multiplayer.is_server():
		return
	stake_sol = sol
	_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)

func set_wallet(pubkey: String) -> void:
	local_wallet = pubkey
	if not is_online:
		return
	if multiplayer.is_server() and not is_dedicated:
		if peers.has(my_id()):
			peers[my_id()].wallet = pubkey
			_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)
	else:
		rpc_id(1, "_rpc_set_wallet", pubkey)

@rpc("any_peer", "reliable")
func _rpc_set_wallet(pubkey: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if peers.has(id):
		peers[id].wallet = pubkey
		_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)

func set_team(team: String) -> void:
	local_team = team
	if not is_online:
		return
	if multiplayer.is_server() and not is_dedicated:
		_apply_team(my_id(), team)
	else:
		rpc_id(1, "_rpc_set_team", team)

func host_start_match() -> void:
	request_start_match()

func request_start_match() -> void:
	if not is_online:
		return
	if multiplayer.is_server():
		_try_start_match()
	else:
		rpc_id(1, "_rpc_request_start")

@rpc("any_peer", "reliable")
func _rpc_request_start() -> void:
	if not multiplayer.is_server():
		return
	# Free play: any connected human may start. Staked matches need a funded pot.
	_try_start_match()

func _try_start_match() -> void:
	if match_active:
		return
	if peers.is_empty():
		return
	# Free play (no SOL): start whenever someone hits START — ready is optional UX.
	# Staked: require exactly 2 players and a funded pot.
	if stake_sol > 0.0:
		if peers.size() != 2:
			return
		if not Wager.pot_ready and Wager.status != "funded":
			return
	else:
		# Prefer at least one ready flag when 2+ players, but don't hard-block
		# if UI ready-state desynced (common with Dictionary key typing over RPC).
		var any_ready := false
		for p in peers.values():
			if p.get("ready", false):
				any_ready = true
				break
		if peers.size() > 1 and not any_ready:
			# Still allow start — both players being in the room is enough for free play.
			pass
	match_active = true
	pending_mode = selected_mode
	if stake_sol > 0.0:
		Wager.room = room_code
		Wager.stake_sol = stake_sol
	_rpc_start_match.rpc(selected_mode)

@rpc("authority", "call_local", "reliable")
func _rpc_start_match(mode_id: String) -> void:
	pending_mode = mode_id
	selected_mode = mode_id
	match_active = true
	status_text = "Starting %s…" % mode_id
	match_starting.emit(mode_id)

func notify_match_over() -> void:
	match_active = false
	if multiplayer.is_server():
		# Fresh code next session so late joiners don't slam into an ending fight.
		room_code = _generate_room_code()
		for id in peers.keys():
			peers[id].ready = false
		stake_sol = 0.0
		Wager.reset_match()
		_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)

@rpc("any_peer", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if peers.has(id):
		peers[id].ready = ready
		_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)
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
	_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)
	peer_list_changed.emit()

@rpc("authority", "call_local", "reliable")
func _sync_lobby(peer_map: Dictionary, mode_id: String, code: String, p_stake: float = 0.0) -> void:
	peers = peer_map
	selected_mode = mode_id
	room_code = code
	stake_sol = p_stake
	Wager.set_stake(p_stake)
	is_online = true
	status_text = "Room %s — %d player(s)" % [room_code, peers.size()]
	lobby_changed.emit()
	peer_list_changed.emit()

func wallet_for_team(team: String) -> String:
	for p in peers.values():
		if str(p.get("team", "")) == team and str(p.get("wallet", "")) != "":
			return str(p.wallet)
	return ""

func settle_wager_for_green_win(green_won: bool) -> void:
	var team := "green_army" if green_won else "chrome_legion"
	settle_wager_for_team(team)

func settle_wager_for_team(team: String) -> void:
	if not multiplayer.is_server() or stake_sol <= 0.0:
		return
	var w := wallet_for_team(team)
	if w != "":
		Wager.room = room_code
		Wager.stake_sol = stake_sol
		Wager.api_base = wager_api_url()
		Wager.settle_winner(w)

func settle_wager_for_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or stake_sol <= 0.0:
		return
	if not peers.has(peer_id):
		return
	var w := str(peers[peer_id].get("wallet", ""))
	if w != "":
		Wager.room = room_code
		Wager.stake_sol = stake_sol
		Wager.api_base = wager_api_url()
		Wager.settle_winner(w)

func wallet_for_peer(peer_id: int) -> String:
	if peers.has(peer_id):
		return str(peers[peer_id].get("wallet", ""))
	return ""

@rpc("any_peer", "reliable")
func _rpc_hello(player_name: String, team: String, code: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	# Soft room gate: if client sent a code and it doesn't match, kick.
	var want := code.strip_edges().to_upper()
	if want != "" and room_code != "" and want != room_code:
		_rpc_kick.rpc_id(id, "Wrong room code.")
		return
	peers[id] = {
		"name": player_name,
		"team": team if team != "" else _auto_team(),
		"ready": false,
		"wallet": "",
	}
	_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)
	peer_list_changed.emit()

@rpc("authority", "reliable")
func _rpc_kick(reason: String) -> void:
	connection_failed.emit(reason)
	reset()

func _register_self() -> void:
	if is_dedicated:
		# Dedicated authority is not a playable peer.
		peers.clear()
		peer_list_changed.emit()
		return
	var nm := "Host" if is_host else ("Soldier-%d" % my_id())
	peers[my_id()] = {
		"name": nm, "team": local_team, "ready": is_host, "id": my_id(),
		"wallet": local_wallet,
	}
	peer_list_changed.emit()

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[Net] peer connected: ", id)
		# Wait for hello (with optional room code).
	peer_list_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	print("[Net] peer disconnected: ", id)
	peers.erase(id)
	if multiplayer.is_server():
		_sync_lobby.rpc(peers, selected_mode, room_code, stake_sol)
	peer_list_changed.emit()

func _on_connected_ok() -> void:
	is_online = true
	is_host = false
	is_dedicated = false
	status_text = "Connected"
	rpc_id(1, "_rpc_hello", "Soldier-%d" % my_id(), local_team, _wanted_room_code)
	if local_wallet != "":
		set_wallet(local_wallet)
	connection_succeeded.emit()
	lobby_changed.emit()

func _on_connected_fail() -> void:
	reset()
	connection_failed.emit("Could not reach server. Check wss URL / server running.")

func _on_server_disconnected() -> void:
	reset()
	connection_failed.emit("Server disconnected.")
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

func _generate_room_code() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var code := ""
	for i in 4:
		code += CHARS[rng.randi_range(0, CHARS.length() - 1)]
	return code

func host_address_hint() -> String:
	if room_code != "":
		return room_code
	return public_ws_url()

func team_for_peer(peer_id: int) -> String:
	if peers.has(peer_id):
		return str(peers[peer_id].get("team", "green_army"))
	return "green_army"

func name_for_peer(peer_id: int) -> String:
	if peers.has(peer_id):
		return str(peers[peer_id].get("name", "Soldier-%d" % peer_id))
	return "Soldier-%d" % peer_id

## ---- human sync -----------------------------------------------------------

func broadcast_pose(pos: Vector3, yaw: float, vel: Vector3) -> void:
	if not is_online or is_dedicated:
		return
	_rpc_pose.rpc(pos, yaw, vel)

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_pose(pos: Vector3, yaw: float, vel: Vector3) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		return
	peer_pose.emit(id, pos, yaw, vel)

## Every human shot is replayed on the other clients as a cosmetic tracer from
## that peer's puppet, so a firefight looks identical on both screens.
func broadcast_shot(origin: Vector3, dir: Vector3, weapon_path: String) -> void:
	if not is_online or is_dedicated:
		return
	_rpc_shot.rpc(origin, dir, weapon_path)

@rpc("any_peer", "unreliable", "call_remote")
func _rpc_shot(origin: Vector3, dir: Vector3, weapon_path: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		return
	peer_shot.emit(id, origin, dir, weapon_path)

## HP lives on the machine that owns the body, so that owner publishes it
## rather than letting every client guess from the hits it happened to see.
var _hp_sent := -1.0
var _hp_sent_at := 0.0

func broadcast_health(hp: float, max_hp: float, force: bool = false) -> void:
	if not is_online or is_dedicated:
		return
	# Regen ticks every frame; rate-limit so trickle healing can't flood the
	# link, but never delay a real damage or death packet.
	var now := float(Time.get_ticks_msec()) * 0.001
	if not force and (absf(hp - _hp_sent) < 1.0 or now - _hp_sent_at < 0.1):
		return
	_hp_sent = hp
	_hp_sent_at = now
	_rpc_health.rpc(hp, max_hp)

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_health(hp: float, max_hp: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		return
	peer_health.emit(id, maxf(hp, 0.0), maxf(max_hp, 1.0))

func report_hit(victim_peer_id: int, amount: float) -> void:
	if not is_online or amount <= 0.0:
		return
	_rpc_hit.rpc(victim_peer_id, clampf(amount, 0.0, 400.0))

@rpc("any_peer", "reliable", "call_local")
func _rpc_hit(victim_id: int, amount: float) -> void:
	var attacker := multiplayer.get_remote_sender_id()
	if attacker == 0:
		attacker = my_id()
	peer_hurt.emit(victim_id, clampf(amount, 0.0, 400.0), attacker)

## Only the victim can say a hit truly landed and how much it took off, so the
## hitmarker a shooter sees is the victim's own accounting, not a local guess.
func confirm_hit(attacker_id: int, amount: float, killed: bool) -> void:
	if not is_online or amount <= 0.0 or attacker_id <= 0 or attacker_id == my_id():
		return
	if not peers.has(attacker_id):
		return
	_rpc_hit_ack.rpc_id(attacker_id, amount, killed)

@rpc("any_peer", "reliable")
func _rpc_hit_ack(amount: float, killed: bool) -> void:
	var victim := multiplayer.get_remote_sender_id()
	if victim == 0:
		return
	hit_landed.emit(victim, maxf(amount, 0.0), killed)

func announce_down(killer_id: int = 0) -> void:
	if not is_online:
		return
	_rpc_down.rpc(killer_id)

@rpc("any_peer", "reliable", "call_local")
func _rpc_down(killer_id: int = 0) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = my_id()
	peer_down.emit(id)
	kill_feed.emit(killer_id, id)

## Fresh body, fresh HP accounting — force the next health packet through.
func reset_health_sync() -> void:
	_hp_sent = -1.0

## First finisher wins — server arbitrates so match_active clears + wager settles.
func report_race_finish() -> void:
	if not is_online or not match_active:
		return
	if multiplayer.is_server():
		_finalize_race_win(my_id())
	else:
		rpc_id(1, "_rpc_request_race_win")

@rpc("any_peer", "reliable")
func _rpc_request_race_win() -> void:
	if not multiplayer.is_server() or not match_active:
		return
	_finalize_race_win(multiplayer.get_remote_sender_id())

func _finalize_race_win(peer_id: int) -> void:
	if not multiplayer.is_server() or not match_active:
		return
	if peer_id <= 0 or not peers.has(peer_id):
		return
	settle_wager_for_peer(peer_id)
	_rpc_race_win.rpc(peer_id)

@rpc("authority", "reliable", "call_local")
func _rpc_race_win(id: int) -> void:
	race_won.emit(id)
	notify_match_over()

## ---- bot authority sync ---------------------------------------------------

func spawn_bot_net(bot_id: int, team: String, pos: Vector3, variant: String) -> void:
	if not is_online or not multiplayer.is_server():
		return
	_rpc_bot_spawn.rpc(bot_id, team, pos, variant)

@rpc("authority", "reliable", "call_remote")
func _rpc_bot_spawn(bot_id: int, team: String, pos: Vector3, variant: String) -> void:
	bot_spawned.emit(bot_id, team, pos, variant)

func broadcast_bot_pose(bot_id: int, pos: Vector3, yaw: float, hp_ratio: float = 1.0) -> void:
	if not is_online or not multiplayer.is_server():
		return
	_rpc_bot_pose.rpc(bot_id, pos, yaw, hp_ratio)

@rpc("authority", "unreliable_ordered", "call_remote")
func _rpc_bot_pose(bot_id: int, pos: Vector3, yaw: float, hp_ratio: float = 1.0) -> void:
	bot_pose.emit(bot_id, pos, yaw, clampf(hp_ratio, 0.0, 1.0))

## Bots only truly exist on the authority, so their shots have to be relayed
## or clients watch NPCs kill them with invisible bullets.
func broadcast_bot_shot(bot_id: int, origin: Vector3, dir: Vector3, weapon_path: String) -> void:
	if not is_online or not multiplayer.is_server():
		return
	_rpc_bot_shot.rpc(bot_id, origin, dir, weapon_path)

@rpc("authority", "unreliable", "call_remote")
func _rpc_bot_shot(bot_id: int, origin: Vector3, dir: Vector3, weapon_path: String) -> void:
	bot_shot.emit(bot_id, origin, dir, weapon_path)

func report_bot_hit(bot_id: int, amount: float) -> void:
	if not is_online or amount <= 0.0:
		return
	amount = clampf(amount, 0.0, 400.0)
	# Only authority applies damage to the live bot; clients get FX via pose/death.
	if multiplayer.is_server():
		bot_hurt.emit(bot_id, amount)
	else:
		rpc_id(1, "_rpc_bot_hit", bot_id, amount)

@rpc("any_peer", "reliable")
func _rpc_bot_hit(bot_id: int, amount: float) -> void:
	if not multiplayer.is_server():
		return
	bot_hurt.emit(bot_id, clampf(amount, 0.0, 400.0))

func announce_bot_death(bot_id: int) -> void:
	if not is_online or not multiplayer.is_server():
		return
	_rpc_bot_died.rpc(bot_id)

@rpc("authority", "reliable", "call_remote")
func _rpc_bot_died(bot_id: int) -> void:
	bot_died.emit(bot_id)

## ---- match outcome / score ------------------------------------------------

func broadcast_match_end(green_won: bool, win_title: String, lose_reason: String) -> void:
	if not is_online or not multiplayer.is_server():
		return
	settle_wager_for_green_win(green_won)
	_rpc_match_end.rpc(green_won, win_title, lose_reason)

@rpc("authority", "reliable", "call_local")
func _rpc_match_end(green_won: bool, win_title: String, lose_reason: String) -> void:
	match_ended.emit(green_won, win_title, lose_reason)
	notify_match_over()

func broadcast_squad_win(winner_squad: String, win_title: String) -> void:
	if not is_online or not multiplayer.is_server():
		return
	settle_wager_for_team(winner_squad)
	_rpc_squad_win.rpc(winner_squad, win_title)

@rpc("authority", "reliable", "call_local")
func _rpc_squad_win(winner_squad: String, win_title: String) -> void:
	squad_match_ended.emit(winner_squad, win_title)
	notify_match_over()

func broadcast_scores(green_score: int, chrome_score: int) -> void:
	if not is_online or not multiplayer.is_server():
		return
	_rpc_scores.rpc(green_score, chrome_score)

@rpc("authority", "reliable", "call_remote")
func _rpc_scores(green_score: int, chrome_score: int) -> void:
	score_synced.emit(green_score, chrome_score)

func broadcast_hold_state(hold_amount: float, wave: int, time_left: float) -> void:
	if not is_online or not multiplayer.is_server():
		return
	_rpc_hold.rpc(hold_amount, wave, time_left)

@rpc("authority", "reliable", "call_remote")
func _rpc_hold(hold_amount: float, wave: int, time_left: float) -> void:
	hold_synced.emit(hold_amount, wave, time_left)

## Client reports own hull/armor loss so dedicated/listen host can score.
func report_hull_loss(victim_team: String) -> void:
	if not is_online:
		return
	if multiplayer.is_server():
		hull_lost.emit(victim_team)
	else:
		rpc_id(1, "_rpc_hull_loss", victim_team)

@rpc("any_peer", "reliable")
func _rpc_hull_loss(victim_team: String) -> void:
	if not multiplayer.is_server():
		return
	hull_lost.emit(victim_team)

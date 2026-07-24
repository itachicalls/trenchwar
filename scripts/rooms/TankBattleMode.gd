class_name TankBattleMode
extends ArenaBase
## TANK BATTLE — plastic armor duel in THE SANDBOX.
## Offline: board a Green hull vs Chrome AI. Online: humans on either side
## deploy boarded; bots fill empty armor slots. First to SCORE_TARGET hull kills.

const SCORE_TARGET := 8
const GREEN := "res://data/factions/green_army.tres"
const CHROME := "res://data/factions/chrome_legion.tres"

var green_score := 0
var chrome_score := 0
var _player_tank: ToyTank
var _player_respawn := -1.0
var _spawn_queue: Array[Dictionary] = []
var _hull_lost := false
var _remount_existing := false

func _init() -> void:
	arena_half = 55.0

func _green_base() -> Vector3:
	return Vector3(-arena_half + 14, 1, 0)

func _chrome_base() -> Vector3:
	return Vector3(arena_half - 14, 1, 0)

func _setup_mode() -> void:
	Missions.start_mission("TANK BATTLE — THE SANDBOX")
	var team := Net.local_team if Net.is_online else "green_army"
	var base := _chrome_base() if team == "chrome_legion" else _green_base()
	var yaw := -90.0 if team == "chrome_legion" else 90.0
	var player: Player = null
	if Net.is_online:
		player = spawn_online_humans({"green_army": _green_base(), "chrome_legion": _chrome_base()})
	else:
		player = spawn_player(base)
	if Net.is_dedicated:
		_player_tank = null
	else:
		_player_tank = spawn_tank(base, yaw)
		if player != null:
			_player_tank.call_deferred("force_board", player)
	var enemy_tanks := bot_slots(3 if Game.low_gfx() else 4, "chrome_legion")
	# Chrome humans replace some AI hulls; always keep at least one AI if solo green.
	if Net.is_online and Net.humans_on_team("chrome_legion") > 0:
		enemy_tanks = maxi(1, enemy_tanks)
	for i in enemy_tanks:
		_spawn_enemy_tank(i)
	# Extra boarded hulls for chrome human peers beyond the local player.
	if Net.is_online:
		for id in Net.peers.keys():
			var pid: int = int(id)
			if pid == Net.my_id():
				continue
			if Net.team_for_peer(pid) == "chrome_legion":
				spawn_tank(_chrome_base() + Vector3(0, 0, randf_range(-10, 10)), -90.0)
			elif Net.team_for_peer(pid) == "green_army":
				spawn_tank(_green_base() + Vector3(0, 0, randf_range(-10, 10)), 90.0)
	var flank := bot_slots(2 if Game.low_gfx() else 3, "chrome_legion")
	var green_flank := bot_slots(2 if Game.low_gfx() else 3, "green_army")
	for i in flank:
		spawn_bot(CHROME, Vector3(arena_half - 16, 1, (i - 1) * 10.0), ["heavy", "grenadier", "commando"][i % 3])
	for i in green_flank:
		spawn_bot(GREEN, Vector3(-arena_half + 18, 1, (i - 1) * 8.0), ["trooper", "scout", "commando"][i % 3])
	spawn_weapon_drop(Vector3(0, 4.2, 0), "marble", 50.0)
	_update_banner()
	sub_banner.text = ("ONLINE PVP  •  FIRST TO %d HULL KILLS" if Net.is_online else "FIRST TO %d HULL KILLS  •  MOUSE AIMS TURRET  •  A/D HULL") % SCORE_TARGET
	Events.notify.emit("TANK BATTLE: click to lock mouse look, A/D turns the hull, W/S drives.")

func _spawn_enemy_tank(slot: int) -> void:
	var ang := TAU * 0.15 + slot * 0.55
	var r := arena_half * 0.55
	var pos := Vector3(cos(ang) * r, 1, sin(ang) * r)
	spawn_tank(pos, rad_to_deg(-ang) + 180.0, "chrome_legion")

func _process(delta: float) -> void:
	super(delta)
	if _match_over or not Game.is_playing():
		return
	if not _hull_lost and _player_tank != null and not is_instance_valid(_player_tank):
		_hull_lost = true
		_score_against_local()
		_update_banner()
		_check_win()
		if not _match_over:
			_player_respawn = 5.0
			_remount_existing = false
	for job in _spawn_queue.duplicate():
		job.t -= delta
		if job.t <= 0.0:
			_spawn_queue.erase(job)
			_spawn_enemy_tank(randi() % 4)
	if _player_respawn > 0.0:
		_player_respawn -= delta
		banner.text = ("REBOARD IN %d..." if _remount_existing else "NEW HULL IN %d...") % ceili(_player_respawn)
		if _player_respawn <= 0.0:
			_respawn_player_armor()

func _score_against_local() -> void:
	var team := Net.local_team if Net.is_online else "green_army"
	if team == "green_army":
		chrome_score += 1
	else:
		green_score += 1

func _respawn_player_armor() -> void:
	var team := Net.local_team if Net.is_online else "green_army"
	var base := _chrome_base() if team == "chrome_legion" else _green_base()
	var yaw := -90.0 if team == "chrome_legion" else 90.0
	var player := Game.player
	if _remount_existing and is_instance_valid(_player_tank):
		_remount_existing = false
		if player == null or not is_instance_valid(player):
			player = spawn_player(_player_tank.global_position + Vector3(0, 1, 0))
		_player_tank.call_deferred("force_board", player)
		_update_banner()
		return
	_hull_lost = false
	_remount_existing = false
	_player_tank = spawn_tank(base + Vector3(0, 0, randf_range(-8, 8)), yaw)
	if player == null or not is_instance_valid(player):
		player = spawn_player(_player_tank.position)
	_player_tank.call_deferred("force_board", player)
	_update_banner()

func _on_arena_unit_died(unit: Node) -> void:
	if _match_over:
		return
	if unit is ToyTank and (unit as ToyTank).ai_controlled:
		green_score += 1
		_spawn_queue.append({"t": 6.0 if not Game.low_gfx() else 8.0})
		_update_banner()
		_check_win()
	elif unit is RemoteSoldier and unit.faction != null:
		if unit.faction.id == "green_army":
			chrome_score += 1
		else:
			green_score += 1
		_update_banner()
		_check_win()

func _on_player_died() -> void:
	if _match_over:
		return
	if is_instance_valid(_player_tank) and not _hull_lost:
		_remount_existing = true
		_player_respawn = 3.5
		return
	if not _hull_lost:
		_score_against_local()
		_update_banner()
		_check_win()
	if not _match_over and _player_respawn < 0.0:
		_player_respawn = 5.0
		_hull_lost = true
		_remount_existing = false

func _update_banner() -> void:
	banner.text = "GREEN ARMOR  %d   —   %d  CHROME" % [green_score, chrome_score]
	if Net.is_online and Net.is_match_authority():
		Net.broadcast_scores(green_score, chrome_score)

func _check_win() -> void:
	if green_score >= SCORE_TARGET:
		resolve_team_match(true,
			"GREEN ARMOR WINS  %d - %d" % [green_score, chrome_score],
			"Green armor crushed the sandbox %d - %d." % [green_score, chrome_score])
	elif chrome_score >= SCORE_TARGET:
		resolve_team_match(false,
			"CHROME ARMOR WINS  %d - %d" % [chrome_score, green_score],
			"Chrome armor rolled the sandbox %d - %d." % [chrome_score, green_score])

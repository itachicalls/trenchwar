class_name TankBattleMode
extends ArenaBase
## TANK BATTLE — plastic armor duel in THE SANDBOX. You deploy already
## boarded; Chrome AI tanks hunt you. First to SCORE_TARGET hull kills wins.

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

func _setup_mode() -> void:
	Missions.start_mission("TANK BATTLE — THE SANDBOX")
	_player_tank = spawn_tank(Vector3(-arena_half + 14, 1, 0), 90.0)
	var player := spawn_player(Vector3(-arena_half + 14, 1, 0))
	_player_tank.call_deferred("force_board", player)
	var enemy_tanks := 3 if Game.low_gfx() else 4
	for i in enemy_tanks:
		_spawn_enemy_tank(i)
	# Infantry skirmishers — fewer on web/mobile.
	var flank := 2 if Game.low_gfx() else 3
	for i in flank:
		spawn_bot(CHROME, Vector3(arena_half - 16, 1, (i - 1) * 10.0), ["heavy", "grenadier", "commando"][i])
		spawn_bot(GREEN, Vector3(-arena_half + 18, 1, (i - 1) * 8.0), ["trooper", "scout", "commando"][i])
	spawn_weapon_drop(Vector3(0, 4.2, 0), "marble", 50.0)
	_update_banner()
	sub_banner.text = "FIRST TO %d HULL KILLS  •  MOUSE AIMS TURRET  •  A/D HULL"
	Events.notify.emit("TANK BATTLE: click to lock mouse look, A/D turns the hull, W/S drives. Crush Chrome armor!")

func _spawn_enemy_tank(slot: int) -> void:
	var ang := TAU * 0.15 + slot * 0.55
	var r := arena_half * 0.55
	var pos := Vector3(cos(ang) * r, 1, sin(ang) * r)
	spawn_tank(pos, rad_to_deg(-ang) + 180.0, "chrome_legion")

func _process(delta: float) -> void:
	super(delta)
	if _match_over or not Game.is_playing():
		return
	# Player hull cooked (AI tanks emit unit_died; player tanks just free).
	if not _hull_lost and _player_tank != null and not is_instance_valid(_player_tank):
		_hull_lost = true
		chrome_score += 1
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

func _respawn_player_armor() -> void:
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
	_player_tank = spawn_tank(Vector3(-arena_half + 14, 1, randf_range(-8, 8)), 90.0)
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

func _on_player_died() -> void:
	if _match_over:
		return
	# Bail / on-foot death with hull still alive: remount the same tank (no orphan hulls).
	if is_instance_valid(_player_tank) and not _hull_lost:
		_remount_existing = true
		_player_respawn = 3.5
		return
	if not _hull_lost:
		chrome_score += 1
		_update_banner()
		_check_win()
	if not _match_over and _player_respawn < 0.0:
		_player_respawn = 5.0
		_hull_lost = true
		_remount_existing = false

func _update_banner() -> void:
	banner.text = "GREEN ARMOR  %d   —   %d  CHROME" % [green_score, chrome_score]

func _check_win() -> void:
	if green_score >= SCORE_TARGET:
		win_match("TANK BATTLE WON  %d - %d" % [green_score, chrome_score])
	elif chrome_score >= SCORE_TARGET:
		lose_match("Chrome armor rolled the sandbox %d - %d." % [chrome_score, green_score])

class_name SkirmishMode
extends ArenaBase
## TEAM SKIRMISH: Green Army vs Chrome Legion in the Sandbox.
## Offline = vs bots. Online = humans on either team + bots fill empty slots.
## Everyone respawns; first team to SCORE_TARGET eliminations wins.

const SCORE_TARGET := 25
const BOT_RESPAWN := 5.0
const PLAYER_RESPAWN := 4.0

const GREEN := "res://data/factions/green_army.tres"
const CHROME := "res://data/factions/chrome_legion.tres"
const MIX := ["trooper", "scout", "commando", "heavy", "grenadier", "sniper", "trooper"]

var green_score := 0
var chrome_score := 0
var _pending: Array[Dictionary] = []   # bot respawn queue
var _player_respawn := -1.0

func _green_base() -> Vector3:
	return Vector3(-arena_half + 10, 1, 0)

func _chrome_base() -> Vector3:
	return Vector3(arena_half - 10, 1, 0)

func _setup_mode() -> void:
	Missions.start_mission("SKIRMISH — THE SANDBOX")
	if Net.is_online:
		spawn_online_humans({"green_army": _green_base(), "chrome_legion": _chrome_base()})
	else:
		spawn_player(_green_base())
	var green_n := bot_slots(3 if Game.low_gfx() else 5, "green_army")
	var chrome_n := bot_slots(5 if Game.low_gfx() else 7, "chrome_legion")
	for i in green_n:
		spawn_bot(GREEN, _green_base() + Vector3(3 + i * 2.5, 0, (i - 2) * 4.0), MIX[i])
	for i in chrome_n:
		spawn_bot(CHROME, _chrome_base() + Vector3(-3 - (i % 3) * 2.5, 0, (i - 3) * 4.0), MIX[i])
	_update_banner()
	sub_banner.text = ("FIRST TO %d  •  ONLINE PVP + BOTS" if Net.is_online else "FIRST TO %d  •  CASUAL VS BOTS") % SCORE_TARGET
	spawn_weapon_drop(Vector3(0, 4.2, 0), "marble", 45.0)
	spawn_weapon_drop(Vector3(0, 0, -arena_half * 0.55), "scatter")
	spawn_weapon_drop(Vector3(0, 0, arena_half * 0.55), "sniper")
	if not Game.low_gfx():
		spawn_weapon_drop(Vector3(-arena_half * 0.55, 0, 0), "soaker")
		spawn_weapon_drop(Vector3(arena_half * 0.55, 0, 0), "repeater")
	spawn_tank(Vector3(-18, 1, 22), -40.0)
	if not Game.low_gfx():
		spawn_tank(Vector3(20, 1, -18), 130.0)
		spawn_plane(Vector3(0, 5, -28), 0.0)
	spawn_tank(Vector3(arena_half - 20, 1, 14), 180.0, "chrome_legion")
	Pickup.spawn_fuel(self, Vector3(-8, 0, 10), 40)
	Events.notify.emit("SKIRMISH: push the sandcastles, board the toys, hold the dune. First to %d!" % SCORE_TARGET)

func _process(delta: float) -> void:
	super(delta)
	if _match_over or not Game.is_playing():
		return
	if Net.is_online and not Net.is_match_authority():
		if _player_respawn > 0.0:
			_player_respawn -= delta
			banner.text = "REDEPLOYING IN %d..." % ceili(_player_respawn)
			if _player_respawn <= 0.0:
				var team := Net.local_team
				var base := _chrome_base() if team == "chrome_legion" else _green_base()
				spawn_player(base + Vector3(0, 0, randf_range(-4, 4)))
				_update_banner()
		return
	for job in _pending.duplicate():
		job.t -= delta
		if job.t <= 0.0:
			_pending.erase(job)
			var base: Vector3 = _green_base() if job.team == GREEN else _chrome_base()
			if job.get("as_tank", false):
				spawn_tank(base + Vector3(randf_range(-6, 6), 0, randf_range(-8, 8)), 180.0, "chrome_legion")
			else:
				spawn_bot(job.team, base + Vector3(randf_range(-4, 4), 0, randf_range(-8, 8)), job.variant)
	if _player_respawn > 0.0:
		_player_respawn -= delta
		banner.text = "REDEPLOYING IN %d..." % ceili(_player_respawn)
		if _player_respawn <= 0.0:
			var team := Net.local_team if Net.is_online else "green_army"
			var base := _chrome_base() if team == "chrome_legion" else _green_base()
			spawn_player(base + Vector3(0, 0, randf_range(-4, 4)))
			_update_banner()

func _on_arena_unit_died(unit: Node) -> void:
	if _match_over:
		return
	if Net.is_online and not Net.is_match_authority():
		return
	if unit is ToyTank and (unit as ToyTank).ai_controlled:
		green_score += 1
		_pending.append({"team": CHROME, "t": BOT_RESPAWN + 4.0, "variant": "heavy", "as_tank": true})
		_update_banner()
		_check_win()
		return
	var team := ""
	if unit is RemoteSoldier and unit.faction != null:
		team = unit.faction.id
	elif unit is CombatBot:
		team = unit.faction.id
		_pending.append({"team": GREEN if team == "green_army" else CHROME, "t": BOT_RESPAWN, "variant": unit.variant})
	else:
		return
	if team == "green_army":
		chrome_score += 1
	else:
		green_score += 1
		Game.kills += 1
	_update_banner()
	_check_win()

func _on_player_died() -> void:
	if _match_over:
		return
	# Dedicated authority scores via RemoteSoldier death; listen-host scores here.
	if not Net.is_online or Net.is_match_authority():
		var team := Net.local_team if Net.is_online else "green_army"
		if team == "green_army":
			chrome_score += 1
		else:
			green_score += 1
		_update_banner()
		_check_win()
	if not _match_over:
		_player_respawn = PLAYER_RESPAWN

func _update_banner() -> void:
	banner.text = "GREEN  %d   —   %d  CHROME" % [green_score, chrome_score]
	if Net.is_online and Net.is_match_authority():
		Net.broadcast_scores(green_score, chrome_score)

func _check_win() -> void:
	if green_score >= SCORE_TARGET:
		resolve_team_match(true,
			"GREEN WINS SKIRMISH  %d - %d" % [green_score, chrome_score],
			"Green Army takes the sandbox %d - %d." % [green_score, chrome_score])
	elif chrome_score >= SCORE_TARGET:
		resolve_team_match(false,
			"CHROME WINS SKIRMISH  %d - %d" % [chrome_score, green_score],
			"Chrome Legion takes the sandbox %d - %d." % [chrome_score, green_score])

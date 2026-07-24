class_name SkirmishMode
extends ArenaBase
## TEAM SKIRMISH (casual, vs bots): Green Army + you against the Chrome
## Legion in the Sandbox. Everyone respawns; first team to SCORE_TARGET
## eliminations takes the match.

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
	spawn_player(_green_base())
	var green_n := 3 if Game.low_gfx() else 5
	var chrome_n := 5 if Game.low_gfx() else 7
	for i in green_n:
		spawn_bot(GREEN, _green_base() + Vector3(3 + i * 2.5, 0, (i - 2) * 4.0), MIX[i])
	for i in chrome_n:
		spawn_bot(CHROME, _chrome_base() + Vector3(-3 - (i % 3) * 2.5, 0, (i - 3) * 4.0), MIX[i])
	_update_banner()
	sub_banner.text = "FIRST TO %d  •  CASUAL VS BOTS" % SCORE_TARGET
	# Weapon drops: the dune rewards aggression, the flanks reward rotation.
	spawn_weapon_drop(Vector3(0, 4.2, 0), "marble", 45.0)
	spawn_weapon_drop(Vector3(0, 0, -arena_half * 0.55), "scatter")
	spawn_weapon_drop(Vector3(0, 0, arena_half * 0.55), "sniper")
	if not Game.low_gfx():
		spawn_weapon_drop(Vector3(-arena_half * 0.55, 0, 0), "soaker")
		spawn_weapon_drop(Vector3(arena_half * 0.55, 0, 0), "repeater")
	# Mountable toys mid-field — optional power spikes, not required.
	spawn_tank(Vector3(-18, 1, 22), -40.0)
	if not Game.low_gfx():
		spawn_tank(Vector3(20, 1, -18), 130.0)
		spawn_plane(Vector3(0, 5, -28), 0.0)
	# One Chrome AI hull so armor fights break out without a dedicated mode.
	spawn_tank(Vector3(arena_half - 20, 1, 14), 180.0, "chrome_legion")
	Pickup.spawn_fuel(self, Vector3(-8, 0, 10), 40)
	Events.notify.emit("SKIRMISH: push the sandcastles, board the toys, hold the dune. First to %d!" % SCORE_TARGET)

func _process(delta: float) -> void:
	super(delta)
	if _match_over or not Game.is_playing():
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
			spawn_player(_green_base())
			_update_banner()

func _on_arena_unit_died(unit: Node) -> void:
	if _match_over:
		return
	# AI tank hulls count as Chrome eliminations (no infantry respawn).
	if unit is ToyTank and (unit as ToyTank).ai_controlled:
		green_score += 1
		_pending.append({"team": CHROME, "t": BOT_RESPAWN + 4.0, "variant": "heavy", "as_tank": true})
		_update_banner()
		_check_win()
		return
	if not (unit is CombatBot):
		return
	var team: String = unit.faction.id
	if team == "green_army":
		chrome_score += 1
		_pending.append({"team": GREEN, "t": BOT_RESPAWN, "variant": unit.variant})
	else:
		green_score += 1
		Game.kills += 1
		_pending.append({"team": CHROME, "t": BOT_RESPAWN, "variant": unit.variant})
	_update_banner()
	_check_win()

func _on_player_died() -> void:
	if _match_over:
		return
	chrome_score += 1
	_update_banner()
	_check_win()
	if not _match_over:
		_player_respawn = PLAYER_RESPAWN

func _update_banner() -> void:
	banner.text = "GREEN  %d   —   %d  CHROME" % [green_score, chrome_score]

func _check_win() -> void:
	if green_score >= SCORE_TARGET:
		win_match("SKIRMISH WON  %d - %d" % [green_score, chrome_score])
	elif chrome_score >= SCORE_TARGET:
		lose_match("Chrome takes the sandbox %d - %d." % [chrome_score, green_score])

class_name SkirmishMode
extends ArenaBase
## TEAM SKIRMISH: Green Army vs Chrome Legion in the Sandbox.
## Online VS rules: each side gets 3 NPCs (3 lives each) + each human gets
## 3 respawns. Wipe the other team's soldiers to win.

const BOTS_PER_TEAM := 3
const BOT_LIVES := 3
const PLAYER_RESPAWNS := 3
const BOT_RESPAWN := 4.0
const PLAYER_RESPAWN := 4.0

const GREEN := "res://data/factions/green_army.tres"
const CHROME := "res://data/factions/chrome_legion.tres"
const MIX := ["trooper", "commando", "heavy"]

## Remaining lives per bot slot id ("green_0" …). Authority-owned.
var _bot_lives: Dictionary = {}
## Remaining respawns per peer id (online) or "local" (offline).
var _player_lives: Dictionary = {}
var _pending: Array[Dictionary] = []
var _player_respawn := -1.0
var _elim_green := false
var _elim_chrome := false

func _green_base() -> Vector3:
	return Vector3(-arena_half + 10, 1, 0)

func _chrome_base() -> Vector3:
	return Vector3(arena_half - 10, 1, 0)

func _setup_mode() -> void:
	Missions.start_mission("SKIRMISH — THE SANDBOX")
	if Net.is_online:
		spawn_online_humans({"green_army": _green_base(), "chrome_legion": _chrome_base()})
		for id in Net.peers.keys():
			_player_lives[int(id)] = PLAYER_RESPAWNS
	else:
		spawn_player(_green_base())
		_player_lives["local"] = PLAYER_RESPAWNS
	var green_n := bot_slots(BOTS_PER_TEAM, "green_army")
	var chrome_n := bot_slots(BOTS_PER_TEAM, "chrome_legion")
	for i in green_n:
		var slot := "green_%d" % i
		_bot_lives[slot] = BOT_LIVES
		var bot := spawn_bot(GREEN, _green_base() + Vector3(3 + i * 2.5, 0, (i - 1) * 5.0), MIX[i % MIX.size()])
		if bot != null:
			bot.set_meta("skirmish_slot", slot)
			_push_bot_into_fight(bot, true)
	for i in chrome_n:
		var slot := "chrome_%d" % i
		_bot_lives[slot] = BOT_LIVES
		var bot2 := spawn_bot(CHROME, _chrome_base() + Vector3(-3 - i * 2.5, 0, (i - 1) * 5.0), MIX[i % MIX.size()])
		if bot2 != null:
			bot2.set_meta("skirmish_slot", slot)
			_push_bot_into_fight(bot2, false)
	_plant_base_beacon(_green_base(), Color(0.35, 0.85, 0.45))
	_plant_base_beacon(_chrome_base(), Color(0.95, 0.35, 0.3))
	Fx.ring_pulse(self, Vector3(0, 1, 0), Color(1.0, 0.85, 0.4), 8.0, 0.7)
	_update_banner()
	sub_banner.text = "3 NPCS / SIDE  •  3 LIVES EACH  •  3 PLAYER RESPAWNS"
	spawn_weapon_drop(Vector3(0, 4.2, 0), "marble", 45.0)
	spawn_weapon_drop(Vector3(0, 0, -arena_half * 0.55), "scatter")
	spawn_weapon_drop(Vector3(0, 0, arena_half * 0.55), "sniper")
	if not Game.low_gfx():
		spawn_weapon_drop(Vector3(-arena_half * 0.55, 0, 0), "soaker")
		spawn_weapon_drop(Vector3(arena_half * 0.55, 0, 0), "repeater")
	spawn_tank(Vector3(-18, 1, 22), -40.0)
	if not Game.low_gfx():
		spawn_tank(Vector3(20, 1, -18), 130.0)
	spawn_tank(Vector3(arena_half - 20, 1, 14), 180.0, "chrome_legion")
	Pickup.spawn_fuel(self, Vector3(-8, 0, 10), 40)
	Events.notify.emit("SKIRMISH VS: 3 squadmates each, 3 lives per NPC, 3 respawns for you. Wipe the other side!")

func _plant_base_beacon(pos: Vector3, color: Color) -> void:
	var pillar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.55
	cm.height = 6.0
	pillar.mesh = cm
	pillar.material_override = ToyMaterials.glow(color, 1.6 if not Game.low_gfx() else 0.9)
	pillar.position = pos + Vector3(0, 3.0, 0)
	add_child(pillar)
	if not Game.low_gfx():
		var omni := OmniLight3D.new()
		omni.light_color = color
		omni.light_energy = 2.4
		omni.omni_range = 16.0
		omni.position = pos + Vector3(0, 5, 0)
		add_child(omni)

## Kick bots out of idle patrol into the midfield immediately.
func _push_bot_into_fight(bot: CombatBot, green: bool) -> void:
	if bot == null:
		return
	var push := Vector3(12 if green else -12, 1, randf_range(-8, 8))
	bot.patrol_points = [
		bot.global_position if bot.is_inside_tree() else bot.position,
		push,
		Vector3(0, 1, randf_range(-10, 10)),
		Vector3(-push.x * 0.4, 1, push.z),
	]
	bot.state = EnemySoldier.AiState.ALERT
	bot.call_deferred("_think")

func _process(delta: float) -> void:
	super(delta)
	if _match_over or not Game.is_playing():
		return
	if Net.is_online and not Net.is_match_authority():
		if _player_respawn > 0.0:
			_player_respawn -= delta
			banner.text = "REDEPLOYING IN %d...  (%d left)" % [
				ceili(_player_respawn), _lives_for_local()]
			if _player_respawn <= 0.0:
				_respawn_local_player()
		return
	for job in _pending.duplicate():
		job.t -= delta
		if job.t <= 0.0:
			_pending.erase(job)
			_respawn_bot_slot(job)
	if _player_respawn > 0.0:
		_player_respawn -= delta
		banner.text = "REDEPLOYING IN %d...  (%d left)" % [
			ceili(_player_respawn), _lives_for_local()]
		if _player_respawn <= 0.0:
			_respawn_local_player()
	_check_wipe()

func _lives_for_local() -> int:
	if Net.is_online:
		return int(_player_lives.get(Net.my_id(), 0))
	return int(_player_lives.get("local", 0))

func _respawn_local_player() -> void:
	var team := Net.local_team if Net.is_online else "green_army"
	var base := _chrome_base() if team == "chrome_legion" else _green_base()
	spawn_player(base + Vector3(0, 0, randf_range(-4, 4)))
	_update_banner()

func _respawn_bot_slot(job: Dictionary) -> void:
	var slot: String = str(job.get("slot", ""))
	var lives := int(_bot_lives.get(slot, 0))
	if lives <= 0:
		return
	var team_path: String = job.team
	var base: Vector3 = _green_base() if team_path == GREEN else _chrome_base()
	var bot := spawn_bot(team_path, base + Vector3(randf_range(-4, 4), 0, randf_range(-6, 6)), job.variant)
	if bot != null:
		bot.set_meta("skirmish_slot", slot)
		_push_bot_into_fight(bot, team_path == GREEN)
	_update_banner()

func _on_arena_unit_died(unit: Node) -> void:
	if _match_over:
		return
	if Net.is_online and not Net.is_match_authority():
		return
	if unit is ToyTank and (unit as ToyTank).ai_controlled:
		# Armor is bonus — doesn't consume NPC lives.
		_update_banner()
		return
	if unit is CombatBot:
		var slot := str(unit.get_meta("skirmish_slot", ""))
		if slot == "":
			slot = "green_x" if unit.faction != null and unit.faction.id == "green_army" else "chrome_x"
		var left := int(_bot_lives.get(slot, 1)) - 1
		_bot_lives[slot] = left
		if left > 0:
			_pending.append({
				"slot": slot,
				"team": GREEN if unit.faction != null and unit.faction.id == "green_army" else CHROME,
				"t": BOT_RESPAWN,
				"variant": unit.variant,
			})
		_update_banner()
		_check_wipe()
		return
	if unit is RemoteSoldier and unit.faction != null:
		# Human peer down on dedicated — spend that peer's respawn.
		var pid := int(unit.peer_id)
		var left := int(_player_lives.get(pid, 0)) - 1
		_player_lives[pid] = maxi(left, 0)
		_update_banner()
		_check_wipe()

func _on_player_died() -> void:
	if _match_over:
		return
	var key: Variant = Net.my_id() if Net.is_online else "local"
	# Authority / offline spends lives; clients also decrement locally for UI,
	# dedicated spends via RemoteSoldier death above.
	if not Net.is_online or not Net.is_dedicated:
		var left := int(_player_lives.get(key, 0)) - 1
		_player_lives[key] = maxi(left, 0)
	_update_banner()
	if int(_player_lives.get(key, 0)) > 0:
		_player_respawn = PLAYER_RESPAWN
	else:
		Events.notify.emit("No respawns left — spectating.")
		_check_wipe()

func _team_bot_lives(prefix: String) -> int:
	var n := 0
	for k in _bot_lives.keys():
		if str(k).begins_with(prefix):
			n += int(_bot_lives[k])
	return n

func _team_player_lives(team: String) -> int:
	if not Net.is_online:
		if team == "green_army":
			return int(_player_lives.get("local", 0))
		return 0
	var n := 0
	for id in Net.peers.keys():
		if Net.team_for_peer(int(id)) == team:
			n += int(_player_lives.get(int(id), 0))
	return n

func _team_alive_units(team: String) -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("team_" + team):
		if not is_instance_valid(u):
			continue
		if u.has_method("is_dead") and u.is_dead():
			continue
		# Pending respawns still count as "in the fight" via lives.
		n += 1
	return n

func _check_wipe() -> void:
	if _match_over:
		return
	if Net.is_online and not Net.is_match_authority():
		return
	var green_force := _team_bot_lives("green_") + _team_player_lives("green_army")
	var chrome_force := _team_bot_lives("chrome_") + _team_player_lives("chrome_legion")
	# Also respect pending bot respawns already queued.
	for job in _pending:
		if str(job.team) == GREEN:
			green_force += 1
		else:
			chrome_force += 1
	if green_force <= 0 and not _elim_green:
		_elim_green = true
		resolve_team_match(false, "CHROME WIPES GREEN", "Green Army is out of lives.")
	elif chrome_force <= 0 and not _elim_chrome:
		_elim_chrome = true
		resolve_team_match(true, "GREEN WIPES CHROME", "Chrome Legion is out of lives.")

func _on_score_synced(g: int, c: int) -> void:
	# Reuse score channel: green_lives_total, chrome_lives_total.
	banner.text = "GREEN LIVES  %d   —   %d  CHROME" % [g, c]

func _update_banner() -> void:
	var g := _team_bot_lives("green_") + _team_player_lives("green_army")
	var c := _team_bot_lives("chrome_") + _team_player_lives("chrome_legion")
	banner.text = "GREEN LIVES  %d   —   %d  CHROME" % [g, c]
	if Net.is_online and Net.is_match_authority():
		Net.broadcast_scores(g, c)

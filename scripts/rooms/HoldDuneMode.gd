class_name HoldDuneMode
extends ArenaBase
## HOLD THE DUNE — king-of-the-hill on the sandbox shovel mound.
## Premade sandbags and barriers ring the objective; fill the meter while
## standing on the dune. Chrome waves contest the hill.

const HOLD_TARGET := 28.0
const MATCH_TIME := 120.0
const GREEN := "res://data/factions/green_army.tres"
const CHROME := "res://data/factions/chrome_legion.tres"

var _hold := 0.0
var _time_left := MATCH_TIME
var _wave := 0
var _wave_cd := 8.0
var _player_respawn := -1.0
var _label: Label3D
var _chrome_cache := false
var _chrome_scan_cd := 0.0
var _banner_cd := 0.0
var _spawned_chrome_tank := false

func _init() -> void:
	arena_half = 52.0

func _max_chrome() -> int:
	return 8 if Game.low_gfx() else 12

func _setup_mode() -> void:
	Missions.start_mission("HOLD THE DUNE")
	spawn_player(Vector3(-arena_half + 12, 1, 0))
	var mates := 2 if Game.low_gfx() else 3
	for i in mates:
		spawn_bot(GREEN, Vector3(-arena_half + 14, 1, (i - 1) * 6.0), ["trooper", "scout", "commando"][i])
	_ring_dune()
	_build_hold_marker()
	spawn_weapon_drop(Vector3(14, 0, -10), "scatter")
	spawn_weapon_drop(Vector3(-14, 0, 10), "repeater")
	if not Game.low_gfx():
		spawn_tank(Vector3(-22, 1, -16), 30.0)
	_update_banner()
	sub_banner.text = "STAND ON THE DUNE  •  FILL THE METER"
	Events.notify.emit("HOLD THE DUNE: plant boots on the shovel mound. Chrome will try to push you off!")

func _ring_dune() -> void:
	# Premade sandbag / barrier ring — solid cover you can land on.
	add_prop("sacktrench", Vector3(0, 0, -14), 0.0, 8.0)
	add_prop("sacktrench_small", Vector3(12, 0, 8), -50.0, 5.0)
	add_prop("sacktrench_small", Vector3(-12, 0, 8), 50.0, 5.0)
	add_prop("barrier_large", Vector3(0, 0, 16), 0.0, 6.0)
	add_prop("crate", Vector3(18, 0, -6), 25.0, 3.2)
	add_prop("crate", Vector3(-18, 0, -4), -20.0, 3.0)
	add_prop("cone", Vector3(6, 0, -18), 0.0, 1.6)
	add_prop("cone", Vector3(-6, 0, -18), 0.0, 1.6)

func _build_hold_marker() -> void:
	add_prop("sign", Vector3(0, 0, -11), 0.0, 3.4)
	_label = Label3D.new()
	_label.text = "HOLD THE DUNE"
	_label.font_size = 64
	_label.pixel_size = 0.02
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1.0, 0.8, 0.35)
	_label.outline_size = 14
	_label.position = Vector3(0, 20, 0)
	add_child(_label)

func _process(delta: float) -> void:
	super(delta)
	if _match_over or not Game.is_playing():
		return
	_time_left -= delta
	_wave_cd -= delta
	if _wave_cd <= 0.0:
		_spawn_wave()
		_wave_cd = maxf(14.0 - _wave * 1.2, 8.0 if Game.low_gfx() else 7.0)
	_chrome_scan_cd -= delta
	if _chrome_scan_cd <= 0.0:
		_chrome_scan_cd = 0.28 if Game.low_gfx() else 0.18
		_chrome_cache = _chrome_on_hill()
	var on_hill := _player_on_hill()
	var contested := _chrome_cache
	if on_hill and not contested:
		_hold = minf(_hold + delta, HOLD_TARGET)
		_label.text = "HOLDING  %d%%" % int((_hold / HOLD_TARGET) * 100)
		_label.modulate = Color(0.4, 1.0, 0.55)
	elif on_hill and contested:
		_hold = maxf(_hold - delta * 0.35, 0.0)
		_label.text = "CONTESTED"
		_label.modulate = Color(1.0, 0.55, 0.3)
	else:
		_hold = maxf(_hold - delta * 0.55, 0.0)
		_label.text = "HOLD THE DUNE"
		_label.modulate = Color(1.0, 0.8, 0.35)
	_banner_cd -= delta
	if _banner_cd <= 0.0:
		_banner_cd = 0.2
		_update_banner()
	if _hold >= HOLD_TARGET:
		win_match("DUNE SECURED — Chrome pushed back")
		return
	if _time_left <= 0.0:
		lose_match("Time's up — the dune slipped away.")
		return
	if _player_respawn > 0.0:
		_player_respawn -= delta
		banner.text = "REDEPLOYING IN %d..." % ceili(_player_respawn)
		if _player_respawn <= 0.0:
			spawn_player(Vector3(-arena_half + 12, 1, randf_range(-6, 6)))
			_update_banner()

func _player_on_hill() -> bool:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return false
	# Foot / tank on the mound only — airborne plane camping does not count.
	if p.current_vehicle is PaperPlane:
		return false
	var pos: Vector3 = p.global_position
	if p.current_vehicle != null and is_instance_valid(p.current_vehicle):
		pos = p.current_vehicle.global_position
	var flat := Vector2(pos.x, pos.z).length()
	return flat < 11.0 and pos.y >= 0.5 and pos.y < 8.5

func _chrome_on_hill() -> bool:
	for n in get_tree().get_nodes_in_group("team_chrome_legion"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if n.has_method("is_dead") and n.is_dead():
			continue
		var pos: Vector3 = n.global_position
		var flat := Vector2(pos.x, pos.z).length()
		# On the mound top / mid-slope — not the sand at the foot.
		if flat < 11.0 and pos.y >= 1.2 and pos.y < 9.0:
			return true
	return false

func _chrome_alive() -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("team_chrome_legion"):
		if is_instance_valid(u) and not (u.has_method("is_dead") and u.is_dead()):
			n += 1
	return n

func _spawn_wave() -> void:
	_wave += 1
	var room := _max_chrome() - _chrome_alive()
	if room <= 0:
		_wave_cd = 5.0
		return
	var variants := ["trooper", "scout", "commando", "heavy", "grenadier"]
	var count := mini(mini(2 + _wave / 2, 5), room)
	for i in count:
		var ang := randf() * TAU
		var r := arena_half * 0.72
		var pos := Vector3(cos(ang) * r, 1, sin(ang) * r)
		spawn_bot(CHROME, pos, variants[i % variants.size()])
	if _wave == 3 and not _spawned_chrome_tank:
		_spawned_chrome_tank = true
		spawn_tank(Vector3(arena_half - 16, 1, 0), 180.0, "chrome_legion")
		Events.notify.emit("Chrome armor rolling on the dune!")
	elif _wave % 2 == 0:
		Events.notify.emit("Chrome wave %d inbound!" % _wave)

func _on_arena_unit_died(unit: Node) -> void:
	if unit is ToyTank and (unit as ToyTank).ai_controlled:
		pass  # Game.kills via enemies group
	elif unit is CombatBot and unit.faction != null and unit.faction.id != "green_army":
		Game.kills += 1  # CombatBots are not in enemies

func _on_player_died() -> void:
	if _match_over:
		return
	_player_respawn = 4.0
	_hold = maxf(_hold - 4.0, 0.0)

func _update_banner() -> void:
	if _player_respawn > 0.0:
		return
	banner.text = "DUNE  %d%%      TIME  %ds" % [int((_hold / HOLD_TARGET) * 100), maxi(0, ceili(_time_left))]

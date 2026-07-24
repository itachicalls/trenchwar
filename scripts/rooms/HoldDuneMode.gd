class_name HoldDuneMode
extends ArenaBase
## HOLD THE DUNE — king-of-the-hill survival. Chrome rushes the shovel mound
## in relentless waves. Fill the meter while standing on the dune; contested
## ground drains hard. Survive the onslaught.

const HOLD_TARGET := 48.0
const MATCH_TIME := 150.0
const GREEN := "res://data/factions/green_army.tres"
const CHROME := "res://data/factions/chrome_legion.tres"
const DUNE := Vector3(0, 1, 0)

var _hold := 0.0
var _time_left := MATCH_TIME
var _wave := 0
var _wave_cd := 3.0
var _player_respawn := -1.0
var _label: Label3D
var _chrome_cache := false
var _chrome_scan_cd := 0.0
var _banner_cd := 0.0
var _tanks_spawned := 0

func _init() -> void:
	arena_half = 52.0

func _max_chrome() -> int:
	return 11 if Game.low_gfx() else 16

func _setup_mode() -> void:
	Missions.start_mission("HOLD THE DUNE")
	if Net.is_online:
		spawn_online_humans({
			"green_army": Vector3(-arena_half + 12, 1, 0),
			"chrome_legion": Vector3(arena_half - 12, 1, 0),
		})
	else:
		spawn_player(Vector3(-arena_half + 12, 1, 0))
	# Greens dig in on the mound flanks.
	var mates := bot_slots(2 if Game.low_gfx() else 3, "green_army")
	for i in mates:
		var mate := spawn_bot(GREEN, Vector3(-6 + i * 4.0, 1, 8), ["commando", "heavy", "trooper"][i])
		mate.patrol_points = [Vector3(-4 + i * 3.0, 1, 2), Vector3(4, 1, -2), DUNE]
	_ring_dune()
	_build_hold_marker()
	spawn_weapon_drop(Vector3(14, 0, -10), "scatter")
	spawn_weapon_drop(Vector3(-14, 0, 10), "repeater")
	spawn_weapon_drop(Vector3(0, 4.2, 0), "marble", 55.0)
	if not Game.low_gfx():
		spawn_tank(Vector3(-22, 1, -16), 30.0)
	_update_banner()
	sub_banner.text = ("ONLINE  •  GREEN HOLDS  •  CHROME CONTESTS" if Net.is_online
		else "HOLD THE MOUND  •  WAVE AFTER WAVE")
	Events.notify.emit("HOLD THE DUNE: Chrome is coming in waves. Plant boots on the shovel mound and don't give it back!")
	_spawn_wave()

func _ring_dune() -> void:
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
		_wave_cd = maxf(9.0 - _wave * 0.45, 4.2 if Game.low_gfx() else 3.6)
		if not Net.is_online or Net.is_match_authority():
			_spawn_wave()
	_chrome_scan_cd -= delta
	if _chrome_scan_cd <= 0.0:
		_chrome_scan_cd = 0.25 if Game.low_gfx() else 0.15
		_chrome_cache = _chrome_on_hill()
	var on_hill := _player_on_hill()
	var contested := _chrome_cache
	if on_hill and not contested:
		_hold = minf(_hold + delta * 0.85, HOLD_TARGET)
		_label.text = "HOLDING  %d%%" % int((_hold / HOLD_TARGET) * 100)
		_label.modulate = Color(0.4, 1.0, 0.55)
	elif on_hill and contested:
		_hold = maxf(_hold - delta * 0.95, 0.0)
		_label.text = "CONTESTED — CLEAR THE HILL"
		_label.modulate = Color(1.0, 0.45, 0.25)
	else:
		_hold = maxf(_hold - delta * 1.1, 0.0)
		_label.text = "GET ON THE DUNE"
		_label.modulate = Color(1.0, 0.8, 0.35)
	_banner_cd -= delta
	if _banner_cd <= 0.0:
		_banner_cd = 0.2
		_update_banner()
	if _hold >= HOLD_TARGET:
		resolve_team_match(true, "DUNE SECURED — %d waves held" % _wave,
			"Green locked the dune after %d waves." % _wave)
		return
	if _time_left <= 0.0:
		resolve_team_match(false, "CHROME TAKES THE DUNE",
			"Time's up — Chrome took the dune.")
		return
	if _player_respawn > 0.0:
		_player_respawn -= delta
		banner.text = "REDEPLOYING IN %d..." % ceili(_player_respawn)
		if _player_respawn <= 0.0:
			var team := Net.local_team if Net.is_online else "green_army"
			var base := Vector3(arena_half - 12, 1, 0) if team == "chrome_legion" \
				else Vector3(-arena_half + 12, 1, 0)
			spawn_player(base + Vector3(0, 0, randf_range(-6, 6)))
			_update_banner()

func _pos_on_hill(pos: Vector3, pad: float = 11.0) -> bool:
	var flat := Vector2(pos.x, pos.z).length()
	return flat < pad and pos.y >= 0.5 and pos.y < 8.5

func _player_on_hill() -> bool:
	# Any green human (local or remote puppet) counts for the hold.
	if Net.is_online and Net.local_team == "chrome_legion":
		# Chrome humans contest instead of filling the meter.
		return false
	for n in get_tree().get_nodes_in_group("team_green_army"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if n is CombatBot:
			continue
		if n.has_method("is_dead") and n.is_dead():
			continue
		if _pos_on_hill((n as Node3D).global_position):
			return true
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return false
	if p.current_vehicle is PaperPlane:
		return false
	var pos: Vector3 = p.global_position
	if p.current_vehicle != null and is_instance_valid(p.current_vehicle):
		pos = p.current_vehicle.global_position
	return _pos_on_hill(pos)

func _chrome_on_hill() -> bool:
	for n in get_tree().get_nodes_in_group("team_chrome_legion"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if n.has_method("is_dead") and n.is_dead():
			continue
		var pos: Vector3 = n.global_position
		if _pos_on_hill(pos, 11.5):
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
		# Cap hit — still tick the clock so later culls open slots.
		_wave_cd = mini(_wave_cd, 3.5)
		return
	var variants := ["trooper", "scout", "commando", "heavy", "grenadier", "chrome_beetle"]
	# Escalating pack size: 3 → 7 (desktop), slightly leaner on web.
	var pack := mini(3 + _wave / 2 + (_wave / 4), 7 if not Game.low_gfx() else 5)
	var count := mini(pack, room)
	Events.notify.emit("CHROME WAVE %d — %d inbound!" % [_wave, count])
	Sfx.play("shoot_heavy", -5.0, 0.4)
	for i in count:
		var ang := (TAU * float(i) / float(count)) + _wave * 0.35 + randf_range(-0.15, 0.15)
		var r := arena_half * (0.78 if i % 2 == 0 else 0.68)
		var pos := Vector3(cos(ang) * r, 1, sin(ang) * r)
		var vname: String = variants[(i + _wave) % variants.size()]
		if _wave >= 4 and i == 0:
			vname = "heavy"
		if _wave >= 7 and i == 1:
			vname = "juggernaut" if not Game.low_gfx() else "heavy"
		_spawn_rusher(pos, vname)
	# Armor every few waves — keep pressure after the first tank dies.
	if _wave == 3 or (_wave > 3 and _wave % 4 == 0):
		if _tanks_spawned < (2 if Game.low_gfx() else 3):
			_tanks_spawned += 1
			var tang := randf() * TAU
			var tpos := Vector3(cos(tang) * arena_half * 0.75, 1, sin(tang) * arena_half * 0.75)
			spawn_tank(tpos, rad_to_deg(-tang) + 180.0, "chrome_legion")
			Events.notify.emit("Chrome armor on the dune!")

## Chrome that paths straight at the mound (not random mid-field wander).
func _spawn_rusher(pos: Vector3, variant_name: String) -> CombatBot:
	var bot := spawn_bot(CHROME, pos, variant_name)
	if bot == null:
		return null
	# Approach lanes → mound crest. Avoids aimless circles into sandbox clutter.
	var approach := pos.normalized() * 8.0
	approach.y = 1.0
	bot.patrol_points = [approach, DUNE + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), DUNE]
	bot.vision_range = 36.0
	bot.attack_range = 18.0
	bot.call_deferred("_begin_dune_rush")
	return bot

func _on_arena_unit_died(unit: Node) -> void:
	if unit is CombatBot and unit.faction != null and unit.faction.id != "green_army":
		Game.kills += 1

func _on_player_died() -> void:
	if _match_over:
		return
	_player_respawn = 3.5
	_hold = maxf(_hold - 6.0, 0.0)

func _update_banner() -> void:
	if _player_respawn > 0.0:
		return
	banner.text = "DUNE  %d%%   WAVE  %d   TIME  %ds" % [
		int((_hold / HOLD_TARGET) * 100), _wave, maxi(0, ceili(_time_left))]

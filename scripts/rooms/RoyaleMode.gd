class_name RoyaleMode
extends ArenaBase
## BATTLE ROYALE — RESURGENCE (casual, vs bots). Four toy squads drop into
## the Sandbox. A closing "cleanup zone" (mom is tidying up) crushes anyone
## outside it. Resurgence rules: while any of your squad is still standing,
## fallen members redeploy — until the final circles, when respawns go dark.
## Last squad standing wins.

const SQUADS := {
	"green_army": "res://data/factions/green_army.tres",
	"chrome_legion": "res://data/factions/chrome_legion.tres",
	"brick_kingdom": "res://data/factions/brick_kingdom.tres",
	"wind_up_empire": "res://data/factions/wind_up_empire.tres",
}
const SQUAD_SIZE := 3
const RESPAWN_TIME := 9.0
## Zone stages: [radius, hold seconds before next shrink]. Respawns die at
## stage index >= NO_RESPAWN_STAGE.
const STAGES := [[95.0, 20.0], [65.0, 20.0], [42.0, 18.0], [24.0, 15.0], [11.0, 999.0]]
const NO_RESPAWN_STAGE := 3
const ZONE_DPS := 7.0
const SHRINK_TIME := 10.0

var stage := 0
var stage_clock: float = STAGES[0][1]
var zone_radius: float = STAGES[0][0]
var _shrinking := false
var _pending: Array[Dictionary] = []
var _player_respawn := -1.0
var _eliminated := {}
var _zone_wall: MeshInstance3D
var _tick := 0.0

func _init() -> void:
	arena_half = 65.0

func _squad_corner(id: String) -> Vector3:
	match id:
		"green_army": return Vector3(-arena_half + 12, 1, arena_half - 12)
		"chrome_legion": return Vector3(arena_half - 12, 1, -arena_half + 12)
		"brick_kingdom": return Vector3(arena_half - 12, 1, arena_half - 12)
		_: return Vector3(-arena_half + 12, 1, -arena_half + 12)

func _setup_mode() -> void:
	Missions.start_mission("BATTLE ROYALE — RESURGENCE")
	for id in SQUADS:
		_eliminated[id] = false
		var corner := _squad_corner(id)
		var n := SQUAD_SIZE - 1 if id == "green_army" else SQUAD_SIZE
		for i in n:
			spawn_bot(SQUADS[id], corner + Vector3((i - 1) * 3.5, 0, i * 2.5), ["commando", "scout", "heavy"][i % 3])
	spawn_player(_squad_corner("green_army") + Vector3(0, 0, -4))
	_build_zone_wall()
	# Loot spread: strong weapons pull squads toward the center early.
	spawn_weapon_drop(Vector3(0, 4.2, 0), "marble", 60.0)
	var loot := ["scatter", "sniper", "soaker", "repeater", "scatter", "sniper"]
	for i in loot.size():
		var ang := TAU * i / loot.size() + 0.4
		var r := arena_half * (0.35 + 0.25 * (i % 2))
		spawn_weapon_drop(Vector3(cos(ang) * r, 0, sin(ang) * r), loot[i], 40.0)
	# Mid-loot vehicles — high-risk high-reward pulls.
	spawn_tank(Vector3(-10, 1, 18), 45.0)
	spawn_tank(Vector3(16, 1, -12), -120.0)
	spawn_plane(Vector3(0, 6, 24), 180.0)
	Pickup.spawn_fuel(self, Vector3(8, 0, 8), 60)
	Pickup.spawn_fuel(self, Vector3(-14, 0, -10), 60)
	_update_banner()
	Events.notify.emit("RESURGENCE: keep one squadmate alive and the fallen return. Outlast every squad!")

## Translucent energy cylinder marking the safe zone edge.
func _build_zone_wall() -> void:
	_zone_wall = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 60.0
	cyl.radial_segments = 48
	_zone_wall.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.75, 1.0, 0.12)
	m.emission_enabled = true
	m.emission = Color(0.3, 0.75, 1.0)
	m.emission_energy_multiplier = 1.2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_zone_wall.material_override = m
	_zone_wall.position.y = 30.0
	add_child(_zone_wall)
	_zone_wall.scale = Vector3(zone_radius, 1, zone_radius)

func _process(delta: float) -> void:
	super(delta)
	if _match_over or not Game.is_playing():
		return
	_run_zone(delta)
	_run_respawns(delta)
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_zone_damage()
		_check_squads()
	_update_banner()

func _run_zone(delta: float) -> void:
	if _shrinking:
		var target: float = STAGES[stage][0]
		zone_radius = maxf(zone_radius - delta * ((STAGES[stage - 1][0] - target) / SHRINK_TIME), target)
		if zone_radius <= target:
			_shrinking = false
			stage_clock = STAGES[stage][1]
			if stage == NO_RESPAWN_STAGE:
				Events.notify.emit("RESURGENCE OFFLINE — no more respawns. Make it count.")
	else:
		stage_clock -= delta
		if stage_clock <= 0.0 and stage < STAGES.size() - 1:
			stage += 1
			_shrinking = true
			Events.notify.emit("The cleanup zone is closing in!")
			Sfx.play("shoot_heavy", -6.0, 0.4)
	_zone_wall.scale = Vector3(zone_radius, 1, zone_radius)

func _zone_damage() -> void:
	var victims: Array[Node] = []
	victims.append_array(get_tree().get_nodes_in_group("combat_bots"))
	if Game.player != null and is_instance_valid(Game.player):
		# Boarded: sweep damages the hull/plane so camping outside in armor fails.
		var veh = Game.player.current_vehicle
		if veh != null and is_instance_valid(veh):
			victims.append(veh)
		else:
			victims.append(Game.player)
	for v in victims:
		if v is Node3D and Vector2(v.global_position.x, v.global_position.z).length() > zone_radius:
			if v.has_method("take_damage") and not (v.has_method("is_dead") and v.is_dead()):
				v.take_damage(ZONE_DPS)
				if v == Game.player or (Game.player != null and v == Game.player.current_vehicle):
					Events.notify.emit("You're outside the zone! Get inside the light!")

func _respawns_allowed() -> bool:
	return stage < NO_RESPAWN_STAGE

func _squad_alive_count(id: String) -> int:
	var count := get_tree().get_nodes_in_group("team_" + id).size()
	if id == "green_army" and Game.player != null and is_instance_valid(Game.player):
		count += 1
	return count

func _run_respawns(delta: float) -> void:
	for job in _pending.duplicate():
		job.t -= delta
		if job.t <= 0.0:
			_pending.erase(job)
			if not _respawns_allowed() or _eliminated[job.id] or _squad_alive_count(job.id) == 0:
				continue
			var pos := _drop_point(job.id)
			spawn_bot(SQUADS[job.id], pos, job.variant)
			if job.id == "green_army":
				Events.notify.emit("Squadmate redeployed!")
	if _player_respawn > 0.0:
		_player_respawn -= delta
		banner.text = "RESURGENCE IN %d..." % ceili(_player_respawn)
		if _player_respawn <= 0.0:
			if _squad_alive_count("green_army") > 0:
				spawn_player(_drop_point("green_army"))
				Events.notify.emit("You're back in the fight. Resurgence complete.")
			else:
				lose_match("Green squad wiped. The sandbox belongs to someone else tonight.")

## Respawn inside the current zone, biased toward the squad's corner.
func _drop_point(id: String) -> Vector3:
	var corner := _squad_corner(id)
	var dir := Vector2(corner.x, corner.z)
	if dir.length() > zone_radius * 0.7:
		dir = dir.normalized() * zone_radius * 0.7
	return Vector3(dir.x + randf_range(-4, 4), 1, dir.y + randf_range(-4, 4))

func _on_arena_unit_died(unit: Node) -> void:
	if _match_over or not (unit is CombatBot):
		return
	if unit.faction.id != "green_army":
		Game.kills += 1
	if _respawns_allowed():
		_pending.append({"id": unit.faction.id, "t": RESPAWN_TIME, "variant": unit.variant})

func _on_player_died() -> void:
	if _match_over:
		return
	if _respawns_allowed() and _squad_alive_count("green_army") > 0:
		_player_respawn = RESPAWN_TIME
	else:
		lose_match("You were swept away. No resurgence in the endgame.")

func _check_squads() -> void:
	var alive_squads: Array[String] = []
	for id in SQUADS:
		if _eliminated[id]:
			continue
		var pending := false
		for job in _pending:
			if job.id == id:
				pending = true
				break
		var living := _squad_alive_count(id)
		if id == "green_army" and _player_respawn > 0.0:
			pending = true
		if living == 0 and (not pending or not _respawns_allowed()):
			_eliminated[id] = true
			Events.notify.emit("%s squad ELIMINATED. %d remain." % [id.to_upper().replace("_", " "), 4 - _count_eliminated()])
		else:
			alive_squads.append(id)
	if _eliminated["green_army"]:
		lose_match("Green squad eliminated.")
	elif alive_squads.size() == 1 and alive_squads[0] == "green_army":
		win_match("VICTORY ROYALE — LAST SQUAD STANDING")

func _count_eliminated() -> int:
	var n := 0
	for id in _eliminated:
		if _eliminated[id]:
			n += 1
	return n

func _update_banner() -> void:
	if _player_respawn > 0.0:
		return   # banner shows the respawn countdown
	var zone_txt: String
	if _shrinking:
		zone_txt = "ZONE CLOSING"
	elif stage >= STAGES.size() - 1:
		zone_txt = "FINAL ZONE"
	else:
		zone_txt = "NEXT ZONE %ds" % ceili(stage_clock)
	banner.text = "SQUADS LEFT  %d      %s" % [4 - _count_eliminated(), zone_txt]
	sub_banner.text = ("RESURGENCE ACTIVE — squad respawns online" if _respawns_allowed() else "NO RESPAWNS — final circles") \
		+ "  •  tanks & plane mid-loot"

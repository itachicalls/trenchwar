class_name GardenBed
extends RoomBase
## ACT 3-1: THE TRENCHES — the raised garden bed, the game's namesake level.
## The Chrome Legion dug a three-line trench network through the vegetable
## garden. Capture the trench lines flag by flag, silence the artillery, then
## hold the line against the counterattack.
##
## Built almost entirely from the war-prop pack: sandbag trenches, barbed
## wire, bunker structures, water tower, barrels, pipes and debris.

const ROOM_W := 150.0
const ROOM_D := 120.0

## Trench line z positions, player side (south, +z) to Legion side (north).
const LINES := [28.0, 0.0, -28.0]

var _wave := 0
var _lines_captured := 0

func _ready() -> void:
	LostToy.reset_level_counters()
	_setup_nav()
	_build_lighting()
	_build_field()
	_build_trench_lines()
	_build_legion_rear()
	_build_garden_flora()
	_spawn_units()
	_spawn_pickups_and_toys()
	_bake_navmesh()
	_start_mission()
	Events.unit_died.connect(_on_unit_died)

# =========================================================================
#  LIGHTING — moonlit open field, flare light over no-man's-land.
# =========================================================================
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	we.environment = RoomBase.make_night_environment(Color(0.1, 0.13, 0.18), Color(0.4, 0.45, 0.55), 1.05)
	add_child(we)
	add_light_rig(self, Vector3(-42, 155, 0), Color(0.66, 0.75, 1.0), 1.35)
	# A hanging garden lantern bathes mid-field in warning amber.
	var flare := OmniLight3D.new()
	flare.light_color = Color(1.0, 0.7, 0.35)
	flare.light_energy = 2.4
	flare.omni_range = 45.0
	flare.position = Vector3(0, 26, 0)
	add_child(flare)
	register_flicker(flare, 2.4, 1.4, 0.18)
	# Cold Chrome glow over the artillery position.
	var rear := OmniLight3D.new()
	rear.light_color = Color(0.4, 0.9, 1.0)
	rear.light_energy = 1.8
	rear.omni_range = 40.0
	rear.position = Vector3(0, 10, -ROOM_D / 2 + 14)
	add_child(rear)
	register_flicker(rear, 1.8, 2.2, 0.15)

# =========================================================================
#  FIELD — tilled dirt, wooden garden-bed frame as the world border.
# =========================================================================
func _build_field() -> void:
	var dirt := ToyMaterials.concrete(Color(0.34, 0.26, 0.18))
	var frame := ToyMaterials.plank_floor(Color(0.42, 0.3, 0.18))
	_static_box(Vector3(0, -0.5, 0), Vector3(ROOM_W, 1.0, ROOM_D), dirt)
	for spec in [
		[Vector3(0, 5, -ROOM_D / 2 - 2), Vector3(ROOM_W + 8, 10, 4)],
		[Vector3(0, 5, ROOM_D / 2 + 2), Vector3(ROOM_W + 8, 10, 4)],
		[Vector3(-ROOM_W / 2 - 2, 5, 0), Vector3(4, 10, ROOM_D + 8)],
		[Vector3(ROOM_W / 2 + 2, 5, 0), Vector3(4, 10, ROOM_D + 8)],
	]:
		_static_box(spec[0], spec[1], frame)
	# Tilled furrows: long low ridges give prone-height cover everywhere.
	var furrow := ToyMaterials.concrete(Color(0.3, 0.22, 0.15))
	for i in 7:
		var z := -ROOM_D / 2 + 12 + i * 16.0
		if absf(z - LINES[0]) < 6 or absf(z - LINES[1]) < 6 or absf(z - LINES[2]) < 6:
			continue
		_static_box(Vector3(randf_range(-8, 8), 0.5, z), Vector3(ROOM_W * 0.7, 1.0, 3.0), furrow, true)
	add_dust_motes(Vector3(0, 10, 0), Vector3(ROOM_W / 2, 10, ROOM_D / 2), 50, Color(0.75, 0.85, 0.5))

# =========================================================================
#  TRENCH LINES — sandbags + barbed wire with assault gaps, one flag each.
# =========================================================================
func _build_trench_lines() -> void:
	for li in LINES.size():
		var z: float = LINES[li]
		# Sandbag wall segments with two gaps per line.
		for xi in range(-5, 6):
			if xi in [-2, 3]:
				continue   # assault gaps
			add_prop("sacktrench", Vector3(xi * 12.0, 0, z), 0.0 if li % 2 == 0 else 180.0, 10.0)
		# Barbed wire on the approach side of each line.
		for xi in range(-4, 5):
			if xi in [-2, 3]:
				continue
			add_prop("metalfence", Vector3(xi * 13.0, 0, z + (5.0 if li > 0 else -5.0)), 90.0, 9.0, false)
		# Capture flag at the middle of each line.
		_make_capture_zone(Vector3(6, 0, z), li)
		# Trench clutter: barrels, crates, debris.
		add_barrel(Vector3(-30 + li * 8, 0, z + 3), randf() * 360.0, 2.6)
		add_prop("crate", Vector3(22 - li * 6, 0, z - 3), randf() * 360.0, 3.0)
		add_prop("debris_pile", Vector3(-52 + li * 20, 0, z), randf() * 360.0, 6.0)
	# Minefield strip between line 1 and 2, marked by a warning sign.
	add_prop("sign", Vector3(-10, 0, 15), 15.0, 3.4)
	for pos in [Vector3(-18, 0, 14), Vector3(-4, 0, 16), Vector3(10, 0, 13), Vector3(24, 0, 15), Vector3(-30, 0, 12)]:
		Landmine.spawn(self, pos)

## Stand in the ring to raise the flag. Leaves drain progress slowly.
func _make_capture_zone(pos: Vector3, index: int) -> void:
	var zone := Area3D.new()
	zone.collision_layer = 0
	zone.collision_mask = 0b0010
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 7.0
	cyl.height = 6.0
	cs.shape = cyl
	cs.position.y = 3.0
	zone.add_child(cs)
	add_child(zone)
	zone.global_position = pos

	# Ground ring so the zone reads at a glance.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 6.55
	tm.outer_radius = 6.85
	ring.mesh = tm
	var ring_mat := ToyMaterials.glow(Color(1.0, 0.55, 0.15), 1.1)
	ring.material_override = ring_mat
	ring.position.y = 0.15
	zone.add_child(ring)
	# Flag pole with a Chrome pennant that swaps to Green on capture.
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.12
	pm.bottom_radius = 0.16
	pm.height = 9.0
	pole.mesh = pm
	pole.material_override = ToyMaterials.metal(Color(0.6, 0.62, 0.68), 0.3)
	pole.position.y = 4.5
	zone.add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(3.2, 1.9, 0.12)
	flag.mesh = fm
	flag.material_override = ToyMaterials.plastic(Color(0.55, 0.62, 0.78), 0.4)
	flag.position = Vector3(1.7, 7.9, 0)
	zone.add_child(flag)
	var label := Label3D.new()
	label.text = "HOLD TO CAPTURE"
	label.font_size = 64
	label.pixel_size = 0.02
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.75, 0.3)
	label.outline_size = 16
	label.position.y = 10.6
	zone.add_child(label)

	var progress := {"v": 0.0, "done": false}
	zone.set_meta("line_index", index)
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	zone.add_child(timer)
	timer.timeout.connect(func():
		if progress.done or not Game.is_playing():
			return
		var inside := Game.player != null and is_instance_valid(Game.player) \
			and zone.overlaps_body(Game.player)
		progress.v = clampf(progress.v + (0.1 / 6.0 if inside else -0.1 / 12.0), 0.0, 1.0)
		if progress.v <= 0.0 and not inside:
			label.text = "HOLD TO CAPTURE"
		elif not progress.done:
			label.text = "CAPTURING  %d%%" % int(progress.v * 100)
		if progress.v >= 1.0:
			progress.done = true
			label.text = "LINE SECURED"
			label.modulate = UiTheme.GREEN
			flag.material_override = ToyMaterials.plastic(Color(0.35, 0.65, 0.25), 0.4)
			ring.material_override = ToyMaterials.glow(Color(0.4, 0.9, 0.35), 1.6)
			Sfx.play("objective")
			_lines_captured += 1
			Missions.progress("lines")
			Pickup.spawn_coin(self, zone.global_position + Vector3(2, 0, 2), 10)
			if _lines_captured >= LINES.size():
				_begin_counterattack())

# =========================================================================
#  LEGION REAR — artillery pods behind bunkers, water-tower sniper nest.
# =========================================================================
func _build_legion_rear() -> void:
	var rear_z := -ROOM_D / 2 + 16
	add_prop("structure_1", Vector3(-34, 0, rear_z), 0.0, 16.0)
	add_prop("structure_2", Vector3(34, 0, rear_z), 0.0, 16.0)
	add_prop("watertank", Vector3(58, 0, rear_z + 14), 0.0, 14.0)
	add_prop("container_long", Vector3(-58, 0, rear_z + 12), 90.0, 12.0)
	add_prop("pipes", Vector3(12, 0, rear_z - 2), 0.0, 6.0)
	add_prop("gastank", Vector3(-14, 0, rear_z - 2), 30.0, 5.0)
	# The three artillery pods (destructible objectives).
	for x in [-24.0, 0.0, 24.0]:
		var pod := DropPod.new()
		add_child(pod)
		pod.position = Vector3(x, 0, rear_z + 4)
		add_barrel(Vector3(x + 3.5, 0, rear_z + 7), randf() * 360.0, 2.8, true)

# =========================================================================
#  FLORA — tomato-plant jungle along the flanks (trees at toy scale).
# =========================================================================
func _build_garden_flora() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31415
	for i in 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(side * rng.randf_range(52, 68), 0, rng.randf_range(-ROOM_D / 2 + 12, ROOM_D / 2 - 12))
		add_prop("tree_%d" % (1 + i % 4), pos, rng.randf() * 360.0, rng.randf_range(10, 16))
	add_prop("streetlight", Vector3(52, 0, 34), -90.0, 12.0)
	add_prop("tires", Vector3(-48, 0, 40), 20.0, 6.0)
	add_prop("trashcontainer", Vector3(48, 0, -44), 160.0, 8.0)

# =========================================================================
#  UNITS
# =========================================================================
func _spawn_units() -> void:
	var green: FactionData = load("res://data/factions/green_army.tres")
	var player := Player.new()
	player.faction = green
	add_child(player)
	player.position = Vector3(-8, 1, ROOM_D / 2 - 10)

	for pos in [Vector3(14, 1, 40), Vector3(-34, 1, 20)]:
		var mate := SquadMate.new()
		mate.faction = green
		add_child(mate)
		mate.position = pos

	# Trench garrisons: each line gets a patrol; deeper lines hit harder.
	var mixes := [["trooper", "scout", "trooper"], ["commando", "heavy", "scout"], ["grenadier", "sniper", "juggernaut"]]
	for li in LINES.size():
		var z: float = LINES[li]
		var route: Array[Vector3] = [Vector3(-30, 1, z - 3), Vector3(10, 1, z + 3), Vector3(38, 1, z - 2)]
		for i in mixes[li].size():
			_spawn_enemy(mixes[li][i], route, route[i % route.size()] + Vector3(i * 2.0, 0, 0))
	# Water-tower sniper overwatch + rear guards.
	var rear_z := -ROOM_D / 2 + 16
	_spawn_enemy("sniper", [Vector3(58, 1, rear_z + 8)], Vector3(58, 1, rear_z + 8))
	_spawn_enemy("heavy", [Vector3(-24, 1, rear_z + 8), Vector3(24, 1, rear_z + 8)], Vector3(-20, 1, rear_z + 8))
	_spawn_enemy("trooper", [Vector3(0, 1, rear_z + 10), Vector3(12, 1, rear_z + 6)], Vector3(8, 1, rear_z + 8))

func _spawn_enemy(variant_name: String, route: Array[Vector3], pos: Vector3, alerted: bool = false) -> void:
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var enemy := EnemySoldier.new()
	enemy.faction = chrome
	enemy.variant = variant_name
	enemy.patrol_points = route
	add_child(enemy)
	enemy.position = pos
	if alerted:
		enemy.set_meta("wave", true)
		enemy.state = EnemySoldier.AiState.ALERT
		if Game.player != null:
			enemy.target = Game.player

func _spawn_pickups_and_toys() -> void:
	scatter_coins(ROOM_W * 0.4, ROOM_D * 0.4)
	for pos in [Vector3(-40, 0, 34), Vector3(30, 0, 6), Vector3(-20, 0, -20), Vector3(50, 0, -30)]:
		Pickup.spawn_health(self, pos)
	for pos in [Vector3(20, 0, 34), Vector3(-16, 0, 4), Vector3(6, 0, -34)]:
		Pickup.spawn_ammo(self, pos)
	for pos in [Vector3(-26, 0, 42), Vector3(44, 0, 20), Vector3(-52, 0, -8), Vector3(16, 0, -44)]:
		Pickup.spawn_coin(self, pos, 5)
	Pickup.spawn_powerup(self, Vector3(0, 0, 14), Pickup.Kind.RAPID)
	Pickup.spawn_powerup(self, Vector3(-44, 0, -26), Pickup.Kind.SHIELD)
	spawn_weapon_drop(Vector3(24, 0, 20), "sniper")
	spawn_weapon_drop(Vector3(-36, 0, 8), "marble")
	spawn_weapon_drop(Vector3(10, 0, -26), "scatter")
	var toy_spots := [
		["Corporal Sprout", Vector3(-60, 0.6, 44)],
		["Muddy", Vector3(58, 0.6, -46)],
		["The General's Monocle", Vector3(60, 9.5, -44)],
		["Twig", Vector3(-56, 0.6, -40)],
		["Berry", Vector3(52, 0.6, 36)],
	]
	for spot in toy_spots:
		var toy := LostToy.new()
		toy.toy_name = spot[0]
		add_child(toy)
		toy.position = spot[1]

# =========================================================================
#  MISSION — capture, silence, hold.
# =========================================================================
func _start_mission() -> void:
	Missions.start_mission("ACT 3 — THE TRENCHES")
	Missions.add_objective("lines", "Capture the trench lines (stand at the flags)", 3)
	Missions.add_objective("pods", "Silence the Chrome artillery", 3)
	Missions.add_objective("counter", "Break the counterattack", 12)
	Missions.marker_provider = func(id: String) -> Vector3:
		match id:
			"lines":
				return _nearest_uncaptured_flag()
			"pods":
				return nearest_in_group("chrome_pods")
			"counter":
				return nearest_in_group("enemies")
		return Vector3.INF
	Events.notify.emit("This is it, soldier — the trench war the toybox will sing about. Take the first line.")

func _nearest_uncaptured_flag() -> Vector3:
	# Flags progress south to north; point at the next line by capture count.
	if _lines_captured < LINES.size():
		return Vector3(6, 0, LINES[_lines_captured])
	return Vector3.INF

## All three lines taken: the Legion throws everything it has left at you.
func _begin_counterattack() -> void:
	Events.notify.emit("All lines secured! Chrome counterattack inbound — HOLD THE LINE!")
	for wave in 3:
		get_tree().create_timer(4.0 + wave * 18.0).timeout.connect(func():
			if not Game.is_playing():
				return
			_wave += 1
			Events.notify.emit("COUNTERATTACK WAVE %d!" % _wave)
			Sfx.play("shoot_heavy", -4.0, 0.35)
			var mix := ["trooper", "commando", "grenadier", "heavy"]
			for i in 4:
				var x := -30.0 + i * 20.0
				_spawn_enemy(mix[i], [Vector3(x, 1, 20)], Vector3(x, 1, -ROOM_D / 2 + 8), true))

func _on_unit_died(unit: Node) -> void:
	if unit is EnemySoldier and unit.has_meta("wave"):
		Missions.progress("counter")

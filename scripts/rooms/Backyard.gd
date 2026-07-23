class_name Backyard
extends RoomBase
## THE BACKYARD — Act 2, Mission 3: "NO MAN'S LAWN".
##
## The first open-sky battlefield: moonlit grass plains cratered with molehills,
## the sandbox is a desert theater, the flowerbed a jungle front, and the great
## Oak Tree looms over everything. The Chrome Legion has dug a trench network
## across the lawn — the largest battle of Act 2, and the finale.

const ROOM_W := 180.0
const ROOM_D := 140.0

var _counterattack_sent := false
var _final_wave_sent := false

func _ready() -> void:
	LostToy.reset_level_counters()
	_setup_nav()
	_build_lighting()
	_build_lawn()
	_build_fence_perimeter()
	_build_oak_tree()
	_build_sandbox_theater()
	_build_flowerbed_jungle()
	_build_trench_network()
	_build_scattered_props()
	_spawn_units()
	_spawn_pickups_and_toys()
	_bake_navmesh()
	_start_mission()
	Events.unit_died.connect(_on_unit_died)

# =========================================================================
#  LIGHTING — full moon, open sky, fireflies. The prettiest map at night.
# =========================================================================
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	var env := RoomBase.make_night_environment(Color(0.1, 0.14, 0.2), Color(0.42, 0.5, 0.6), 1.3)
	env.background_color = Color(0.04, 0.06, 0.14)   # open night sky, a shade lighter
	env.fog_density = 0.002                          # ground mist rolls over the lawn
	we.environment = env
	add_child(we)
	add_light_rig(self, Vector3(-52, 30, 0), Color(0.7, 0.8, 1.0), 1.7)

	# Porch light by the back door: the warm safe zone.
	var porch := SpotLight3D.new()
	porch.light_color = Color(1.0, 0.8, 0.5)
	porch.light_energy = 3.2
	porch.spot_range = 55.0
	porch.spot_angle = 42.0
	porch.position = Vector3(-70, 30, 46)
	porch.rotation_degrees = Vector3(-58, -35, 0)
	add_child(porch)
	register_flicker(porch, 3.2, 0.8, 0.05)

	# Chrome trench glow across the mid-lawn.
	var trench_glow := OmniLight3D.new()
	trench_glow.light_color = Color(0.4, 0.9, 1.0)
	trench_glow.light_energy = 1.8
	trench_glow.omni_range = 44.0
	trench_glow.position = Vector3(20, 8, -10)
	add_child(trench_glow)
	register_flicker(trench_glow, 1.8, 2.2, 0.14)

	# Fireflies: drifting warm sparks over the flowerbed.
	var flies := CPUParticles3D.new()
	flies.amount = 26
	flies.lifetime = 8.0
	flies.preprocess = 8.0
	flies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flies.emission_box_extents = Vector3(30, 5, 14)
	flies.gravity = Vector3.ZERO
	flies.initial_velocity_min = 0.3
	flies.initial_velocity_max = 1.0
	flies.scale_amount_min = 0.06
	flies.scale_amount_max = 0.12
	var fm := SphereMesh.new()
	fm.radius = 0.5
	fm.height = 1.0
	fm.material = ToyMaterials.glow(Color(0.95, 0.9, 0.4), 2.2)
	flies.mesh = fm
	flies.position = Vector3(38, 6, 48)
	add_child(flies)

# =========================================================================
#  LAWN — grass plains with molehill craters and a winding stone path.
# =========================================================================
func _build_lawn() -> void:
	var grass := ToyMaterials.carpet(Color(0.22, 0.34, 0.2))
	_static_box(Vector3(0, -0.5, 0), Vector3(ROOM_W, 1.0, ROOM_D), grass)

	# Molehills: shell-crater mounds, walkable cover.
	var dirt := ToyMaterials.soft(Color(0.34, 0.26, 0.18))
	for spec in [[Vector3(-20, 0, -24), 9.0], [Vector3(8, 0, 24), 7.0], [Vector3(44, 0, -30), 8.0], [Vector3(-46, 0, -6), 6.5]]:
		var mound := _static_box(spec[0] + Vector3(0, 1.6, 0), Vector3(spec[1] * 2.0, 3.2, spec[1] * 2.0), dirt, true)
		mound.name = "Molehill"

	# Stepping-stone path from the porch to the sandbox.
	var stone := ToyMaterials.plastic(Color(0.55, 0.56, 0.58), 0.8)
	for i in 7:
		var step := _static_box(Vector3(-56 + i * 12.0, 0.4, 38 - i * 7.0), Vector3(9, 0.8, 7), stone)
		step.rotation_degrees.y = randf_range(-15, 15)

	# Tufts of tall grass: visual only, scattered across the lawn.
	var rng := RandomNumberGenerator.new()
	rng.seed = 24601
	var tuft_mat := ToyMaterials.soft(Color(0.28, 0.42, 0.24))
	for i in 40:
		var tuft := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(rng.randf_range(1.0, 2.2), rng.randf_range(2.0, 4.0), 0.4)
		tuft.mesh = tm
		tuft.material_override = tuft_mat
		tuft.position = Vector3(rng.randf_range(-80, 80), tm.size.y * 0.5, rng.randf_range(-60, 60))
		tuft.rotation_degrees.y = rng.randf_range(0, 180)
		add_child(tuft)

# =========================================================================
#  FENCE PERIMETER — the world's edge, moonlight streaming between slats.
# =========================================================================
func _build_fence_perimeter() -> void:
	var plank := ToyMaterials.wood(Color(0.42, 0.34, 0.26))
	# North and south fence lines from slats with glowing gaps.
	for side: float in [-1.0, 1.0]:
		var z: float = side * (ROOM_D / 2 - 2.0)
		var x := -ROOM_W / 2 + 4.0
		while x < ROOM_W / 2 - 4.0:
			_static_box(Vector3(x, 14, z), Vector3(7.5, 28, 2), plank)
			x += 9.0
	for side: float in [-1.0, 1.0]:
		var x2: float = side * (ROOM_W / 2 - 2.0)
		var z2 := -ROOM_D / 2 + 4.0
		while z2 < ROOM_D / 2 - 4.0:
			_static_box(Vector3(x2, 14, z2), Vector3(2, 28, 7.5), plank)
			z2 += 9.0
	# Invisible boundary walls seal the slat gaps so nobody slips off the map.
	for spec in [[Vector3(0, 15, -ROOM_D / 2), Vector3(ROOM_W, 30, 2)], [Vector3(0, 15, ROOM_D / 2), Vector3(ROOM_W, 30, 2)], [Vector3(-ROOM_W / 2, 15, 0), Vector3(2, 30, ROOM_D)], [Vector3(ROOM_W / 2, 15, 0), Vector3(2, 30, ROOM_D)]]:
		var wall := StaticBody3D.new()
		wall.collision_layer = 0b0001
		wall.collision_mask = 0
		wall.add_to_group("nav_geometry")
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[1]
		cs.shape = bs
		wall.add_child(cs)
		wall.position = spec[0]
		add_child(wall)
	# One broken slat in the east fence: the glowing hole the Legion came from.
	var hole := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.5, 16, 7)
	hole.mesh = hm
	hole.material_override = ToyMaterials.glow(Color(0.4, 0.85, 1.0), 0.9)
	hole.position = Vector3(ROOM_W / 2 - 2.0, 8, -22)
	add_child(hole)

# =========================================================================
#  THE OAK TREE — northwest. A tower of bark with a rope-swing tire.
# =========================================================================
func _build_oak_tree() -> void:
	var bark := ToyMaterials.wood(Color(0.36, 0.27, 0.2))
	var trunk := Vector3(-52, 0, -40)
	_static_cylinder(trunk + Vector3(0, 20, 0), 8.0, 40.0, bark)
	# Root buttresses: natural ramps and cover.
	for spec in [[Vector3(12, 0, 4), 25.0], [Vector3(-10, 0, 8), -40.0], [Vector3(2, 0, -12), 160.0]]:
		var root := _static_box(trunk + spec[0] + Vector3(0, 1.8, 0), Vector3(14, 3.6, 6), bark, true)
		root.rotation_degrees.y = spec[1]
	# Canopy: a huge dark dome far overhead (visual only).
	var canopy := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 34.0
	cm.height = 40.0
	canopy.mesh = cm
	canopy.material_override = ToyMaterials.soft(Color(0.14, 0.22, 0.14))
	canopy.position = trunk + Vector3(0, 48, 0)
	add_child(canopy)
	# Asset-pack trees fill out the fence line like a hedge row.
	add_prop("tree_1", Vector3(-76, 0, -20), 20, 14.0)
	add_prop("tree_2", Vector3(70, 0, 52), -35, 12.0)
	add_prop("tree_3", Vector3(76, 0, -48), 60, 13.0)
	add_prop("tree_4", Vector3(-30, 0, -62), 10, 11.0)
	# The tire swing, fallen at the tree's foot: round bunker.
	add_prop("tires", Vector3(-38, 0, -28), 30, 4.4)

# =========================================================================
#  SANDBOX THEATER — southeast. A desert war within the lawn war.
# =========================================================================
func _build_sandbox_theater() -> void:
	var frame := ToyMaterials.wood(Color(0.5, 0.4, 0.28))
	var sand := ToyMaterials.soft(Color(0.78, 0.68, 0.45))
	var box := Vector3(46, 0, 34)
	# Wooden frame walls (climbable rim).
	_static_box(box + Vector3(0, 2, -16), Vector3(40, 4, 3), frame)
	_static_box(box + Vector3(0, 2, 16), Vector3(40, 4, 3), frame)
	_static_box(box + Vector3(-20, 2, 0), Vector3(3, 4, 34), frame)
	_static_box(box + Vector3(20, 2, 0), Vector3(3, 4, 34), frame)
	# Sand floor, slightly raised, with dunes.
	_static_box(box + Vector3(0, 0.6, 0), Vector3(38, 1.2, 30), sand)
	for spec in [[Vector3(-8, 0, -4), 6.0], [Vector3(10, 0, 6), 5.0]]:
		_static_box(box + spec[0] + Vector3(0, 1.9, 0), Vector3(spec[1] * 2.0, 2.6, spec[1] * 1.6), sand, true)
	# The abandoned toy bulldozer: a yellow steel landmark.
	_static_box(box + Vector3(2, 4, -8), Vector3(10, 5, 6), ToyMaterials.plastic(Color(0.9, 0.7, 0.1), 0.4))
	var blade := _static_box(box + Vector3(-5, 2.6, -8), Vector3(2.5, 4, 9), ToyMaterials.metal(Color(0.6, 0.62, 0.66), 0.5))
	blade.rotation_degrees.y = 8.0
	# A forgotten bucket tower.
	_static_cylinder(box + Vector3(12, 4.4, -10), 3.5, 8.8, ToyMaterials.plastic(Color(0.85, 0.3, 0.25), 0.35))

# =========================================================================
#  FLOWERBED JUNGLE — east edge. Stem forests and leaf canopies.
# =========================================================================
func _build_flowerbed_jungle() -> void:
	var soil := ToyMaterials.soft(Color(0.3, 0.22, 0.16))
	var bed := Vector3(38, 0, 52)
	_static_box(bed + Vector3(0, 0.8, 0), Vector3(64, 1.6, 22), soil)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var petal_colors := [Color(0.85, 0.3, 0.4), Color(0.9, 0.7, 0.2), Color(0.6, 0.4, 0.85), Color(0.9, 0.5, 0.6)]
	for i in 9:
		var x := rng.randf_range(-28.0, 28.0)
		var z := rng.randf_range(-7.0, 7.0)
		var h := rng.randf_range(12.0, 22.0)
		_static_box(bed + Vector3(x, h * 0.5 + 1.6, z), Vector3(1.8, h, 1.8), ToyMaterials.plastic(Color(0.3, 0.5, 0.25), 0.7))
		var bloom := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = rng.randf_range(3.0, 5.0)
		bm.height = bm.radius * 1.4
		bloom.mesh = bm
		bloom.material_override = ToyMaterials.plastic(petal_colors[i % petal_colors.size()], 0.4)
		bloom.position = bed + Vector3(x, h + 3.2, z)
		add_child(bloom)

# =========================================================================
#  TRENCH NETWORK — the Chrome line cutting the lawn in half.
# =========================================================================
func _build_trench_network() -> void:
	# Sandbag walls zigzagging across mid-field, with the HQ pods behind.
	add_prop("sacktrench", Vector3(2, 0, -8), 10, 8.0)
	add_prop("sacktrench", Vector3(20, 0, -16), -30, 8.0)
	add_prop("sacktrench", Vector3(38, 0, -6), 20, 8.0)
	add_prop("sacktrench_small", Vector3(12, 0, 2), 65, 4.5)
	add_prop("sacktrench_small", Vector3(30, 0, -26), -15, 4.5)
	add_prop("metalfence", Vector3(10, 0, -22), 5, 5.5)
	add_prop("metalfence", Vector3(28, 0, 4), -40, 5.5)
	add_prop("brickwall", Vector3(46, 0, -18), 15, 5.0)
	# The Chrome field HQ: five pods dug in behind the trench line.
	for offset in [Vector3(56, 0, -38), Vector3(66, 0, -30), Vector3(60, 0, -22), Vector3(70, 0, -42), Vector3(52, 0, -28)]:
		var pod := DropPod.new()
		add_child(pod)
		pod.position = offset

# =========================================================================
#  SCATTERED PROPS — a lawn's worth of battle litter.
# =========================================================================
func _build_scattered_props() -> void:
	add_prop("structure_1", Vector3(-24, 0, 40), 25, 9.0)     # toy watchtower
	add_prop("structure_2", Vector3(58, 0, 10), -50, 8.0)
	add_prop("crate", Vector3(-40, 0, 22), 30, 3.2)
	add_prop("crate", Vector3(-36.8, 0, 25), -20, 2.6)
	add_barrel(Vector3(-10, 0, 52), 0, 1.8)
	add_barrel(Vector3(-6.6, 0, 54), 60, 2.2, true)
	add_barrel(Vector3(-4, 0, 48), -25, 1.8)
	add_prop("debris_pile", Vector3(-58, 0, 12), 45, 5.0)
	add_prop("pallet", Vector3(14, 0, 34), 70, 3.4)
	add_prop("pallet_broken", Vector3(-14, 0, -44), 115, 3.2)
	add_prop("watertank", Vector3(-72, 0, -52), 20, 6.5)      # rain barrel
	add_prop("streetlight", Vector3(-64, 0, 40), 160, 9.0)    # solar path light
	add_prop("sign", Vector3(-48, 0, 44), -25, 2.8)
	add_prop("gascan", Vector3(24, 0, 24), 35, 1.6)
	add_prop("woodplanks", Vector3(4, 0, 44), 95, 4.4)
	add_prop("cardboard_2", Vector3(64, 0, 28), -70, 4.6)
	Landmine.spawn(self, Vector3(18, 0, -34))
	Landmine.spawn(self, Vector3(34, 0, -38))
	Landmine.spawn(self, Vector3(44, 0, -46))
	Landmine.spawn(self, Vector3(8, 0, -42))

	# Ground mist over the whole lawn; pollen motes near the flowerbed.
	add_dust_motes(Vector3(0, 4, 0), Vector3(70, 3, 50), 50, Color(0.75, 0.82, 0.95))
	add_dust_motes(Vector3(38, 8, 48), Vector3(28, 6, 12), 30, Color(0.9, 0.88, 0.6))

# =========================================================================
#  UNITS — the largest battle in the game so far.
# =========================================================================
func _spawn_units() -> void:
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var green: FactionData = load("res://data/factions/green_army.tres")

	# Player deploys from the porch steps, southwest.
	var player := Player.new()
	player.faction = green
	add_child(player)
	player.position = Vector3(-70, 1, 48)
	player.rotation_degrees.y = -50.0

	# Captives: oak tree roots, sandbox, and the flowerbed jungle.
	for pos in [Vector3(-46, 1, -30), Vector3(46, 2, 34), Vector3(30, 2.6, 52)]:
		var mate := SquadMate.new()
		mate.faction = green
		add_child(mate)
		mate.position = pos

	var patrols := [
		{"route": [Vector3(-24, 1, 8), Vector3(-6, 1, 20), Vector3(-30, 1, 26)], "mix": ["trooper", "chrome_ant"]},
		{"route": [Vector3(6, 1, -14), Vector3(24, 1, -4), Vector3(14, 1, -28)], "mix": ["trooper", "heavy"]},   # trench line
		{"route": [Vector3(36, 1, -14), Vector3(48, 1, -28), Vector3(28, 1, -22)], "mix": ["heavy", "chrome_beetle"]},
		{"route": [Vector3(56, 1, -32)], "mix": ["heavy", "sniper"]},                                            # HQ guards
		{"route": [Vector3(-38, 1, -50), Vector3(-14, 1, -56), Vector3(-30, 1, -38)], "mix": ["chrome_ant", "scout"]},
		{"route": [Vector3(50, 2, 30), Vector3(38, 2, 40), Vector3(56, 2, 42)], "mix": ["trooper", "chrome_beetle"]},    # sandbox
		{"route": [Vector3(-20, 4.6, -24)], "mix": ["sniper", "trooper"]},                                       # molehill overwatch
		{"route": [Vector3(64, 1, 6), Vector3(74, 1, -10), Vector3(58, 1, -4)], "mix": ["scout", "trooper"]},    # fence-hole watch
	]
	for patrol in patrols:
		var route: Array = patrol.route
		for i in 2:
			var enemy := EnemySoldier.new()
			enemy.faction = chrome
			enemy.variant = patrol.mix[i]
			var typed: Array[Vector3] = []
			typed.assign(route)
			enemy.patrol_points = typed
			add_child(enemy)
			enemy.position = route[i % route.size()] + Vector3(i * 1.5, 0, 0)

	# The tank waits by the porch; the paper plane is parked on a molehill.
	var tank := ToyTank.new()
	add_child(tank)
	tank.position = Vector3(-58, 1, 36)
	tank.rotation_degrees.y = -45.0
	var plane := PaperPlane.new()
	add_child(plane)
	plane.position = Vector3(-20, 4.4, -24)
	plane.rotation_degrees.y = 120.0

func _spawn_pickups_and_toys() -> void:
	scatter_coins(ROOM_W * 0.4, ROOM_D * 0.4)
	for pos in [Vector3(-36, 0, 8), Vector3(8, 0, 12), Vector3(40, 2, 34), Vector3(-24, 3.4, -24), Vector3(60, 0, -14)]:
		Pickup.spawn_health(self, pos)
	for pos in [Vector3(-16, 0, -12), Vector3(26, 0, 14), Vector3(-52, 0, -18), Vector3(52, 0, 48)]:
		Pickup.spawn_parts(self, pos, 5)
	for pos in [Vector3(-4, 0, 30), Vector3(20, 0, -20), Vector3(-44, 0, 36)]:
		Pickup.spawn_ammo(self, pos)
	spawn_weapon_drop(Vector3(34, 0, 6), "marble")
	spawn_weapon_drop(Vector3(-30, 0, -20), "sniper")
	var toy_spots := [
		["Acorn Annie", Vector3(-52, 0.5, -28)],   # oak tree roots
		["Dune Dougie", Vector3(46, 2.2, 26)],     # sandbox dune
		["Petals", Vector3(38, 2.6, 56)],          # flowerbed jungle
		["Mister Mole", Vector3(-20, 3.6, -24)],   # on a molehill
		["Fence-Post Fred", Vector3(78, 0.5, -22)],# by the fence hole
	]
	for spot in toy_spots:
		var toy := LostToy.new()
		toy.toy_name = spot[0]
		add_child(toy)
		toy.position = spot[1]

# =========================================================================
#  MISSION — "NO MAN'S LAWN"
# =========================================================================
func _start_mission() -> void:
	Missions.start_mission("ACT 2 — NO MAN'S LAWN")
	Missions.add_objective("rescue", "Rescue the lawn expedition  [E]", 3)
	Missions.add_objective("barrels", "Torch the trench fuel dumps", 3)
	Missions.add_objective("pods", "Destroy the Chrome field HQ", 5)
	Missions.marker_provider = func(id: String) -> Vector3:
		match id:
			"rescue":
				return nearest_in_group("green_allies", func(n): return n is SquadMate and n.captive)
			"barrels":
				return nearest_in_group("explosive_barrels")
			"pods":
				return nearest_in_group("chrome_pods")
		return Vector3.INF
	Events.notify.emit("Open sky. Full moon. The Legion dug in across the lawn. End this, soldier.")

func _on_unit_died(_unit: Node) -> void:
	if not _counterattack_sent and Missions.objectives.size() > 2 and Missions.objectives[2].count_done >= 2:
		_send_counterattack()
	if not _final_wave_sent and Missions.objectives.size() > 2 and Missions.objectives[2].count_done >= 4:
		_send_final_wave()

func _send_counterattack() -> void:
	_counterattack_sent = true
	Events.notify.emit("WARNING: Chrome reinforcements pouring through the fence hole!")
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var mix := ["trooper", "scout", "heavy", "scout", "trooper"]
	for i in 5:
		var enemy := EnemySoldier.new()
		enemy.faction = chrome
		enemy.variant = mix[i]
		var route: Array[Vector3] = [Vector3(56, 1, -32)]
		enemy.patrol_points = route
		add_child(enemy)
		enemy.position = Vector3(82, 1, -26 + i * 3.0)
		enemy.state = EnemySoldier.AiState.ALERT
		if Game.player != null:
			enemy.target = Game.player

func _send_final_wave() -> void:
	_final_wave_sent = true
	Events.notify.emit("FINAL PUSH: the Legion is throwing everything at the lawn!")
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var mix := ["juggernaut", "sniper", "commando", "scout", "grenadier", "scout"]
	for i in 6:
		var enemy := EnemySoldier.new()
		enemy.faction = chrome
		enemy.variant = mix[i]
		var route: Array[Vector3] = [Vector3(20, 1, -16)]
		enemy.patrol_points = route
		add_child(enemy)
		enemy.position = Vector3(82, 1, -40 + i * 4.0)
		enemy.state = EnemySoldier.AiState.ALERT
		if Game.player != null:
			enemy.target = Game.player

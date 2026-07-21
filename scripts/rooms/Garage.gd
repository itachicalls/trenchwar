class_name Garage
extends RoomBase
## THE GARAGE — Act 2, Mission 2: "MOTOR POOL".
##
## The most industrial battlefield: an oil-stained concrete plain under THE
## CAR — a steel sky you fight beneath — with a workbench mesa, tool-shelf
## cliffs, and a Chrome armor depot in the far corner. Two tanks spawn here:
## this is the mission where the Green Army fields real armor.

const ROOM_W := 160.0
const ROOM_D := 120.0
const WALL_H := 90.0

var _counterattack_sent := false

func _ready() -> void:
	LostToy.reset_level_counters()
	_setup_nav()
	_build_lighting()
	_build_room_shell()
	_build_the_car()
	_build_workbench_mesa()
	_build_shelf_cliffs()
	_build_armor_depot()
	_build_scattered_props()
	_spawn_units()
	_spawn_pickups_and_toys()
	_bake_navmesh()
	_start_mission()
	Events.unit_died.connect(_on_unit_died)

# =========================================================================
#  LIGHTING — one bare hanging bulb, moonlit door crack, cold depot glow.
# =========================================================================
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	we.environment = RoomBase.make_night_environment(Color(0.09, 0.11, 0.16), Color(0.4, 0.44, 0.54), 1.15)
	add_child(we)
	add_light_rig(self, Vector3(-46, 60, 0), Color(0.6, 0.7, 0.95), 1.45)

	# The bare bulb over the workbench: warm cone, gently swinging flicker.
	var bulb := SpotLight3D.new()
	bulb.light_color = Color(1.0, 0.85, 0.6)
	bulb.light_energy = 3.4
	bulb.spot_range = 70.0
	bulb.spot_angle = 35.0
	bulb.position = Vector3(-40, 60, -30)
	bulb.rotation_degrees = Vector3(-88, 0, 0)
	add_child(bulb)
	register_flicker(bulb, 3.4, 1.6, 0.1)

	# Moonlight knifing under the garage door, south wall.
	var crack := SpotLight3D.new()
	crack.light_color = Color(0.6, 0.72, 1.0)
	crack.light_energy = 2.6
	crack.spot_range = 60.0
	crack.spot_angle = 18.0
	crack.position = Vector3(0, 3, ROOM_D / 2 - 4)
	crack.rotation_degrees = Vector3(6, 180, 0)
	add_child(crack)

	# Chrome armor depot glow, northeast corner.
	var depot := OmniLight3D.new()
	depot.light_color = Color(0.4, 0.9, 1.0)
	depot.light_energy = 2.0
	depot.omni_range = 40.0
	depot.position = Vector3(56, 10, -38)
	add_child(depot)
	register_flicker(depot, 2.0, 2.5, 0.15)

# =========================================================================
#  ROOM SHELL — stained concrete, oil slicks, the half-open garage door.
# =========================================================================
func _build_room_shell() -> void:
	var concrete := ToyMaterials.concrete(Color(0.5, 0.5, 0.52))
	var wall_mat := ToyMaterials.concrete(Color(0.44, 0.46, 0.5))
	_build_shell(ROOM_W, ROOM_D, WALL_H, concrete, wall_mat)

	# Oil stains: dark glossy patches, pure floor character.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for i in 7:
		var stain := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = rng.randf_range(3.0, 8.0)
		sm.bottom_radius = sm.top_radius
		sm.height = 0.06
		stain.mesh = sm
		stain.material_override = ToyMaterials.plastic(Color(0.12, 0.12, 0.14), 0.05)
		stain.position = Vector3(rng.randf_range(-55, 55), 0.04, rng.randf_range(-40, 45))
		add_child(stain)

	# The garage door: a vast ribbed wall with a moonlit crack at the bottom.
	var door_mat := ToyMaterials.plastic(Color(0.55, 0.58, 0.62), 0.5)
	for i in 6:
		_static_box(Vector3(0, 12 + i * 12.0, ROOM_D / 2 - 2.5), Vector3(100, 11, 3), door_mat)
	var crack_glow := MeshInstance3D.new()
	var cg := BoxMesh.new()
	cg.size = Vector3(100, 2.4, 0.5)
	crack_glow.mesh = cg
	crack_glow.material_override = ToyMaterials.glow(Color(0.55, 0.68, 1.0), 1.0)
	crack_glow.position = Vector3(0, 1.4, ROOM_D / 2 - 4.2)
	add_child(crack_glow)

	# Side door back into the house, west wall.
	var door := MeshInstance3D.new()
	var dmesh := BoxMesh.new()
	dmesh.size = Vector3(16, 34, 0.5)
	door.mesh = dmesh
	door.material_override = ToyMaterials.glow(Color(1.0, 0.75, 0.4), 0.55)
	door.position = Vector3(-ROOM_W / 2 + 1.3, 17, 30)
	door.rotation_degrees.y = 90.0
	add_child(door)

# =========================================================================
#  THE CAR — center-north. A steel sky held up by four tire towers.
# =========================================================================
func _build_the_car() -> void:
	var rubber := ToyMaterials.plastic(Color(0.14, 0.14, 0.16), 0.75)
	var car := Vector3(6, 0, -18)
	# Real vehicle asset (Quaternius sports car, ~76 x 23 x 36 at this scale,
	# rotated so its length runs east-west). The gap under the body is a
	# genuine crawl arena; wheels are solid pillars.
	# Up on cinder blocks (mid-repair), so the crawl space is soldier-height.
	var car_rig := add_landmark("car", car + Vector3(0, 4, 0), 90, 76.0)
	if car_rig != null:
		# Local space: model length along +z before the 90° yaw.
		_landmark_box(car_rig, Vector3(0, 13.5, 0), Vector3(31, 17, 70))    # body slab, clearance ~6
		_landmark_box(car_rig, Vector3(0, 17, 2), Vector3(29, 12, 40))      # cabin
		var block_mat := ToyMaterials.plastic(Color(0.6, 0.6, 0.58), 0.8)
		for wheel in [Vector3(-15, 0, -24), Vector3(15, 0, -24), Vector3(-15, 0, 24), Vector3(15, 0, 24)]:
			_landmark_box(car_rig, wheel + Vector3(0, 1.5, 0), Vector3(7, 11, 12))   # wheel + block
			var block := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(8, 4, 13)
			block.mesh = bm
			block.material_override = block_mat
			block.position = wheel + Vector3(0, -2, 0)
			car_rig.add_child(block)
	else:
		_static_box(car + Vector3(0, 21, 0), Vector3(76, 6, 42), ToyMaterials.metal(Color(0.5, 0.12, 0.14), 0.35))
	# Spare tire stack beside the car (real prop, still a bunker).
	var spare := _static_cylinder(car + Vector3(-30, 4, 26), 5.5, 8.0, rubber)
	spare.name = "SpareTires"
	# Dangling exhaust pipe = ramp toward the rear bumper.
	var pipe := _static_box(car + Vector3(34, 8, 18), Vector3(3, 1.8, 24), ToyMaterials.metal(Color(0.6, 0.62, 0.66), 0.5))
	pipe.rotation_degrees.x = -32.0

# =========================================================================
#  WORKBENCH MESA — west wall. The Green staging ground, bulb-lit.
# =========================================================================
func _build_workbench_mesa() -> void:
	var bench := Vector3(-52, 0, -30)
	# Real furniture asset (Quaternius desk as the workbench, ~42 x 21 x 19.5).
	var bench_rig := add_landmark("desk", bench, 0, 42.0)
	if bench_rig != null:
		_landmark_box(bench_rig, Vector3(0, 20, 0), Vector3(42, 2.4, 19.5))   # benchtop
		_landmark_box(bench_rig, Vector3(-19.5, 9.4, 0), Vector3(2.5, 18.8, 18))
		_landmark_box(bench_rig, Vector3(19.5, 9.4, 0), Vector3(2.5, 18.8, 18))
	else:
		_static_box(bench + Vector3(0, 20, 0), Vector3(42, 2, 20), ToyMaterials.wood(Color(0.44, 0.34, 0.24)))
	# Vise + toolbox on top: cover for the plateau fight.
	_static_box(bench + Vector3(-12, 23.6, -4), Vector3(8, 5, 6), ToyMaterials.metal(Color(0.45, 0.5, 0.55), 0.4))
	_static_box(bench + Vector3(10, 23.4, 2), Vector3(12, 4.5, 7), ToyMaterials.plastic(Color(0.75, 0.2, 0.15), 0.4))
	# Hanging extension cord = the climb (draped from bench to floor).
	var cord := _static_box(bench + Vector3(24, 10, 12), Vector3(2.2, 1.6, 26), ToyMaterials.plastic(Color(0.9, 0.55, 0.1), 0.5))
	cord.rotation_degrees.x = -42.0

	# Washer in the far northwest corner, dryer against the east wall.
	var washer := add_landmark("washing_machine", Vector3(-70, 0, -52), 90, 16.0)
	if washer != null:
		_landmark_box(washer, Vector3(0, 9.1, 0), Vector3(16, 18.2, 16.4))
	var dryer := add_landmark("washing_machine", Vector3(70, 0, 2), -90, 16.0)
	if dryer != null:
		_landmark_box(dryer, Vector3(0, 9.1, 0), Vector3(16, 18.2, 16.4))

# =========================================================================
#  SHELF CLIFFS — north wall. Paint-can towers on steel shelving.
# =========================================================================
func _build_shelf_cliffs() -> void:
	var steel := ToyMaterials.metal(Color(0.5, 0.54, 0.6), 0.4)
	var shelf := Vector3(-4, 0, -ROOM_D / 2 + 10)
	_static_box(shelf + Vector3(-20, 22, 0), Vector3(2.5, 44, 8), steel)
	_static_box(shelf + Vector3(20, 22, 0), Vector3(2.5, 44, 8), steel)
	var paint_colors := [Color(0.8, 0.3, 0.2), Color(0.25, 0.5, 0.75), Color(0.85, 0.75, 0.2), Color(0.35, 0.6, 0.35)]
	for level in 3:
		var y := 12.0 + level * 13.0
		_static_box(shelf + Vector3(0, y, 0), Vector3(42, 1.8, 8), steel)
		for i in 4:
			_static_cylinder(shelf + Vector3(-15 + i * 10.0, y + 4.4, 0), 3.0, 7.0, ToyMaterials.metal(paint_colors[(level + i) % paint_colors.size()], 0.3))
	# A fallen broom leaning on the first shelf = the climb route.
	var broom := _static_box(shelf + Vector3(-30, 6.5, 10), Vector3(2, 1.6, 26), ToyMaterials.wood(Color(0.62, 0.45, 0.28)))
	broom.rotation_degrees.x = -30.0

# =========================================================================
#  ARMOR DEPOT — northeast corner. Chrome's vehicle yard: the objective.
# =========================================================================
func _build_armor_depot() -> void:
	var depot := Vector3(54, 0, -36)
	# Depot walls from stacked storage bins.
	var bin := ToyMaterials.plastic(Color(0.35, 0.42, 0.55), 0.5)
	_static_box(depot + Vector3(-14, 6, -4), Vector3(4, 12, 26), bin)
	_static_box(depot + Vector3(0, 6, -16), Vector3(24, 12, 4), bin)
	# Supply pods inside.
	for offset in [Vector3(-6, 0, -6), Vector3(6, 0, 0), Vector3(-2, 0, 8), Vector3(8, 0, -8)]:
		var pod := DropPod.new()
		add_child(pod)
		pod.position = depot + offset
	# Warning ring.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 16.0
	torus.outer_radius = 17.5
	ring.mesh = torus
	ring.material_override = ToyMaterials.glow(Color(0.3, 0.8, 1.0), 0.8)
	ring.position = depot + Vector3(0, 0.1, 0)
	add_child(ring)

# =========================================================================
#  SCATTERED PROPS — this room was MADE for the industrial prop set.
# =========================================================================
func _build_scattered_props() -> void:
	add_prop("tires", Vector3(-24, 0, 24), 20, 4.2)
	add_prop("tires", Vector3(-18, 0, 28), -50, 3.6)
	add_prop("container_long", Vector3(48, 0, 28), 10, 8.0)
	add_prop("container_small", Vector3(60, 0, 12), -20, 4.6)
	add_prop("trashcontainer", Vector3(-64, 0, 8), 90, 6.4)
	add_prop("pipes", Vector3(24, 0, 36), 45, 5.0)
	add_prop("pipes", Vector3(-40, 0, 42), -15, 4.4)
	add_prop("debris_pile", Vector3(12, 0, 12), 70, 5.0)
	add_prop("pallet", Vector3(-8, 0, 38), 25, 3.4)
	add_prop("pallet_broken", Vector3(30, 0, -44), 100, 3.2)
	add_prop("barrel", Vector3(-32, 0, -6), 0, 1.8)
	add_prop("barrel", Vector3(-29.6, 0, -3.8), 45, 1.8)
	add_prop("barrel_spilled", Vector3(-27, 0, -8.4), -70, 2.2)
	add_prop("gastank", Vector3(-58, 0, -48), 30, 3.0)
	add_prop("gascan", Vector3(-36, 0, -26), -15, 1.6)
	add_prop("watertank", Vector3(68, 0, -14), -40, 6.0)
	add_prop("crate", Vector3(38, 0, 8), 15, 3.2)
	add_prop("crate", Vector3(41.4, 0, 11), -25, 2.6)
	add_prop("cardboard_1", Vector3(-52, 0, 34), 60, 5.2)
	add_prop("cardboard_2", Vector3(20, 0, 46), -30, 4.4)
	add_prop("sacktrench", Vector3(-30, 0, 10), -70, 7.5)
	add_prop("sacktrench_small", Vector3(6, 0, 28), 15, 4.5)
	add_prop("barrier_large", Vector3(34, 0, -8), -55, 5.5)
	add_prop("barrier_single", Vector3(-12, 0, -38), 25, 3.6)
	add_prop("sign", Vector3(46, 0, -22), -10, 2.8)
	add_prop("cone", Vector3(-2, 0, 20), 0, 1.6)
	add_prop("cone", Vector3(2, 0, 22), 0, 1.6)
	Landmine.spawn(self, Vector3(44, 0, -30))
	Landmine.spawn(self, Vector3(58, 0, -24))
	Landmine.spawn(self, Vector3(50, 0, -48))

	# Sawdust motes in the bulb cone; exhaust haze under the car.
	add_dust_motes(Vector3(-40, 20, -30), Vector3(16, 16, 14), 50, Color(1.0, 0.9, 0.7))
	add_dust_motes(Vector3(6, 8, -18), Vector3(30, 7, 18), 30, Color(0.7, 0.72, 0.78))

# =========================================================================
#  UNITS — heaviest garrison of Act 2; the Green Army fields TWO tanks.
# =========================================================================
func _spawn_units() -> void:
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var green: FactionData = load("res://data/factions/green_army.tres")

	# Player spawns at the side door, southwest.
	var player := Player.new()
	player.faction = green
	add_child(player)
	player.position = Vector3(-66, 1, 28)
	player.rotation_degrees.y = -70.0

	# Captives: workbench top, under the car, by the garage door.
	for pos in [Vector3(-52, 21.5, -30), Vector3(6, 1, -18), Vector3(30, 1, 44)]:
		var mate := SquadMate.new()
		mate.faction = green
		add_child(mate)
		mate.position = pos

	var patrols := [
		{"route": [Vector3(-20, 1, 0), Vector3(0, 1, -8), Vector3(-12, 1, 16)], "mix": ["trooper", "scout"]},
		{"route": [Vector3(20, 1, -30), Vector3(36, 1, -18), Vector3(14, 1, -40)], "mix": ["heavy", "trooper"]},
		{"route": [Vector3(40, 1, 20), Vector3(56, 1, 34), Vector3(30, 1, 34)], "mix": ["trooper", "scout"]},
		{"route": [Vector3(-40, 1, -44), Vector3(-16, 1, -50), Vector3(-30, 1, -34)], "mix": ["scout", "sniper"]},
		{"route": [Vector3(-4, 40.2, -ROOM_D / 2 + 10), Vector3(12, 40.2, -ROOM_D / 2 + 10)], "mix": ["sniper", "trooper"]},   # shelf top
		{"route": [Vector3(48, 1, -36)], "mix": ["heavy", "heavy"]},   # depot guards
		{"route": [Vector3(-52, 1, 44), Vector3(-30, 1, 50), Vector3(-44, 1, 34)], "mix": ["trooper", "trooper"]},
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

	# TWO tanks: one at spawn, one hidden under the car.
	var tank := ToyTank.new()
	add_child(tank)
	tank.position = Vector3(-56, 1, 38)
	tank.rotation_degrees.y = -55.0
	var tank2 := ToyTank.new()
	add_child(tank2)
	tank2.position = Vector3(-8, 1, -22)
	tank2.rotation_degrees.y = 100.0

func _spawn_pickups_and_toys() -> void:
	for pos in [Vector3(-30, 0, 16), Vector3(18, 0, -10), Vector3(-52, 21.6, -26), Vector3(48, 0, 2), Vector3(6, 0, 40)]:
		Pickup.spawn_health(self, pos)
	for pos in [Vector3(-14, 0, -26), Vector3(34, 0, 26), Vector3(-44, 0, -12), Vector3(58, 0, 42)]:
		Pickup.spawn_parts(self, pos, 5)
	for pos in [Vector3(2, 0, 6), Vector3(-38, 0, 30), Vector3(28, 0, -24)]:
		Pickup.spawn_ammo(self, pos)
	var toy_spots := [
		["Wrench Wendy", Vector3(-52, 21.6, -34)],        # workbench top
		["Lugnut", Vector3(6, 0.5, -26)],                  # under the car
		["Turpentine Tim", Vector3(-4, 38.5, -ROOM_D / 2 + 10)],  # shelf cliff
		["Treads", Vector3(-21, 0.5, 26)],                 # in the tire pile
		["Oily", Vector3(66, 0.5, 46)],                    # dark corner
	]
	for spot in toy_spots:
		var toy := LostToy.new()
		toy.toy_name = spot[0]
		add_child(toy)
		toy.position = spot[1]

# =========================================================================
#  MISSION — "MOTOR POOL"
# =========================================================================
func _start_mission() -> void:
	Missions.start_mission("ACT 2 — MOTOR POOL")
	Missions.add_objective("rescue", "Rescue the motor-pool crew  [E]", 3)
	Missions.add_objective("patrols", "Break the Chrome garage garrison", 11)
	Missions.add_objective("pods", "Destroy the Chrome armor depot", 4)
	Missions.marker_provider = func(id: String) -> Vector3:
		match id:
			"rescue":
				return nearest_in_group("green_allies", func(n): return n is SquadMate and n.captive)
			"patrols":
				return nearest_in_group("enemies")
			"pods":
				return nearest_in_group("chrome_pods")
		return Vector3.INF
	Events.notify.emit("Chrome armor is massing in the garage. Roll out, soldier — take a tank.")

func _on_unit_died(unit: Node) -> void:
	if unit is EnemySoldier:
		Missions.progress("patrols")
	if not _counterattack_sent and Missions.objectives.size() > 2 and Missions.objectives[2].count_done >= 2:
		_send_counterattack()

func _send_counterattack() -> void:
	_counterattack_sent = true
	Events.notify.emit("WARNING: Chrome armor column rolling in under the garage door!")
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var mix := ["heavy", "heavy", "trooper", "scout", "sniper", "trooper"]
	for i in 6:
		var enemy := EnemySoldier.new()
		enemy.faction = chrome
		enemy.variant = mix[i]
		var route: Array[Vector3] = [Vector3(54, 1, -36)]
		enemy.patrol_points = route
		add_child(enemy)
		enemy.position = Vector3(-20 + i * 8.0, 1, 52)
		enemy.state = EnemySoldier.AiState.ALERT
		if Game.player != null:
			enemy.target = Game.player

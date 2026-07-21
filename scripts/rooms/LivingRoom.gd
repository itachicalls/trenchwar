class_name LivingRoom
extends RoomBase
## THE LIVING ROOM — Act 1, Mission 2: "RUG BURN".
##
## The largest open combat zone so far: couch mountain range along the north
## wall, the coffee table plateau at center (paper plane airstrip on top),
## the TV command center held by the Chrome Legion, and the rug battlefield
## between them. Clearing the Chrome outposts wakes THE VACUUM.

const ROOM_W := 150.0
const ROOM_D := 120.0
const WALL_H := 70.0

var _vacuum: VacuumBoss = null
var _vacuum_spawned := false

func _ready() -> void:
	LostToy.reset_level_counters()
	_setup_nav()
	_build_lighting()
	_build_room_shell()
	_build_couch_mountains()
	_build_coffee_table_plateau()
	_build_tv_command_center()
	_build_rug_and_props()
	_build_chrome_outposts()
	_spawn_units()
	_spawn_pickups_and_toys()
	_bake_navmesh()
	_start_mission()
	Events.objectives_changed.connect(_check_vacuum_trigger)

# =========================================================================
#  LIGHTING — deeper night than the bedroom; TV glow is the main landmark.
# =========================================================================
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	we.environment = RoomBase.make_night_environment(Color(0.1, 0.12, 0.22), Color(0.42, 0.46, 0.64), 1.25)
	add_child(we)

	# Cinematic three-point rig keyed by window moonlight from the west.
	add_light_rig(self, Vector3(-42, -120, 0), Color(0.62, 0.72, 1.0), 1.6)

	# The TV was left on: a genuinely flickering blue wash over the battlefield.
	var tv_light := OmniLight3D.new()
	tv_light.light_color = Color(0.5, 0.7, 1.0)
	tv_light.light_energy = 2.4
	tv_light.omni_range = 45.0
	tv_light.position = Vector3(0, 20, 52)
	add_child(tv_light)
	register_flicker(tv_light, 2.4, 9.0, 0.22)

	# Warm hallway spill from the bedroom door (where you came from).
	var hall := OmniLight3D.new()
	hall.light_color = Color(1.0, 0.8, 0.5)
	hall.light_energy = 1.6
	hall.omni_range = 25.0
	hall.position = Vector3(-68, 6, -20)
	add_child(hall)
	register_flicker(hall, 1.6, 0.9, 0.06)

func _build_room_shell() -> void:
	var rug_base := ToyMaterials.carpet(Color(0.42, 0.44, 0.4))
	var wall_mat := ToyMaterials.wallpaper(Color(0.5, 0.52, 0.58), Color(0.44, 0.46, 0.53))
	_build_shell(ROOM_W, ROOM_D, WALL_H, rug_base, wall_mat)
	# Doorway back toward the bedroom.
	var door := MeshInstance3D.new()
	var dmesh := BoxMesh.new()
	dmesh.size = Vector3(16, 34, 0.5)
	door.mesh = dmesh
	door.material_override = ToyMaterials.glow(Color(1.0, 0.75, 0.4), 0.6)
	door.position = Vector3(-ROOM_W / 2 + 1.3, 17, -20)
	door.rotation_degrees.y = 90.0
	add_child(door)

# =========================================================================
#  COUCH MOUNTAINS — north wall. A cushion range with a canyon between seats.
# =========================================================================
func _build_couch_mountains() -> void:
	var couch_z := -41.0
	# Real furniture asset (sofa, ~80 x 31.6 x 35 at this scale).
	# Colliders shape the classic couch terrain: seat deck, backrest cliff,
	# armrest towers — all walkable, reached by the magazine ramp.
	var couch := add_landmark("sofa", Vector3(0, 0, couch_z), 0, 80.0)
	if couch != null:
		_landmark_box(couch, Vector3(0, 7, 3), Vector3(66, 14, 26))       # seat deck, top 14
		_landmark_box(couch, Vector3(0, 16, -12.5), Vector3(80, 32, 10))  # backrest cliff, top 32
		_landmark_box(couch, Vector3(-36.5, 10, 3), Vector3(9, 20, 26))   # armrest towers, top 20
		_landmark_box(couch, Vector3(36.5, 10, 3), Vector3(9, 20, 26))
	else:
		_static_box(Vector3(0, 5, couch_z), Vector3(80, 10, 22), ToyMaterials.soft(Color(0.35, 0.42, 0.55)))
	# Fallen-magazine ramp up the west armrest.
	var ramp := _static_box(Vector3(-50, 6.4, couch_z + 24), Vector3(10, 1.2, 24), ToyMaterials.plastic(Color(0.8, 0.75, 0.65), 0.7))
	ramp.rotation_degrees.x = -27.0
	# A dropped TV remote on the seat deck: future secret interaction.
	_static_box(Vector3(0, 14.8, couch_z + 4), Vector3(3, 1.2, 8), ToyMaterials.plastic(Color(0.12, 0.12, 0.14)))

# =========================================================================
#  COFFEE TABLE PLATEAU — center. The paper plane airstrip is on top.
# =========================================================================
func _build_coffee_table_plateau() -> void:
	var wood := ToyMaterials.wood(Color(0.4, 0.26, 0.16))
	# Real furniture asset (Kenney coffee table, ~46 x 16 x 27.8 at this scale).
	var table := add_landmark("coffee_table", Vector3.ZERO, 0, 46.0)
	if table != null:
		_landmark_box(table, Vector3(0, 15, 0), Vector3(46, 2.2, 27.8))   # tabletop plateau
		for leg in [Vector3(-20.5, 0, -11.5), Vector3(20.5, 0, -11.5), Vector3(-20.5, 0, 11.5), Vector3(20.5, 0, 11.5)]:
			_landmark_box(table, leg + Vector3(0, 7, 0), Vector3(3.5, 14, 3.5))
	else:
		_static_box(Vector3(0, 15, 0), Vector3(46, 2, 22), wood)
	# Coaster helipad marking.
	var coaster := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 5.0
	cyl.bottom_radius = 5.0
	cyl.height = 0.3
	coaster.mesh = cyl
	coaster.material_override = ToyMaterials.plastic(Color(0.75, 0.3, 0.25), 0.6)
	coaster.position = Vector3(-12, 16.2, 0)
	add_child(coaster)
	# Stacked-book staircase up to the plateau.
	var colors := [Color(0.25, 0.45, 0.6), Color(0.7, 0.55, 0.2), Color(0.5, 0.3, 0.5)]
	for i in 4:
		_static_box(Vector3(28 + i * 4.5, 1.9 + i * 3.8, 14 - i * 2.0), Vector3(10, 3.8, 14), ToyMaterials.plastic(colors[i % colors.size()], 0.65))

# =========================================================================
#  TV COMMAND CENTER — south wall. Chrome-occupied high-value ground.
# =========================================================================
func _build_tv_command_center() -> void:
	var dark_wood := ToyMaterials.wood(Color(0.3, 0.22, 0.16))
	var center_z := 50.0
	# Entertainment center: long low cabinet with shelf alcoves.
	_static_box(Vector3(0, 8, center_z), Vector3(70, 16, 12), dark_wood)
	for side in [-1.0, 1.0]:
		_static_box(Vector3(side * 40, 14, center_z), Vector3(10, 28, 12), dark_wood)
	# The TV itself: a real flat-screen model on the cabinet, with a glowing
	# static screen overlaid so it still lights the battlefield.
	var tv := add_landmark("tv", Vector3(0, 16, center_z + 2), 180, 52.0)
	if tv != null:
		_landmark_box(tv, Vector3(0, 17.4, 0), Vector3(52, 34.8, 4.6))
	var glow := MeshInstance3D.new()
	var tv_mesh := BoxMesh.new()
	tv_mesh.size = Vector3(44, 24, 0.6)
	glow.mesh = tv_mesh
	glow.material_override = ToyMaterials.glow(Color(0.55, 0.7, 1.0), 1.1)
	glow.position = Vector3(0, 34, center_z - 0.9)
	add_child(glow)
	# Game console + cables spilling off the cabinet = climbable route.
	_static_box(Vector3(-20, 17.5, center_z - 2), Vector3(10, 3, 8), ToyMaterials.plastic(Color(0.9, 0.9, 0.92), 0.4))
	var cable := _static_box(Vector3(-28, 6.5, center_z - 14), Vector3(2.4, 1.6, 26), ToyMaterials.plastic(Color(0.1, 0.1, 0.12), 0.5))
	cable.rotation_degrees.x = -28.0

# =========================================================================
#  RUG BATTLEFIELD + PROPS — the open middle ground.
# =========================================================================
func _build_rug_and_props() -> void:
	# The great rug: main combat arena with a fringe border.
	var rug := MeshInstance3D.new()
	var rug_mesh := BoxMesh.new()
	rug_mesh.size = Vector3(90, 0.08, 60)
	rug.mesh = rug_mesh
	rug.material_override = ToyMaterials.soft(Color(0.5, 0.28, 0.3))
	rug.position = Vector3(0, 0.05, 0)
	add_child(rug)
	var border := MeshInstance3D.new()
	var border_mesh := BoxMesh.new()
	border_mesh.size = Vector3(94, 0.06, 64)
	border.mesh = border_mesh
	border.material_override = ToyMaterials.soft(Color(0.65, 0.55, 0.35))
	border.position = Vector3(0, 0.03, 0)
	add_child(border)

	var rng := RandomNumberGenerator.new()
	rng.seed = 44100
	# Scattered kid-clutter cover: juice cups, crayons, a slipper.
	for i in 6:
		var cup := StaticBody3D.new()
		cup.collision_layer = 0b0001
		var cshape := CollisionShape3D.new()
		var ccyl := CylinderShape3D.new()
		ccyl.radius = 2.2
		ccyl.height = 6.0
		cshape.shape = ccyl
		cshape.position.y = 3.0
		cup.add_child(cshape)
		var cmesh := MeshInstance3D.new()
		var cylm := CylinderMesh.new()
		cylm.top_radius = 2.2
		cylm.bottom_radius = 1.7
		cylm.height = 6.0
		cmesh.mesh = cylm
		cmesh.material_override = ToyMaterials.plastic(Color(rng.randf_range(0.3, 0.9), rng.randf_range(0.3, 0.9), rng.randf_range(0.3, 0.9)), 0.3)
		cmesh.position.y = 3.0
		cup.add_child(cmesh)
		cup.position = Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-25, 30))
		add_child(cup)
	for i in 8:
		var crayon := _static_box(Vector3(rng.randf_range(-50, 50), 0.7, rng.randf_range(-30, 35)), Vector3(1.4, 1.4, 10), ToyMaterials.plastic(Color(rng.randf_range(0.4, 1.0), rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8)), 0.6))
		crayon.rotation_degrees.y = rng.randf_range(0, 180)
	# The slipper: a soft bunker near spawn.
	_static_box(Vector3(-52, 2, 18), Vector3(9, 4, 20), ToyMaterials.soft(Color(0.55, 0.4, 0.45)), true)

	# Asset-pack battlefield dressing: dug-in positions across the rug.
	add_prop("sacktrench", Vector3(-44, 0, 20), 80, 7.5)      # squad's trench line
	add_prop("sacktrench_small", Vector3(-12, 0, 12), -30, 4.5)
	add_prop("sacktrench_small", Vector3(26, 0, -14), 55, 4.5)
	add_prop("barrier_large", Vector3(8, 0, 24), 5, 5.5)       # outpost barricade
	add_prop("barrier_single", Vector3(-28, 0, 30), -45, 3.6)
	add_prop("crate", Vector3(-48, 0, 8), 30, 3.0)
	add_prop("crate", Vector3(34, 0, 34), -15, 3.2)
	add_prop("cardboard_1", Vector3(56, 0, -24), 40, 5.5)
	add_prop("cardboard_2", Vector3(-38, 0, -38), -70, 4.5)
	add_prop("container_small", Vector3(46, 0, 20), 20, 4.2)   # chrome supply drop
	add_prop("barrel", Vector3(12, 0, 33), 0, 1.8)
	add_prop("barrel", Vector3(14.4, 0, 31.6), 70, 1.8)
	add_prop("gascan", Vector3(-20, 0, -24), 15, 1.6)
	add_prop("pallet", Vector3(20, 0, 4), 45, 3.4)
	add_prop("woodplanks", Vector3(-4, 0, -30), 100, 4.2)
	# Deep-detail pass: heavier fortifications and Chrome siege gear.
	add_prop("tires", Vector3(-8, 0, 40), -20, 3.8)
	add_prop("debris_pile", Vector3(40, 0, -2), 65, 4.8)
	add_prop("pallet_broken", Vector3(-26, 0, 6), 120, 3.2)
	add_prop("pipes", Vector3(-58, 0, 32), -40, 4.6)
	add_prop("trashcontainer", Vector3(58, 0, 6), 90, 6.0)
	add_prop("sign", Vector3(-50, 0, 28), 15, 2.6)
	add_prop("barrel_spilled", Vector3(28, 0, 18), -60, 2.2)
	add_prop("gastank", Vector3(-62, 0, 8), 45, 2.8)
	add_prop("fence", Vector3(4, 0, -18), 70, 5.0)
	add_prop("metalfence", Vector3(-16, 0, 24), -10, 5.0)
	add_prop("container_long", Vector3(54, 0, -42), 25, 7.0)
	Landmine.spawn(self, Vector3(16, 0, 26))
	Landmine.spawn(self, Vector3(-20, 0, 32))

	# Dust motes in the TV glow and over the rug.
	add_dust_motes(Vector3(0, 14, 40), Vector3(26, 10, 14), 45, Color(0.7, 0.8, 1.0))
	add_dust_motes(Vector3(-10, 8, -6), Vector3(34, 7, 24), 30)

# =========================================================================
#  CHROME OUTPOSTS — two forward pods guarding the TV center approach.
# =========================================================================
func _build_chrome_outposts() -> void:
	for pos in [Vector3(22, 0, 30), Vector3(-24, 0, 34)]:
		var pod := DropPod.new()
		add_child(pod)
		pod.position = pos

func _spawn_units() -> void:
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var green: FactionData = load("res://data/factions/green_army.tres")

	# Player enters from the hallway door, west side.
	var player := Player.new()
	player.faction = green
	add_child(player)
	player.position = Vector3(-62, 1, -20)
	player.rotation_degrees.y = -75.0   # face into the room

	# Squadmates pinned down in the trench line beside the slipper bunker.
	# (NOT inside the slipper's collider — spawning there shoved them on top
	# of it, out of rescue range, and blocked mission progress.)
	for pos in [Vector3(-44, 1, 33), Vector3(-38, 1, 12), Vector3(-36, 1, 24)]:
		var mate := SquadMate.new()
		mate.faction = green
		add_child(mate)
		mate.position = pos

	# Chrome patrols: rug sweeps, TV center garrison, couch ridge lookouts.
	# The TV garrison fields a heavy; a sniper overwatches from the couch ridge.
	var patrols := [
		{"route": [Vector3(-20, 1, 0), Vector3(10, 1, -10), Vector3(0, 1, 15)], "mix": ["trooper", "scout"]},
		{"route": [Vector3(30, 1, 10), Vector3(45, 1, -15), Vector3(20, 1, -20)], "mix": ["scout", "trooper"]},
		{"route": [Vector3(15, 1, 38), Vector3(-18, 1, 40), Vector3(0, 1, 28)], "mix": ["heavy", "trooper"]},
		{"route": [Vector3(-35, 1, -20), Vector3(-10, 1, -18), Vector3(-30, 1, -12)], "mix": ["trooper", "scout"]},
		{"route": [Vector3(50, 1, 35), Vector3(58, 1, 12), Vector3(40, 1, 25)], "mix": ["heavy", "sniper"]},
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

	# Vehicles: tank near spawn, paper plane on the coffee table coaster.
	var tank := ToyTank.new()
	add_child(tank)
	tank.position = Vector3(-56, 1, -2)
	tank.rotation_degrees.y = -70.0
	var plane := PaperPlane.new()
	add_child(plane)
	plane.position = Vector3(-12, 16.6, 0)
	plane.rotation_degrees.y = -90.0

func _spawn_pickups_and_toys() -> void:
	for pos in [Vector3(-30, 0, 0), Vector3(12, 0, -25), Vector3(0, 16.2, 5), Vector3(38, 0, 30), Vector3(0, 14.6, -40)]:
		Pickup.spawn_health(self, pos)
	for pos in [Vector3(-15, 0, 20), Vector3(25, 0, -8), Vector3(52, 0, -30)]:
		Pickup.spawn_parts(self, pos, 5)
	for pos in [Vector3(-40, 0, -5), Vector3(18, 0, 20), Vector3(0, 16.2, -6)]:
		Pickup.spawn_ammo(self, pos)
	var toy_spots := [
		["Captain Cushion", Vector3(0, 14.6, -40)],       # on the couch seat
		["Remote-Keeper", Vector3(52, 0.5, 44)],          # behind the cabinet
		["Dust Bunny Dan", Vector3(48, 0.5, -52)],        # dark corner past the couch
		["Ace Foldwell", Vector3(12, 16.6, 0)],           # coffee table plateau
		["Crayona", Vector3(-58, 0.5, 40)],               # far corner
	]
	for spot in toy_spots:
		var toy := LostToy.new()
		toy.toy_name = spot[0]
		add_child(toy)
		toy.position = spot[1]

# =========================================================================
#  MISSION — "RUG BURN": clear outposts, then survive THE VACUUM.
# =========================================================================
func _start_mission() -> void:
	Missions.start_mission("ACT 1 — RUG BURN")
	Missions.add_objective("rescue", "Rescue the pinned-down squad  [E]", 3)
	Missions.add_objective("pods", "Destroy the Chrome outpost pods", 2)
	Missions.add_objective("filters", "??? — something sleeps in the closet", 3)
	Missions.marker_provider = func(id: String) -> Vector3:
		match id:
			"rescue":
				return nearest_in_group("green_allies", func(n): return n is SquadMate and n.captive)
			"pods":
				return nearest_in_group("chrome_pods")
			"filters":
				if _vacuum != null and is_instance_valid(_vacuum):
					return _vacuum.global_position + Vector3.UP * 5.0
				return Vector3.INF
		return Vector3.INF
	Events.notify.emit("The Chrome Legion holds the TV. Take back the living room.")

func _check_vacuum_trigger() -> void:
	if _vacuum_spawned or not Missions.is_done("pods"):
		return
	_vacuum_spawned = true
	# Rename the mystery objective now that the threat is revealed.
	for o in Missions.objectives:
		if o.id == "filters":
			o.text = "Destroy THE VACUUM's filter pods"
	Events.objectives_changed.emit()
	# Dramatic entrance from the closet corner.
	_vacuum = VacuumBoss.new()
	add_child(_vacuum)
	_vacuum.global_position = Vector3(60, 1, -45)
	Events.notify.emit("A ROAR FROM THE CLOSET... THE VACUUM AWAKENS!")
	Sfx.play("explosion", 0.0, 0.2)
	Fx.explosion(self, Vector3(60, 3, -45), 4.0)
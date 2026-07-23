class_name Bedroom
extends RoomBase
## THE BEDROOM — starting battlefield of The Trenches.
## Night time. The child is asleep down the hall. The Chrome Legion has landed.
##
## Built procedurally from primitives so the layout is data-tweakable and every
## landmark (bed fortress, desk command center, bookshelf cliffs, LEGO city,
## toy chest bunker, under-bed tunnels) is a self-contained builder function
## that can be swapped for real asset-pack models later.
##
## Scale: 1 unit = ~3 cm at toy scale. A soldier is 1.4 u tall; the room is a
## 120 x 100 u battlefield, so the bed genuinely reads as a mountain fortress.

const ROOM_W := 120.0
const ROOM_D := 100.0
const WALL_H := 60.0

var _reinforcements_sent := false

func _ready() -> void:
	LostToy.reset_level_counters()
	_setup_nav()
	_build_lighting()
	_build_room_shell()
	_build_bed_fortress()
	_build_desk_command_center()
	_build_bookshelf_cliffs()
	_build_lego_city()
	_build_toy_chest_bunker()
	_build_scattered_props()
	_build_chrome_beachhead()
	_spawn_units()
	_spawn_pickups_and_toys()
	_bake_navmesh()
	_start_mission()
	Events.unit_died.connect(_on_unit_died)

# =========================================================================
#  LIGHTING — night, moonlight through the window, warm nightlight.
# =========================================================================
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	we.environment = RoomBase.make_night_environment(Color(0.12, 0.14, 0.24), Color(0.4, 0.44, 0.6), 1.15)
	add_child(we)

	# Cinematic three-point rig keyed by the window moonlight.
	add_light_rig(self, Vector3(-38, 145, 0), Color(0.68, 0.76, 1.0), 1.5)

	# A visible moonlight pool on the carpet under the window.
	var moon_pool := SpotLight3D.new()
	moon_pool.light_color = Color(0.65, 0.75, 1.0)
	moon_pool.light_energy = 3.5
	moon_pool.spot_range = 55.0
	moon_pool.spot_angle = 26.0
	moon_pool.position = Vector3(15, 42, -ROOM_D / 2 + 4)
	moon_pool.rotation_degrees = Vector3(-58, 15, 0)
	add_child(moon_pool)

	# Nightlight near the player spawn — warm, safe, gently breathing.
	var nightlight := OmniLight3D.new()
	nightlight.light_color = Color(1.0, 0.75, 0.45)
	nightlight.light_energy = 2.2
	nightlight.omni_range = 30.0
	nightlight.position = Vector3(-48, 4, 40)
	add_child(nightlight)
	register_flicker(nightlight, 2.2, 1.1, 0.08)

	# Cold glow above the Chrome beachhead, pulsing like a machine heartbeat.
	var chrome_glow := OmniLight3D.new()
	chrome_glow.light_color = Color(0.4, 0.9, 1.0)
	chrome_glow.light_energy = 1.6
	chrome_glow.omni_range = 35.0
	chrome_glow.position = Vector3(38, 8, -30)
	add_child(chrome_glow)
	register_flicker(chrome_glow, 1.6, 2.4, 0.15)

# =========================================================================
#  ROOM SHELL — carpet plains and distant giant walls.
# =========================================================================
func _build_room_shell() -> void:
	var carpet := ToyMaterials.carpet(Color(0.36, 0.3, 0.42))
	var wall_mat := ToyMaterials.wallpaper(Color(0.55, 0.6, 0.7), Color(0.48, 0.53, 0.64))
	_build_shell(ROOM_W, ROOM_D, WALL_H, carpet, wall_mat)

	# Carpet pattern patches — landmarks for navigation ("meet at the blue rug").
	for patch in [
		[Vector3(-30, 0.02, 25), Vector2(26, 20), Color(0.28, 0.36, 0.55)],
		[Vector3(20, 0.02, 30), Vector2(18, 14), Color(0.5, 0.32, 0.3)],
		[Vector3(0, 0.02, -10), Vector2(30, 22), Color(0.32, 0.42, 0.34)],
	]:
		var m := MeshInstance3D.new()
		var plane := BoxMesh.new()
		plane.size = Vector3(patch[1].x, 0.06, patch[1].y)
		m.mesh = plane
		m.material_override = ToyMaterials.soft(patch[2])
		m.position = patch[0]
		add_child(m)

	# Window on the back wall (moonlight source), purely visual.
	var window := MeshInstance3D.new()
	var wmesh := BoxMesh.new()
	wmesh.size = Vector3(28, 22, 0.5)
	window.mesh = wmesh
	window.material_override = ToyMaterials.glow(Color(0.5, 0.62, 0.95), 0.9)
	window.position = Vector3(15, 30, -ROOM_D / 2 + 1.3)
	add_child(window)

	# Door outline on the south wall — future exit to the HALLWAY region.
	var door := MeshInstance3D.new()
	var dmesh := BoxMesh.new()
	dmesh.size = Vector3(16, 34, 0.5)
	door.mesh = dmesh
	door.material_override = ToyMaterials.wood(Color(0.4, 0.28, 0.18))
	door.position = Vector3(-30, 17, ROOM_D / 2 - 1.3)
	add_child(door)

# =========================================================================
#  BED FORTRESS — west side. Pillow mountains on top, tunnels underneath.
# =========================================================================
func _build_bed_fortress() -> void:
	var blanket := ToyMaterials.soft(Color(0.65, 0.3, 0.3))
	var pillow := ToyMaterials.soft(Color(0.9, 0.88, 0.8))
	var bed_pos := Vector3(-38, 0, -22)

	# Real furniture asset (Kenney double bed, ~42 x 17 x 50 at this scale).
	# Colliders are hand-shaped: mattress plateau you fight on + headboard.
	var bed := add_landmark("bed_double", bed_pos, 0, 50.0)
	if bed != null:
		_landmark_box(bed, Vector3(0, 5.4, 0), Vector3(41, 10.8, 49))   # mattress deck (raised)
		_landmark_box(bed, Vector3(0, 13, -23.5), Vector3(41, 7.5, 3))  # headboard wall
		_landmark_deck(bed, 0.85, 1.3)
	else:
		_static_box(bed_pos + Vector3(0, 8, 0), Vector3(38, 4, 50), blanket)
	# Pillows are VISUAL only — colliding cushions used to swallow the player.
	_deco_box(bed_pos + Vector3(0, 11.6, -16), Vector3(26, 3.2, 10), pillow, true)
	_deco_box(bed_pos + Vector3(-7, 13.6, -18), Vector3(12, 2.6, 7), pillow, true)
	# Blanket ramp: the route up the fortress.
	var ramp := _static_box(bed_pos + Vector3(23, 4.6, 12), Vector3(14, 1.5, 16), blanket)
	ramp.rotation_degrees.z = -30.0

# =========================================================================
#  DESK COMMAND CENTER — northeast. High ground reached via cable/books.
# =========================================================================
func _build_desk_command_center() -> void:
	var wood := ToyMaterials.wood()
	var desk_pos := Vector3(40, 0, -38)
	# Real furniture asset (Quaternius desk, ~34 x 17 x 16 at this scale).
	var desk := add_landmark("desk", desk_pos, 0, 34.0)
	if desk != null:
		_landmark_box(desk, Vector3(0, 16.2, 0), Vector3(34, 2.4, 15.8))   # desktop plateau
		_landmark_box(desk, Vector3(-16, 7.6, 0), Vector3(2, 15.2, 15))   # side panels
		_landmark_box(desk, Vector3(16, 7.6, 0), Vector3(2, 15.2, 15))
		_landmark_deck(desk, 0.9, 1.0)
	else:
		_static_box(desk_pos + Vector3(0, 16, 0), Vector3(34, 2, 16), wood)
	# Monitor glow — the "command screen".
	var screen := MeshInstance3D.new()
	var smesh := BoxMesh.new()
	smesh.size = Vector3(12, 8, 0.8)
	screen.mesh = smesh
	screen.material_override = ToyMaterials.glow(Color(0.3, 0.8, 0.6), 1.4)
	screen.position = desk_pos + Vector3(0, 21.5, -5)
	add_child(screen)
	# Book staircase up to the desk.
	var colors := [Color(0.7, 0.25, 0.2), Color(0.2, 0.4, 0.65), Color(0.75, 0.6, 0.2), Color(0.3, 0.55, 0.3)]
	for i in 5:
		var h := 3.5 * (i + 1)
		_static_box(desk_pos + Vector3(-22 + i * -4.2, h - 1.75, 10 - i * 1.5), Vector3(9, 3.5, 12), ToyMaterials.plastic(colors[i % colors.size()], 0.6))

# =========================================================================
#  BOOKSHELF CLIFFS — north wall. Vertical terrain.
# =========================================================================
func _build_bookshelf_cliffs() -> void:
	var shelf_pos := Vector3(-5, 0, -46)
	# Real furniture asset (Quaternius bookcase with books, ~26 x 48 x 9).
	var shelf := add_landmark("bookshelf", shelf_pos, 0, 26.0)
	if shelf != null:
		_landmark_box(shelf, Vector3(0, 23.8, 0), Vector3(26, 47.6, 9.4))
	else:
		_static_box(shelf_pos + Vector3(0, 20, 0), Vector3(28, 40, 7), ToyMaterials.wood(Color(0.45, 0.32, 0.2)))
	# One fallen book leaning against the shelf = floor cover.
	var fallen := _static_box(shelf_pos + Vector3(-20, 3.6, 8), Vector3(7, 1.2, 18), ToyMaterials.plastic(Color(0.6, 0.5, 0.25), 0.7))
	fallen.rotation_degrees.x = -24.0

# =========================================================================
#  LEGO CITY — center-east. Brick Kingdom's neutral outpost. Great cover.
# =========================================================================
func _build_lego_city() -> void:
	var plate_pos := Vector3(18, 0, 8)
	_static_box(plate_pos + Vector3(0, 0.4, 0), Vector3(34, 0.8, 28), ToyMaterials.plastic(Color(0.2, 0.55, 0.25), 0.5))
	var brick_colors := [Color(0.85, 0.15, 0.12), Color(0.95, 0.75, 0.1), Color(0.15, 0.4, 0.85), Color(0.9, 0.9, 0.9), Color(0.2, 0.6, 0.3)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260720
	for i in 9:
		var bx := rng.randf_range(-13.0, 13.0)
		var bz := rng.randf_range(-10.0, 10.0)
		var floors := rng.randi_range(1, 4)
		for f in floors:
			var c: Color = brick_colors[rng.randi() % brick_colors.size()]
			var size := Vector3(rng.randf_range(3.5, 6.0), 2.4, rng.randf_range(3.5, 6.0))
			var brick := _static_box(plate_pos + Vector3(bx, 0.8 + 2.4 * f + 1.2, bz), size, ToyMaterials.plastic(c, 0.35))
			# Studs on top — the LEGO read.
			for sx in 2:
				for sz in 2:
					var stud := MeshInstance3D.new()
					var cyl := CylinderMesh.new()
					cyl.top_radius = 0.5
					cyl.bottom_radius = 0.5
					cyl.height = 0.4
					stud.mesh = cyl
					stud.material_override = ToyMaterials.plastic(c, 0.35)
					stud.position = Vector3((sx - 0.5) * size.x * 0.5, size.y / 2 + 0.2, (sz - 0.5) * size.z * 0.5)
					brick.add_child(stud)

# =========================================================================
#  TOY CHEST BUNKER — southeast. Green Army forward base; the tank is here.
# =========================================================================
func _build_toy_chest_bunker() -> void:
	var chest_pos := Vector3(42, 0, 34)
	var wood := ToyMaterials.wood(Color(0.5, 0.36, 0.22))
	_static_box(chest_pos + Vector3(0, 6, -7), Vector3(24, 12, 2), wood)
	_static_box(chest_pos + Vector3(-11, 6, 0), Vector3(2, 12, 16), wood)
	_static_box(chest_pos + Vector3(11, 6, 0), Vector3(2, 12, 16), wood)
	# Open lid leaning back = roof canopy.
	var lid := _static_box(chest_pos + Vector3(0, 13.5, -10), Vector3(24, 1.5, 12), wood)
	lid.rotation_degrees.x = 55.0
	# Sandbag line out front (folded socks, if we're honest).
	for i in 5:
		_static_box(chest_pos + Vector3(-8 + i * 4.0, 1.0, 12), Vector3(3.4, 2.0, 2.0), ToyMaterials.soft(Color(0.75, 0.72, 0.6)))

# =========================================================================
#  SCATTERED PROPS — cover across the open carpet.
# =========================================================================
func _build_scattered_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8675309
	# Wooden alphabet blocks.
	for i in 10:
		var pos := Vector3(rng.randf_range(-40, 40), 2.0, rng.randf_range(-30, 40))
		if pos.distance_to(Vector3(18, 0, 8)) < 20.0:
			continue   # keep LEGO city clear
		var c := Color(rng.randf_range(0.4, 0.9), rng.randf_range(0.3, 0.8), rng.randf_range(0.3, 0.8))
		var block := _static_box(pos, Vector3(4, 4, 4), ToyMaterials.plastic(c, 0.55))
		block.rotation_degrees.y = rng.randf_range(0, 90)
	# Pencils — long thin cover.
	for i in 5:
		var pencil := _static_box(Vector3(rng.randf_range(-45, 45), 0.6, rng.randf_range(-40, 42)), Vector3(1.2, 1.2, 14), ToyMaterials.plastic(Color(0.95, 0.7, 0.15), 0.5))
		pencil.rotation_degrees.y = rng.randf_range(0, 180)
	# Asset-pack battlefield dressing: the toys have dug in for a long war.
	# Sandbag trenches guard approaches; crates and boxes are supply lines.
	add_prop("sacktrench", Vector3(-18, 0, 16), 25, 7.0)
	add_prop("sacktrench_small", Vector3(6, 0, -6), -60, 4.5)
	add_prop("sacktrench_small", Vector3(-2, 0, -32), 110, 4.5)
	add_prop("crate", Vector3(-34, 0, 14), 15, 3.2)
	add_prop("crate", Vector3(-31, 0, 17.4), 40, 2.6)
	add_prop("cardboard_1", Vector3(30, 0, 26), -20, 5.0)
	# Against the west wall — parked in the spawn sightline it read as a
	# featureless monolith blocking the whole opening view of the room.
	add_prop("cardboard_2", Vector3(-56, 0, 6), 25, 4.2)
	add_prop("barrier_single", Vector3(12, 0, -22), 30, 3.6)
	add_prop("barrier_large", Vector3(26, 0, -20), -75, 5.2)
	add_prop("pallet", Vector3(-10, 0, 34), 10, 3.4)
	add_barrel(Vector3(48, 0, -14), 0, 1.8)
	add_barrel(Vector3(46.4, 0, -11.8), 40, 1.8)
	add_prop("cone", Vector3(-24, 0, -8), 0, 1.6)
	add_prop("woodplanks", Vector3(14, 0, 38), 75, 4.0)
	# Deep-detail pass: the Green Army has fortified every approach.
	add_prop("tires", Vector3(-8, 0, 22), 30, 3.6)
	add_prop("debris_pile", Vector3(28, 0, -34), -50, 4.6)
	add_prop("pallet_broken", Vector3(-40, 0, -2), 80, 3.2)
	add_prop("pipes", Vector3(52, 0, 24), 15, 4.4)
	add_prop("sign", Vector3(-36, 0, 32), -30, 2.6)
	add_prop("gastank", Vector3(48, 0, 30), 110, 2.8)
	add_barrel(Vector3(20, 0, 16), -85, 2.2, true)
	add_prop("fence", Vector3(-14, 0, 6), 40, 5.0)
	add_prop("metalfence", Vector3(34, 0, 12), -15, 5.0)
	# Landmines ring the beachhead (visual dressing, toys play fair... mostly).
	Landmine.spawn(self, Vector3(30, 0, -22))
	Landmine.spawn(self, Vector3(44, 0, -18))
	Landmine.spawn(self, Vector3(24, 0, -30))

	# Dust motes drifting through the moonlight and over the carpet plains.
	add_dust_motes(Vector3(15, 12, -30), Vector3(24, 10, 16))
	add_dust_motes(Vector3(-20, 8, 20), Vector3(30, 7, 22), 30)

	# A giant bouncy ball.
	var ball := StaticBody3D.new()
	ball.collision_layer = 0b0001
	var bshape := CollisionShape3D.new()
	var bsphere := SphereShape3D.new()
	bsphere.radius = 5.0
	bshape.shape = bsphere
	ball.add_child(bshape)
	var bmesh := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 5.0
	bs.height = 10.0
	bmesh.mesh = bs
	bmesh.material_override = ToyMaterials.plastic(Color(0.85, 0.25, 0.3), 0.15)
	ball.add_child(bmesh)
	ball.position = Vector3(-15, 5, 42)
	add_child(ball)

# =========================================================================
#  CHROME BEACHHEAD — northeast quadrant. The mission objective.
# =========================================================================
func _build_chrome_beachhead() -> void:
	var camp := Vector3(38, 0, -30)
	for offset in [Vector3(-8, 0, -4), Vector3(8, 0, -6), Vector3(0, 0, 8)]:
		var pod := DropPod.new()
		add_child(pod)
		pod.position = camp + offset
	# Landing scorch ring.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 14.0
	torus.outer_radius = 15.5
	ring.mesh = torus
	ring.material_override = ToyMaterials.glow(Color(0.3, 0.8, 1.0), 0.8)
	ring.position = camp + Vector3(0, 0.1, 0)
	add_child(ring)

# =========================================================================
#  UNITS
# =========================================================================
func _spawn_units() -> void:
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var green: FactionData = load("res://data/factions/green_army.tres")

	# Player spawns at the nightlight corner, southwest.
	var player := Player.new()
	player.faction = green
	add_child(player)
	player.position = Vector3(-46, 1, 38)

	# Two captive squadmates along the route to the objective.
	for pos in [Vector3(-28, 1, 24), Vector3(2, 1, 30)]:
		var mate := SquadMate.new()
		mate.faction = green
		add_child(mate)
		mate.position = pos

	# Chrome patrols guarding routes and camp. Each route pairs a variant mix
	# so fights feel different: scouts harass, the camp fields a heavy.
	var patrols := [
		{"route": [Vector3(0, 1, 0), Vector3(12, 1, -14), Vector3(-8, 1, -18)], "mix": ["trooper", "scout"]},
		{"route": [Vector3(24, 1, -12), Vector3(34, 1, 2), Vector3(14, 1, 4)], "mix": ["trooper", "scout"]},
		{"route": [Vector3(38, 1, -18), Vector3(50, 1, -34), Vector3(28, 1, -40)], "mix": ["heavy", "trooper"]},
		{"route": [Vector3(-14, 1, -34), Vector3(4, 1, -40), Vector3(-2, 1, -26)], "mix": ["sniper", "trooper"]},
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

	# The tank waits at the toy chest bunker.
	var tank := ToyTank.new()
	add_child(tank)
	tank.position = Vector3(34, 1, 40)
	tank.rotation_degrees.y = 40.0

func _spawn_pickups_and_toys() -> void:
	scatter_coins(ROOM_W * 0.4, ROOM_D * 0.4)
	for pos in [Vector3(-20, 0, 10), Vector3(10, 0, -20), Vector3(30, 0, 20), Vector3(-38, 10, -22)]:
		Pickup.spawn_health(self, pos)
	for pos in [Vector3(-10, 0, 0), Vector3(25, 0, -5), Vector3(45, 0, 10)]:
		Pickup.spawn_parts(self, pos, 5)
	for pos in [Vector3(0, 0, 18), Vector3(20, 0, -28)]:
		Pickup.spawn_ammo(self, pos)
	spawn_weapon_drop(Vector3(34, 0, -14), "repeater")
	spawn_weapon_drop(Vector3(-28, 0, 24), "scatter")
	# Lost toys hide in hard-to-reach spots: under the bed, on the desk,
	# on a bookshelf, in the LEGO city, behind the ball.
	var toy_spots := [
		["Dusty the Bear", Vector3(-38, 10.2, -22)],   # on the bed plateau
		["Sergeant Buttons", Vector3(40, 17.8, -38)],  # on the desk
		["Professor Paws", Vector3(-25, 0.8, -38)],    # beside the fallen book
		["Brickley", Vector3(18, 1.2, 8)],
		["Bounce", Vector3(-22, 0.5, 44)],
	]
	for spot in toy_spots:
		var toy := LostToy.new()
		toy.toy_name = spot[0]
		add_child(toy)
		toy.position = spot[1]

# =========================================================================
#  MISSION — Act 1, Mission 1: "LIGHTS OUT"
# =========================================================================
func _start_mission() -> void:
	Missions.start_mission("ACT 1 — LIGHTS OUT")
	Missions.add_objective("rescue", "Rescue captured Green Army soldiers  [E]", 2)
	Missions.add_objective("barrels", "Detonate Chrome fuel barrels", 3)
	Missions.add_objective("pods", "Destroy the Chrome beachhead drop pods", 3)
	Missions.marker_provider = func(id: String) -> Vector3:
		match id:
			"rescue":
				return nearest_in_group("green_allies", func(n): return n is SquadMate and n.captive)
			"barrels":
				return nearest_in_group("explosive_barrels")
			"pods":
				return nearest_in_group("chrome_pods")
		return Vector3.INF
	Events.notify.emit("The lights are out. The Chrome Legion has landed. Move out, soldier.")

func _on_unit_died(_unit: Node) -> void:
	# Reinforcement system: losing the first pod triggers a Chrome counterattack.
	if not _reinforcements_sent and Missions.objectives.size() > 2 and Missions.objectives[2].count_done >= 1:
		_send_reinforcements()

func _send_reinforcements() -> void:
	_reinforcements_sent = true
	Events.notify.emit("WARNING: Chrome Legion reinforcements inbound!")
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var mix := ["trooper", "scout", "scout", "heavy"]
	for i in 4:
		var enemy := EnemySoldier.new()
		enemy.faction = chrome
		enemy.variant = mix[i]
		var route: Array[Vector3] = [Vector3(38, 1, -30)]
		enemy.patrol_points = route
		add_child(enemy)
		enemy.position = Vector3(50 - i * 3.0, 1, -42)
		enemy.state = EnemySoldier.AiState.ALERT
		if Game.player != null:
			enemy.target = Game.player

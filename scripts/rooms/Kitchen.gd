class_name Kitchen
extends RoomBase
## THE KITCHEN — Act 1, Mission 3: "COUNTER STRIKE".
##
## Checkerboard-tile arena with vertical terrain: the table mesa at center,
## the counter ridge along the north wall (reached by the open-drawer
## staircase), the humming fridge monolith, and the Chrome supply depot dug
## into a cereal-box fort in the southeast. Biggest garrison yet: heavies
## hold the fort, snipers overwatch from the counter ridge.

const ROOM_W := 140.0
const ROOM_D := 110.0
const WALL_H := 80.0

var _counterattack_sent := false

func _ready() -> void:
	LostToy.reset_level_counters()
	_setup_nav()
	_build_lighting()
	_build_room_shell()
	_build_table_mesa()
	_build_counter_ridge()
	_build_fridge_monolith()
	_build_cereal_fort()
	_build_scattered_props()
	_spawn_units()
	_spawn_pickups_and_toys()
	_bake_navmesh()
	_start_mission()
	Events.unit_died.connect(_on_unit_died)

# =========================================================================
#  LIGHTING — moonlight over the sink window, appliance glows everywhere.
# =========================================================================
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	we.environment = RoomBase.make_night_environment(Color(0.1, 0.14, 0.2), Color(0.44, 0.5, 0.62), 1.2)
	add_child(we)
	add_light_rig(self, Vector3(-44, 25, 0), Color(0.66, 0.76, 1.0), 1.55)

	# Moon pool through the window above the sink.
	var moon := SpotLight3D.new()
	moon.light_color = Color(0.66, 0.78, 1.0)
	moon.light_energy = 3.2
	moon.spot_range = 70.0
	moon.spot_angle = 24.0
	moon.position = Vector3(-10, 55, -ROOM_D / 2 + 6)
	moon.rotation_degrees = Vector3(-62, 0, 0)
	add_child(moon)

	# The fridge hums with cold light, breathing slowly.
	var fridge_glow := OmniLight3D.new()
	fridge_glow.light_color = Color(0.6, 0.85, 1.0)
	fridge_glow.light_energy = 1.9
	fridge_glow.omni_range = 34.0
	fridge_glow.position = Vector3(52, 12, -34)
	add_child(fridge_glow)
	register_flicker(fridge_glow, 1.9, 0.7, 0.1)

	# Warm oven clock: the only cozy light, near the player spawn.
	var oven := OmniLight3D.new()
	oven.light_color = Color(1.0, 0.7, 0.4)
	oven.light_energy = 2.0
	oven.omni_range = 28.0
	oven.position = Vector3(-52, 8, 34)
	add_child(oven)
	register_flicker(oven, 2.0, 1.3, 0.07)

	# Cold Chrome depot glow over the cereal fort.
	var depot := OmniLight3D.new()
	depot.light_color = Color(0.4, 0.9, 1.0)
	depot.light_energy = 1.7
	depot.omni_range = 38.0
	depot.position = Vector3(40, 10, 34)
	add_child(depot)
	register_flicker(depot, 1.7, 2.2, 0.16)

# =========================================================================
#  ROOM SHELL — checkerboard tile floor reads instantly as "kitchen".
# =========================================================================
func _build_room_shell() -> void:
	var tile_base := ToyMaterials.plastic(Color(0.82, 0.8, 0.74), 0.55)
	var wall_mat := ToyMaterials.wallpaper(Color(0.62, 0.66, 0.62), Color(0.55, 0.6, 0.55))
	_build_shell(ROOM_W, ROOM_D, WALL_H, tile_base, wall_mat)

	# Dark checker tiles: thin visual planes, no collision needed.
	var dark_tile := ToyMaterials.plastic(Color(0.3, 0.34, 0.4), 0.5)
	var tile := 14.0
	for ix in range(-4, 5):
		for iz in range(-3, 4):
			if (ix + iz) % 2 == 0:
				continue
			var m := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(tile, 0.06, tile)
			m.mesh = pm
			m.material_override = dark_tile
			m.position = Vector3(ix * tile, 0.03, iz * tile)
			add_child(m)

	# Window above the sink on the north wall.
	var window := MeshInstance3D.new()
	var wmesh := BoxMesh.new()
	wmesh.size = Vector3(30, 24, 0.5)
	window.mesh = wmesh
	window.material_override = ToyMaterials.glow(Color(0.5, 0.64, 0.95), 0.9)
	window.position = Vector3(-10, 42, -ROOM_D / 2 + 1.3)
	add_child(window)

	# Doorway back to the living room, west wall.
	var door := MeshInstance3D.new()
	var dmesh := BoxMesh.new()
	dmesh.size = Vector3(16, 34, 0.5)
	door.mesh = dmesh
	door.material_override = ToyMaterials.glow(Color(1.0, 0.75, 0.4), 0.6)
	door.position = Vector3(-ROOM_W / 2 + 1.3, 17, 10)
	door.rotation_degrees.y = 90.0
	add_child(door)

# =========================================================================
#  TABLE MESA — center. Chair-seat hopscotch is the way up.
# =========================================================================
func _build_table_mesa() -> void:
	var wood := ToyMaterials.wood(Color(0.5, 0.34, 0.2))
	var table_pos := Vector3(-6, 0, 2)
	# Real furniture asset (dining table, ~44 x 20.5 x 45 at this scale).
	var table := add_landmark("dining_table", table_pos, 0, 44.0)
	if table != null:
		# Round tabletop: two crossed boxes approximate the disc.
		_landmark_box(table, Vector3(0, 19.5, 0), Vector3(43, 2, 30))     # tabletop mesa
		_landmark_box(table, Vector3(0, 19.5, 0), Vector3(30, 2, 43))
		_landmark_box(table, Vector3(0, 9.5, 0), Vector3(8, 19, 8))       # center pedestal
	else:
		_static_box(table_pos + Vector3(0, 19.5, 0), Vector3(44, 2, 26), wood)

	# Two real chairs: seat height ~9 = the stepping stones to the mesa top.
	for spec in [[Vector3(-28, 0, 18), 25.0], [Vector3(26, 0, -20), -160.0]]:
		var chair := add_landmark("chair", table_pos + spec[0], spec[1], 8.7)
		if chair != null:
			_landmark_box(chair, Vector3(0, 4.5, 0), Vector3(8.7, 9.0, 9.4))    # seat
			_landmark_box(chair, Vector3(0, 14.5, 4), Vector3(8.7, 11.0, 1.6))  # backrest
		else:
			var seat := _static_box(table_pos + spec[0] + Vector3(0, 4.5, 0), Vector3(13, 9, 13), wood)
			seat.rotation_degrees.y = spec[1]

	# Cookbook staircase: the fighting route up the mesa.
	var colors := [Color(0.7, 0.3, 0.25), Color(0.25, 0.45, 0.6), Color(0.8, 0.65, 0.25)]
	for i in 6:
		var h := 3.3 * (i + 1)
		_static_box(table_pos + Vector3(26 + i * 3.8, h - 1.65, 16 - i * 2.2), Vector3(9, 3.3, 11), ToyMaterials.plastic(colors[i % colors.size()], 0.65))

	# Fruit bowl on top: soft round cover for the plateau fight.
	var bowl := _static_box(table_pos + Vector3(6, 21.9, 0), Vector3(10, 3, 10), ToyMaterials.plastic(Color(0.85, 0.5, 0.2), 0.3), true)
	bowl.name = "FruitBowl"

# =========================================================================
#  COUNTER RIDGE — north wall plateau, reached by the open-drawer staircase.
# =========================================================================
func _build_counter_ridge() -> void:
	var cabinet := ToyMaterials.wood(Color(0.36, 0.3, 0.26))
	var top_mat := ToyMaterials.plastic(Color(0.75, 0.78, 0.8), 0.25)
	var ridge_z := -ROOM_D / 2 + 12.0
	# Cabinet base and the countertop plateau.
	_static_box(Vector3(-16, 12, ridge_z), Vector3(88, 24, 18), cabinet)
	_static_box(Vector3(-16, 25, ridge_z), Vector3(92, 2, 20), top_mat)
	# Sink basin: a walled pit on the counter (great sniper cover).
	for wall_spec in [[Vector3(-34, 27.5, ridge_z - 6), Vector3(20, 3, 2)], [Vector3(-34, 27.5, ridge_z + 6), Vector3(20, 3, 2)], [Vector3(-43, 27.5, ridge_z), Vector3(2, 3, 10)], [Vector3(-25, 27.5, ridge_z), Vector3(2, 3, 10)]]:
		_static_box(wall_spec[0], wall_spec[1], top_mat)
	# Open drawers: the staircase up the east end of the counter.
	for i in 3:
		_static_box(Vector3(24 + i * 1.5, 5.0 + i * 7.0, ridge_z + 11 - i * 2.5), Vector3(16, 1.6, 8), cabinet)

# =========================================================================
#  FRIDGE MONOLITH — northeast. Magnet letters on its face.
# =========================================================================
func _build_fridge_monolith() -> void:
	# Real furniture asset (Quaternius fridge, ~20 x 51 x 20 at this scale).
	var fridge := add_landmark("fridge", Vector3(52, 0, -38), -90, 20.0)
	if fridge != null:
		_landmark_box(fridge, Vector3(0, 25.5, 0), Vector3(20, 51, 20))
	else:
		_static_box(Vector3(52, 21, -38), Vector3(26, 42, 20), ToyMaterials.metal(Color(0.72, 0.76, 0.8), 0.3))
	# The stove hulks against the west wall, halfway to the spawn corner.
	var stove := add_landmark("stove", Vector3(-58, 0, 14), 90, 22.0)
	if stove != null:
		_landmark_box(stove, Vector3(0, 15.5, 0), Vector3(22, 31, 22))
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var letter_colors := [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.15), Color(0.3, 0.7, 0.3)]
	for i in 7:
		var mag := MeshInstance3D.new()
		var mm := BoxMesh.new()
		mm.size = Vector3(2.6, 3.0, 0.8)
		mag.mesh = mm
		mag.material_override = ToyMaterials.plastic(letter_colors[i % letter_colors.size()], 0.5)
		mag.position = Vector3(52 + rng.randf_range(-9, 9), rng.randf_range(8, 30), -27.4)
		mag.rotation_degrees.z = rng.randf_range(-20, 20)
		add_child(mag)

# =========================================================================
#  CEREAL FORT — southeast. The Chrome supply depot: mission objective.
# =========================================================================
func _build_cereal_fort() -> void:
	var fort := Vector3(40, 0, 34)
	var box_colors := [Color(0.85, 0.25, 0.2), Color(0.95, 0.7, 0.15), Color(0.25, 0.55, 0.8)]
	# Cereal boxes form the fort walls with a gap entrance on the west side.
	var specs := [
		[Vector3(-12, 0, -10), 10.0], [Vector3(2, 0, -14), -6.0], [Vector3(14, 0, -8), 18.0],
		[Vector3(16, 0, 6), -12.0], [Vector3(8, 0, 16), 8.0], [Vector3(-6, 0, 17), -15.0],
	]
	for i in specs.size():
		var box := _static_box(fort + specs[i][0] + Vector3(0, 9, 0), Vector3(12, 18, 4.5), ToyMaterials.plastic(box_colors[i % box_colors.size()], 0.6))
		box.rotation_degrees.y = specs[i][1]
	# One toppled box = the ramp onto the fort walls.
	var fallen := _static_box(fort + Vector3(-18, 2.6, 6), Vector3(12, 1.8, 18), ToyMaterials.plastic(box_colors[1], 0.6))
	fallen.rotation_degrees.x = -18.0

	# The depot itself: three supply pods inside the fort.
	for offset in [Vector3(-4, 0, -4), Vector3(6, 0, 2), Vector3(-2, 0, 8)]:
		var pod := DropPod.new()
		add_child(pod)
		pod.position = fort + offset

	# Spilled cereal loops: scattered torus decor around the fort.
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	for i in 14:
		var loop := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.5
		tm.outer_radius = 1.0
		loop.mesh = tm
		loop.material_override = ToyMaterials.plastic(Color(0.85, 0.65, 0.35), 0.8)
		loop.position = fort + Vector3(rng.randf_range(-26, 10), 0.35, rng.randf_range(-24, 14))
		loop.rotation_degrees = Vector3(rng.randf_range(-15, 15), rng.randf_range(0, 180), 0)
		add_child(loop)

# =========================================================================
#  SCATTERED PROPS — cover across the open tile.
# =========================================================================
func _build_scattered_props() -> void:
	# Asset-pack dressing: the Green Army has dug into the kitchen floor.
	add_prop("sacktrench", Vector3(-40, 0, 22), -15, 7.5)
	add_prop("sacktrench_small", Vector3(-14, 0, 30), 60, 4.5)
	add_prop("sacktrench_small", Vector3(10, 0, -28), -40, 4.5)
	add_prop("barrier_large", Vector3(18, 0, 20), 30, 5.5)
	add_prop("barrier_single", Vector3(-30, 0, -18), -70, 3.6)
	add_prop("crate", Vector3(-52, 0, 26), 20, 3.2)
	add_prop("crate", Vector3(-48.6, 0, 28.8), -35, 2.6)
	add_prop("cardboard_1", Vector3(56, 0, 8), -25, 5.2)
	add_prop("cardboard_2", Vector3(-56, 0, -32), 45, 4.4)
	add_prop("container_small", Vector3(30, 0, -40), 10, 4.4)
	add_prop("barrel", Vector3(-2, 0, 40), 0, 1.8)
	add_prop("barrel", Vector3(0.6, 0, 42.2), 55, 1.8)
	add_prop("gascan", Vector3(24, 0, -6), -20, 1.6)
	add_prop("pallet", Vector3(-24, 0, 8), 65, 3.4)
	add_prop("woodplanks", Vector3(44, 0, -16), 130, 4.2)
	add_prop("cone", Vector3(-8, 0, -42), 0, 1.6)
	add_prop("cone", Vector3(-12, 0, -44), 0, 1.6)
	# Deep-detail pass: spill zone, pipe runs under the counter, supply lines.
	add_prop("tires", Vector3(-44, 0, -8), 50, 3.6)
	add_prop("debris_pile", Vector3(14, 0, 44), -35, 4.4)
	add_prop("pallet_broken", Vector3(34, 0, 2), 95, 3.2)
	add_prop("pipes", Vector3(-6, 0, -30), 20, 4.6)
	add_prop("trashcontainer", Vector3(-60, 0, 0), 90, 6.2)
	add_prop("sign", Vector3(-26, 0, 40), -50, 2.6)
	add_prop("barrel_spilled", Vector3(6, 0, 14), 30, 2.2)
	add_prop("gastank", Vector3(58, 0, -34), -70, 2.8)
	add_prop("metalfence", Vector3(-20, 0, -14), 35, 5.0)
	add_prop("fence_long", Vector3(22, 0, 32), -8, 7.0)
	add_prop("watertank", Vector3(-52, 0, -44), 15, 5.5)
	Landmine.spawn(self, Vector3(32, 0, 24))
	Landmine.spawn(self, Vector3(48, 0, 40))

	# Dust motes in the moon pool over the sink and across the tiles.
	add_dust_motes(Vector3(-10, 30, -42), Vector3(20, 12, 12), 40, Color(0.75, 0.85, 1.0))
	add_dust_motes(Vector3(0, 8, 10), Vector3(38, 7, 28), 32)

# =========================================================================
#  UNITS — the biggest garrison yet.
# =========================================================================
func _spawn_units() -> void:
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var green: FactionData = load("res://data/factions/green_army.tres")

	# Player spawns at the oven corner, southwest.
	var player := Player.new()
	player.faction = green
	add_child(player)
	player.position = Vector3(-56, 1, 36)
	player.rotation_degrees.y = -60.0

	# Captives: one under the table (clear of the pedestal), one on the ridge.
	for pos in [Vector3(-16, 1, 10), Vector3(-10, 27, -ROOM_D / 2 + 12)]:
		var mate := SquadMate.new()
		mate.faction = green
		add_child(mate)
		mate.position = pos

	var patrols := [
		{"route": [Vector3(-24, 1, -8), Vector3(-2, 1, -20), Vector3(8, 1, 4)], "mix": ["trooper", "scout"]},
		{"route": [Vector3(22, 1, 28), Vector3(36, 1, 12), Vector3(48, 1, 28)], "mix": ["heavy", "trooper"]},
		{"route": [Vector3(40, 1, -24), Vector3(56, 1, -8), Vector3(34, 1, -2)], "mix": ["trooper", "scout"]},
		{"route": [Vector3(-36, 1, -34), Vector3(-14, 1, -40), Vector3(-28, 1, -22)], "mix": ["scout", "scout"]},
		{"route": [Vector3(12, 26.5, -ROOM_D / 2 + 12), Vector3(-30, 26.5, -ROOM_D / 2 + 12)], "mix": ["sniper", "trooper"]},
		{"route": [Vector3(30, 1, 40), Vector3(44, 1, 44), Vector3(52, 1, 36)], "mix": ["heavy", "sniper"]},
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

	# The tank waits by the oven.
	var tank := ToyTank.new()
	add_child(tank)
	tank.position = Vector3(-44, 1, 40)
	tank.rotation_degrees.y = -50.0

func _spawn_pickups_and_toys() -> void:
	scatter_coins(ROOM_W * 0.4, ROOM_D * 0.4)
	for pos in [Vector3(-30, 0, 12), Vector3(14, 0, -16), Vector3(-6, 21.2, 2), Vector3(46, 0, 0), Vector3(-16, 26.2, -ROOM_D / 2 + 12)]:
		Pickup.spawn_health(self, pos)
	for pos in [Vector3(-18, 0, -12), Vector3(28, 0, 8), Vector3(52, 0, -22), Vector3(2, 0, 32)]:
		Pickup.spawn_parts(self, pos, 5)
	for pos in [Vector3(-36, 0, 2), Vector3(20, 0, 34), Vector3(0, 21.2, -4)]:
		Pickup.spawn_ammo(self, pos)
	spawn_weapon_drop(Vector3(38, 0, 20), "soaker")
	spawn_weapon_drop(Vector3(-24, 0, 24), "repeater")
	var toy_spots := [
		["Chef Whiskers", Vector3(-34, 26.6, -ROOM_D / 2 + 12)],  # in the sink
		["Sgt. Spoon", Vector3(-6, 21.6, 8)],                     # on the table
		["Magneto Max", Vector3(52, 0.5, -24)],                   # behind the fridge
		["Crunchy", Vector3(40, 0.5, 34)],                        # inside the fort
		["Mopsy", Vector3(-58, 0.5, -40)],                        # far dark corner
	]
	for spot in toy_spots:
		var toy := LostToy.new()
		toy.toy_name = spot[0]
		add_child(toy)
		toy.position = spot[1]

# =========================================================================
#  MISSION — "COUNTER STRIKE"
# =========================================================================
func _start_mission() -> void:
	Missions.start_mission("ACT 1 — COUNTER STRIKE")
	Missions.add_objective("rescue", "Rescue the scattered squad  [E]", 2)
	Missions.add_objective("patrols", "Eliminate the Chrome kitchen garrison", 8)
	Missions.add_objective("pods", "Destroy the cereal-fort supply depot", 3)
	Missions.marker_provider = func(id: String) -> Vector3:
		match id:
			"rescue":
				return nearest_in_group("green_allies", func(n): return n is SquadMate and n.captive)
			"patrols":
				return nearest_in_group("enemies")
			"pods":
				return nearest_in_group("chrome_pods")
		return Vector3.INF
	Events.notify.emit("The Legion is raiding the pantry. Take back the kitchen, soldier.")

func _on_unit_died(unit: Node) -> void:
	if unit is EnemySoldier:
		Missions.progress("patrols")
	if not _counterattack_sent and Missions.objectives.size() > 2 and Missions.objectives[2].count_done >= 2:
		_send_counterattack()

func _send_counterattack() -> void:
	_counterattack_sent = true
	Events.notify.emit("WARNING: Chrome dropship on the counter! Reinforcements rappelling down!")
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var mix := ["heavy", "commando", "scout", "grenadier", "sniper"]
	for i in 5:
		var enemy := EnemySoldier.new()
		enemy.faction = chrome
		enemy.variant = mix[i]
		var route: Array[Vector3] = [Vector3(40, 1, 34)]
		enemy.patrol_points = route
		add_child(enemy)
		enemy.position = Vector3(58 - i * 3.5, 1, 46)
		enemy.state = EnemySoldier.AiState.ALERT
		if Game.player != null:
			enemy.target = Game.player

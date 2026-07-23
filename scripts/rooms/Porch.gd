class_name Porch
extends RoomBase
## ACT 3-3: PORCH LIGHT — outdoor porch + yard, lawn-quality craft from
## premade trees/fences/structures/streetlights. Capture the porch, burn the depot.

const ROOM_W := 150.0
const ROOM_D := 120.0

var _counterattack_sent := false

func _ready() -> void:
	LostToy.reset_level_counters()
	_setup_nav()
	_build_lighting()
	_build_yard()
	_build_porch_furniture()
	_build_perimeter()
	_build_depot()
	_build_clutter()
	_spawn_units()
	_spawn_pickups_and_toys()
	_bake_navmesh()
	_start_mission()
	Events.unit_died.connect(_on_unit_died)

func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	var env := RoomBase.make_night_environment(Color(0.12, 0.15, 0.22), Color(0.4, 0.48, 0.58), 1.25)
	env.background_color = Color(0.05, 0.07, 0.14)
	env.fog_density = 0.0018
	we.environment = env
	add_child(we)
	add_light_rig(self, Vector3(-48, 28, 10), Color(0.65, 0.75, 1.0), 1.55)
	# Warm porch bulb — the mission's namesake.
	var porch := SpotLight3D.new()
	porch.light_color = Color(1.0, 0.82, 0.5)
	porch.light_energy = 3.4
	porch.spot_range = 50.0
	porch.spot_angle = 40.0
	porch.position = Vector3(-48, 26, 38)
	porch.rotation_degrees = Vector3(-55, -20, 0)
	add_child(porch)
	register_flicker(porch, porch.light_energy, 0.9, 0.06)
	var yard := OmniLight3D.new()
	yard.light_color = Color(0.45, 0.9, 1.0)
	yard.light_energy = 1.6
	yard.omni_range = 36.0
	yard.position = Vector3(30, 10, -20)
	add_child(yard)
	register_flicker(yard, 1.6, 2.0, 0.12)
	var flies := CPUParticles3D.new()
	flies.amount = 24
	flies.lifetime = 7.0
	flies.preprocess = 7.0
	flies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flies.emission_box_extents = Vector3(22, 4, 12)
	flies.gravity = Vector3.ZERO
	flies.initial_velocity_min = 0.25
	flies.initial_velocity_max = 0.9
	flies.scale_amount_min = 0.05
	flies.scale_amount_max = 0.1
	var fm := SphereMesh.new()
	fm.radius = 0.4
	fm.height = 0.8
	fm.material = ToyMaterials.glow(Color(0.95, 0.9, 0.4), 2.0)
	flies.mesh = fm
	flies.position = Vector3(40, 5, 30)
	add_child(flies)

func _build_yard() -> void:
	var grass := ToyMaterials.carpet(Color(0.2, 0.32, 0.18))
	_build_shell(ROOM_W, ROOM_D, 40.0, grass, ToyMaterials.wood(Color(0.4, 0.34, 0.28)))
	# Stone path props via woodplanks as porch steps approach.
	add_prop("woodplanks", Vector3(-40, 0, 28), 90, 5.0)
	add_prop("woodplanks", Vector3(-28, 0, 20), 70, 4.5)
	add_prop("woodplanks", Vector3(-16, 0, 10), 50, 4.5)

func _build_porch_furniture() -> void:
	# Premade porch lounge + watchtower silhouettes.
	add_prop("sofa_small", Vector3(-52, 0, 40), 20, 10.0)
	add_prop("sofa_small", Vector3(-40, 0, 46), -30, 9.0)
	var porch_chair_a := add_landmark("chair", Vector3(-58, 0, 34), 40, 4.5)
	if porch_chair_a != null:
		_setup_chair_collision(porch_chair_a)
	var porch_chair_b := add_landmark("chair", Vector3(-34, 0, 42), -50, 4.5)
	if porch_chair_b != null:
		_setup_chair_collision(porch_chair_b)
	add_prop("streetlight", Vector3(-30, 0, 36), 180, 10.0)
	add_prop("structure_1", Vector3(8, 0, 42), -15, 12.0)
	add_prop("crate", Vector3(-46, 0, 32), 10, 2.8)
	add_prop("crate", Vector3(-43, 0, 34), -25, 2.4)
	add_capture_zone(Vector3(-46, 0, 38), "capture", 5.5, 7.5)
	add_capture_zone(Vector3(10, 0, 36), "capture", 5.5, 7.0)

func _build_perimeter() -> void:
	# Hedge / fence line from premade props only.
	for i in 6:
		var x := -60.0 + i * 22.0
		add_prop("fence_long", Vector3(x, 0, -ROOM_D / 2 + 4), 0, 14.0)
		add_prop("metalfence", Vector3(x + 8, 0, ROOM_D / 2 - 4), 180, 6.0)
	for i in 5:
		var z := -50.0 + i * 22.0
		add_prop("fence", Vector3(-ROOM_W / 2 + 3, 0, z), 90, 7.0)
		add_prop("fence", Vector3(ROOM_W / 2 - 3, 0, z), -90, 7.0)
	add_prop("tree_1", Vector3(50, 0, 28), 15, 14.0)
	add_prop("tree_2", Vector3(58, 0, -10), -40, 13.0)
	add_prop("tree_3", Vector3(-64, 0, -20), 55, 12.0)
	add_prop("tree_4", Vector3(20, 0, -48), 10, 12.0)
	add_prop("tree_1", Vector3(-20, 0, -52), -20, 11.0)

func _build_depot() -> void:
	add_prop("structure_2", Vector3(40, 0, -30), 25, 14.0)
	add_prop("sacktrench", Vector3(24, 0, -18), -20, 8.0)
	add_prop("sacktrench_small", Vector3(36, 0, -8), 40, 5.0)
	add_prop("barrier_large", Vector3(18, 0, -28), 10, 6.0)
	add_prop("watertank", Vector3(56, 0, -40), 0, 10.0)
	for offset in [Vector3(44, 0, -36), Vector3(52, 0, -28), Vector3(34, 0, -40)]:
		var pod := DropPod.new()
		add_child(pod)
		pod.position = offset
	add_barrel(Vector3(30, 0, -24), 0, 2.0)
	add_barrel(Vector3(33, 0, -22), 40, 2.0)
	add_barrel(Vector3(48, 0, -34), -30, 2.2, true)

func _build_clutter() -> void:
	add_prop("tires", Vector3(-10, 0, 18), 30, 4.0)
	add_prop("debris_pile", Vector3(6, 0, -6), 50, 5.0)
	add_prop("pallet", Vector3(-22, 0, 6), 15, 3.4)
	add_prop("cone", Vector3(-36, 0, 24), 0, 1.6)
	add_prop("cone", Vector3(-32, 0, 22), 0, 1.6)
	add_prop("gascan", Vector3(28, 0, -12), 20, 1.6)
	add_prop("cardboard_1", Vector3(-8, 0, 44), -25, 5.0)
	Landmine.spawn(self, Vector3(16, 0, -14))
	Landmine.spawn(self, Vector3(26, 0, -20))
	add_dust_motes(Vector3(0, 4, 0), Vector3(50, 3, 40), 36, Color(0.8, 0.85, 0.95))

func _spawn_units() -> void:
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var green: FactionData = load("res://data/factions/green_army.tres")
	var player := Player.new()
	player.faction = green
	add_child(player)
	player.position = Vector3(-62, 1, 44)
	player.rotation_degrees.y = -40.0
	for pos in [Vector3(-50, 1, 36), Vector3(-38, 1, 44)]:
		var mate := SquadMate.new()
		mate.faction = green
		add_child(mate)
		mate.position = pos
	var patrols := [
		{"route": [Vector3(-20, 1, 20), Vector3(-8, 1, 30)], "mix": ["trooper", "scout"]},
		{"route": [Vector3(8, 1, 30), Vector3(18, 1, 40)], "mix": ["yard_sniper", "trooper"]},
		{"route": [Vector3(30, 1, -16), Vector3(42, 1, -8)], "mix": ["heavy", "yard_sniper"]},
		{"route": [Vector3(48, 1, -32)], "mix": ["yard_sniper", "commando"]},
		{"route": [Vector3(50, 1, 20), Vector3(40, 1, 8)], "mix": ["scout", "yard_sniper"]},
	]
	for patrol in patrols:
		var route: Array = patrol.route
		for i in mini(2, patrol.mix.size()):
			var enemy := EnemySoldier.new()
			enemy.faction = chrome
			enemy.variant = patrol.mix[i]
			var typed: Array[Vector3] = []
			typed.assign(route)
			enemy.patrol_points = typed
			add_child(enemy)
			enemy.position = route[i % route.size()] + Vector3(i * 1.4, 0.5, 0)
	var tank := ToyTank.new()
	add_child(tank)
	tank.position = Vector3(-54, 1, 28)
	tank.rotation_degrees.y = -30.0

func _spawn_pickups_and_toys() -> void:
	scatter_coins(ROOM_W * 0.35, ROOM_D * 0.35)
	for pos in [Vector3(-40, 0, 30), Vector3(12, 0, 20), Vector3(36, 0, -20)]:
		Pickup.spawn_health(self, pos)
	for pos in [Vector3(-16, 0, 8), Vector3(24, 0, 4)]:
		Pickup.spawn_ammo(self, pos)
	spawn_weapon_drop(Vector3(-28, 0, 34), "sniper")
	spawn_weapon_drop(Vector3(20, 0, -10), "scatter")
	for spot in [["Porch Pat", Vector3(-52, 0.5, 42)], ["Glowbug", Vector3(48, 0.5, 26)],
			["Lantern Lou", Vector3(-30, 0.5, 38)], ["Hedge Harry", Vector3(56, 0.5, -8)],
			["Step-Stone Sam", Vector3(-18, 0.5, 12)]]:
		var toy := LostToy.new()
		toy.toy_name = spot[0]
		add_child(toy)
		toy.position = spot[1]

func _start_mission() -> void:
	Missions.start_mission("ACT 3 — PORCH LIGHT")
	Missions.add_objective("capture", "Secure the porch & watchtower (hold the signs)", 2)
	Missions.add_objective("pods", "Destroy the yard depot pods", 3)
	Missions.add_objective("snipers", "Eliminate Chrome yard snipers", 4)
	Missions.marker_provider = func(id: String) -> Vector3:
		match id:
			"capture":
				return nearest_in_group("capture_zones", func(n): return not n.get_meta("captured", false))
			"pods":
				return nearest_in_group("chrome_pods")
			"snipers":
				return nearest_in_group("enemies", func(n): return n is EnemySoldier and n.variant == "yard_sniper")
		return Vector3.INF
	Events.notify.emit("Porch light's on. Take the steps, hold the signs, burn their depot.")

func _on_unit_died(unit: Node) -> void:
	if unit is EnemySoldier and unit.variant == "yard_sniper":
		Missions.progress("snipers")
	if not _counterattack_sent and Missions.is_done("capture") and Missions.is_done("pods"):
		_send_counterattack()

func _send_counterattack() -> void:
	_counterattack_sent = true
	Events.notify.emit("WARNING: Yard snipers falling back through the hedge!")
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var mix := ["yard_sniper", "commando", "yard_sniper", "heavy"]
	for i in 4:
		var enemy := EnemySoldier.new()
		enemy.faction = chrome
		enemy.variant = mix[i]
		var route: Array[Vector3] = [Vector3(40, 1, -20)]
		enemy.patrol_points = route
		add_child(enemy)
		enemy.position = Vector3(60 - i * 4.0, 1, -44)
		enemy.state = EnemySoldier.AiState.ALERT

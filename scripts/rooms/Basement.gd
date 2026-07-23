class_name Basement
extends RoomBase
## ACT 4-1: UNDER THE STAIRS — cramped storage basement built entirely from
## premade industrial props + washer/desk landmarks. Fuel dumps + lost toys.

const ROOM_W := 120.0
const ROOM_D := 100.0
const WALL_H := 28.0

var _counterattack_sent := false

func _ready() -> void:
	LostToy.reset_level_counters()
	_setup_nav()
	_build_lighting()
	_build_shell_and_stairs()
	_build_storage_rows()
	_build_boiler_corner()
	_build_clutter()
	_spawn_units()
	_spawn_pickups_and_toys()
	_bake_navmesh()
	_start_mission()
	Events.unit_died.connect(_on_unit_died)

func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	var env := RoomBase.make_night_environment(Color(0.08, 0.1, 0.14), Color(0.35, 0.38, 0.48), 1.05)
	env.background_color = Color(0.04, 0.05, 0.08)
	env.fog_density = 0.0035
	we.environment = env
	add_child(we)
	add_light_rig(self, Vector3(-30, 40, 0), Color(0.55, 0.65, 0.85), 1.2)
	# Bare bulb over the washer landing.
	var bulb := SpotLight3D.new()
	bulb.light_color = Color(1.0, 0.9, 0.65)
	bulb.light_energy = 2.8
	bulb.spot_range = 45.0
	bulb.spot_angle = 38.0
	bulb.position = Vector3(-30, 24, -20)
	bulb.rotation_degrees = Vector3(-88, 0, 0)
	add_child(bulb)
	register_flicker(bulb, bulb.light_energy, 1.4, 0.12)
	var red := OmniLight3D.new()
	red.light_color = Color(1.0, 0.35, 0.2)
	red.light_energy = 1.5
	red.omni_range = 28.0
	red.position = Vector3(36, 8, 28)
	add_child(red)
	register_flicker(red, 1.5, 2.4, 0.18)

func _build_shell_and_stairs() -> void:
	var concrete := ToyMaterials.concrete(Color(0.42, 0.44, 0.48))
	var wall := ToyMaterials.concrete(Color(0.36, 0.38, 0.42))
	_build_shell(ROOM_W, ROOM_D, WALL_H, concrete, wall)
	# Stair massing from premade woodplanks + pallets — kept clear of the brick walls.
	add_prop("woodplanks", Vector3(-46, 0, 42), 0, 8.0)
	add_prop("pallet", Vector3(-40, 0, 36), 10, 4.0)
	add_prop("pallet", Vector3(-36, 1.8, 30), -15, 4.0)
	add_prop("pallet_broken", Vector3(-32, 0, 24), 40, 3.6)
	add_prop("brickwall", Vector3(-56, 0, 12), 90, 8.0)
	add_prop("brickwall", Vector3(-56, 0, -6), 90, 8.0)

func _build_storage_rows() -> void:
	# Shipping-container aisles.
	add_prop("container_long", Vector3(-10, 0, -10), 0, 16.0)
	add_prop("container_long", Vector3(10, 0, -10), 0, 16.0)
	add_prop("container_small", Vector3(-10, 0, 18), 90, 8.0)
	add_prop("container_small", Vector3(14, 0, 22), -90, 8.0)
	add_prop("trashcontainer", Vector3(40, 0, -30), 20, 8.0)
	add_prop("pipes", Vector3(-20, 0, 30), 0, 7.0)
	add_prop("pipes", Vector3(22, 0, -28), 45, 6.0)
	add_prop("pipes", Vector3(0, 0, 36), -20, 6.5)
	for i in 4:
		add_prop("crate", Vector3(-30 + i * 8, 0, 8), randf() * 40.0, 2.8)
	add_prop("cardboard_1", Vector3(28, 0, 10), -30, 5.5)
	add_prop("cardboard_2", Vector3(-34, 0, -28), 50, 5.0)

func _build_boiler_corner() -> void:
	var washer := add_landmark("washing_machine", Vector3(-36, 0, -28), 90, 14.0)
	if washer != null:
		_setup_solid_hull(washer)
	var desk := add_landmark("desk", Vector3(34, 0, 30), -30, 12.0)
	if desk != null:
		_setup_desk_collision(desk)
	add_prop("gastank", Vector3(40, 0, 20), 25, 4.5)
	add_prop("watertank", Vector3(48, 0, 32), -40, 8.0)
	add_prop("sacktrench_small", Vector3(24, 0, 28), 70, 4.5)
	# Fuel dump cluster — mission barrels.
	add_barrel(Vector3(32, 0, 18), 0, 2.0)
	add_barrel(Vector3(35.5, 0, 20), 55, 2.0)
	add_barrel(Vector3(30, 0, 22), -20, 2.0)
	add_barrel(Vector3(-28, 0, -20), 30, 2.2, true)
	add_barrel(Vector3(-24, 0, -24), -60, 2.2, true)

func _build_clutter() -> void:
	add_prop("tires", Vector3(12, 0, 36), 40, 3.8)
	add_prop("debris_pile", Vector3(-8, 0, -36), 80, 5.5)
	add_prop("barrier_single", Vector3(0, 0, 0), 25, 3.6)
	add_prop("barrier_large", Vector3(18, 0, -36), -40, 5.5)
	add_prop("sign", Vector3(-40, 0, -8), 10, 2.6)
	add_prop("cone", Vector3(-16, 0, 14), 0, 1.5)
	add_prop("gascan", Vector3(36, 0, 14), -15, 1.5)
	add_prop("crate", Vector3(-20, 0, 28), 20, 2.8)
	Landmine.spawn(self, Vector3(6, 0, -20))
	Landmine.spawn(self, Vector3(-6, 0, 16))
	add_dust_motes(Vector3(0, 6, 0), Vector3(40, 5, 35), 40, Color(0.7, 0.72, 0.78))

func _spawn_units() -> void:
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var green: FactionData = load("res://data/factions/green_army.tres")
	var player := Player.new()
	player.faction = green
	add_child(player)
	player.position = Vector3(-50, 1, 42)
	player.rotation_degrees.y = -60.0
	for pos in [Vector3(-42, 1, 34), Vector3(-30, 1, 40)]:
		var mate := SquadMate.new()
		mate.faction = green
		add_child(mate)
		mate.position = pos
	var patrols := [
		{"route": [Vector3(-16, 1, 10), Vector3(0, 1, 16)], "mix": ["trooper", "roomba_drone"]},
		{"route": [Vector3(12, 1, -8), Vector3(-8, 1, -12)], "mix": ["tunnel_heavy", "chrome_ant"]},
		{"route": [Vector3(30, 1, 22), Vector3(40, 1, 28)], "mix": ["tunnel_heavy", "roomba_drone"]},
		{"route": [Vector3(-30, 1, -24), Vector3(-20, 1, -30)], "mix": ["chrome_beetle", "commando"]},
		{"route": [Vector3(20, 1, -30)], "mix": ["chrome_ant", "grenadier"]},
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
			enemy.position = route[i % route.size()] + Vector3(i * 1.6, 0.5, 0)

func _spawn_pickups_and_toys() -> void:
	scatter_coins(ROOM_W * 0.35, ROOM_D * 0.35)
	for pos in [Vector3(-28, 0, 20), Vector3(16, 0, 8), Vector3(34, 0, 26)]:
		Pickup.spawn_health(self, pos)
	for pos in [Vector3(-12, 0, -16), Vector3(8, 0, 24)]:
		Pickup.spawn_parts(self, pos, 5)
	spawn_weapon_drop(Vector3(0, 0, 12), "scatter")
	spawn_weapon_drop(Vector3(32, 0, 24), "marble")
	for spot in [["Dust Bunny", Vector3(-36, 0.5, -26)], ["Sock Puppet", Vector3(34, 0.5, 32)],
			["Cobweb Carl", Vector3(42, 0.5, -28)], ["Fuse Box Fred", Vector3(-48, 0.5, 18)],
			["Lint Lucy", Vector3(10, 0.5, -8)]]:
		var toy := LostToy.new()
		toy.toy_name = spot[0]
		add_child(toy)
		toy.position = spot[1]

func _start_mission() -> void:
	Missions.start_mission("ACT 4 — UNDER THE STAIRS")
	Missions.add_objective("rescue", "Rescue the basement crew  [E]", 2)
	Missions.add_objective("barrels", "Detonate the basement fuel dumps", 5)
	Missions.add_objective("toys", "Recover the lost toys in the dark", 3)
	Missions.add_objective("drones", "Scrap the Chrome roomba drones", 3)
	Missions.marker_provider = func(id: String) -> Vector3:
		match id:
			"rescue":
				return nearest_in_group("green_allies", func(n): return n is SquadMate and n.captive)
			"barrels":
				return nearest_in_group("explosive_barrels")
			"toys":
				return nearest_in_group("lost_toys")
			"drones":
				return nearest_in_group("enemies", func(n): return n is EnemySoldier and n.variant == "roomba_drone")
		return Vector3.INF
	Events.notify.emit("Under the stairs. Fuel, drones, and forgotten toys. Clear the basement.")

func _on_unit_died(unit: Node) -> void:
	if unit is EnemySoldier and unit.variant == "roomba_drone":
		Missions.progress("drones")
	if not _counterattack_sent and Missions.is_done("barrels"):
		_send_counterattack()

func _send_counterattack() -> void:
	_counterattack_sent = true
	Events.notify.emit("WARNING: Tunnel heavies pouring from the container aisle!")
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var mix := ["tunnel_heavy", "roomba_drone", "tunnel_heavy", "roomba_drone"]
	for i in 4:
		var enemy := EnemySoldier.new()
		enemy.faction = chrome
		enemy.variant = mix[i]
		var route: Array[Vector3] = [Vector3(0, 1, -8)]
		enemy.patrol_points = route
		add_child(enemy)
		enemy.position = Vector3(-20 + i * 8.0, 1, -40)
		enemy.state = EnemySoldier.AiState.ALERT

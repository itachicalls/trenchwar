class_name LaundryRoom
extends RoomBase
## ACT 3-2: SPIN CYCLE — the laundry room, final campaign chapter.
## The Chrome Legion wired the washing machine into a doomsday agitator.
## Rescue the laundry crew, destroy the detergent pumps feeding the machine,
## then survive the SPIN CYCLE assault while the room itself shakes.
##
## Landmark: the real washing-machine model as a towering centerpiece.
## Every 30 seconds the machine hits spin cycle: the floor rumbles, foam
## erupts, and everyone standing gets staggered — fight around the rhythm.

const ROOM_W := 130.0
const ROOM_D := 110.0
const WALL_H := 66.0

var _machine_pos := Vector3(0, 0, -ROOM_D / 2 + 24)
var _cycle_timer: Timer
var _rumbling := false
var _foam: CPUParticles3D

func _ready() -> void:
	LostToy.reset_level_counters()
	_setup_nav()
	_build_lighting()
	_build_room_shell()
	_build_machine_tower()
	_build_sock_dunes()
	_build_supply_shelf()
	_build_props()
	_spawn_units()
	_spawn_pickups_and_toys()
	_bake_navmesh()
	_start_mission()
	_start_spin_cycle_clock()
	Events.unit_died.connect(_on_unit_died)

# =========================================================================
#  LIGHTING — one bare ceiling bulb + the machine's ominous drum glow.
# =========================================================================
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	we.environment = RoomBase.make_night_environment(Color(0.1, 0.12, 0.16), Color(0.42, 0.46, 0.56), 1.0)
	add_child(we)
	add_light_rig(self, Vector3(-48, 130, 0), Color(0.7, 0.78, 1.0), 1.3)
	# Bare hanging bulb mid-room, swinging warm light.
	var bulb := OmniLight3D.new()
	bulb.light_color = Color(1.0, 0.85, 0.6)
	bulb.light_energy = 2.2
	bulb.omni_range = 50.0
	bulb.position = Vector3(0, 40, 0)
	add_child(bulb)
	register_flicker(bulb, 2.2, 1.1, 0.12)
	# Sickly Chrome-green glow leaking from the machine drum.
	var drum := OmniLight3D.new()
	drum.light_color = Color(0.45, 1.0, 0.7)
	drum.light_energy = 2.0
	drum.omni_range = 36.0
	drum.position = _machine_pos + Vector3(0, 14, 8)
	add_child(drum)
	register_flicker(drum, 2.0, 2.6, 0.2)

# =========================================================================
#  SHELL — cold tile floor, painted-block walls.
# =========================================================================
func _build_room_shell() -> void:
	var floor_mat := ToyMaterials.concrete(Color(0.58, 0.6, 0.62))
	var wall_mat := ToyMaterials.wallpaper(Color(0.5, 0.56, 0.6), Color(0.45, 0.5, 0.55), 40)
	_build_shell(ROOM_W, ROOM_D, WALL_H, floor_mat, wall_mat)
	# Floor drain (visual) mid-room: the foam pools around it.
	var drain := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 4.0
	dm.bottom_radius = 4.0
	dm.height = 0.12
	drain.mesh = dm
	drain.material_override = ToyMaterials.metal(Color(0.3, 0.32, 0.35), 0.5)
	drain.position = Vector3(8, 0.08, 6)
	add_child(drain)

# =========================================================================
#  THE MACHINE — washing-machine landmark, climbable via detergent boxes.
# =========================================================================
func _build_machine_tower() -> void:
	var machine := add_landmark("washing_machine", _machine_pos, 0, 44.0)
	if machine != null:
		var aabb: AABB = machine.get_meta("aabb")
		# Solid hull + walkable lid.
		_landmark_box(machine, Vector3(0, aabb.size.y * 0.5, 0),
			Vector3(aabb.size.x, aabb.size.y, aabb.size.z))
	else:
		_static_box(_machine_pos + Vector3(0, 20, 0), Vector3(44, 40, 40),
			ToyMaterials.porcelain(Color(0.76, 0.78, 0.8), 0.48))
	# Detergent-box staircase up the east flank: each crate sits half-sunk
	# into the one below so the stack reads as leaning boxes, not floaters.
	for i in 6:
		add_prop("crate", _machine_pos + Vector3(25 + (5 - i) * 4.5, i * 3.3, 14 - i * 2.4),
			8.0 * i, 6.5)
	# Foam eruption emitter parked on the lip of the drum.
	_foam = CPUParticles3D.new()
	_foam.amount = 60
	_foam.lifetime = 2.2
	_foam.one_shot = false
	_foam.emitting = false
	_foam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_foam.emission_sphere_radius = 6.0
	_foam.direction = Vector3(0, 1, 0.3)
	_foam.spread = 55.0
	_foam.initial_velocity_min = 9.0
	_foam.initial_velocity_max = 18.0
	_foam.gravity = Vector3(0, -14, 0)
	_foam.scale_amount_min = 0.5
	_foam.scale_amount_max = 1.4
	var bubble := SphereMesh.new()
	bubble.radius = 0.5
	bubble.height = 1.0
	bubble.material = ToyMaterials.glow(Color(0.85, 0.95, 1.0), 0.9)
	_foam.mesh = bubble
	_foam.position = _machine_pos + Vector3(0, 30, 6)
	add_child(_foam)

# =========================================================================
#  SOCK DUNES — soft rolling cover across the middle of the floor.
# =========================================================================
func _build_sock_dunes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 60660
	var sock_colors := [Color(0.85, 0.82, 0.75), Color(0.4, 0.5, 0.75), Color(0.75, 0.45, 0.45), Color(0.5, 0.65, 0.5)]
	for i in 10:
		var pos := Vector3(rng.randf_range(-46, 46), 1.2, rng.randf_range(-18, 40))
		var c: Color = sock_colors[rng.randi() % sock_colors.size()]
		var dune := _static_box(pos, Vector3(rng.randf_range(7, 12), 2.4, rng.randf_range(3.5, 5.0)),
			ToyMaterials.soft(c), true)
		dune.rotation_degrees.y = rng.randf_range(0, 180)
	# The laundry basket: a wire fort mid-field (fence props in a square).
	for spec in [[Vector3(-30, 0, 8), 0.0], [Vector3(-30, 0, 24), 0.0],
			[Vector3(-38, 0, 16), 90.0], [Vector3(-22, 0, 16), 90.0]]:
		add_prop("metalfence", spec[0], spec[1], 9.0)

# =========================================================================
#  SUPPLY SHELF — east wall shelf with the water heater in the corner.
# =========================================================================
func _build_supply_shelf() -> void:
	var wood := ToyMaterials.wood(Color(0.42, 0.3, 0.2))
	# Low shelf: walkable sniper deck reached from the dryer-box stack.
	_static_box(Vector3(ROOM_W / 2 - 8, 14, 10), Vector3(12, 1.6, 60), wood)
	for z in [-16.0, 34.0]:
		_static_box(Vector3(ROOM_W / 2 - 8, 7, z), Vector3(3, 14, 3), wood)
	# Climb: stacked cardboard boxes (real props).
	add_prop("cardboard_1", Vector3(ROOM_W / 2 - 14, 0, 42), -15.0, 7.0)
	add_prop("cardboard_2", Vector3(ROOM_W / 2 - 9, 4.8, 38), 30.0, 5.5)
	# Corner water heater = the watertank prop, big.
	add_prop("watertank", Vector3(-ROOM_W / 2 + 14, 0, -ROOM_D / 2 + 14), 15.0, 18.0)
	add_prop("pipes", Vector3(-ROOM_W / 2 + 10, 0, -ROOM_D / 2 + 30), 90.0, 7.0)

# =========================================================================
#  PROPS — war clutter from the asset pack; Chrome pumps come in _spawn.
# =========================================================================
func _build_props() -> void:
	add_prop("sacktrench", Vector3(-8, 0, 32), 10.0, 9.0)
	add_prop("sacktrench_small", Vector3(22, 0, 12), -50.0, 4.8)
	add_prop("sacktrench_small", Vector3(-42, 0, -12), 120.0, 4.8)
	add_prop("barrier_large", Vector3(12, 0, -14), 20.0, 5.5)
	add_prop("barrier_single", Vector3(36, 0, 26), -35.0, 3.6)
	add_prop("container_small", Vector3(-52, 0, 30), 45.0, 5.0)
	add_prop("pallet", Vector3(30, 0, -30), 60.0, 3.6)
	add_prop("pallet_broken", Vector3(-16, 0, -30), -20.0, 3.2)
	add_barrel(Vector3(44, 0, -6), 0.0, 2.0)
	add_barrel(Vector3(46.5, 0, -3), 80.0, 2.4, true)
	add_prop("debris_pile", Vector3(-48, 0, -34), 200.0, 5.0)
	add_prop("gascan", Vector3(18, 0, 40), 30.0, 1.8)
	add_prop("woodplanks", Vector3(-6, 0, -44), 95.0, 4.4)
	add_prop("tires", Vector3(52, 0, 40), -25.0, 4.2)
	Landmine.spawn(self, Vector3(-2, 0, -8))
	Landmine.spawn(self, Vector3(26, 0, -2))
	add_dust_motes(Vector3(0, 12, 0), Vector3(ROOM_W / 2 - 10, 10, ROOM_D / 2 - 10), 45, Color(0.8, 0.85, 0.95))

# =========================================================================
#  UNITS
# =========================================================================
func _spawn_units() -> void:
	var green: FactionData = load("res://data/factions/green_army.tres")
	var player := Player.new()
	player.faction = green
	add_child(player)
	player.position = Vector3(-10, 1, ROOM_D / 2 - 10)

	# Laundry crew captives: one in the basket fort, one by the water heater.
	for pos in [Vector3(-30, 1, 16), Vector3(-ROOM_W / 2 + 22, 1, -ROOM_D / 2 + 18)]:
		var mate := SquadMate.new()
		mate.faction = green
		add_child(mate)
		mate.position = pos

	# The three detergent pumps (drop pods) ring the machine.
	for x in [-26.0, 0.0, 26.0]:
		var pod := DropPod.new()
		add_child(pod)
		pod.position = _machine_pos + Vector3(x, 0, 16)

	# Garrison: pump guards + shelf sniper + roaming patrols.
	var patrols := [
		{"route": [Vector3(-20, 1, -20), Vector3(14, 1, -26), Vector3(0, 1, -10)], "mix": ["commando", "trooper"]},
		{"route": [Vector3(28, 1, 20), Vector3(44, 1, -2), Vector3(20, 1, 0)], "mix": ["heavy", "scout"]},
		{"route": [Vector3(-44, 1, 4), Vector3(-24, 1, -8), Vector3(-36, 1, 22)], "mix": ["trooper", "grenadier"]},
	]
	for patrol in patrols:
		var route: Array[Vector3] = []
		route.assign(patrol.route)
		for i in 2:
			_spawn_enemy(patrol.mix[i], route, route[i % route.size()] + Vector3(i * 2.0, 0, 0))
	_spawn_enemy("sniper", [Vector3(ROOM_W / 2 - 8, 17, 10)], Vector3(ROOM_W / 2 - 8, 17.5, 10))
	_spawn_enemy("juggernaut", [_machine_pos + Vector3(0, 1, 20)], _machine_pos + Vector3(0, 1, 20))

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
	for pos in [Vector3(-38, 0, 36), Vector3(24, 0, 30), Vector3(-14, 0, -22), Vector3(40, 0, -24)]:
		Pickup.spawn_health(self, pos)
	for pos in [Vector3(6, 0, 22), Vector3(-30, 0, -24), Vector3(48, 0, 14)]:
		Pickup.spawn_ammo(self, pos)
	for pos in [Vector3(-50, 0, 42), Vector3(52, 0, -34), Vector3(12, 0, -38)]:
		Pickup.spawn_coin(self, pos, 5)
	Pickup.spawn_powerup(self, Vector3(-30, 0, 16), Pickup.Kind.SHIELD)
	Pickup.spawn_powerup(self, Vector3(8, 0, 6), Pickup.Kind.RAPID)
	spawn_weapon_drop(Vector3(20, 0, 18), "soaker")
	spawn_weapon_drop(Vector3(-40, 0, -20), "marble")
	spawn_weapon_drop(Vector3(ROOM_W / 2 - 8, 16, 22), "sniper")
	var toy_spots := [
		["Lefty the Lost Sock", Vector3(-48, 1.0, 44)],
		["Lint Roller Larry", Vector3(ROOM_W / 2 - 8, 16.0, -8)],
		["Bubbles", _machine_pos + Vector3(0, 41, 0)],
		["Peggy the Clothespin", Vector3(-ROOM_W / 2 + 10, 0.6, 40)],
		["Static Cling Carl", Vector3(50, 0.6, -42)],
	]
	for spot in toy_spots:
		var toy := LostToy.new()
		toy.toy_name = spot[0]
		add_child(toy)
		toy.position = spot[1]

# =========================================================================
#  MISSION + SPIN CYCLE
# =========================================================================
func _start_mission() -> void:
	Missions.start_mission("ACT 3 — SPIN CYCLE")
	Missions.add_objective("rescue", "Rescue the laundry crew  [E]", 2)
	Missions.add_objective("pods", "Destroy the detergent pumps", 3)
	Missions.add_objective("counter", "Survive the spin-cycle assault", 14)
	Missions.marker_provider = func(id: String) -> Vector3:
		match id:
			"rescue":
				return nearest_in_group("green_allies", func(n): return n is SquadMate and n.captive)
			"pods":
				return nearest_in_group("chrome_pods")
			"counter":
				return nearest_in_group("enemies")
		return Vector3.INF
	Events.notify.emit("Last stop, soldier. Shut down the machine before the whole house gets agitated.")
	Events.objectives_changed.connect(_check_assault_trigger)

var _assault_started := false
func _check_assault_trigger() -> void:
	if _assault_started or not Missions.is_done("pods"):
		return
	_assault_started = true
	_begin_assault()

## The room's heartbeat: every ~30s the machine rumbles for 4 seconds.
## Cover shakes, foam erupts, and everyone's aim (including yours) suffers.
func _start_spin_cycle_clock() -> void:
	_cycle_timer = Timer.new()
	_cycle_timer.wait_time = 30.0
	_cycle_timer.autostart = true
	add_child(_cycle_timer)
	_cycle_timer.timeout.connect(_run_rumble)

func _run_rumble() -> void:
	if _rumbling or not Game.is_playing():
		return
	_rumbling = true
	Events.notify.emit("SPIN CYCLE! Brace!")
	Sfx.play("shoot_heavy", -2.0, 0.25)
	_foam.emitting = true
	var ticks := Timer.new()
	ticks.wait_time = 0.4
	ticks.autostart = true
	add_child(ticks)
	ticks.timeout.connect(func():
		# Stagger every soldier on the floor a little — toy physics comedy.
		for u in get_tree().get_nodes_in_group("enemies") + [Game.player]:
			if u is CharacterBody3D and is_instance_valid(u) and u.is_on_floor():
				u.velocity += Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3))
		if Game.player != null and is_instance_valid(Game.player):
			Game.player._shake = minf(Game.player._shake + 0.4, 1.6))
	get_tree().create_timer(4.0).timeout.connect(func():
		_rumbling = false
		_foam.emitting = false
		ticks.queue_free())

## Pumps down: the Legion pours out of the wall vent for the final stand.
func _begin_assault() -> void:
	Events.notify.emit("The pumps are down! Chrome forces flooding in — SURVIVE THE SPIN CYCLE!")
	_cycle_timer.wait_time = 18.0   # the machine thrashes harder now
	for wave in 3:
		get_tree().create_timer(3.0 + wave * 16.0).timeout.connect(func():
			if not Game.is_playing():
				return
			Sfx.play("shoot_heavy", -4.0, 0.35)
			var mix := ["commando", "heavy", "grenadier", "trooper", "scout"]
			for i in 5:
				var x := -40.0 + i * 20.0
				_spawn_enemy(mix[i], [Vector3(x, 1, 0)], Vector3(x, 1, -ROOM_D / 2 + 8), true))

func _on_unit_died(unit: Node) -> void:
	if unit is EnemySoldier and unit.has_meta("wave"):
		Missions.progress("counter")

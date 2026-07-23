class_name Bathroom
extends RoomBase
## THE BATHROOM — Act 2, Mission 1: "TUB THUMPING".
##
## Slick porcelain war: the tub is a white canyon fortress with a rubber-duck
## gun emplacement, the toilet is a watchtower, and the sink cabinet hides a
## Chrome listening post. The bath mat is the only soft ground; everything
## else is hard, echoing tile lit by a buzzing vanity strip.

const ROOM_W := 110.0
const ROOM_D := 90.0
const WALL_H := 70.0

var _counterattack_sent := false

func _ready() -> void:
	LostToy.reset_level_counters()
	_setup_nav()
	_build_lighting()
	_build_room_shell()
	_build_tub_fortress()
	_build_toilet_tower()
	_build_sink_cabinet()
	_build_scattered_props()
	_spawn_units()
	_spawn_pickups_and_toys()
	_bake_navmesh()
	_start_mission()
	Events.unit_died.connect(_on_unit_died)

# =========================================================================
#  LIGHTING — cold porcelain bounce, buzzing vanity strip, nightlight plug.
# =========================================================================
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	# White porcelain bounces everything: run the rig dimmer than other rooms.
	we.environment = RoomBase.make_night_environment(Color(0.1, 0.15, 0.19), Color(0.36, 0.42, 0.5), 0.85)
	add_child(we)
	add_light_rig(self, Vector3(-50, 35, 0), Color(0.7, 0.82, 1.0), 0.95)

	# Vanity strip — kept modest so porcelain does not wash to pure white.
	var vanity := SpotLight3D.new()
	vanity.light_color = Color(0.85, 0.95, 0.85)
	vanity.light_energy = 1.15
	vanity.spot_range = 50.0
	vanity.spot_angle = 40.0
	vanity.position = Vector3(-30, 46, -ROOM_D / 2 + 8)
	vanity.rotation_degrees = Vector3(-75, 0, 0)
	add_child(vanity)
	register_flicker(vanity, 1.15, 11.0, 0.1)

	# Warm nightlight plug near the door — the safe corner.
	var plug := OmniLight3D.new()
	plug.light_color = Color(1.0, 0.72, 0.42)
	plug.light_energy = 1.2
	plug.omni_range = 22.0
	plug.position = Vector3(46, 4, 32)
	add_child(plug)
	register_flicker(plug, 1.2, 1.0, 0.06)

	# Cold Chrome glow leaking from under the sink cabinet.
	var depot := OmniLight3D.new()
	depot.light_color = Color(0.4, 0.9, 1.0)
	depot.light_energy = 1.1
	depot.omni_range = 28.0
	depot.position = Vector3(-38, 6, -26)
	add_child(depot)
	register_flicker(depot, 1.1, 2.3, 0.12)

# =========================================================================
#  ROOM SHELL — hexagon-feel tile floor, glossy wainscot walls.
# =========================================================================
func _build_room_shell() -> void:
	# Matte + mid-tone, not glossy near-white: the old floor rendered as a
	# blinding pool near the camera (full-brightness white up close, fading
	# into fog with distance). Darker albedo keeps "white tile" readable
	# without searing the screen.
	var tile := ToyMaterials.floor_mat(Color(0.42, 0.47, 0.53))
	var wall_mat := ToyMaterials.plastic(Color(0.62, 0.72, 0.76), 0.35)
	_build_shell(ROOM_W, ROOM_D, WALL_H, tile, wall_mat)

	# Grout lines: thin dark strips give the floor scale.
	var grout := ToyMaterials.plastic(Color(0.5, 0.55, 0.6), 0.7)
	for ix in range(-4, 5):
		var line := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.5, 0.05, ROOM_D - 4)
		line.mesh = lm
		line.material_override = grout
		line.position = Vector3(ix * 12.0, 0.03, 0)
		add_child(line)
	for iz in range(-3, 4):
		var line2 := MeshInstance3D.new()
		var lm2 := BoxMesh.new()
		lm2.size = Vector3(ROOM_W - 4, 0.05, 0.5)
		line2.mesh = lm2
		line2.material_override = grout
		line2.position = Vector3(0, 0.03, iz * 12.0)
		add_child(line2)

	# Bath mat: the soft island in a sea of tile.
	var mat := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(34, 0.5, 22)
	mat.mesh = mm
	mat.material_override = ToyMaterials.soft(Color(0.45, 0.6, 0.65))
	mat.position = Vector3(8, 0.25, 12)
	add_child(mat)

	# Frosted window, high on the north wall.
	var window := MeshInstance3D.new()
	var wmesh := BoxMesh.new()
	wmesh.size = Vector3(22, 18, 0.5)
	window.mesh = wmesh
	window.material_override = ToyMaterials.glow(Color(0.6, 0.72, 0.95), 0.7)
	window.position = Vector3(20, 44, -ROOM_D / 2 + 1.3)
	add_child(window)

	# Door back to the hallway, east wall.
	var door := MeshInstance3D.new()
	var dmesh := BoxMesh.new()
	dmesh.size = Vector3(16, 34, 0.5)
	door.mesh = dmesh
	door.material_override = ToyMaterials.glow(Color(1.0, 0.75, 0.4), 0.55)
	door.position = Vector3(ROOM_W / 2 - 1.3, 17, 26)
	door.rotation_degrees.y = 90.0
	add_child(door)

# =========================================================================
#  TUB FORTRESS — west side. A porcelain canyon with a duck on the rim.
# =========================================================================
func _build_tub_fortress() -> void:
	var porcelain := ToyMaterials.porcelain()
	var tub := Vector3(-34, 0, 18)
	# Real furniture asset (Kenney bathtub, ~44 x 15.5 x 20.7 at this scale).
	# Colliders form the canyon: walls all around, walkable rim, raised
	# interior floor so soldiers inside are hidden behind the porcelain.
	var tub_rig := add_landmark("bathtub", tub, 0, 44.0)
	if tub_rig != null:
		_setup_bathtub_collision(tub_rig)
	else:
		_static_box(tub + Vector3(0, 7, -14), Vector3(44, 14, 4), porcelain)
		_static_box(tub + Vector3(0, 7, 14), Vector3(44, 14, 4), porcelain)
	# Towel draped over the rim = the ramp up.
	var towel := _static_box(tub + Vector3(14, 7.0, 15.5), Vector3(12, 1.4, 17), ToyMaterials.soft(Color(0.75, 0.55, 0.6)))
	towel.rotation_degrees.x = -42.0

	# The rubber duck: rotund guardian on the rim, pure landmark joy.
	var duck_body := _static_box(tub + Vector3(-8, 18.5, -9.5), Vector3(9, 6, 7), ToyMaterials.plastic(Color(0.98, 0.82, 0.1), 0.15), true)
	duck_body.name = "RubberDuck"
	var duck_head := MeshInstance3D.new()
	var dh := SphereMesh.new()
	dh.radius = 2.6
	dh.height = 5.2
	duck_head.mesh = dh
	duck_head.material_override = ToyMaterials.plastic(Color(0.98, 0.82, 0.1), 0.15)
	duck_head.position = tub + Vector3(-11.5, 23.3, -9.5)
	add_child(duck_head)
	var beak := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.2, 1.4, 2.2)
	beak.mesh = bm
	beak.material_override = ToyMaterials.plastic(Color(0.95, 0.5, 0.1), 0.3)
	beak.position = tub + Vector3(-14.5, 22.7, -9.5)
	add_child(beak)

	# Puddle of "water" on the raised interior floor: glowing, harmless, pretty.
	var puddle := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 7.0
	pm.bottom_radius = 7.0
	pm.height = 0.2
	puddle.mesh = pm
	puddle.material_override = ToyMaterials.glow(Color(0.4, 0.7, 0.95), 0.5)
	puddle.position = tub + Vector3(-6, 3.15, 0)
	add_child(puddle)

# =========================================================================
#  TOILET TOWER — northeast. The porcelain watchtower snipers love.
# =========================================================================
func _build_toilet_tower() -> void:
	var base := Vector3(34, 0, -28)
	# Real furniture asset (toilet, ~13.6 x 26.5 x 22 at this scale).
	# Colliders: pedestal, walkable bowl-seat platform, tank wall at the back.
	var toilet := add_landmark("toilet", base, 0, 22.0)
	if toilet != null:
		# Kenney toilet seat surface sits ~44% up the AABB (old hand boxes
		# topped out at y=16 while the mesh seat is ~11.6 — float gap).
		_setup_toilet_collision(toilet)
	else:
		_static_cylinder(base + Vector3(0, 8, 0), 8.0, 16.0, ToyMaterials.porcelain())
	# Plunger ramp: handle leaning against the bowl = the climb.
	var handle := _static_box(base + Vector3(-10, 6.5, 10), Vector3(1.8, 1.8, 22), ToyMaterials.wood(Color(0.6, 0.42, 0.25)))
	handle.rotation_degrees.x = -36.0
	var cup := _static_box(base + Vector3(-10, 1.2, 19), Vector3(5, 2.4, 5), ToyMaterials.plastic(Color(0.6, 0.25, 0.3), 0.4), true)
	cup.name = "PlungerCup"

# =========================================================================
#  SINK CABINET — northwest. The Chrome listening post hides beneath it.
# =========================================================================
func _build_sink_cabinet() -> void:
	var wood := ToyMaterials.wood(Color(0.42, 0.32, 0.26))
	var top_mat := ToyMaterials.porcelain(Color(0.78, 0.8, 0.83), 0.45)
	var z := -ROOM_D / 2 + 12.0
	# Cabinet on legs: the dark crawlspace under it is the depot.
	for leg in [Vector3(-52, 0, z - 6), Vector3(-14, 0, z - 6), Vector3(-52, 0, z + 6), Vector3(-14, 0, z + 6)]:
		_static_box(leg + Vector3(0, 5, 0), Vector3(3, 10, 3), wood)
	_static_box(Vector3(-33, 17, z), Vector3(44, 14, 18), wood)
	_static_box(Vector3(-33, 25, z), Vector3(48, 2, 20), top_mat)
	# Toothbrush cup + soap on the counter: sniper cover up top.
	_static_box(Vector3(-44, 28.5, z), Vector3(5, 7, 5), ToyMaterials.plastic(Color(0.4, 0.65, 0.85), 0.3), true)
	_static_box(Vector3(-24, 27, z - 4), Vector3(8, 2.4, 5), ToyMaterials.plastic(Color(0.9, 0.6, 0.7), 0.25), true)
	# Hanging towel = the ramp onto the counter.
	var towel := _static_box(Vector3(-10, 13, z + 12), Vector3(10, 1.4, 22), ToyMaterials.soft(Color(0.55, 0.68, 0.6)))
	towel.rotation_degrees.x = -42.0

	# A giant pedestal sink guards the far corner (real model, solid).
	var sink := add_landmark("sink", Vector3(48, 0, -12), -90, 16.0)
	if sink != null:
		_setup_solid_hull(sink, 0.92)

	# The depot: three supply pods in the crawlspace shadow.
	for offset in [Vector3(-44, 0, z), Vector3(-33, 0, z + 3), Vector3(-22, 0, z - 2)]:
		var pod := DropPod.new()
		add_child(pod)
		pod.position = offset

# =========================================================================
#  SCATTERED PROPS — soap-slick cover across the tile.
# =========================================================================
func _build_scattered_props() -> void:
	# Toilet paper roll barricades (fresh + fallen).
	var paper := ToyMaterials.soft(Color(0.92, 0.9, 0.86))
	for spec in [[Vector3(4, 0, -18), 0.0], [Vector3(18, 0, 2), 90.0], [Vector3(-8, 0, 34), 30.0]]:
		var roll := _static_cylinder(spec[0] + Vector3(0, 3.5, 0), 3.5, 6.0, paper)
		roll.rotation_degrees.z = spec[1]
	# Soap bars: low slippery cover.
	for spec in [[Vector3(-12, 0, -2), Color(0.5, 0.85, 0.6)], [Vector3(26, 0, 22), Color(0.9, 0.7, 0.8)]]:
		_static_box(spec[0] + Vector3(0, 1.2, 0), Vector3(8, 2.4, 5), ToyMaterials.plastic(spec[1], 0.2))
	# Asset-pack dressing.
	add_prop("sacktrench", Vector3(24, 0, 34), -25, 7.0)
	add_prop("sacktrench_small", Vector3(-4, 0, 18), 45, 4.5)
	add_prop("barrier_large", Vector3(12, 0, -32), 15, 5.2)
	add_prop("barrier_single", Vector3(-24, 0, 30), -60, 3.6)
	add_prop("crate", Vector3(40, 0, 14), 25, 3.0)
	add_prop("crate", Vector3(43, 0, 17), -30, 2.5)
	add_barrel(Vector3(-2, 0, -36), 0, 1.8)
	add_barrel(Vector3(2, 0, -38.6), 70, 2.2, true)
	add_prop("pipes", Vector3(-48, 0, 8), 30, 4.6)
	add_prop("cardboard_1", Vector3(46, 0, -10), -35, 4.8)
	add_prop("pallet", Vector3(14, 0, 14), 55, 3.2)
	add_prop("cone", Vector3(30, 0, -6), 0, 1.6)
	add_prop("tires", Vector3(-16, 0, -30), 40, 3.4)
	Landmine.spawn(self, Vector3(-30, 0, -14))
	Landmine.spawn(self, Vector3(-40, 0, -20))

	# Steam motes drifting near the tub, dust everywhere else.
	add_dust_motes(Vector3(-34, 10, 18), Vector3(22, 8, 14), 45, Color(0.85, 0.9, 0.95))
	add_dust_motes(Vector3(10, 8, 0), Vector3(30, 7, 24), 28)

# =========================================================================
#  UNITS — scouts skirmish on the slick tile; snipers hold the toilet tower.
# =========================================================================
func _spawn_units() -> void:
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var green: FactionData = load("res://data/factions/green_army.tres")

	# Player spawns by the nightlight plug at the door, southeast.
	var player := Player.new()
	player.faction = green
	add_child(player)
	player.position = Vector3(44, 1, 28)
	player.rotation_degrees.y = 65.0

	# Captives: one inside the tub canyon, one behind the toilet.
	for pos in [Vector3(-38, 5, 18), Vector3(44, 1, -34)]:
		var mate := SquadMate.new()
		mate.faction = green
		add_child(mate)
		mate.position = pos

	var patrols := [
		{"route": [Vector3(8, 1, -8), Vector3(-8, 1, 4), Vector3(12, 1, 10)], "mix": ["scout", "scout"]},
		{"route": [Vector3(-16, 1, -22), Vector3(-36, 1, -12), Vector3(-20, 1, -34)], "mix": ["trooper", "heavy"]},
		{"route": [Vector3(28, 1, -20), Vector3(40, 1, -6), Vector3(20, 1, -30)], "mix": ["trooper", "scout"]},
		{"route": [Vector3(-20, 18, 8.5), Vector3(-44, 18, 8.5)], "mix": ["sniper", "trooper"]},   # tub rim
		{"route": [Vector3(34, 19, -28)], "mix": ["sniper", "heavy"]},                             # toilet seat
		{"route": [Vector3(-6, 1, 30), Vector3(14, 1, 38), Vector3(28, 1, 30)], "mix": ["trooper", "trooper"]},
	]
	for patrol in patrols:
		var route: Array = patrol.route
		for i in mini(2, route.size()):
			var enemy := EnemySoldier.new()
			enemy.faction = chrome
			enemy.variant = patrol.mix[i]
			var typed: Array[Vector3] = []
			typed.assign(route)
			enemy.patrol_points = typed
			add_child(enemy)
			enemy.position = route[i % route.size()] + Vector3((i - 0.5) * 1.8, 0.5, 0)

	# The tank idles on the bath mat.
	var tank := ToyTank.new()
	add_child(tank)
	tank.position = Vector3(16, 1, 20)
	tank.rotation_degrees.y = 30.0

func _spawn_pickups_and_toys() -> void:
	scatter_coins(ROOM_W * 0.4, ROOM_D * 0.4)
	for pos in [Vector3(-20, 0, 12), Vector3(22, 0, -12), Vector3(-34, 3.4, 18), Vector3(34, 16.4, -28), Vector3(6, 0, 40)]:
		Pickup.spawn_health(self, pos)
	for pos in [Vector3(-6, 0, -14), Vector3(36, 0, 4), Vector3(-46, 0, 30)]:
		Pickup.spawn_parts(self, pos, 5)
	for pos in [Vector3(12, 0, -24), Vector3(-28, 0, 6), Vector3(-38, 3.4, 18)]:
		Pickup.spawn_ammo(self, pos)
	spawn_weapon_drop(Vector3(18, 0, 26), "scatter")
	spawn_weapon_drop(Vector3(-14, 0, -30), "sniper")
	var toy_spots := [
		["Quackers", Vector3(-42, 16.4, 8.5)],            # beside the duck
		["Scrubs", Vector3(-33, 26.4, -ROOM_D / 2 + 12)], # on the sink counter
		["Plunger Pete", Vector3(34, 16.6, -28)],          # toilet seat
		["Soapy", Vector3(-12, 0.5, -2)],                  # by the soap bar
		["Mildew Mike", Vector3(-50, 0.5, 38)],            # dark corner
	]
	for spot in toy_spots:
		var toy := LostToy.new()
		toy.toy_name = spot[0]
		add_child(toy)
		toy.position = spot[1]

# =========================================================================
#  MISSION — "TUB THUMPING"
# =========================================================================
func _start_mission() -> void:
	Missions.start_mission("ACT 2 — TUB THUMPING")
	Missions.add_objective("rescue", "Rescue the stranded squad  [E]", 2)
	Missions.add_objective("toys", "Recover the lost bath toys", 3)
	Missions.add_objective("pods", "Destroy the under-sink listening post", 3)
	Missions.marker_provider = func(id: String) -> Vector3:
		match id:
			"rescue":
				return nearest_in_group("green_allies", func(n): return n is SquadMate and n.captive)
			"toys":
				return nearest_in_group("lost_toys")
			"pods":
				return nearest_in_group("chrome_pods")
		return Vector3.INF
	Events.notify.emit("Chrome ears under the sink. Scrub this bathroom clean, soldier.")

func _on_unit_died(_unit: Node) -> void:
	if not _counterattack_sent and Missions.objectives.size() > 2 and Missions.objectives[2].count_done >= 2:
		_send_counterattack()

func _send_counterattack() -> void:
	_counterattack_sent = true
	Events.notify.emit("WARNING: Chrome divers surfacing from the drain!")
	var chrome: FactionData = load("res://data/factions/chrome_legion.tres")
	var mix := ["scout", "scout", "heavy", "trooper", "sniper"]
	for i in 5:
		var enemy := EnemySoldier.new()
		enemy.faction = chrome
		enemy.variant = mix[i]
		var route: Array[Vector3] = [Vector3(-34, 1, 18)]
		enemy.patrol_points = route
		add_child(enemy)
		enemy.position = Vector3(-44 + i * 3.0, 1, 10)
		enemy.state = EnemySoldier.AiState.ALERT
		if Game.player != null:
			enemy.target = Game.player

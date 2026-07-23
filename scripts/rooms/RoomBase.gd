class_name RoomBase
extends Node3D
## Shared foundation for every room battlefield: navmesh region, runtime
## nav baking, and the static-geometry helper all landmark builders use.
## New rooms subclass this and compose their layout in _ready().

var nav_region: NavigationRegion3D
var _flickers: Array[Dictionary] = []

## Shared cinematic night environment.
## Movie-night rules: shadows are deep BLUE, never black; fog is thin and only
## eats far distance; emissives bloom; exposure is generous so toys stay toys.
static func make_night_environment(fog_color: Color, ambient: Color, ambient_energy: float) -> Environment:
	var env := Environment.new()
	# Deep-navy solid background. Empirically bisected: BG_SKY radiance was
	# crushing all lit surfaces to black in 4.3, and rooms barely see the sky.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.35
	# Bloom is a full-screen post pass — phones skip it, emissive materials
	# still read bright without it.
	# Bloom stays on for the toy look; phones keep emissives even if glow is light.
	env.glow_enabled = true
	env.glow_intensity = 0.55 if Game.is_touch() else 0.7
	env.glow_bloom = 0.12 if Game.is_touch() else 0.15
	env.glow_hdr_threshold = 0.9
	# SSAO is a Forward+ desktop effect — Compatibility/web gets nothing from it.
	env.ssao_enabled = not OS.has_feature("web")
	env.ssao_intensity = 0.7
	env.ssao_radius = 0.4
	env.ssao_light_affect = 0.0
	env.ssao_ao_channel_affect = 0.0
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	return env

## Three-point cinematic light rig, the reason characters never go black:
##   KEY  — the shadowed moonlight (given yaw/pitch)
##   FILL — soft opposite-side bounce, no shadows, lifts the dark side
##   RIM  — cool top-back edge light, separates toys from the carpet
static func add_light_rig(parent: Node, key_rotation_deg: Vector3, key_color: Color, key_energy: float) -> DirectionalLight3D:
	# Phones: every DirectionalLight3D is a full extra pass over ALL geometry
	# on the Compatibility renderer, and shadow maps are the single biggest
	# GPU line item. Two lights, no shadows, key brightened to compensate.
	var touch := Game.is_touch()
	var key := DirectionalLight3D.new()
	key.light_color = key_color
	key.light_energy = key_energy * (1.18 if touch else 1.0)
	key.shadow_enabled = not touch
	key.shadow_opacity = 0.72          # shadows stay readable, never pitch black
	key.shadow_blur = 1.6
	key.rotation_degrees = key_rotation_deg
	parent.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.45, 0.5, 0.75)   # blue bounce off the walls
	fill.light_energy = key_energy * 0.45
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-32, key_rotation_deg.y + 165.0, 0)
	parent.add_child(fill)

	if not touch:
		var rim := DirectionalLight3D.new()
		rim.light_color = Color(0.75, 0.85, 1.0)
		rim.light_energy = key_energy * 0.55
		rim.shadow_enabled = false
		rim.rotation_degrees = Vector3(-64, key_rotation_deg.y + 100.0, 0)
		parent.add_child(rim)
	return key

## Register a light to flicker organically (TV static, nightlight breathing).
func register_flicker(light: Light3D, base_energy: float, speed: float, depth: float) -> void:
	_flickers.append({"light": light, "base": base_energy, "speed": speed, "depth": depth, "phase": randf() * TAU})

func _process(_delta: float) -> void:
	if _flickers.is_empty():
		return
	var t := Time.get_ticks_msec() * 0.001
	# Keep every light in the scene — just sleep ones far from the camera so
	# the look is intact when you're there, without paying for the whole map.
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else Vector3.ZERO
	for f in _flickers:
		var light: Light3D = f.light
		if not is_instance_valid(light):
			continue
		var near := cam == null or light.global_position.distance_squared_to(cam_pos) < 4200.0
		light.visible = near
		if not near:
			continue
		var wave: float = 0.6 * sin(t * f.speed + f.phase) + 0.4 * sin(t * f.speed * 2.7 + f.phase * 1.7)
		light.light_energy = f.base * (1.0 + wave * f.depth)

## Position of the node in `group` nearest the player (Vector3.INF when none).
func nearest_in_group(group: String, filter: Callable = Callable()) -> Vector3:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return Vector3.INF
	var best := Vector3.INF
	var best_d := INF
	for node in get_tree().get_nodes_in_group(group):
		if node is Node3D and is_instance_valid(node):
			if filter.is_valid() and not filter.call(node):
				continue
			var d: float = p.global_position.distance_to(node.global_position)
			if d < best_d:
				best_d = d
				best = node.global_position
	return best

func _setup_nav() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)

func _bake_navmesh() -> void:
	var mesh := NavigationMesh.new()
	# Parse physics colliders, not visual meshes: exact match for gameplay
	# collision and works in headless CI where the renderer is a dummy.
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	# The region has no children — geometry lives across the room subtree, so
	# bake from the explicit "nav_geometry" group (_static_box adds to it).
	# Default ROOT_NODE_CHILDREN mode produced an EMPTY navmesh: no AI could
	# path anywhere (squadmates stood still after rescue, patrols never walked).
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = "nav_geometry"
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.6
	mesh.agent_max_climb = 1.2
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	nav_region.navigation_mesh = mesh
	nav_region.bake_navigation_mesh.call_deferred(true)

## Static collidable box with a matching mesh (or a capsule visual if rounded).
func _static_box(pos: Vector3, size: Vector3, mat: Material, rounded: bool = false) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 0b0001
	body.collision_mask = 0
	body.add_to_group("nav_geometry")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	if rounded:
		var cap := CapsuleMesh.new()
		cap.radius = min(size.y, size.z) * 0.5
		cap.height = size.x
		mi.mesh = cap
		mi.rotation_degrees.z = 90.0
		mi.scale = Vector3(1, size.y / min(size.y, size.z), size.z / min(size.y, size.z))
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	body.position = pos
	add_child(body)
	return body

## Furniture landmark: asset visual only, centered at pos, floor at pos.y.
## Pair with _invisible_box colliders shaped to the model.
func add_landmark(land_name: String, pos: Vector3, yaw_deg: float, target_size: float) -> Node3D:
	var rig := ModelLib.build_landmark(land_name, target_size)
	if rig == null:
		return null
	rig.position = pos
	rig.rotation_degrees.y = yaw_deg
	add_child(rig)
	return rig

## Collision box parented to a landmark rig (inherits the rig's rotation).
## Positions are in the rig's local space, so a rotated landmark keeps its
## colliders aligned automatically.
func _landmark_box(rig: Node3D, local_pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 0b0001
	body.collision_mask = 0
	body.add_to_group("nav_geometry")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = local_pos
	rig.add_child(body)

## Thin walkable deck on top of a landmark's visual AABB. Stops the player
## sinking into soft-looking cushions whose hand colliders sat too low.
func _landmark_deck(rig: Node3D, inset: float = 0.92, thickness: float = 1.2) -> void:
	if rig == null or not rig.has_meta("aabb"):
		return
	var aabb: AABB = rig.get_meta("aabb")
	var top_y := aabb.size.y
	var size := Vector3(aabb.size.x * inset, thickness, aabb.size.z * inset)
	_landmark_box(rig, Vector3(0, top_y - thickness * 0.35, 0), size)

## Local-space top of a landmark's scaled AABB (floor of rig is y=0).
func landmark_top_local(rig: Node3D) -> float:
	if rig == null or not rig.has_meta("aabb"):
		return 0.0
	return (rig.get_meta("aabb") as AABB).size.y

## Raycast down onto world geometry; returns Y for an object resting on the hit.
## Call after the node is inside the tree (prefer call_deferred).
static func surface_y_at(world: World3D, xz: Vector3, hover: float = 0.05, probe_up: float = 28.0) -> float:
	if world == null:
		return xz.y + hover
	var from := Vector3(xz.x, xz.y + probe_up, xz.z)
	var to := Vector3(xz.x, xz.y - 60.0, xz.z)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0b0001
	var hit := world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return xz.y + hover
	return hit.position.y + hover

## Visual-only prop (no collision) — pillows, cushions, clutter that must not
## swallow the player when they land on the furniture deck underneath.
func _deco_box(pos: Vector3, size: Vector3, mat: Material, rounded: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if rounded:
		var cap := CapsuleMesh.new()
		cap.radius = minf(size.y, size.z) * 0.5
		cap.height = size.x
		mi.mesh = cap
		mi.rotation_degrees.z = 90.0
		mi.scale = Vector3(1, size.y / minf(size.y, size.z), size.z / minf(size.y, size.z))
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

## Collision-only box: invisible, but AI navigation still respects it.
func _invisible_box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 0b0001
	body.collision_mask = 0
	body.add_to_group("nav_geometry")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	add_child(body)
	return body

## Static collidable upright cylinder (tree trunks, tires, drums, pedestals).
## The capsule visual in _static_box(rounded) stretches badly at pillar
## proportions — this renders true cylinders instead.
func _static_cylinder(pos: Vector3, radius: float, height: float, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 0b0001
	body.collision_mask = 0
	body.add_to_group("nav_geometry")
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	body.add_child(mi)
	body.position = pos
	add_child(body)
	return body

## Asset-pack prop with an auto-generated box collider (from the model AABB).
## Props participate in navmesh baking so AI paths around them.
func add_prop(prop_name: String, pos: Vector3, yaw_deg: float = 0.0, target_size: float = 3.0, collide: bool = true) -> Node3D:
	var rig := ModelLib.build_prop(prop_name, target_size)
	if rig == null:
		return null
	rig.position = pos
	rig.rotation_degrees.y = yaw_deg
	add_child(rig)
	if collide:
		var aabb: AABB = rig.get_meta("aabb")
		var body := StaticBody3D.new()
		body.collision_layer = 0b0001
		body.collision_mask = 0
		body.add_to_group("nav_geometry")
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size
		cs.shape = box
		cs.position = aabb.position + aabb.size * 0.5
		body.add_child(cs)
		rig.add_child(body)
	return rig

## Shootable fuel barrel (prop mesh). Spilled variants tip on their side.
func add_barrel(pos: Vector3, yaw_deg: float = 0.0, target_size: float = 1.8, spilled: bool = false) -> ExplosiveBarrel:
	var barrel := ExplosiveBarrel.new()
	barrel.spilled = spilled
	barrel.target_size = target_size
	add_child(barrel)
	barrel.position = pos
	barrel.rotation_degrees.y = yaw_deg
	return barrel

## Stand-to-capture zone marked with a premade sign prop (no freestyle flags).
## Calls on_captured once when hold completes. Returns the Area3D zone.
func add_capture_zone(pos: Vector3, objective_id: String = "capture",
		hold_seconds: float = 6.0, radius: float = 7.0, on_captured: Callable = Callable()) -> Area3D:
	var zone := Area3D.new()
	zone.collision_layer = 0
	zone.collision_mask = 0b0010
	zone.add_to_group("capture_zones")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 6.0
	cs.shape = cyl
	cs.position.y = 3.0
	zone.add_child(cs)
	add_child(zone)
	zone.global_position = pos
	add_prop("sign", pos + Vector3(0.0, 0.0, 0.0), 15.0, 3.2)
	var label := Label3D.new()
	label.text = "HOLD TO CAPTURE"
	label.font_size = 56
	label.pixel_size = 0.02
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.75, 0.3)
	label.outline_size = 14
	label.position = Vector3(0, 9.5, 0)
	zone.add_child(label)
	var progress := {"v": 0.0, "done": false}
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	zone.add_child(timer)
	timer.timeout.connect(func():
		if progress.done or not Game.is_playing():
			return
		var inside := Game.player != null and is_instance_valid(Game.player) \
			and zone.overlaps_body(Game.player)
		progress.v = clampf(progress.v + (0.1 / hold_seconds if inside else -0.1 / (hold_seconds * 2.0)), 0.0, 1.0)
		if progress.v <= 0.0 and not inside:
			label.text = "HOLD TO CAPTURE"
		elif not progress.done:
			label.text = "CAPTURING  %d%%" % int(progress.v * 100)
		if progress.v >= 1.0:
			progress.done = true
			label.text = "SECURED"
			label.modulate = UiTheme.GREEN
			zone.set_meta("captured", true)
			Sfx.play("objective")
			Missions.progress(objective_id)
			if on_captured.is_valid():
				on_captured.call()
	)
	return zone

## Drifting ambient dust motes: cheap, huge atmosphere win in dark rooms.
func add_dust_motes(center: Vector3, extents: Vector3, amount: int = 40, color: Color = Color(0.9, 0.85, 0.7)) -> void:
	var motes := CPUParticles3D.new()
	# Ambience is the first thing to thin out on weak GPUs.
	motes.amount = amount
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = extents
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.1
	motes.initial_velocity_max = 0.5
	motes.direction = Vector3(0.3, -0.15, 0.1)
	motes.scale_amount_min = 0.02
	motes.scale_amount_max = 0.055
	var mm := BoxMesh.new()
	mm.size = Vector3.ONE
	mm.material = ToyMaterials.glow(color, 0.7)
	motes.mesh = mm
	motes.position = center
	add_child(motes)

## Floating supply crate that swaps the player's weapon on touch — the pickup
## is a loaner, it doesn't change the saved Armory loadout. Respawns later.
func spawn_weapon_drop(pos: Vector3, weapon_id: String, respawn_after: float = 30.0) -> void:
	var info: Dictionary = Game.weapon_info(weapon_id)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 0b0010
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.6
	cs.shape = sphere
	area.add_child(cs)
	add_child(area)
	area.global_position = pos + Vector3.UP * 1.2

	var vis := Node3D.new()
	area.add_child(vis)
	var crate := ModelLib.build_prop("crate", 1.8)
	if crate != null:
		crate.position.y = -0.9
		vis.add_child(crate)
	# Weapon-colored beacon ring + light so drops read across the room.
	var wd: WeaponData = load(info.path)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.0
	tm.outer_radius = 1.2
	ring.mesh = tm
	ring.material_override = ToyMaterials.glow(wd.projectile_color, 2.4)
	ring.position.y = -1.0
	vis.add_child(ring)
	if not Game.low_gfx():
		var light := OmniLight3D.new()
		light.light_color = wd.projectile_color
		light.light_energy = 1.6
		light.omni_range = 7.0
		vis.add_child(light)

	var taken := {"v": false}
	area.body_entered.connect(func(body: Node3D):
		if taken.v or body != Game.player:
			return
		taken.v = true
		Game.player.equip_weapon_data(wd, info.gun)
		Events.notify.emit("PICKED UP: %s" % wd.display_name.to_upper())
		Sfx.play("pickup")
		vis.visible = false
		area.set_deferred("monitoring", false)
		get_tree().create_timer(respawn_after).timeout.connect(func():
			if is_instance_valid(area):
				taken.v = false
				vis.visible = true
				area.set_deferred("monitoring", true)))

	# Idle motion: slow spin + bob.
	var tw := area.create_tween().set_loops()
	tw.tween_property(vis, "position:y", 0.35, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(vis, "position:y", -0.35, 1.2).set_trans(Tween.TRANS_SINE)
	var spin := area.create_tween().set_loops()
	spin.tween_property(vis, "rotation:y", TAU, 4.0).from(0.0)

## Deterministic coin trails across the floor: exploration always pays.
## Call from _spawn_pickups with the room's walkable half-extents.
func scatter_coins(half_w: float, half_d: float, clusters: int = 6) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(get_script().resource_path) + 7
	for c in clusters:
		var center := Vector3(rng.randf_range(-half_w, half_w), 0, rng.randf_range(-half_d, half_d))
		var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		for i in rng.randi_range(3, 5):
			Pickup.spawn_coin(self, center + dir * i * 1.6, 1)
		# Every other trail ends at a jetpack gas can — flight fuel is
		# common enough that exploring keeps the tank topped up.
		if c % 2 == 1:
			Pickup.spawn_fuel(self, center + dir * 8.0)

## Four walls + floor for a room shell.
func _build_shell(width: float, depth: float, wall_height: float, floor_mat: Material, wall_mat: Material) -> void:
	_static_box(Vector3(0, -0.5, 0), Vector3(width, 1.0, depth), floor_mat)
	_static_box(Vector3(0, wall_height / 2, -depth / 2), Vector3(width, wall_height, 2), wall_mat)
	_static_box(Vector3(0, wall_height / 2, depth / 2), Vector3(width, wall_height, 2), wall_mat)
	_static_box(Vector3(-width / 2, wall_height / 2, 0), Vector3(2, wall_height, depth), wall_mat)
	_static_box(Vector3(width / 2, wall_height / 2, 0), Vector3(2, wall_height, depth), wall_mat)
	_add_wall_trim(width, depth, wall_height)

## Baseboards + crown molding + outlet plates: the small-scale trim that sells
## "you are two inches tall in a real house".
func _add_wall_trim(width: float, depth: float, wall_height: float, trim_color: Color = Color(0.88, 0.86, 0.8)) -> void:
	var trim := ToyMaterials.plastic(trim_color, 0.45)
	var w2 := width / 2.0 - 1.0
	var d2 := depth / 2.0 - 1.0
	# Baseboards (visual only — flush against walls, no gameplay impact).
	for spec in [
		[Vector3(0, 1.5, -d2 - 0.4), Vector3(width, 3.0, 1.2)],
		[Vector3(0, 1.5, d2 + 0.4), Vector3(width, 3.0, 1.2)],
		[Vector3(-w2 - 0.4, 1.5, 0), Vector3(1.2, 3.0, depth)],
		[Vector3(w2 + 0.4, 1.5, 0), Vector3(1.2, 3.0, depth)],
	]:
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[1]
		board.mesh = bm
		board.material_override = trim
		board.position = spec[0]
		add_child(board)
	# Crown molding at the ceiling line.
	for spec in [
		[Vector3(0, wall_height - 1.0, -d2 - 0.4), Vector3(width, 2.0, 1.0)],
		[Vector3(0, wall_height - 1.0, d2 + 0.4), Vector3(width, 2.0, 1.0)],
		[Vector3(-w2 - 0.4, wall_height - 1.0, 0), Vector3(1.0, 2.0, depth)],
		[Vector3(w2 + 0.4, wall_height - 1.0, 0), Vector3(1.0, 2.0, depth)],
	]:
		var crown := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = spec[1]
		crown.mesh = cm
		crown.material_override = trim
		crown.position = spec[0]
		add_child(crown)
	# A couple of giant outlet plates low on the walls.
	var outlet_mat := ToyMaterials.plastic(Color(0.92, 0.9, 0.84), 0.35)
	var socket_mat := ToyMaterials.plastic(Color(0.2, 0.2, 0.22))
	for spec in [[Vector3(width * 0.22, 5.5, -d2 - 0.2), 0.0], [Vector3(-w2 - 0.2, 5.5, depth * 0.18), 90.0]]:
		var plate := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(4.4, 6.6, 0.5)
		plate.mesh = pm
		plate.material_override = outlet_mat
		plate.position = spec[0]
		plate.rotation_degrees.y = spec[1]
		add_child(plate)
		for dy in [1.4, -1.4]:
			var socket := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(1.6, 2.2, 0.3)
			socket.mesh = sm
			socket.material_override = socket_mat
			socket.position = spec[0] + Vector3(0, dy, 0.15 if spec[1] == 0.0 else 0.0) + (Vector3(0.15, 0, 0) if spec[1] != 0.0 else Vector3.ZERO)
			socket.rotation_degrees.y = spec[1]
			add_child(socket)

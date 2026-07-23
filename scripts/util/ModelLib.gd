class_name ModelLib
extends Object
## Loads and prepares the CC0 asset-pack models (Quaternius "Toon Shooter Game
## Kit" characters/guns + Quaternius tank, all Public Domain). Every function
## returns a ready-to-parent Node3D and falls back to the procedural
## ToyBodyBuilder primitives if an asset is missing, so the game never breaks.

const SOLDIER_SCENE := "res://assets/models/soldier.gltf"
const ENEMY_SCENE := "res://assets/models/enemy.gltf"
const TANK_SCENE := "res://assets/models/tank.glb"

## Every weapon prop that ships attached to the character skeletons.
const CHARACTER_GUNS := ["AK", "GrenadeLauncher", "Knife_1", "Knife_2", "Pistol",
	"Revolver", "Revolver_Small", "RocketLauncher", "ShortCannon", "Shotgun",
	"Shovel", "SMG", "Sniper", "Sniper_2"]

## Builds an animated character rig for a faction.
## The returned rig exposes the same contract as ToyBodyBuilder:
## child "WeaponMount" node + meta "anim" -> AnimationPlayer (may be absent).
## gun: which in-hand weapon prop stays visible; scale_mult/tint distinguish
## enemy variants (scout/heavy) without extra models.
## skin_path: optional override glTF (e.g. enemy_yard / enemy_tunnel). Empty = default faction mold.
static func build_character(faction: FactionData, is_chrome: bool = false,
		gun: String = "", tint: Color = Color.WHITE, scale_mult: float = 1.0,
		skin_path: String = "") -> Node3D:
	var path := skin_path
	if path == "" or not ResourceLoader.exists(path):
		path = ENEMY_SCENE if is_chrome else SOLDIER_SCENE
	if not ResourceLoader.exists(path):
		return ToyBodyBuilder.build_soldier(faction, is_chrome)
	var rig := Node3D.new()
	rig.name = "BodyRig"
	var model: Node3D = (load(path) as PackedScene).instantiate()
	# glTF characters face +Z; the game's forward convention is -Z.
	model.rotation.y = PI
	model.scale = Vector3.ONE * 0.85 * scale_mult
	rig.add_child(model)

	if gun == "":
		gun = "SMG" if is_chrome else "AK"
	_keep_only_gun(model, gun)
	if is_chrome:
		_tint(model, Color(0.55, 0.62, 0.78) * tint, 0.55, 0.3)
	else:
		_tint(model, Color(0.78, 1.0, 0.72) * tint, 0.0, 0.8)

	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if anim != null:
		for a_name in anim.get_animation_list():
			if a_name in ["Idle", "Idle_Shoot", "Run", "Run_Gun", "Run_Shoot", "Walk", "Walk_Shoot", "Duck", "Jump_Idle"]:
				anim.get_animation(a_name).loop_mode = Animation.LOOP_LINEAR
		anim.play("Idle")
		rig.set_meta("anim", anim)

	var mount := Node3D.new()
	mount.name = "WeaponMount"
	mount.position = Vector3(0.3, 0.75, -0.5)
	rig.add_child(mount)
	return rig

## Premade landmark/prop driven as a unit body (roomba drones, etc.).
## Special names insect_beetle / insect_ant build toy chrome pest molds.
static func build_prop_unit(prop_or_land: String, target_size: float, tint: Color = Color.WHITE) -> Node3D:
	var rig: Node3D = null
	if prop_or_land.begins_with("insect_"):
		rig = build_insect(prop_or_land.trim_prefix("insect_"), target_size, tint)
	else:
		rig = build_landmark(prop_or_land, target_size)
		if rig == null:
			rig = build_prop(prop_or_land, target_size)
		if rig == null:
			rig = Node3D.new()
		elif tint != Color.WHITE:
			_tint(rig, tint, 0.2, 0.5)
	rig.name = "BodyRig"
	var mount := Node3D.new()
	mount.name = "WeaponMount"
	mount.position = Vector3(0.0, target_size * 0.35, -target_size * 0.25)
	rig.add_child(mount)
	return rig

## Toy-scale chrome pests (beetle / ant). Low-poly capsule molds so levels can
## sprinkle insect variety beside humanoid Chrome without a separate pack.
static func build_insect(kind: String, target_size: float, tint: Color = Color.WHITE) -> Node3D:
	var rig := Node3D.new()
	var shell := ToyMaterials.metal(Color(0.45, 0.55, 0.62) * tint, 0.28)
	var dark := ToyMaterials.metal(Color(0.22, 0.26, 0.32) * tint, 0.45)
	var s := target_size
	var is_ant := kind == "ant"
	# Abdomen
	var abdomen := MeshInstance3D.new()
	var am := CapsuleMesh.new()
	am.radius = s * (0.22 if is_ant else 0.28)
	am.height = s * (0.55 if is_ant else 0.62)
	abdomen.mesh = am
	abdomen.material_override = shell
	abdomen.position = Vector3(0, s * 0.28, s * (0.12 if is_ant else 0.08))
	abdomen.rotation_degrees.x = 90.0
	rig.add_child(abdomen)
	# Thorax
	var thorax := MeshInstance3D.new()
	var tm := SphereMesh.new()
	tm.radius = s * (0.18 if is_ant else 0.22)
	tm.height = s * (0.32 if is_ant else 0.4)
	thorax.mesh = tm
	thorax.material_override = shell
	thorax.position = Vector3(0, s * 0.3, s * (-0.12 if is_ant else -0.16))
	rig.add_child(thorax)
	# Head
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = s * (0.14 if is_ant else 0.16)
	hm.height = s * (0.26 if is_ant else 0.3)
	head.mesh = hm
	head.material_override = dark
	head.position = Vector3(0, s * 0.32, s * (-0.32 if is_ant else -0.38))
	rig.add_child(head)
	# Mandibles / horn
	for side in [-1.0, 1.0]:
		var fang := MeshInstance3D.new()
		var fm := CapsuleMesh.new()
		fm.radius = s * 0.03
		fm.height = s * (0.22 if is_ant else 0.18)
		fang.mesh = fm
		fang.material_override = dark
		fang.position = Vector3(side * s * 0.08, s * 0.28, s * (-0.44 if is_ant else -0.5))
		fang.rotation_degrees = Vector3(55.0, side * 25.0, 0)
		rig.add_child(fang)
	# Six legs
	for i in 3:
		for side in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var lm := CapsuleMesh.new()
			lm.radius = s * 0.035
			lm.height = s * 0.42
			leg.mesh = lm
			leg.material_override = dark
			var z := s * (-0.2 + i * 0.16)
			leg.position = Vector3(side * s * 0.22, s * 0.12, z)
			leg.rotation_degrees = Vector3(15.0, 0, side * (55.0 + i * 8.0))
			rig.add_child(leg)
	if is_ant:
		# Ant antennae
		for side in [-1.0, 1.0]:
			var feeler := MeshInstance3D.new()
			var atm := CapsuleMesh.new()
			atm.radius = s * 0.02
			atm.height = s * 0.35
			feeler.mesh = atm
			feeler.material_override = dark
			feeler.position = Vector3(side * s * 0.06, s * 0.48, s * -0.36)
			feeler.rotation_degrees = Vector3(-35.0, side * 20.0, 0)
			rig.add_child(feeler)
	else:
		# Beetle wing-case ridge
		var ridge := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(s * 0.04, s * 0.08, s * 0.45)
		ridge.mesh = rm
		ridge.material_override = dark
		ridge.position = Vector3(0, s * 0.42, s * 0.06)
		rig.add_child(ridge)
	var mount_y := s * 0.55
	rig.set_meta("insect_height", mount_y)
	return rig

## Environment prop (crates, sandbag trenches, barriers...). Uniformly scaled
## so its largest horizontal dimension equals target_size, resting on y=0.
## Meta "aabb" holds the scaled AABB for collision generation.
static func build_prop(prop_name: String, target_size: float = 2.0) -> Node3D:
	var path := "res://assets/models/prop_%s.gltf" % prop_name
	if not ResourceLoader.exists(path):
		return null
	var rig := Node3D.new()
	rig.name = "Prop_" + prop_name
	var model: Node3D = (load(path) as PackedScene).instantiate()
	rig.add_child(model)
	var aabb := _merged_aabb(model)
	# Scale by the largest dimension INCLUDING height: tall-thin props
	# (streetlights, signs) must not explode to skyscraper size just because
	# their footprint is small.
	var s := target_size / maxf(maxf(aabb.size.x, aabb.size.z), maxf(aabb.size.y, 0.001))
	model.scale = Vector3.ONE * s
	model.position.y = -aabb.position.y * s
	var scaled := AABB(Vector3(aabb.position.x * s, 0.0, aabb.position.z * s), aabb.size * s)
	rig.set_meta("aabb", scaled)
	_dampen_bright_materials(model)
	return rig

## Large furniture landmark (bed, tub, car...). Scaled so the largest
## HORIZONTAL dimension equals target_size, centered on x/z, floor at y=0.
## No collider is generated: landmarks need hand-shaped collision (walkable
## tops, crawlspaces) that a single AABB box would ruin — rooms build their
## own invisible boxes against meta "aabb".
static func build_landmark(land_name: String, target_size: float) -> Node3D:
	var path := "res://assets/models/land_%s.glb" % land_name
	if not ResourceLoader.exists(path):
		path = "res://assets/models/prop_%s.gltf" % land_name
	if not ResourceLoader.exists(path):
		return null
	var rig := Node3D.new()
	rig.name = "Land_" + land_name
	var model: Node3D = (load(path) as PackedScene).instantiate()
	rig.add_child(model)
	var aabb := _merged_aabb(model)
	var s := target_size / maxf(maxf(aabb.size.x, aabb.size.z), 0.001)
	model.scale = Vector3.ONE * s
	var center := aabb.position + aabb.size * 0.5
	model.position = Vector3(-center.x * s, -aabb.position.y * s, -center.z * s)
	rig.set_meta("aabb", AABB(
		Vector3(-aabb.size.x * s * 0.5, 0.0, -aabb.size.z * s * 0.5),
		aabb.size * s))
	# Kenney toilets/tubs/sinks ship near-white albedo that blooms under our
	# night exposure — tone them so porcelain reads solid, not lit.
	_dampen_bright_materials(model)
	return rig

	## Military toy jetpack: olive twin tanks with muted amber trim rings,
## chrome thruster bells, and a slim armored spine plate.
## Meta "nozzles" holds the two exhaust Node3Ds for flame FX.
static func build_jetpack() -> Node3D:
	var rig := Node3D.new()
	rig.name = "Jetpack"
	var olive := ToyMaterials.plastic(Color(0.32, 0.4, 0.22), 0.35)
	var olive_dark := ToyMaterials.plastic(Color(0.2, 0.25, 0.15), 0.5)
	var chrome := ToyMaterials.metal(Color(0.62, 0.66, 0.7), 0.35)
	var amber := ToyMaterials.plastic(Color(0.72, 0.5, 0.18), 0.45)

	# Armored spine plate hugging the back.
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.4, 0.52, 0.08)
	plate.mesh = pm
	plate.material_override = olive_dark
	rig.add_child(plate)

	var nozzles: Array = []
	for side in [-1.0, 1.0]:
		# Main tank: olive body...
		var tank := MeshInstance3D.new()
		var tm := CapsuleMesh.new()
		tm.radius = 0.105
		tm.height = 0.56
		tank.mesh = tm
		tank.material_override = olive
		tank.position = Vector3(side * 0.13, 0.0, 0.1)
		tank.rotation_degrees.z = side * -4.0   # slight outward cant
		rig.add_child(tank)
		# ...amber trim ring near the top...
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.108
		rm.bottom_radius = 0.108
		rm.height = 0.05
		ring.mesh = rm
		ring.material_override = amber
		ring.position = tank.position + Vector3(side * -0.012, 0.16, 0)
		ring.rotation_degrees.z = side * -4.0
		rig.add_child(ring)
		# ...chrome dome cap...
		var cap := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 0.1
		cm.height = 0.15
		cap.mesh = cm
		cap.material_override = chrome
		cap.position = tank.position + Vector3(side * -0.02, 0.28, 0)
		rig.add_child(cap)
		# ...chrome thruster bell with a warm (non-blooming) throat...
		var bell := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.055
		bm.bottom_radius = 0.095
		bm.height = 0.13
		bell.mesh = bm
		bell.material_override = chrome
		bell.position = tank.position + Vector3(side * 0.015, -0.33, 0)
		rig.add_child(bell)
		var throat := MeshInstance3D.new()
		var thm := CylinderMesh.new()
		thm.top_radius = 0.04
		thm.bottom_radius = 0.075
		thm.height = 0.05
		throat.mesh = thm
		throat.material_override = ToyMaterials.plastic(Color(0.85, 0.4, 0.12), 0.35)
		throat.position = bell.position + Vector3(0, -0.05, 0)
		rig.add_child(throat)
		var nozzle := Node3D.new()
		nozzle.position = bell.position + Vector3(0, -0.1, 0)
		rig.add_child(nozzle)
		nozzles.append(nozzle)

	# Cross-brace between tanks (no yellow prism fin — that read as broken geo).
	var brace := MeshInstance3D.new()
	var bm2 := BoxMesh.new()
	bm2.size = Vector3(0.22, 0.06, 0.05)
	brace.mesh = bm2
	brace.material_override = olive_dark
	brace.position = Vector3(0, 0.02, 0.14)
	rig.add_child(brace)
	# Fuel gauge: recessed matte slot, not an emissive lamp.
	var window := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.1, 0.14, 0.02)
	window.mesh = wm
	window.material_override = ToyMaterials.plastic(Color(0.55, 0.42, 0.18), 0.55)
	window.position = Vector3(0, -0.14, 0.05)
	rig.add_child(window)
	rig.set_meta("nozzles", nozzles)
	return rig

## Straps the jetpack onto a built character rig's Torso BONE so it rides
## every animation (aim lean, run bob, jump tuck) glued to the back instead
## of floating at a fixed offset. Returns the pack (meta "nozzles" inside).
static func attach_jetpack(rig: Node3D) -> Node3D:
	var pack := build_jetpack()
	var skel: Skeleton3D = rig.find_child("Skeleton3D", true, false)
	if skel != null and skel.find_bone("Torso") >= 0:
		var att := BoneAttachment3D.new()
		skel.add_child(att)
		att.bone_name = "Torso"
		att.add_child(pack)
		# Bone space: tuned against the aim/run poses in the jetpack lab.
		pack.position = Vector3(0, 0.08, -0.2)
		pack.rotation_degrees = Vector3(-6, 180, 0)
	else:
		# Fallback primitive rigs have no skeleton; pin behind the torso.
		pack.position = Vector3(0, 0.95, 0.3)
		rig.add_child(pack)
	return pack

## Standalone gun prop (weapon pickups, menu dressing).
static func build_gun(gun_name: String) -> Node3D:
	var path := "res://assets/models/gun_%s.gltf" % gun_name
	if not ResourceLoader.exists(path):
		return null
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.rotation.y = PI
	model.scale = Vector3.ONE * 0.5
	return model

## Tank body visual. Returns a rig with meta "turret" (Node3D pivot holding the
## turret + gun meshes) so the vehicle script can aim it, or null if missing.
static func build_tank(target_length: float = 3.4) -> Node3D:
	if not ResourceLoader.exists(TANK_SCENE):
		return null
	var rig := Node3D.new()
	rig.name = "TankRig"
	var model: Node3D = (load(TANK_SCENE) as PackedScene).instantiate()
	# This tank model's hull runs along +X; rotate so the gun faces -Z.
	model.rotation.y = -PI / 2.0
	rig.add_child(model)

	var aabb := _merged_aabb(model)
	var length: float = maxf(aabb.size.x, maxf(aabb.size.z, 0.001))
	var s := target_length / length
	model.scale = Vector3.ONE * s
	# Sit the hull on y=0.
	model.position.y = -aabb.position.y * s

	_tint(model, Color(0.75, 1.0, 0.68), 0.0, 0.8)

	# Reparent turret + gun meshes under a pivot so the turret can track aim.
	var turret_pivot := Node3D.new()
	turret_pivot.name = "TurretPivot"
	var turret_mesh: Node3D = model.find_child("Tank_Turret", true, false)
	var gun_mesh: Node3D = model.find_child("Tank_Gun", true, false)
	if turret_mesh != null:
		var parent := turret_mesh.get_parent()
		parent.add_child(turret_pivot)
		turret_pivot.position = turret_mesh.position
		for m in [turret_mesh, gun_mesh]:
			if m != null:
				var xf: Transform3D = m.transform
				m.get_parent().remove_child(m)
				turret_pivot.add_child(m)
				m.transform = Transform3D(xf.basis, xf.origin - turret_pivot.position)
		rig.set_meta("turret", turret_pivot)
	return rig

## Hides all bone-attached weapon props except the requested one.
## Public: swap which in-hand gun prop is visible on a built rig.
static func set_gun(rig: Node, keep: String) -> void:
	_keep_only_gun(rig, keep)

static func _keep_only_gun(model: Node, keep: String) -> void:
	for gun_name in CHARACTER_GUNS:
		var attachment: Node = model.find_child(gun_name.replace(".", "_"), true, false)
		if attachment is BoneAttachment3D:
			attachment.visible = (gun_name == keep)

## Soften imported near-white surfaces so they do not bloom like lamps under
## night exposure + glow. Applies to EVERY level (landmarks + props), not just
## new rooms. Hot whites get a full porcelain override (kills white textures).
static func _dampen_bright_materials(model: Node) -> void:
	var enamel := ToyMaterials.porcelain(Color(0.48, 0.52, 0.55), 0.62)
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				if mat == null:
					continue
				# Compatibility/web can surface BaseMaterial3D subclasses.
				if mat is BaseMaterial3D:
					var src := mat as BaseMaterial3D
					var c: Color = src.albedo_color
					# White textures often leave albedo_color at WHITE — treat
					# textured near-white the same as solid hot white.
					var mx := maxf(c.r, maxf(c.g, c.b))
					var mn := minf(c.r, minf(c.g, c.b))
					var chroma := mx - mn
					var lum := c.get_luminance()
					var hot := (chroma < 0.22 and lum > 0.62) \
						or (src.albedo_texture != null and chroma < 0.25 and lum > 0.55)
					if hot:
						mi.set_surface_override_material(i, enamel)
						continue
					var soft_emit := src.emission_enabled and src.emission.get_luminance() > 0.7 \
						and src.emission_energy_multiplier > 0.0 and src.emission_energy_multiplier < 0.4
					if soft_emit:
						var m: BaseMaterial3D = src.duplicate()
						m.emission_enabled = false
						mi.set_surface_override_material(i, m)
		stack.append_array(n.get_children())

## Multiplies a tint into every material (textures keep their detail) and
## nudges metallic/roughness so factions read as different plastics.
static func _tint(model: Node, tint: Color, metallic: float, roughness: float) -> void:
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			for i in n.mesh.get_surface_count():
				var mat: Material = n.get_active_material(i)
				if mat is StandardMaterial3D:
					var m: StandardMaterial3D = mat.duplicate()
					m.albedo_color = m.albedo_color * tint
					m.metallic = maxf(m.metallic, metallic)
					m.roughness = minf(m.roughness, roughness)
					m.rim_enabled = true
					m.rim = 0.4
					m.rim_tint = 0.6
					n.set_surface_override_material(i, m)
		stack.append_array(n.get_children())

static func _merged_aabb(node: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	var stack: Array = [[node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var xf: Transform3D = entry[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var ab: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
			if first:
				merged = ab
				first = false
			else:
				merged = merged.merge(ab)
		for child in n.get_children():
			stack.append([child, xf])
	return merged

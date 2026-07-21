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
static func build_character(faction: FactionData, is_chrome: bool = false,
		gun: String = "", tint: Color = Color.WHITE, scale_mult: float = 1.0) -> Node3D:
	var path := ENEMY_SCENE if is_chrome else SOLDIER_SCENE
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
	return rig

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
static func _keep_only_gun(model: Node, keep: String) -> void:
	for gun_name in CHARACTER_GUNS:
		var attachment: Node = model.find_child(gun_name.replace(".", "_"), true, false)
		if attachment is BoneAttachment3D:
			attachment.visible = (gun_name == keep)

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

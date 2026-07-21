class_name ToyBodyBuilder
extends Object
## Procedural low-poly toy soldier built from primitives, standing on the classic
## oval army-man base. Serves as the placeholder character until rigged asset-pack
## models (KayKit/Quaternius) are dropped in — the returned rig exposes the same
## attachment points either way: "Head", "WeaponMount", "Base".

static func build_soldier(faction: FactionData, is_chrome: bool = false) -> Node3D:
	var rig := Node3D.new()
	rig.name = "BodyRig"
	var mat: StandardMaterial3D
	if is_chrome:
		mat = ToyMaterials.metal(faction.primary_color, 0.2)
	else:
		mat = ToyMaterials.plastic(faction.primary_color)
	var dark := ToyMaterials.plastic(faction.secondary_color)

	# Classic molded oval base — instantly reads as "army man".
	var base := _mesh(rig, _cyl(0.42, 0.42, 0.07), mat)
	base.name = "Base"
	base.scale = Vector3(1.0, 1.0, 0.72)
	base.position.y = 0.035

	# Legs (single molded block, like a real plastic soldier).
	_mesh(rig, _box(0.34, 0.5, 0.22), mat).position.y = 0.32

	# Torso.
	var torso := _mesh(rig, _box(0.42, 0.42, 0.28), mat)
	torso.position.y = 0.78

	# Chest strap / vest detail.
	_mesh(rig, _box(0.44, 0.12, 0.30), dark).position.y = 0.84

	# Glowing faction emblem on the chest — instant team readability at night.
	var emblem := _mesh(rig, _box(0.11, 0.11, 0.03), ToyMaterials.glow(faction.accent_color, 1.3))
	emblem.position = Vector3(-0.11, 0.95, -0.155)

	# Backpack.
	_mesh(rig, _box(0.3, 0.3, 0.14), dark).position = Vector3(0, 0.82, 0.2)

	# Arms angled forward holding the weapon.
	var arm_l := _mesh(rig, _box(0.11, 0.4, 0.11), mat)
	arm_l.position = Vector3(-0.25, 0.85, -0.12)
	arm_l.rotation_degrees = Vector3(-55, 0, 10)
	var arm_r := _mesh(rig, _box(0.11, 0.4, 0.11), mat)
	arm_r.position = Vector3(0.25, 0.85, -0.12)
	arm_r.rotation_degrees = Vector3(-55, 0, -10)

	# Head + helmet.
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 1.13
	rig.add_child(head)
	var face := _mesh(head, _sphere(0.16), mat)
	face.position.y = 0.0
	var helmet := _mesh(head, _sphere(0.2), dark)
	helmet.position.y = 0.06
	helmet.scale = Vector3(1.0, 0.72, 1.0)
	if is_chrome:
		var visor := _mesh(head, _box(0.24, 0.07, 0.05), ToyMaterials.glow(faction.accent_color, 3.0))
		visor.position = Vector3(0, 0.0, -0.15)

	# Weapon mount: the Weapon node (and its visual) parents here.
	var mount := Node3D.new()
	mount.name = "WeaponMount"
	mount.position = Vector3(0.12, 0.88, -0.34)
	rig.add_child(mount)
	_mesh(mount, _box(0.07, 0.09, 0.55), dark).position.z = -0.1  # rifle body
	_mesh(mount, _box(0.05, 0.05, 0.16), dark).position = Vector3(0, -0.09, 0.12)  # grip

	return rig

## Tiny plush bear for collectibles / Plush Alliance placeholders.
static func build_plush_bear(color: Color = Color(0.72, 0.5, 0.32)) -> Node3D:
	var rig := Node3D.new()
	var mat := ToyMaterials.soft(color)
	_mesh(rig, _sphere(0.3), mat).position.y = 0.3            # body
	_mesh(rig, _sphere(0.2), mat).position.y = 0.65           # head
	for side in [-1.0, 1.0]:
		var ear := _mesh(rig, _sphere(0.08), mat)
		ear.position = Vector3(side * 0.14, 0.82, 0)
		var arm := _mesh(rig, _sphere(0.1), mat)
		arm.position = Vector3(side * 0.3, 0.35, 0)
	_mesh(rig, _sphere(0.07), ToyMaterials.plastic(Color(0.15, 0.1, 0.08))).position = Vector3(0, 0.62, -0.17)
	return rig

# --- primitive helpers ---

static func _mesh(parent: Node, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi

static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s

static func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 14
	return c

class_name Landmine
extends Area3D
## Live hazard: blinks lazily until something steps on it (or shoots it),
## then beeps, flashes fast, and detonates with radius falloff damage.
## Hurts everyone — enemies can be herded across their own minefields.

const BLAST_RADIUS := 4.5
const MAX_DAMAGE := 55.0
const FUSE_TIME := 0.55

var _armed := true
var _lamp: MeshInstance3D
var _lamp_mat: StandardMaterial3D
var _light: OmniLight3D
var _t := randf() * TAU
var _fusing := false

static func spawn(root: Node, pos: Vector3) -> void:
	var m := Landmine.new()
	root.add_child(m)
	m.global_position = pos

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0b1110   # units | vehicles | squadmates
	monitoring = true
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 1.1
	shape.shape = s
	shape.position.y = 0.4
	add_child(shape)

	var rig := ModelLib.build_prop("landmine", 1.3)
	if rig != null:
		add_child(rig)
	else:
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.55
		cyl.bottom_radius = 0.65
		cyl.height = 0.22
		disc.mesh = cyl
		disc.position.y = 0.11
		disc.material_override = ToyMaterials.metal(Color(0.35, 0.36, 0.32), 0.5)
		add_child(disc)

	# Blinking arm lamp — the "do not step here" warning players learn to read.
	_lamp = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.09
	lm.height = 0.18
	_lamp.mesh = lm
	_lamp_mat = ToyMaterials.glow(Color(1.0, 0.15, 0.1), 2.0)
	_lamp.material_override = _lamp_mat
	_lamp.position.y = 0.34
	add_child(_lamp)
	if not Game.low_gfx():
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.2, 0.1)
		_light.omni_range = 2.5
		_light.light_energy = 0.0
		_light.position.y = 0.6
		add_child(_light)

	# Bullet-sensitive plate: shooting a mine detonates it from safety.
	var plate := MineBody.new()
	plate.mine = self
	add_child(plate)

	body_entered.connect(_on_trip)

func _process(delta: float) -> void:
	_t += delta * (16.0 if _fusing else 2.2)
	var pulse := maxf(sin(_t), 0.0)
	_lamp_mat.emission_energy_multiplier = 0.6 + pulse * (6.0 if _fusing else 2.4)
	if _light != null:
		_light.light_energy = pulse * (2.5 if _fusing else 0.7)

func _on_trip(_body: Node3D) -> void:
	trigger()

func trigger() -> void:
	if not _armed:
		return
	_armed = false
	_fusing = true
	Sfx.play_at("click", global_position, 0.0)
	get_tree().create_timer(FUSE_TIME).timeout.connect(_explode)

func _explode() -> void:
	if not is_instance_valid(self):
		return
	var pos := global_position + Vector3.UP * 0.3
	Fx.explosion(self, pos, 3.4)
	Fx.ring_pulse(self, global_position + Vector3.UP * 0.1, Color(1.0, 0.5, 0.2), 4.0, 0.3)
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BLAST_RADIUS
	params.shape = sphere
	params.transform = Transform3D(Basis(), pos)
	params.collision_mask = 0b1110
	for result in get_world_3d().direct_space_state.intersect_shape(params, 16):
		var body: Object = result.collider
		if body is Node3D and body.has_method("take_damage"):
			var falloff: float = 1.0 - clampf(pos.distance_to(body.global_position) / BLAST_RADIUS, 0.0, 0.8)
			body.take_damage(MAX_DAMAGE * falloff)
	queue_free()

## Solid plate so projectiles (world mask) can hit and detonate the mine.
class MineBody:
	extends StaticBody3D
	var mine: Landmine

	func _ready() -> void:
		collision_layer = 0b0001
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.6
		cyl.height = 0.3
		shape.shape = cyl
		shape.position.y = 0.15
		add_child(shape)

	func take_damage(_amount: float, _attacker: Node = null) -> void:
		mine.trigger()

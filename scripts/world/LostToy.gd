class_name LostToy
extends Area3D
## Collection system: lost toys hidden across the room. Finding all of them
## is tracked per-level and feeds the collection meta-game later.

static var total_in_level: int = 0
static var found_in_level: int = 0

@export var toy_name: String = "Lost Bear"

static func reset_level_counters() -> void:
	total_in_level = 0
	found_in_level = 0

func _ready() -> void:
	total_in_level += 1
	collision_layer = 0
	collision_mask = 0b0010
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.2
	shape.shape = sphere
	add_child(shape)
	var rig := ToyBodyBuilder.build_plush_bear(Color(randf_range(0.5, 0.9), randf_range(0.35, 0.6), randf_range(0.2, 0.45)))
	rig.scale = Vector3.ONE * 0.8
	add_child(rig)
	var gold := Color(1.0, 0.85, 0.45)
	if not Game.low_gfx():
		var light := OmniLight3D.new()
		light.light_color = gold
		light.light_energy = 0.7
		light.omni_range = 3.0
		light.position.y = 0.8
		add_child(light)
	# Golden beacon beam + halo ring so hidden toys glint from across the room.
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.35
	cyl.height = 7.0
	beam.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(gold, 0.09)
	mat.emission_enabled = true
	mat.emission = gold
	mat.emission_energy_multiplier = 0.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = mat
	beam.position.y = 3.5
	add_child(beam)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.72
	torus.rings = 20
	torus.ring_segments = 5
	ring.mesh = torus
	ring.material_override = ToyMaterials.glow(gold, 1.3)
	ring.scale.y = 0.25
	ring.position.y = 0.05
	add_child(ring)
	var sparks := CPUParticles3D.new()
	sparks.amount = 8
	sparks.lifetime = 1.5
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.6
	sparks.direction = Vector3.UP
	sparks.spread = 15.0
	sparks.initial_velocity_min = 0.3
	sparks.initial_velocity_max = 0.8
	sparks.gravity = Vector3.ZERO
	sparks.scale_amount_min = 0.02
	sparks.scale_amount_max = 0.06
	var sm := BoxMesh.new()
	sm.size = Vector3.ONE
	sm.material = ToyMaterials.glow(gold, 2.2)
	sparks.mesh = sm
	sparks.position.y = 0.5
	add_child(sparks)
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	rotate_y(delta * 0.7)

func _on_body_entered(body: Node3D) -> void:
	if body != Game.player:
		return
	found_in_level += 1
	Events.collectible_found.emit(toy_name, found_in_level, total_in_level)
	Events.notify.emit("Lost toy found: %s  (%d/%d)" % [toy_name, found_in_level, total_in_level])
	Fx.ring_pulse(self, global_position, Color(1.0, 0.85, 0.45), 2.5, 0.6)
	Sfx.play("objective", -4.0)
	Game.plastic_parts += 10
	queue_free()

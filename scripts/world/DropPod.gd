class_name DropPod
extends StaticBody3D
## Chrome Legion beachhead pod — destructible objective structure.
## Reuses the Health component like every other damageable thing.

@export var pod_health: float = 200.0
var health: Health
var _beacon: OmniLight3D = null
var _blink_phase := randf() * TAU

func _ready() -> void:
	collision_layer = 0b0010   # damageable like a unit
	add_to_group("chrome_pods")
	health = Health.new()
	health.setup(pod_health)
	health.died.connect(_on_destroyed)
	add_child(health)

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.3
	cyl.height = 3.0
	shape.shape = cyl
	shape.position.y = 1.5
	add_child(shape)

	var chrome := ToyMaterials.metal(Color(0.7, 0.75, 0.85), 0.2)
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 1.3
	capsule.height = 3.4
	body.mesh = capsule
	body.material_override = chrome
	body.position.y = 1.5
	add_child(body)
	for i in 3:
		var fin := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.15, 1.2, 0.9)
		fin.mesh = box
		fin.material_override = chrome
		fin.position = Vector3(0, 0.6, 0).rotated(Vector3.UP, i * TAU / 3.0) + Vector3(sin(i * TAU / 3.0), 0.6, cos(i * TAU / 3.0)) * 1.15
		fin.rotation.y = i * TAU / 3.0
		add_child(fin)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	core.mesh = sphere
	core.material_override = ToyMaterials.glow(Color(0.4, 0.95, 1.0), 3.0)
	core.position.y = 1.6
	add_child(core)
	# Blinking warning beacon on top.
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(0.3, 0.9, 1.0)
	_beacon.light_energy = 1.2
	_beacon.omni_range = 8.0
	_beacon.position.y = 3.4
	add_child(_beacon)
	var beacon_bulb := MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.18
	bulb.height = 0.36
	beacon_bulb.mesh = bulb
	beacon_bulb.material_override = ToyMaterials.glow(Color(0.3, 0.9, 1.0), 2.5)
	beacon_bulb.position.y = 3.3
	add_child(beacon_bulb)

func _process(_delta: float) -> void:
	if _beacon != null:
		_beacon.light_energy = 0.4 + 1.4 * maxf(0.0, sin(Time.get_ticks_msec() * 0.005 + _blink_phase))

func take_damage(amount: float, attacker: Node = null) -> void:
	health.damage(amount, attacker)
	Fx.impact(self, global_position + Vector3.UP * 1.5, Color(0.4, 0.95, 1.0))

func is_dead() -> bool:
	return health.dead

func _on_destroyed(_attacker: Node) -> void:
	Fx.explosion(self, global_position + Vector3.UP * 1.5, 3.0)
	Pickup.spawn_parts(get_tree().current_scene, global_position, 10)
	Missions.progress("pods")
	queue_free()

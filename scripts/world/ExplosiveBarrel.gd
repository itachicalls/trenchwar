class_name ExplosiveBarrel
extends StaticBody3D
## Flammable fuel barrel — uses the barrel / barrel_spilled prop meshes.
## Shoot it (or catch splash from another blast) and it cooks off.

const BLAST_RADIUS := 5.5
const BLAST_DAMAGE := 70.0
const HP := 35.0

@export var spilled := false
@export var target_size := 1.8

var health: Health
var _exploded := false

func _ready() -> void:
	collision_layer = 0b0001   # world: blocks movement; projectiles still hit
	collision_mask = 0
	add_to_group("nav_geometry")
	add_to_group("explosive_barrels")

	health = Health.new()
	health.setup(HP)
	health.died.connect(_on_destroyed)
	add_child(health)

	var prop_name := "barrel_spilled" if spilled else "barrel"
	var size := target_size if not spilled else maxf(target_size, 2.2)
	var rig := ModelLib.build_prop(prop_name, size)
	if rig != null:
		add_child(rig)
		var aabb: AABB = rig.get_meta("aabb")
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size
		cs.shape = box
		cs.position = aabb.position + aabb.size * 0.5
		add_child(cs)
	else:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.55
		cyl.height = 1.4
		cs.shape = cyl
		cs.position.y = 0.7
		add_child(cs)

func take_damage(amount: float, attacker: Node = null) -> void:
	if _exploded:
		return
	health.damage(amount, attacker)
	Fx.impact(self, global_position + Vector3.UP * 0.9, Color(1.0, 0.45, 0.15))

func is_dead() -> bool:
	return health.dead or _exploded

func _on_destroyed(_attacker: Node) -> void:
	_detonate()

func _detonate() -> void:
	if _exploded:
		return
	_exploded = true
	var origin := global_position + Vector3.UP * 0.8
	var root := get_tree().current_scene
	Fx.ordnance_explosion(root if root != null else self, origin, BLAST_RADIUS)
	Sfx.play_at("explosion", origin, -2.0)
	Pickup.spawn_parts(root if root != null else self, origin, 4)
	Missions.progress("barrels")

	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BLAST_RADIUS
	params.shape = sphere
	params.transform = Transform3D(Basis(), origin)
	params.collision_mask = 0b1111
	params.exclude = [get_rid()]
	for result in get_world_3d().direct_space_state.intersect_shape(params, 24):
		var body: Object = result.collider
		if body == null or body == self:
			continue
		var falloff: float = 1.0 - clampf(origin.distance_to((body as Node3D).global_position) / BLAST_RADIUS, 0.0, 0.85)
		var dmg := BLAST_DAMAGE * falloff
		if body.has_method("take_damage"):
			body.take_damage(dmg, self)
		if body is CharacterBody3D:
			var away: Vector3 = body.global_position - origin
			away.y = 0.0
			if away.length_squared() > 0.01:
				body.velocity += away.normalized() * 12.0 * falloff + Vector3.UP * 8.0 * falloff
	queue_free()

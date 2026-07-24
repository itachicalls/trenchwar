class_name Projectile
extends Node3D
## Fast projectile using swept raycasts (never tunnels through thin toy walls).
## Spawned by Weapon; carries a WeaponData reference for damage/splash rules.

var velocity: Vector3
var data: WeaponData
var shooter: Node3D
var faction: FactionData
var life: float = 3.0
var damage_scale: float = 1.0
var _exclude: Array[RID] = []

static func spawn(from: Node3D, origin: Vector3, direction: Vector3, weapon_data: WeaponData, shooter_unit: Node3D, shooter_faction: FactionData, damage_mult: float = 1.0) -> void:
	var p := Projectile.new()
	p.data = weapon_data
	p.shooter = shooter_unit
	p.faction = shooter_faction
	p.damage_scale = damage_mult
	p.velocity = direction.normalized() * weapon_data.projectile_speed
	from.get_tree().current_scene.add_child(p)
	p.global_position = origin
	p.look_at(origin + direction, Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
	p._build_visual()

func _build_visual() -> void:
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.045 * data.projectile_scale
	capsule.height = 0.28 * data.projectile_scale
	mesh.mesh = capsule
	mesh.rotation_degrees.x = 90.0
	# Web/mobile: plastic pellet — glow + additive tails multiply draw cost.
	if Game.low_gfx():
		mesh.material_override = ToyMaterials.plastic(data.projectile_color, 0.35)
		add_child(mesh)
		return
	mesh.material_override = ToyMaterials.glow(data.projectile_color, 2.5)
	add_child(mesh)
	# Additive tracer tail so shots read at a distance.
	var tail := MeshInstance3D.new()
	var tail_mesh := CapsuleMesh.new()
	tail_mesh.radius = 0.03 * data.projectile_scale
	tail_mesh.height = 1.1 * data.projectile_scale
	tail.mesh = tail_mesh
	tail.rotation_degrees.x = 90.0
	tail.position.z = 0.55 * data.projectile_scale
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(data.projectile_color, 0.35)
	mat.emission_enabled = true
	mat.emission = data.projectile_color
	mat.emission_energy_multiplier = 1.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tail.material_override = mat
	add_child(tail)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	velocity.y -= 2.0 * delta   # slight toy-physics arc
	var motion := velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + motion)
	query.collision_mask = 0b1111   # world | units | vehicles | squadmates
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		_exclude_rid(shooter.get_rid())
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	# Friendlies never block shots: your squad walking through the line of
	# fire must not eat your bullets. Re-cast past them and keep flying.
	while not hit.is_empty() and _is_friendly(hit.collider):
		_exclude_rid((hit.collider as CollisionObject3D).get_rid())
		query.exclude = _exclude
		hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position += motion
		return
	_on_hit(hit.collider, hit.position)

func _exclude_rid(rid: RID) -> void:
	if not _exclude.has(rid):
		_exclude.append(rid)

func _is_friendly(collider: Object) -> bool:
	return collider is CollisionObject3D and faction != null and "faction" in collider \
		and collider.faction != null and not faction.hostile_to(collider.faction)

var _pierced := 0

func _on_hit(collider: Object, point: Vector3) -> void:
	if data.explosive_radius > 0.0:
		_explode(point)
	else:
		_apply_damage(collider, data.damage * damage_scale)
		Fx.impact(self, point, data.projectile_color)
		Sfx.play_at("hit", point, -8.0)
		# Sniper-style rounds drill straight through soft targets and keep
		# flying — walls (StaticBody3D) always stop them.
		if _pierced < data.pierce and collider is CollisionObject3D and not collider is StaticBody3D:
			_pierced += 1
			_exclude_rid((collider as CollisionObject3D).get_rid())
			return
	queue_free()

func _explode(point: Vector3) -> void:
	if data.explosive_radius >= 3.5:
		Fx.ordnance_explosion(self, point, data.explosive_radius)
	else:
		Fx.explosion(self, point, data.explosive_radius)
	var params := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = data.explosive_radius
	params.shape = sphere
	params.transform = Transform3D(Basis(), point)
	params.collision_mask = 0b1110
	for result in get_world_3d().direct_space_state.intersect_shape(params, 16):
		var body: Object = result.collider
		if body is Node3D:
			var falloff: float = 1.0 - clampf(point.distance_to(body.global_position) / data.explosive_radius, 0.0, 0.85)
			_apply_damage(body, data.damage * damage_scale * falloff)
			# Blast wave hurls survivors away from ground zero.
			if body is CharacterBody3D and body != shooter:
				var away: Vector3 = body.global_position - point
				away.y = 0.0
				body.velocity += away.normalized() * 10.0 * falloff + Vector3.UP * 7.0 * falloff

func _apply_damage(target: Object, amount: float) -> void:
	if target == null or not target.has_method("take_damage"):
		return
	# No friendly fire between toys of the same army.
	if faction != null and "faction" in target and target.faction != null and not faction.hostile_to(target.faction):
		return
	target.take_damage(amount, shooter)
	# Style damage: heavy rubber-band/foam rounds slap toys backwards.
	if data.knockback > 0.0 and target is CharacterBody3D and target != shooter:
		var dir := velocity.normalized()
		dir.y = 0.0
		target.velocity += dir * data.knockback + Vector3.UP * data.knockback * 0.3
	if is_instance_valid(shooter) and shooter == Game.player:
		var killed: bool = target.has_method("is_dead") and target.is_dead()
		Events.hit_confirmed.emit(killed)
		if target is Node3D:
			Fx.damage_number(self, target.global_position + Vector3.UP * 1.5, amount, killed)

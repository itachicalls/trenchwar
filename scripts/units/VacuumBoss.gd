class_name VacuumBoss
extends CharacterBody3D
## BOSS: THE VACUUM — a roaring household leviathan.
##
## Its body is armored (bullets spark off), but three glowing FILTER PODS on its
## back are exposed. Destroy all three to kill the motor.
##
## Behaviour phases by filters remaining:
##   3 — slow patrol sweeps across the rug, suction cone in front
##   2 — actively hunts the player, faster
##   1 — enraged: fastest, periodic charge attacks
##
## The suction cone drags the player toward the intake; getting swallowed
## deals heavy damage and spits you out the side. Fighting it means circling
## behind while it targets your squadmates — squad orders matter here.

signal defeated

const CONTACT_DAMAGE := 25.0
const SUCTION_RANGE := 16.0
const SUCTION_HALF_ANGLE := 0.6   # radians
const CHARGE_WINDUP := 0.9
const CHARGE_SPEED := 13.0
const CHARGE_MAX_TIME := 1.5

var filters_alive := 3
var _target: Node3D = null
var _phase_speed := 2.6
var _charge_timer := 0.0
var _charging := false
var _windup := 0.0
var _charge_life := 0.0
var _charge_dir := Vector3.ZERO
var _roar_timer := 0.0
var _sweep_goal := Vector3.ZERO
var _sweep_timer := 0.0
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO
var _body_tilt: Node3D
var _brush: MeshInstance3D
var _eye_mat: StandardMaterial3D

func _ready() -> void:
	collision_layer = 0b0100
	collision_mask = 0b0011
	add_to_group("enemies")   # squadmates will shoot at it

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 4.4
	cyl.height = 3.2
	shape.shape = cyl
	shape.position.y = 1.6
	add_child(shape)
	_build_visual()
	_last_pos = global_position
	_pick_sweep_goal()

func _build_visual() -> void:
	_body_tilt = Node3D.new()
	add_child(_body_tilt)
	var dark := ToyMaterials.plastic(Color(0.15, 0.13, 0.16))

	# Real robot-vacuum model (giant hunting Roomba).
	var rig := ModelLib.build_landmark("roomba", 9.4)
	if rig != null:
		_body_tilt.add_child(rig)
	else:
		var canister := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 4.2
		cm.bottom_radius = 4.6
		cm.height = 2.6
		canister.mesh = cm
		canister.material_override = ToyMaterials.plastic(Color(0.2, 0.19, 0.22), 0.35)
		canister.position.y = 1.3
		_body_tilt.add_child(canister)

	# Menacing eye visor strip across the front.
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(3.4, 0.5, 0.3)
	visor.mesh = vm
	_eye_mat = ToyMaterials.glow(Color(1.0, 0.12, 0.08), 2.8).duplicate()
	visor.material_override = _eye_mat
	visor.position = Vector3(0, 1.7, -4.25)
	_body_tilt.add_child(visor)

	# Spinning brush skirt under the front lip.
	_brush = MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.4
	bm.bottom_radius = 1.6
	bm.height = 0.5
	_brush.mesh = bm
	_brush.material_override = dark
	_brush.position = Vector3(0, 0.3, -3.0)
	_body_tilt.add_child(_brush)
	for i in 6:
		var bristle := MeshInstance3D.new()
		var brm := BoxMesh.new()
		brm.size = Vector3(0.16, 0.2, 1.3)
		bristle.mesh = brm
		bristle.material_override = ToyMaterials.plastic(Color(0.75, 0.7, 0.3), 0.7)
		bristle.rotation_degrees.y = i * 60.0
		bristle.position = Vector3(sin(deg_to_rad(i * 60.0)) * 1.0, -0.2, cos(deg_to_rad(i * 60.0)) * 1.0)
		_brush.add_child(bristle)

	# Hungry under-glow (it hovers over its own red shadow).
	var glow := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(11.0, 11.0)
	glow.mesh = gq
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = ToyMaterials.radial_glow_tex(Color(1.0, 0.2, 0.1, 0.5))
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.material_override = gm
	glow.rotation_degrees.x = -90.0
	glow.position.y = 0.12
	_body_tilt.add_child(glow)

	# Kicked-up dust trail behind the skirt.
	var dust := CPUParticles3D.new()
	dust.amount = 14
	dust.lifetime = 0.9
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(3.4, 0.1, 0.4)
	dust.position = Vector3(0, 0.3, 4.0)
	dust.direction = Vector3(0, 1, 1)
	dust.spread = 30.0
	dust.initial_velocity_min = 0.8
	dust.initial_velocity_max = 1.8
	dust.gravity = Vector3(0, -1.5, 0)
	dust.scale_amount_min = 0.06
	dust.scale_amount_max = 0.16
	var dm := BoxMesh.new()
	dm.size = Vector3.ONE
	dm.material = ToyMaterials.soft(Color(0.5, 0.46, 0.42))
	dust.mesh = dm
	_body_tilt.add_child(dust)

	# The three filter pods — actual damageable children, on the top deck.
	for i in 3:
		var pod := VacuumFilter.new()
		pod.boss = self
		_body_tilt.add_child(pod)
		pod.position = Vector3(sin(i * TAU / 3.0) * 1.9, 3.1, cos(i * TAU / 3.0) * 1.9)

func filter_destroyed() -> void:
	filters_alive -= 1
	Fx.explosion(self, global_position + Vector3.UP * 5.0, 3.0)
	Missions.progress("filters")
	match filters_alive:
		2:
			_phase_speed = 3.6
			Events.notify.emit("Filter destroyed! The Vacuum is angry — it's hunting YOU now.")
		1:
			_phase_speed = 4.4
			Events.notify.emit("One filter left! WATCH OUT — it charges!")
		0:
			_die()

func _die() -> void:
	Events.notify.emit("THE VACUUM IS DOWN. The living room falls silent.")
	Fx.explosion(self, global_position + Vector3.UP * 3.0, 6.0)
	Fx.plastic_shatter(self, global_position + Vector3.UP * 2.0, Color(0.55, 0.12, 0.5))
	Sfx.play("explosion")
	defeated.emit()
	Events.unit_died.emit(self)
	queue_free()

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	_target = Game.player if Game.player != null and is_instance_valid(Game.player) else null
	# Vacuums can't reach players riding the couch plateau; sweep below instead.
	var target_reachable := _target != null and _target.global_position.y < global_position.y + 3.0

	_roar_timer -= delta
	if _roar_timer <= 0.0:
		_roar_timer = 0.45
		Sfx.play_at("engine", global_position, -2.0)

	if _windup > 0.0:
		_do_windup(delta)
	elif _charging:
		_do_charge(delta)
	elif filters_alive <= 1 and target_reachable:
		_charge_timer -= delta
		if _charge_timer <= 0.0:
			_start_windup()
		else:
			_do_hunt(delta, target_reachable)
	elif filters_alive <= 2 and target_reachable:
		_do_hunt(delta, target_reachable)
	else:
		_do_sweep(delta)
	move_and_slide()
	_apply_suction(delta)
	_check_contact()
	_detect_stuck(delta)
	# Menace wobble + spinning brush + pulsing eye.
	_body_tilt.rotation.z = sin(Time.get_ticks_msec() * 0.004) * 0.02
	if _brush != null:
		_brush.rotate_y(delta * (26.0 if _charging else 9.0))
	if _eye_mat != null:
		_eye_mat.emission_energy_multiplier = 2.2 + sin(Time.get_ticks_msec() * 0.008) * 0.8 + (3.0 if _windup > 0.0 else 0.0)

## Grinding against furniture is the #1 "erratic" read — detect no-progress
## and pick a fresh sweep goal instead of spinning in place.
func _detect_stuck(delta: float) -> void:
	if _charging or _windup > 0.0:
		return
	if global_position.distance_to(_last_pos) < 0.4 * delta * 60.0 * 0.016:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_pos = global_position
	if _stuck_time > 1.4:
		_stuck_time = 0.0
		_pick_sweep_goal()

func _do_sweep(delta: float) -> void:
	_sweep_timer -= delta
	if global_position.distance_to(_sweep_goal) < 3.0 or _sweep_timer <= 0.0:
		_pick_sweep_goal()
	_steer_toward(_sweep_goal, delta, _phase_speed)

func _do_hunt(delta: float, reachable: bool) -> void:
	if _target == null or not reachable:
		_do_sweep(delta)
		return
	_steer_toward(_target.global_position, delta, _phase_speed)

## Telegraphed charge: rev in place with the eye flaring, THEN launch.
func _start_windup() -> void:
	if _target == null:
		return
	_windup = CHARGE_WINDUP
	velocity.x = 0.0
	velocity.z = 0.0
	Events.notify.emit("THE VACUUM IS REVVING UP!")
	Sfx.play("shoot_heavy", 0.0, 0.3)

func _do_windup(delta: float) -> void:
	_windup -= delta
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	# Track the target while revving, shaking with fury.
	if _target != null:
		var dir := _target.global_position - global_position
		dir.y = 0.0
		_face(dir.normalized(), delta, 3.0)
	_body_tilt.position.x = randf_range(-0.08, 0.08)
	if _windup <= 0.0:
		_body_tilt.position.x = 0.0
		_charging = true
		_charge_life = CHARGE_MAX_TIME
		_charge_dir = -global_transform.basis.z
		_charge_dir.y = 0.0
		_charge_dir = _charge_dir.normalized()

func _do_charge(delta: float) -> void:
	_charge_life -= delta
	velocity.x = move_toward(velocity.x, _charge_dir.x * CHARGE_SPEED, 40.0 * delta)
	velocity.z = move_toward(velocity.z, _charge_dir.z * CHARGE_SPEED, 40.0 * delta)
	var ended := _charge_life <= 0.0
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() is StaticBody3D:
			ended = true
			Fx.impact(self, global_position + Vector3.UP * 1.5, Color(0.8, 0.8, 0.9))
			Sfx.play_at("explosion", global_position, -6.0)
			break
	if ended:
		_charging = false
		_charge_timer = randf_range(4.0, 7.0)

## Drive like a vehicle: turn first, roll on when actually facing the goal.
## Direct velocity writes were the old glitchy-jitter bug.
func _steer_toward(goal: Vector3, delta: float, speed: float) -> void:
	var dir := goal - global_position
	dir.y = 0.0
	if dir.length() < 0.5:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
		return
	dir = dir.normalized()
	_face(dir, delta, 1.6)
	var forward := -global_transform.basis.z
	var align := clampf(forward.dot(dir), 0.0, 1.0)
	var desired := forward * speed * align * align
	velocity.x = move_toward(velocity.x, desired.x, 9.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 9.0 * delta)

func _face(dir: Vector3, delta: float, turn: float) -> void:
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(turn * delta, 1.0))

func _pick_sweep_goal() -> void:
	_sweep_timer = 8.0
	_sweep_goal = Vector3(randf_range(-45, 45), 0, randf_range(-30, 35))

## Drag anything in the front cone toward the intake.
func _apply_suction(delta: float) -> void:
	if _target == null:
		return
	var to_target := _target.global_position - global_position
	if to_target.length() > SUCTION_RANGE or to_target.y > 4.0:
		return
	var forward := -global_transform.basis.z
	var flat := to_target
	flat.y = 0.0
	if forward.angle_to(flat.normalized()) > SUCTION_HALF_ANGLE:
		return
	# Pull strength grows near the maw.
	var strength := (1.0 - to_target.length() / SUCTION_RANGE) * 22.0 + 5.0
	var pull := -flat.normalized() * strength   # points from target toward the intake
	if _target is CharacterBody3D:
		_target.velocity += pull * delta * 2.2

func _check_contact() -> void:
	if _target == null:
		return
	var maw_pos := global_position + (-global_transform.basis.z) * 5.0 + Vector3.UP
	if _target.global_position.distance_to(maw_pos) < 2.5:
		# Swallowed! Chewed and spat out the exhaust (onto walkable ground —
		# never inside furniture).
		_target.take_damage(CONTACT_DAMAGE)
		var want := global_position + global_transform.basis.x * 7.0
		var map := get_world_3d().navigation_map
		_target.global_position = NavigationServer3D.map_get_closest_point(map, want) + Vector3.UP * 2.0
		if _target is CharacterBody3D:
			_target.velocity = Vector3(randf_range(-4, 4), 8.0, randf_range(-4, 4))
		Sfx.play("hurt")
		Events.notify.emit("You got vacuumed! Aim for the FILTER PODS on its back!")

## Armored body: bullets ping off harmlessly.
func take_damage(_amount: float, _attacker: Node = null) -> void:
	Fx.impact(self, global_position + Vector3.UP * 3.0, Color(0.9, 0.9, 1.0))
	Sfx.play_at("hit", global_position, -12.0)

func is_dead() -> bool:
	return filters_alive <= 0


## Weak point pod. Lives on the boss's back; separate collider so shots
## must actually land on it.
class VacuumFilter:
	extends StaticBody3D
	var boss: VacuumBoss
	var health: Health

	func _ready() -> void:
		collision_layer = 0b0010
		health = Health.new()
		health.setup(90.0)
		health.died.connect(func(_a):
			boss.filter_destroyed()
			queue_free())
		add_child(health)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.9
		shape.shape = sphere
		add_child(shape)
		var mesh := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.85
		sm.height = 1.7
		mesh.mesh = sm
		mesh.material_override = ToyMaterials.glow(Color(0.4, 1.0, 0.6), 2.5)
		add_child(mesh)

	func take_damage(amount: float, attacker: Node = null) -> void:
		health.damage(amount, attacker)
		Fx.impact(self, global_position, Color(0.4, 1.0, 0.6))

	func is_dead() -> bool:
		return health.dead

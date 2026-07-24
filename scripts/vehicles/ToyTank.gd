class_name ToyTank
extends CharacterBody3D
## Drivable green plastic toy tank. Walk up and press E to mount.
## Hull steers with A/D, moves with W/S; the turret tracks the camera;
## left-click fires the spring-loaded cannon. E again to dismount.

const HULL_SPEED := 9.0
const TURN_SPEED := 1.8

var driver: Player = null
var turret: Node3D
var barrel: Node3D
var cannon: Weapon
var health: Health
var _cam_pivot: Node3D
var _camera: Camera3D
var _yaw := 0.0
var _pitch := -0.35
var _prompt: Label3D
var _engine_on := false
var _aim_point := Vector3.ZERO
## Bot-driven tanks for Tank Battle (no Player driver).
var ai_controlled := false
var ai_team: String = "chrome_legion"
var _ai_fire_cd := 0.0
var _ai_think := 0.0
var _ai_target: Node3D = null
var _last_ammo := -1

func _ready() -> void:
	collision_layer = 0b0100
	collision_mask = 0b0111
	add_to_group("vehicles")
	if ai_controlled:
		# enemies for damage/scoring — not combat_bots (that group is Unit scans).
		add_to_group("enemies")
		add_to_group("team_" + ai_team)

	health = Health.new()
	health.setup(400.0 if not ai_controlled else 320.0)
	health.died.connect(_on_destroyed)
	add_child(health)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.8, 1.4, 4.4)
	shape.shape = box
	shape.position.y = 0.8
	add_child(shape)
	_build_visual()

	_cam_pivot = Node3D.new()
	_cam_pivot.position.y = 2.2
	add_child(_cam_pivot)
	# Soft spring so cover doesn't pin the camera, but never fully collapse.
	var spring := SpringArm3D.new()
	spring.spring_length = 11.0
	spring.margin = 0.4
	spring.collision_mask = 0b0001
	_cam_pivot.add_child(spring)
	_camera = Camera3D.new()
	_camera.fov = 68.0
	_camera.position = Vector3(0, 1.2, 0)   # slight high chase, reads over the hull
	spring.add_child(_camera)

	cannon = Weapon.new()
	cannon.data = load("res://data/weapons/tank_cannon.tres")
	cannon.owner_unit = self
	var fac_path := "res://data/factions/chrome_legion.tres" if ai_controlled and ai_team == "chrome_legion" \
		else "res://data/factions/green_army.tres"
	cannon.faction = load(fac_path)
	barrel.add_child(cannon)
	cannon.position.z = -2.2

	_prompt = Label3D.new()
	_prompt.text = "[E]  DRIVE TANK"
	_prompt.font_size = 64
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.modulate = Color(1, 0.95, 0.6)
	_prompt.position.y = 2.6
	_prompt.visible = false
	add_child(_prompt)

func _build_visual() -> void:
	# Prefer the Quaternius asset-pack tank; fall back to primitives.
	var rig := ModelLib.build_tank(4.6)
	if rig != null:
		add_child(rig)
		if ai_controlled and ai_team == "chrome_legion":
			ModelLib._tint(rig, Color(0.55, 0.62, 0.78), 0.45, 0.35)
		if rig.has_meta("turret"):
			turret = rig.get_meta("turret")
		else:
			turret = Node3D.new()
			add_child(turret)
		# Aim node lives on the (unscaled) tank body; _drive yaws it with the
		# turret visual so the cannon and the mesh stay in sync.
		barrel = Node3D.new()
		barrel.name = "AimBarrel"
		barrel.position = Vector3(0, 1.7, 0)
		add_child(barrel)
		return
	var hull_col := Color(0.55, 0.62, 0.78) if ai_controlled and ai_team == "chrome_legion" else Color(0.3, 0.48, 0.22)
	var green := ToyMaterials.plastic(hull_col)
	var dark := ToyMaterials.plastic(Color(0.18, 0.28, 0.13))
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(2.0, 0.7, 3.0)
	hull.mesh = hull_mesh
	hull.material_override = green
	hull.position.y = 0.65
	add_child(hull)
	for side in [-1.0, 1.0]:
		var tread := MeshInstance3D.new()
		var tread_mesh := BoxMesh.new()
		tread_mesh.size = Vector3(0.5, 0.6, 3.3)
		tread.mesh = tread_mesh
		tread.material_override = dark
		tread.position = Vector3(side * 1.15, 0.35, 0)
		add_child(tread)
	turret = Node3D.new()
	turret.position.y = 1.1
	add_child(turret)
	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 0.7
	dome_mesh.height = 0.9
	dome.mesh = dome_mesh
	dome.material_override = green
	turret.add_child(dome)
	barrel = Node3D.new()
	turret.add_child(barrel)
	var tube := MeshInstance3D.new()
	var tube_mesh := CylinderMesh.new()
	tube_mesh.top_radius = 0.12
	tube_mesh.bottom_radius = 0.16
	tube_mesh.height = 1.8
	tube.mesh = tube_mesh
	tube.material_override = dark
	tube.rotation_degrees.x = 90.0
	tube.position = Vector3(0, 0.15, -1.0)
	barrel.add_child(tube)

func _input(event: InputEvent) -> void:
	if driver == null or ai_controlled:
		return
	# Click / tap re-locks pointer so look works after UI focus loss (web).
	if event is InputEventMouseButton and event.pressed:
		Game.capture_mouse()
	if event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Game.is_touch():
			return
		if event.relative.length() > 250.0:
			return
		_yaw -= event.relative.x * 0.0032
		_pitch = clampf(_pitch - event.relative.y * 0.0032, -0.85, 0.45)

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	if ai_controlled:
		_ai_drive(delta)
		return
	# Touch look-drag steers the turret while driving.
	if driver != null and Game.touch_look != Vector2.ZERO:
		_yaw -= Game.touch_look.x * 0.85
		_pitch = clampf(_pitch - Game.touch_look.y * 0.85, -0.85, 0.45)
		Game.touch_look = Vector2.ZERO
	if driver == null:
		_check_mount()
		if not is_on_floor():
			velocity.y -= 24.0 * delta
			move_and_slide()
		return
	_drive(delta)

## Instantly board the player (arena tank battle start).
func force_board(p: Player) -> void:
	if p == null or not is_instance_valid(p):
		return
	driver = p
	p.enter_vehicle(self)
	_yaw = rotation.y
	_pitch = -0.2
	_camera.make_current()
	Game.capture_mouse()
	if _prompt != null:
		_prompt.visible = false
	Events.weapon_changed.emit(cannon.data.display_name)
	Events.ammo_changed.emit(cannon.ammo, cannon.data.magazine_size)
	Events.player_health_changed.emit(health.current, health.max_health)
	Events.notify.emit("Tank boarded — mouse aims the turret, A/D steers the hull.")

func _ai_drive(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	_ai_think -= delta
	_ai_fire_cd = maxf(_ai_fire_cd - delta, 0.0)
	if _ai_think <= 0.0 or _ai_target == null or not is_instance_valid(_ai_target):
		_ai_think = 0.35 if Game.low_gfx() else 0.22
		_ai_target = _ai_pick_target()
	var target := _ai_target
	var throttle := 0.0
	var steer := 0.0
	if target != null:
		var to := target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		var want_yaw := atan2(-to.x, -to.z)
		var yaw_err := wrapf(want_yaw - rotation.y, -PI, PI)
		steer = clampf(yaw_err * 1.8, -1.0, 1.0)
		throttle = 0.85 if dist > 14.0 else (-0.35 if dist < 7.0 else 0.25)
		# Turret tracks target.
		_yaw = lerp_angle(_yaw, want_yaw, 3.0 * delta)
		var aim_h := target.global_position + Vector3.UP * 0.8
		_aim_point = aim_h
		var to_aim := aim_h - barrel.global_position
		var flat := Vector2(to_aim.x, to_aim.z).length()
		barrel.rotation.x = clampf(atan2(to_aim.y, maxf(flat, 0.01)), -0.55, 0.75)
		turret.rotation.y = _yaw - rotation.y
		if dist < 28.0 and absf(yaw_err) < 0.45 and _ai_fire_cd <= 0.0:
			var dir := (aim_h - cannon.muzzle.global_position).normalized()
			if cannon.try_fire(dir):
				_ai_fire_cd = 1.35
				velocity -= dir * 2.0
	else:
		# Idle circle when no target.
		throttle = 0.35
		steer = 0.4
	rotation.y += steer * TURN_SPEED * delta * (1.0 if throttle >= 0.0 else -1.0)
	var forward := -global_transform.basis.z
	velocity.x = forward.x * throttle * HULL_SPEED * 0.9
	velocity.z = forward.z * throttle * HULL_SPEED * 0.9
	move_and_slide()

func _ai_pick_target() -> Node3D:
	var best: Node3D = null
	var best_d := 40.0
	if Game.player != null and is_instance_valid(Game.player):
		var ppos: Vector3 = Game.player.global_position
		if Game.player.current_vehicle != null and is_instance_valid(Game.player.current_vehicle):
			ppos = Game.player.current_vehicle.global_position
			best = Game.player.current_vehicle
			best_d = global_position.distance_to(ppos)
		else:
			best = Game.player
			best_d = global_position.distance_to(ppos)
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v == self or not is_instance_valid(v):
			continue
		if v is ToyTank and (v as ToyTank).ai_controlled and (v as ToyTank).ai_team == ai_team:
			continue
		if v is ToyTank and (v as ToyTank).driver != null:
			var d := global_position.distance_to(v.global_position)
			if d < best_d:
				best_d = d
				best = v
	return best

func _check_mount() -> void:
	var p := Game.player
	var near: bool = p != null and is_instance_valid(p) and p.current_vehicle == null \
		and global_position.distance_to(p.global_position) < 4.0
	_prompt.visible = near
	if near and Input.is_action_just_pressed("interact"):
		force_board(p)

func _drive(delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		_dismount()
		return
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	var throttle := Input.get_axis("move_back", "move_forward")
	var steer := Input.get_axis("move_right", "move_left")
	# Hull turns with A/D; turret/camera yaw is independent (mouse / look stick).
	rotation.y += steer * TURN_SPEED * delta * (1.0 if throttle >= 0.0 else -1.0)
	var forward := -global_transform.basis.z
	velocity.x = forward.x * throttle * HULL_SPEED
	velocity.z = forward.z * throttle * HULL_SPEED
	move_and_slide()

	# The driver rides along invisibly: keeps squad follow, enemy AI and
	# mission waypoints anchored to the tank instead of the mount point.
	driver.global_position = global_position + Vector3.UP * 0.5

	# Camera orbits in world yaw space so look stays free of hull steering.
	_cam_pivot.rotation = Vector3(_pitch, _yaw - rotation.y, 0)
	turret.rotation.y = _yaw - rotation.y
	if barrel.get_parent() == self:   # asset-pack rig: aim node yaws itself
		barrel.rotation.y = _yaw - rotation.y

	# Crosshair-true aiming: raycast from the camera through screen center,
	# then pitch the barrel at whatever the reticle is on.
	_update_aim_point()
	var to_aim := _aim_point - barrel.global_position
	var flat := Vector2(to_aim.x, to_aim.z).length()
	barrel.rotation.x = clampf(atan2(to_aim.y, maxf(flat, 0.01)), -0.55, 0.75)

	# One looping rumble while throttle is in — the old 5s one-shot spam
	# kept roaring long after the tank stopped.
	var want_engine := absf(throttle) > 0.1
	if want_engine and not _engine_on:
		Sfx.start_loop("engine", -14.0, 0.92)
		_engine_on = true
	elif not want_engine and _engine_on:
		Sfx.stop_loop("engine", 0.08)
		_engine_on = false
	elif _engine_on:
		var rev := clampf(absf(throttle), 0.0, 1.0)
		Sfx.set_loop("engine", lerpf(-16.0, -12.0, rev), lerpf(0.88, 1.05, rev))

	if Input.is_action_just_pressed("fire") or (Game.is_touch() and Input.is_action_pressed("fire")):
		var dir := (_aim_point - cannon.muzzle.global_position).normalized()
		if cannon.try_fire(dir):
			velocity -= dir * 3.5   # recoil shove
			_fire_feedback(dir)
	if cannon.ammo != _last_ammo:
		_last_ammo = cannon.ammo
		Events.ammo_changed.emit(cannon.ammo, cannon.data.magazine_size)

## One raycast from the camera through the reticle. Shots land on the
## crosshair no matter where the barrel sits relative to the camera.
func _update_aim_point() -> void:
	var from := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 250.0)
	query.collision_mask = 0b0111
	query.exclude = [get_rid()]
	if driver != null:
		query.exclude = [get_rid(), driver.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_aim_point = hit.position if not hit.is_empty() else from + dir * 250.0

## Cannon punch: turret kickback, camera slam, smoke ring at the muzzle.
func _fire_feedback(dir: Vector3) -> void:
	var muzzle_pos: Vector3 = cannon.muzzle.global_position
	Fx.ring_pulse(self, muzzle_pos, Color(1.0, 0.75, 0.4), 1.6)
	Fx.dust(self, muzzle_pos, true)
	if turret != null:
		var kick := create_tween()
		kick.tween_property(turret, "position:z", turret.position.z + 0.22, 0.05)
		kick.tween_property(turret, "position:z", turret.position.z, 0.28).set_trans(Tween.TRANS_BACK)
	var slam := create_tween()
	slam.tween_property(_camera, "v_offset", 0.3, 0.05)
	slam.tween_property(_camera, "v_offset", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC)

func _dismount() -> void:
	_stop_engine()
	var exit_pos := global_position + global_transform.basis.x * 2.5 + Vector3.UP * 0.5
	var p := driver
	driver = null
	p.exit_vehicle(exit_pos)
	Events.weapon_changed.emit(p.weapon.data.display_name)
	Events.ammo_changed.emit(p.weapon.ammo, p.weapon.data.magazine_size)
	Events.player_health_changed.emit(p.health.current, p.health.max_health)

func _stop_engine() -> void:
	if _engine_on:
		Sfx.stop_loop("engine")
		_engine_on = false

func take_damage(amount: float, _attacker: Node = null) -> void:
	health.damage(amount * 0.5)   # toy armor
	Fx.impact(self, global_position + Vector3.UP, Color(0.3, 0.48, 0.22))
	if driver != null:
		Events.player_health_changed.emit(health.current, health.max_health)
		Events.player_damaged.emit()

func is_dead() -> bool:
	return health.dead

func _on_destroyed(_attacker: Node) -> void:
	_stop_engine()
	if driver != null:
		_dismount()
	if ai_controlled:
		Events.unit_died.emit(self)
	Fx.explosion(self, global_position + Vector3.UP, 4.0)
	queue_free()

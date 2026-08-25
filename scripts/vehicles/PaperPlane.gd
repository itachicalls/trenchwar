class_name PaperPlane
extends CharacterBody3D
## Arcade paper airplane — built to feel fair and readable, not simulator-hard.
##   W / S      throttle (touch auto-cruises when idle)
##   A / D      yaw — the plane banks to match (visual only)
##   Mouse Y / look stick — pitch only (mouse X no longer yaws you into walls)
##   Left click  dart pods
##   E           bail (disabled when lock_bail)

const MAX_SPEED := 28.0
const MIN_FLY_SPEED := 7.0
const CRUISE_SPEED := 18.0
const THROTTLE_RATE := 16.0
const YAW_RATE := 1.55
const PITCH_RATE := 1.9
const CRASH_SPEED := 20.0
const CRASH_COOLDOWN := 0.85

var driver: Player = null
var health: Health
var guns: Weapon
var _speed := 0.0
var _pitch := 0.0
var _bank := 0.0
var _yaw_input := 0.0
var _cam_pivot: Node3D
var _cam_arm: Node3D
var _camera: Camera3D
var _prompt: Label3D
var _paper_mat: StandardMaterial3D
var lock_bail := false
var _last_ammo := -1
var _crash_cd := 0.0
var _trail: CPUParticles3D
var _speed_label: Label3D

## Public for race HUD.
func speed() -> float:
	return _speed

func stalling() -> bool:
	return _speed < MIN_FLY_SPEED + 1.5

func _ready() -> void:
	collision_layer = 0b0100
	collision_mask = 0b0001
	add_to_group("vehicles")

	health = Health.new()
	health.setup(180.0)
	health.died.connect(_on_destroyed)
	add_child(health)

	# Fuselage-sized hitbox — wings are visual only so posts don't shred you.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.15, 0.55, 2.6)
	shape.shape = box
	shape.position.y = 0.15
	add_child(shape)
	_build_visual()
	_build_trail()

	# Chase cam lives on a lagging pivot so hard banks don't flip the horizon.
	_cam_pivot = Node3D.new()
	add_child(_cam_pivot)
	_cam_arm = Node3D.new()
	_cam_arm.position = Vector3(0, 2.8, 8.2)
	_cam_pivot.add_child(_cam_arm)
	_camera = Camera3D.new()
	_camera.fov = 72.0
	_camera.rotation_degrees.x = -10.0
	_cam_arm.add_child(_camera)

	guns = Weapon.new()
	guns.data = load("res://data/weapons/dart_launcher.tres")
	guns.owner_unit = self
	guns.faction = load("res://data/factions/green_army.tres")
	add_child(guns)
	guns.position = Vector3(0, -0.1, -1.2)

	_prompt = Label3D.new()
	_prompt.text = "[E]  FLY PAPER PLANE"
	_prompt.font_size = 64
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.modulate = Color(1, 0.95, 0.6)
	_prompt.position.y = 2.0
	_prompt.visible = false
	add_child(_prompt)

	_speed_label = Label3D.new()
	_speed_label.font_size = 42
	_speed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speed_label.position = Vector3(0, -0.9, 0)
	_speed_label.modulate = Color(0.95, 0.95, 0.85)
	_speed_label.outline_size = 8
	_speed_label.visible = false
	add_child(_speed_label)

func _build_visual() -> void:
	_paper_mat = ToyMaterials.plastic(Color(0.97, 0.95, 0.9), 0.55)
	var stripe := ToyMaterials.glow(Color(0.25, 0.85, 1.0), 1.4)
	var green := ToyMaterials.plastic(Color(0.35, 0.72, 0.4), 0.45)
	# Folded fuselage.
	var spine := MeshInstance3D.new()
	var spine_mesh := PrismMesh.new()
	spine_mesh.size = Vector3(0.75, 0.95, 3.8)
	spine.mesh = spine_mesh
	spine.material_override = _paper_mat
	spine.position.y = 0.12
	add_child(spine)
	# Leading-edge glow strip — reads at distance against the sky.
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.55, 0.12, 0.35)
	nose.mesh = nm
	nose.material_override = stripe
	nose.position = Vector3(0, 0.35, -1.85)
	add_child(nose)
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wing_mesh := BoxMesh.new()
		wing_mesh.size = Vector3(2.4, 0.07, 2.8)
		wing.mesh = wing_mesh
		wing.material_override = green if side < 0 else _paper_mat
		wing.position = Vector3(side * 1.25, 0.34, 0.1)
		wing.rotation_degrees.z = side * 6.0
		add_child(wing)
		# Wingtip light.
		var tip := MeshInstance3D.new()
		var tm := SphereMesh.new()
		tm.radius = 0.1
		tm.height = 0.2
		tip.mesh = tm
		tip.material_override = ToyMaterials.glow(
			Color(1.0, 0.35, 0.25) if side > 0 else Color(0.3, 1.0, 0.45), 2.0)
		tip.position = Vector3(side * 2.4, 0.4, 0.9)
		add_child(tip)
	var fin := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.08, 0.85, 0.6)
	fin.mesh = fm
	fin.material_override = stripe
	fin.position = Vector3(0, 0.65, 1.55)
	add_child(fin)

func _build_trail() -> void:
	if Game.low_gfx():
		return
	_trail = CPUParticles3D.new()
	_trail.amount = 28
	_trail.lifetime = 0.55
	_trail.emitting = false
	_trail.local_coords = false
	_trail.direction = Vector3(0, 0, 1)
	_trail.spread = 8.0
	_trail.initial_velocity_min = 0.4
	_trail.initial_velocity_max = 1.2
	_trail.gravity = Vector3.ZERO
	_trail.scale_amount_min = 0.08
	_trail.scale_amount_max = 0.2
	_trail.color = Color(0.95, 0.95, 1.0, 0.55)
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	mesh.material = ToyMaterials.glow(Color(0.85, 0.95, 1.0), 0.6)
	_trail.mesh = mesh
	_trail.position = Vector3(0, 0.2, 1.7)
	add_child(_trail)

func _input(event: InputEvent) -> void:
	if driver == null:
		return
	if event is InputEventMouseButton and event.pressed:
		Game.capture_mouse()
	if event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Game.is_touch():
			return
		if event.relative.length() > 250.0:
			return
		# Pitch only — mouse X used to also yaw/roll and made the plane
		# impossible to aim through a gate.
		_pitch = clampf(_pitch + event.relative.y * 0.0022, -0.7, 0.75)

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	_crash_cd = maxf(_crash_cd - delta, 0.0)
	if driver != null and Game.touch_look != Vector2.ZERO:
		_pitch = clampf(_pitch + Game.touch_look.y * 0.55, -0.7, 0.75)
		# Touch X gently assists yaw without the old snap-roll.
		_yaw_input = clampf(_yaw_input - Game.touch_look.x * 0.35, -1.0, 1.0)
		Game.touch_look = Vector2.ZERO
	if driver == null:
		_check_mount()
		_update_camera(delta)
		if not is_on_floor():
			velocity.y -= 10.0 * delta
			velocity.x *= 0.98
			velocity.z *= 0.98
			move_and_slide()
		return
	_fly(delta)
	_update_camera(delta)
	_update_speed_label()

func _check_mount() -> void:
	var p := Game.player
	var near: bool = p != null and is_instance_valid(p) and p.current_vehicle == null \
		and global_position.distance_to(p.global_position) < 4.0
	_prompt.visible = near
	if near and Input.is_action_just_pressed("interact"):
		force_board(p)

func force_board(p: Player) -> void:
	if p == null or not is_instance_valid(p):
		return
	driver = p
	p.enter_vehicle(self)
	_speed = CRUISE_SPEED
	_pitch = -0.04
	_bank = 0.0
	_yaw_input = 0.0
	_camera.make_current()
	Game.capture_mouse()
	if _prompt != null:
		_prompt.visible = false
	if _speed_label != null:
		_speed_label.visible = true
	if _trail != null:
		_trail.emitting = true
	Events.weapon_changed.emit(guns.data.display_name)
	Events.ammo_changed.emit(guns.ammo, guns.data.magazine_size)
	Events.notify.emit("AIRBORNE — W throttle · A/D turn · mouse up/down pitches")

func _fly(delta: float) -> void:
	if not lock_bail and Input.is_action_just_pressed("interact"):
		_bail_out()
		return
	var throttle := Input.get_axis("move_back", "move_forward")
	var yaw_stick := Input.get_axis("move_right", "move_left")
	# Touch: hold cruise when idle so races don't stall out.
	if Game.is_touch() and absf(throttle) < 0.08:
		throttle = 0.55
	# Blend touch assist into yaw, then decay it.
	yaw_stick = clampf(yaw_stick + _yaw_input, -1.0, 1.0)
	_yaw_input = move_toward(_yaw_input, 0.0, 2.5 * delta)

	_speed = clampf(_speed + throttle * THROTTLE_RATE * delta, 0.0, MAX_SPEED)
	# Mild bleed — idle holds near cruise instead of falling out of the sky.
	var bleed := 0.35 if absf(throttle) > 0.05 else 1.8
	_speed = move_toward(_speed, CRUISE_SPEED if absf(throttle) < 0.05 else _speed, bleed * delta)
	_speed = clampf(_speed, 0.0, MAX_SPEED)

	# High-speed turn dampening: fast = wider arcs (arcade readability).
	var turn_scale := lerpf(1.15, 0.55, clampf(_speed / MAX_SPEED, 0.0, 1.0))
	rotation.y += -yaw_stick * YAW_RATE * turn_scale * delta
	# Visual bank from yaw stick only — never from mouse.
	var want_bank := clampf(-yaw_stick * 0.55, -0.65, 0.65)
	_bank = move_toward(_bank, want_bank, 3.2 * delta)
	# Soft auto-level pitch when look input is quiet.
	if absf(_pitch) < 0.04:
		_pitch = move_toward(_pitch, 0.0, 0.6 * delta)
	rotation.x = lerp_angle(rotation.x, -_pitch, PITCH_RATE * delta)
	rotation.z = lerp_angle(rotation.z, _bank, 4.5 * delta)

	var forward := -global_transform.basis.z
	velocity = forward * _speed
	# Gentle stall sink — warning via HUD, not an instant dive.
	if _speed < MIN_FLY_SPEED:
		velocity.y -= (MIN_FLY_SPEED - _speed) * 1.1
	# Soft sand cushion.
	if global_position.y < 3.0 and velocity.y < 0.0:
		velocity.y = maxf(velocity.y, -3.5)
		global_position.y = maxf(global_position.y, 2.4)
	# Hard ceiling so you don't leave the circuit.
	if global_position.y > 42.0:
		global_position.y = 42.0
		velocity.y = minf(velocity.y, 0.0)
	move_and_slide()

	if get_slide_collision_count() > 0 and _speed > CRASH_SPEED and _crash_cd <= 0.0:
		_crash_cd = CRASH_COOLDOWN
		var dmg := (_speed - CRASH_SPEED) * 0.55 + 8.0
		health.damage(dmg)
		_speed *= 0.62
		Fx.impact(self, global_position, Color(0.93, 0.92, 0.86))
		Sfx.play_at("hit", global_position, -6.0)
		Fx.shake_camera(self, 0.25)

	if Input.is_action_pressed("fire"):
		if guns.try_fire(forward) and Net.is_online:
			Net.broadcast_shot(guns.muzzle.global_position, forward, guns.data.resource_path)
	if guns.ammo != _last_ammo:
		_last_ammo = guns.ammo
		Events.ammo_changed.emit(guns.ammo, guns.data.magazine_size)
	if _trail != null:
		_trail.emitting = _speed > 10.0

## Camera tracks a smoothed heading and banks gently — never locks to the
## plane's full roll, so hard turns stay readable.
func _update_camera(delta: float) -> void:
	if _cam_pivot == null:
		return
	_cam_pivot.global_position = global_position
	_cam_pivot.rotation.y = lerp_angle(_cam_pivot.rotation.y, rotation.y, 1.0 - exp(-5.5 * delta))
	_cam_pivot.rotation.x = 0.0
	_cam_pivot.rotation.z = lerpf(_cam_pivot.rotation.z, _bank * 0.2, 1.0 - exp(-4.0 * delta))
	# Ease the arm up when climbing so the next gate stays on screen.
	var want_y := 2.8 + clampf(-_pitch, -0.2, 0.45) * 2.2
	_cam_arm.position.y = lerpf(_cam_arm.position.y, want_y, 1.0 - exp(-3.0 * delta))
	_cam_arm.position.z = lerpf(_cam_arm.position.z, 8.2 + clampf(_speed * 0.04, 0.0, 1.5),
		1.0 - exp(-2.0 * delta))
	if _camera != null:
		_camera.rotation_degrees.x = lerpf(_camera.rotation_degrees.x, -10.0 - _pitch * 8.0,
			1.0 - exp(-3.0 * delta))

func _update_speed_label() -> void:
	if _speed_label == null or not _speed_label.visible:
		return
	var pct := int((_speed / MAX_SPEED) * 100.0)
	_speed_label.text = "STALL" if stalling() else ("%d" % pct)
	_speed_label.modulate = Color(1.0, 0.4, 0.35) if stalling() \
		else Color(0.95, 0.95, 0.85)

func _bail_out() -> void:
	var exit_pos := global_position + Vector3.UP * 0.5
	var p := driver
	driver = null
	_speed = 0.0
	rotation.x = 0.0
	rotation.z = 0.0
	if _speed_label != null:
		_speed_label.visible = false
	if _trail != null:
		_trail.emitting = false
	p.exit_vehicle(exit_pos)
	p.velocity = velocity * 0.5
	Events.weapon_changed.emit(p.weapon.data.display_name)
	Events.ammo_changed.emit(p.weapon.ammo, p.weapon.data.magazine_size)

func take_damage(amount: float, _attacker: Node = null) -> void:
	health.damage(amount)
	Fx.impact(self, global_position, Color(0.93, 0.92, 0.86))

func is_dead() -> bool:
	return health.dead

func _on_destroyed(_attacker: Node) -> void:
	if driver != null:
		_bail_out()
	Fx.explosion(self, global_position, 2.4)
	Fx.shake_camera(self, 0.45)
	queue_free()

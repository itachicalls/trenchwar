class_name PaperPlane
extends CharacterBody3D
## Drivable paper airplane — arcade flight for races and sandbox joyrides.
##   W / S      throttle
##   A / D      yaw (bank follows)
##   Mouse / look stick — pitch + extra bank
##   Left click  dart pods
##   E           bail (disabled when lock_bail)

const MAX_SPEED := 26.0
const MIN_FLY_SPEED := 8.0
const THROTTLE_RATE := 14.0
const YAW_RATE := 1.85

var driver: Player = null
var health: Health
var guns: Weapon
var _speed := 0.0
var _pitch := 0.0
var _roll := 0.0
var _cam_pivot: Node3D
var _camera: Camera3D
var _prompt: Label3D
var _paper_mat: StandardMaterial3D
## Race modes set this so E can't soft-lock the course.
var lock_bail := false
var _last_ammo := -1

func _ready() -> void:
	collision_layer = 0b0100
	collision_mask = 0b0001
	add_to_group("vehicles")

	health = Health.new()
	health.setup(140.0)
	health.died.connect(_on_destroyed)
	add_child(health)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 0.45, 2.4)
	shape.shape = box
	add_child(shape)
	_build_visual()

	# Fixed chase cam (no SpringArm) — spring collapse against the floor was
	# burying the lens in geometry and reading as a black void.
	_cam_pivot = Node3D.new()
	_cam_pivot.position = Vector3(0, 2.4, 7.5)
	add_child(_cam_pivot)
	_camera = Camera3D.new()
	_camera.fov = 78.0
	_camera.rotation_degrees.x = -8.0
	_cam_pivot.add_child(_camera)

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

func _build_visual() -> void:
	_paper_mat = ToyMaterials.plastic(Color(0.96, 0.94, 0.88), 0.7)
	var lined := ToyMaterials.plastic(Color(0.55, 0.78, 1.0), 0.55)
	var spine := MeshInstance3D.new()
	var spine_mesh := PrismMesh.new()
	spine_mesh.size = Vector3(0.7, 0.9, 3.6)
	spine.mesh = spine_mesh
	spine.material_override = _paper_mat
	spine.position.y = 0.1
	add_child(spine)
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wing_mesh := BoxMesh.new()
		wing_mesh.size = Vector3(2.2, 0.06, 3.0)
		wing.mesh = wing_mesh
		wing.material_override = lined if side < 0 else _paper_mat
		wing.position = Vector3(side * 1.15, 0.32, 0.15)
		wing.rotation_degrees.z = side * 8.0
		add_child(wing)
	# Tail fin so orientation reads in chase cam.
	var fin := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.08, 0.7, 0.55)
	fin.mesh = fm
	fin.material_override = lined
	fin.position = Vector3(0, 0.55, 1.5)
	add_child(fin)

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
		_pitch = clampf(_pitch + event.relative.y * 0.0026, -0.85, 0.85)
		_roll = clampf(_roll - event.relative.x * 0.0034, -1.15, 1.15)

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	if driver != null and Game.touch_look != Vector2.ZERO:
		_pitch = clampf(_pitch + Game.touch_look.y * 0.7, -0.85, 0.85)
		_roll = clampf(_roll - Game.touch_look.x * 0.9, -1.15, 1.15)
		Game.touch_look = Vector2.ZERO
	if driver == null:
		_check_mount()
		if not is_on_floor():
			velocity.y -= 10.0 * delta
			velocity.x *= 0.98
			velocity.z *= 0.98
			move_and_slide()
		return
	_fly(delta)

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
	_speed = MIN_FLY_SPEED + 6.0
	_pitch = -0.08
	_roll = 0.0
	_camera.make_current()
	Game.capture_mouse()
	if _prompt != null:
		_prompt.visible = false
	Events.weapon_changed.emit(guns.data.display_name)
	Events.ammo_changed.emit(guns.ammo, guns.data.magazine_size)
	Events.notify.emit("Airborne! W throttle, A/D turn, mouse pitches. Thread the glowing hoops!")

func _fly(delta: float) -> void:
	if not lock_bail and Input.is_action_just_pressed("interact"):
		_bail_out()
		return
	var throttle := Input.get_axis("move_back", "move_forward")
	var yaw_stick := Input.get_axis("move_right", "move_left")
	# Touch: gentle cruise if the stick is idle so races don't stall.
	if Game.is_touch() and absf(throttle) < 0.08:
		throttle = 0.65
	_speed = clampf(_speed + throttle * THROTTLE_RATE * delta, 0.0, MAX_SPEED)
	_speed = maxf(_speed - 0.55 * delta, 0.0)

	# A/D yaws; mouse roll adds coordinated bank. Soft auto-level.
	rotation.y += (-yaw_stick * YAW_RATE - _roll * 1.35) * delta
	_roll = move_toward(_roll, clampf(-yaw_stick * 0.55, -0.7, 0.7), 2.4 * delta)
	rotation.x = lerp_angle(rotation.x, -_pitch, 7.0 * delta)
	rotation.z = lerp_angle(rotation.z, _roll * 0.75, 7.0 * delta)

	var forward := -global_transform.basis.z
	velocity = forward * _speed
	if _speed < MIN_FLY_SPEED:
		velocity.y -= (MIN_FLY_SPEED - _speed) * 2.0
	# Soft floor bounce so you don't dig into sand and black-screen.
	if global_position.y < 2.2 and velocity.y < 0.0:
		velocity.y = maxf(velocity.y, -2.0)
		global_position.y = maxf(global_position.y, 1.8)
	move_and_slide()

	if get_slide_collision_count() > 0 and _speed > 12.0:
		health.damage(_speed * 1.1)
		_speed *= 0.45
		Fx.impact(self, global_position, Color(0.93, 0.92, 0.86))
		Sfx.play_at("hit", global_position)

	if Input.is_action_pressed("fire"):
		guns.try_fire(forward)
	if guns.ammo != _last_ammo:
		_last_ammo = guns.ammo
		Events.ammo_changed.emit(guns.ammo, guns.data.magazine_size)

func _bail_out() -> void:
	var exit_pos := global_position + Vector3.UP * 0.5
	var p := driver
	driver = null
	_speed = 0.0
	rotation.x = 0.0
	rotation.z = 0.0
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
	Fx.explosion(self, global_position, 2.0)
	queue_free()

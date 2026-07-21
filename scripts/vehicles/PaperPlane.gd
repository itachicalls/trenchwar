class_name PaperPlane
extends CharacterBody3D
## Drivable paper airplane with forgiving arcade flight:
##   W / S      throttle up / down
##   Mouse      pitch and banking turns (yaw follows roll, like a real glider)
##   Left click wing-mounted dart pods
##   E          bail out (works anytime; you're a toy, the carpet is soft)
## Below stall speed it glides gently down instead of tumbling.

const MAX_SPEED := 22.0
const MIN_FLY_SPEED := 6.0
const THROTTLE_RATE := 10.0

var driver: Player = null
var health: Health
var guns: Weapon
var _speed := 0.0
var _pitch := 0.0
var _roll := 0.0
var _cam_arm: SpringArm3D
var _camera: Camera3D
var _prompt: Label3D
var _paper_mat: StandardMaterial3D

func _ready() -> void:
	collision_layer = 0b0100
	collision_mask = 0b0001
	add_to_group("vehicles")

	health = Health.new()
	health.setup(120.0)
	health.died.connect(_on_destroyed)
	add_child(health)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.4, 0.5, 2.6)
	shape.shape = box
	add_child(shape)
	_build_visual()

	var pivot := Node3D.new()
	pivot.position.y = 1.0
	add_child(pivot)
	_cam_arm = SpringArm3D.new()
	_cam_arm.spring_length = 8.0
	_cam_arm.collision_mask = 0b0001
	_cam_arm.rotation_degrees.x = -12.0
	pivot.add_child(_cam_arm)
	_camera = Camera3D.new()
	_camera.fov = 75.0
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

func _build_visual() -> void:
	_paper_mat = ToyMaterials.plastic(Color(0.93, 0.92, 0.86), 0.75)
	var lined := ToyMaterials.plastic(Color(0.8, 0.82, 0.88), 0.75)
	# Fuselage crease — two long thin triangular prisms approximated with boxes.
	var spine := MeshInstance3D.new()
	var spine_mesh := PrismMesh.new()
	spine_mesh.size = Vector3(0.7, 0.9, 3.6)
	spine.mesh = spine_mesh
	spine.material_override = _paper_mat
	spine.position.y = 0.1
	add_child(spine)
	# Folded wings, angled slightly up.
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wing_mesh := BoxMesh.new()
		wing_mesh.size = Vector3(2.0, 0.06, 3.2)
		wing.mesh = wing_mesh
		wing.material_override = lined if side < 0 else _paper_mat
		wing.position = Vector3(side * 1.05, 0.32, 0.2)
		wing.rotation_degrees.z = side * 8.0
		add_child(wing)

func _unhandled_input(event: InputEvent) -> void:
	if driver == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_pitch = clampf(_pitch + event.relative.y * 0.0022, -0.9, 0.9)
		_roll = clampf(_roll - event.relative.x * 0.003, -1.1, 1.1)

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	# Touch look-drag flies the plane.
	if driver != null and Game.touch_look != Vector2.ZERO:
		_pitch = clampf(_pitch + Game.touch_look.y * 0.6, -0.9, 0.9)
		_roll = clampf(_roll - Game.touch_look.x * 0.8, -1.1, 1.1)
		Game.touch_look = Vector2.ZERO
	if driver == null:
		_check_mount()
		if not is_on_floor():
			velocity.y -= 10.0 * delta   # paper falls slowly
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
		driver = p
		p.enter_vehicle(self)
		_speed = MIN_FLY_SPEED
		_pitch = -0.15   # gentle initial climb
		_roll = 0.0
		_camera.make_current()
		_prompt.visible = false
		Events.weapon_changed.emit(guns.data.display_name)
		Events.ammo_changed.emit(guns.ammo, guns.data.magazine_size)
		Events.notify.emit("Airborne! W/S throttle, mouse steers, E to bail out.")

func _fly(delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		_bail_out()
		return
	var throttle := Input.get_axis("move_back", "move_forward")
	_speed = clampf(_speed + throttle * THROTTLE_RATE * delta, 0.0, MAX_SPEED)
	# Slow decay toward glide speed; paper planes never just stop mid-air.
	_speed = maxf(_speed - 0.8 * delta, 0.0)
	_roll = move_toward(_roll, 0.0, 1.2 * delta)   # auto-level the bank

	# Yaw follows roll (coordinated turn), pitch is direct.
	rotation.y += -_roll * 1.6 * delta
	rotation.x = lerp_angle(rotation.x, -_pitch, 6.0 * delta)
	rotation.z = lerp_angle(rotation.z, _roll * 0.7, 6.0 * delta)

	var forward := -global_transform.basis.z
	velocity = forward * _speed
	# Below stall speed: mush downward, keep it gentle and readable.
	if _speed < MIN_FLY_SPEED:
		velocity.y -= (MIN_FLY_SPEED - _speed) * 2.2
	move_and_slide()

	# Crashing into things hurts the plane, not the pilot.
	if get_slide_collision_count() > 0 and _speed > 10.0:
		health.damage(_speed * 1.5)
		_speed *= 0.4
		Fx.impact(self, global_position, Color(0.93, 0.92, 0.86))
		Sfx.play_at("hit", global_position)

	if Input.is_action_pressed("fire"):
		guns.try_fire(forward)
	Events.ammo_changed.emit(guns.ammo, guns.data.magazine_size)

func _bail_out() -> void:
	var exit_pos := global_position + Vector3.UP * 0.5
	var p := driver
	driver = null
	_speed = 0.0
	rotation.x = 0.0
	rotation.z = 0.0
	p.exit_vehicle(exit_pos)
	p.velocity = velocity * 0.5   # inherit some momentum, land with style
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

class_name Player
extends Unit
## The player's customizable Green Army soldier: third-person camera with
## over-the-shoulder aim, sprint/jump movement, shooting, squad commands.

const MOUSE_SENS := 0.0028
const SPRINT_MULT := 1.65

var _yaw := 0.0
var _pitch := -0.25
var _spring: SpringArm3D
var _camera: Camera3D
var _cam_pivot: Node3D
var _aiming := false
var _shake := 0.0
var _step_timer := 0.0
var _land_dip := 0.0
var _was_on_floor := true
var current_vehicle: Node = null
var _regen_delay := 0.0
var _face_cam_timer := 0.0

## Timed powerups: id -> seconds remaining ("rapid", "speed", "shield").
var _powerups := {}
var _shield_bubble: MeshInstance3D

## Jetpack: double-tap jump to engage, hold to burn. Gas cans refill it.
const FUEL_MAX := 100.0
const JET_DRAIN := 20.0        ## fuel per second of burn
const JET_LIFT := 14.0         ## target climb speed (clears couch/bed decks)
var fuel := FUEL_MAX
var _jet_engaged := false
var _jet_flames: Array = []
var _fuel_warned := false
var _jet_burning := false
var _jet_was_burning := false

## Read by the HUD every frame for the dynamic crosshair.
var aim_at_enemy := false
var _aim_point := Vector3.ZERO

## Two weapon slots: [0] = Armory loadout, [1] = field pickup.
## Q toggles, so a drop never traps you with a gun you hate.
var _slots: Array[Dictionary] = []
var _slot := 0

func _init() -> void:
	# Equipped Armory loadout, applied before Unit._ready builds the weapon.
	weapon_data = load(Game.weapon_info(Game.selected_weapon).path)

func _body_params() -> Dictionary:
	return {"gun": Game.weapon_info(Game.selected_weapon).gun,
		"tint": Game.skin_data(Game.selected_skin).tint}

func _unit_ready() -> void:
	# Rooms aim the spawn by rotating the Player node — usually AFTER
	# add_child (so after this very function ran). _fold_node_yaw() in the
	# physics loop is what actually adopts it; this just covers pre-rotation.
	_fold_node_yaw()
	# Solid furniture landings: snap to decks, don't sink into couch/bed tops.
	floor_snap_length = 0.4
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(58.0)
	safe_margin = 0.1
	# Slightly slimmer capsule so jet cresting clears furniture lips.
	for c in get_children():
		if c is CollisionShape3D and c.shape is CapsuleShape3D:
			(c.shape as CapsuleShape3D).radius = 0.28
			break
	# Store upgrades bought with coins apply here, on every spawn.
	base_health = 200.0 + 50.0 * Game.upgrades.get("health", 0)
	weapon.damage_mult = 1.0 + 0.2 * Game.upgrades.get("damage", 0)
	weapon.reload_mult = 1.0 - 0.15 * Game.upgrades.get("reload", 0)
	move_speed = move_speed * (1.0 + 0.08 * Game.upgrades.get("speed", 0))
	health.setup(base_health)
	health.changed.connect(func(c, m): Events.player_health_changed.emit(c, m))
	weapon.ammo_updated.connect(func(a, m): Events.ammo_changed.emit(a, m))

	_cam_pivot = Node3D.new()
	_cam_pivot.position.y = 1.25
	add_child(_cam_pivot)
	_spring = SpringArm3D.new()
	_spring.spring_length = 4.2
	_spring.position = Vector3(0.55, 0.25, 0)   # over-the-shoulder offset
	_spring.collision_mask = 0b0001
	_spring.margin = 0.25
	_cam_pivot.add_child(_spring)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_spring.add_child(_camera)
	_camera.make_current()

	_slots = [{"data": weapon.data, "gun": Game.weapon_info(Game.selected_weapon).gun, "ammo": -1}]

	_build_jetpack()

	Events.player_spawned.emit(self)
	Events.fuel_changed.emit(fuel, FUEL_MAX)
	Events.player_health_changed.emit(health.current, health.max_health)
	Events.ammo_changed.emit(weapon.ammo, weapon.data.magazine_size)
	Events.weapon_changed.emit(weapon.data.display_name)

# ----------------------------------------------------------------- JETPACK

## Strap the toy jetpack onto the soldier's back and rig unlit flame jets
## on both nozzles (they only emit while burning).
func _build_jetpack() -> void:
	if body_rig == null:
		return
	# Bone-attached: rides the torso through every animation.
	var pack := ModelLib.attach_jetpack(body_rig)
	for nozzle in pack.get_meta("nozzles", []):
		var flame := CPUParticles3D.new()
		flame.emitting = false
		flame.amount = 22
		flame.lifetime = 0.28
		flame.direction = Vector3.DOWN
		flame.spread = 8.0
		flame.initial_velocity_min = 5.0
		flame.initial_velocity_max = 8.0
		flame.gravity = Vector3.ZERO
		flame.scale_amount_min = 0.05
		flame.scale_amount_max = 0.12
		flame.color = Color(1.0, 0.65, 0.15)
		var fm := BoxMesh.new()
		fm.size = Vector3.ONE
		fm.material = ToyMaterials.glow(Color(1.0, 0.6, 0.2), 3.0)
		flame.mesh = fm
		nozzle.add_child(flame)
		_jet_flames.append(flame)

## Called by gas can pickups.
func refill_fuel(amount: float) -> void:
	fuel = minf(fuel + amount, FUEL_MAX)
	Events.fuel_changed.emit(fuel, FUEL_MAX)

## Double-jump engages the pack; holding jump burns fuel for lift. Landing
## disengages so the next flight is a deliberate double-tap again.
func _update_jetpack(delta: float) -> void:
	if is_on_floor():
		_jet_engaged = false
	elif Input.is_action_just_pressed("jump") and fuel > 0.0:
		_jet_engaged = true
		Fx.ring_pulse(self, global_position, Color(1.0, 0.7, 0.2), 1.2, 0.3)
	_jet_burning = _jet_engaged and not is_on_floor() \
		and Input.is_action_pressed("jump") and fuel > 0.0
	if _jet_engaged and fuel <= 0.0 and not _fuel_warned:
		_fuel_warned = true
		Events.notify.emit("JETPACK EMPTY — grab a GAS CAN to refuel!")
	if _jet_burning:
		velocity.y = move_toward(velocity.y, JET_LIFT, 70.0 * delta)
		fuel = maxf(fuel - JET_DRAIN * delta, 0.0)
		Events.fuel_changed.emit(fuel, FUEL_MAX)
		_try_jet_mantle()
	_update_jet_sfx(delta)
	for f in _jet_flames:
		if f.emitting != _jet_burning:
			f.emitting = _jet_burning

## Seamless thruster loop while burning. No 5s "ignite" one-shot — that kept
## roaring after the player already let go of jump.
func _update_jet_sfx(_delta: float) -> void:
	if _jet_burning and not _jet_was_burning:
		Sfx.start_loop("jet_loop", -14.0, 1.02)
		Sfx.start_loop("jet_hum", -22.0, 0.88)
	elif not _jet_burning and _jet_was_burning:
		Sfx.stop_loop("jet_loop", 0.08)
		Sfx.stop_loop("jet_hum", 0.06)
	if _jet_burning:
		# Climb harder → hotter pitch; easing off softens the roar.
		var climb := clampf((velocity.y + 2.0) / (JET_LIFT + 2.0), 0.0, 1.0)
		var pitch := lerpf(0.9, 1.12, climb)
		var vol := lerpf(-16.0, -11.0, climb)
		Sfx.set_loop("jet_loop", vol, pitch)
		Sfx.set_loop("jet_hum", lerpf(-24.0, -18.0, climb), lerpf(0.82, 0.96, climb))
	_jet_was_burning = _jet_burning

## When the jet hits a furniture SIDE, hop the capsule onto the ledge instead
## of sliding forever against the wall (couch/bed cresting).
func _try_jet_mantle() -> void:
	if get_world_3d() == null:
		return
	var space := get_world_3d().direct_space_state
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3(0, 0, -1)
	else:
		forward = forward.normalized()
	# Blocked at chest, clear above the lip → boost up and onto the deck.
	var chest := global_position + Vector3.UP * 0.9
	var wall := PhysicsRayQueryParameters3D.create(chest, chest + forward * 1.1)
	wall.collision_mask = 0b0001
	wall.exclude = [get_rid()]
	var hit := space.intersect_ray(wall)
	if hit.is_empty():
		return
	var above := global_position + Vector3.UP * 2.4 + forward * 0.35
	var clear := PhysicsRayQueryParameters3D.create(above, above + forward * 0.8)
	clear.collision_mask = 0b0001
	clear.exclude = [get_rid()]
	if not space.intersect_ray(clear).is_empty():
		return
	velocity.y = maxf(velocity.y, JET_LIFT + 4.0)
	velocity.x += forward.x * 6.0
	velocity.z += forward.z * 6.0

# ------------------------------------------------------------- WEAPON SLOTS

## Field pickup: goes into slot 1 and is equipped immediately.
func equip_weapon_data(wd: WeaponData, gun: String) -> void:
	_slots[_slot].ammo = weapon.ammo
	var entry := {"data": wd, "gun": gun, "ammo": -1}
	if _slots.size() < 2:
		_slots.append(entry)
	else:
		_slots[1] = entry
	_slot = 1
	_apply_slot()

## Armory purchase/equip mid-mission: replaces the loadout slot.
func set_loadout(wd: WeaponData, gun: String) -> void:
	_slots[0] = {"data": wd, "gun": gun, "ammo": -1}
	if _slot == 0:
		_apply_slot()

func toggle_weapon() -> void:
	if _slots.size() < 2:
		return
	_slots[_slot].ammo = weapon.ammo
	_slot = 1 - _slot
	_apply_slot()
	Sfx.play("reload", -10.0)
	Events.notify.emit("SWAPPED TO: %s   [Q]" % weapon.data.display_name.to_upper())

func _apply_slot() -> void:
	var s: Dictionary = _slots[_slot]
	weapon.set_data(s.data)
	# Slots remember their partial magazines between swaps.
	if s.ammo >= 0:
		weapon.ammo = s.ammo
		weapon.ammo_updated.emit(weapon.ammo, weapon.data.magazine_size)
	if body_rig != null:
		ModelLib.set_gun(body_rig, s.gun)
	Events.weapon_changed.emit(weapon.data.display_name)

func _unhandled_input(event: InputEvent) -> void:
	if not Game.is_playing():
		return
	# Web: first click captures the mouse (required by browsers). Must work
	# while boarded too — vehicles only look when pointer-lock is active.
	if OS.has_feature("web") and not Game.is_touch() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			Game.capture_mouse()
		return
	if current_vehicle != null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Pointer-lock acquisition can deliver one giant bogus delta (the
		# browser reports the jump to screen center). Swallow it.
		if event.relative.length() > 250.0:
			return
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.35, 1.05)

## THE "force looks left when firing" bug, root-caused: rooms rotate the
## Player NODE to face the action (player.rotation_degrees.y = ...), but they
## do it after add_child, i.e. after _unit_ready already sampled rotation.
## The camera (a child) inherited the node yaw so the VIEW looked correct,
## while _yaw stayed 0 — and everything computed from _yaw (move directions,
## the between-shots body facing) was off by the spawn angle. Firing made it
## obvious: the body whipped toward stale _yaw between snaps.
## Fix: every physics frame, fold any external node yaw into camera yaw and
## zero the node, keeping the body's world facing unchanged.
func _fold_node_yaw() -> void:
	if absf(rotation.y) < 0.0001:
		return
	_yaw += rotation.y
	rotation.y = 0.0
	if _cam_pivot != null:
		_cam_pivot.rotation.y = _yaw
	if body_rig != null:
		body_rig.rotation.y = _yaw

## Touch look-drag accumulated by TouchControls; consumed once per frame.
func _consume_touch_look() -> void:
	if Game.touch_look == Vector2.ZERO:
		return
	_yaw -= Game.touch_look.x
	_pitch = clampf(_pitch - Game.touch_look.y, -1.35, 1.05)
	Game.touch_look = Vector2.ZERO

## Gyro fine-aim (COD-style). Touch does big turns; tilt does micro-adjust.
const GYRO_SENS := 1.35
func _consume_gyro(delta: float) -> void:
	if not Game.is_touch() or not Game.gyro_enabled or Game.needs_landscape:
		return
	var g := Input.get_gyroscope()
	if g.length_squared() < 0.0001:
		return
	# Landscape phone: device Y ≈ world yaw, device X ≈ pitch. Clamp wild spikes.
	_yaw -= clampf(g.y, -4.0, 4.0) * GYRO_SENS * delta
	_pitch = clampf(_pitch - clampf(g.x, -4.0, 4.0) * GYRO_SENS * delta, -1.35, 1.05)

func _physics_process(delta: float) -> void:
	if Game.needs_landscape:
		return
	if _dying or _celebrating:
		# Cinematic moments (death keel-over, victory wave): gravity only, no
		# input. Runs even in VICTORY state, so land softly if we were mid-jump.
		if not get_tree().paused:
			if not is_on_floor():
				velocity.y -= 30.0 * delta
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
			move_and_slide()
		return
	if current_vehicle != null or not Game.is_playing():
		return
	_fold_node_yaw()
	_consume_touch_look()
	_consume_gyro(delta)
	_update_aim_probe()
	_apply_lock_magnet(delta)
	_update_camera(delta)
	_update_movement(delta)
	_update_combat()
	_update_interactions()
	_update_regen(delta)
	_update_powerups(delta)

## Battlefield-style recovery: stay out of fire for a few seconds and
## health climbs back, so one bad firefight isn't a death sentence.
func _update_regen(delta: float) -> void:
	_regen_delay = maxf(_regen_delay - delta, 0.0)
	if _regen_delay <= 0.0 and not health.dead and health.current < health.max_health:
		health.heal(20.0 * delta)

## One screen-center raycast per tick: feeds firing AND the crosshair state.
func _update_aim_probe() -> void:
	var from := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var excludes: Array[RID] = [get_rid()]
	for mate in Game.squad:
		if is_instance_valid(mate):
			excludes.append(mate.get_rid())
	var hit := _aim_ray(from, dir, 200.0, excludes)
	# On a mesa looking down (or under a shelf looking up) the first hit is
	# often YOUR deck/ceiling a meter in front of the lens. Pierce close
	# non-hostiles whenever you're pitched enough to be cresting furniture.
	if not hit.is_empty() and absf(dir.y) > 0.28 \
			and from.distance_to(hit.position) < 5.5 and not _is_hostile(hit.collider):
		var past: Vector3 = hit.position + dir * 0.25
		var pierce := _aim_ray(past, dir, 200.0 - from.distance_to(past), excludes)
		if not pierce.is_empty():
			hit = pierce
		elif absf(dir.y) > 0.35:
			# Empty air past the deck — keep aiming along the look axis.
			hit = {}
	if hit.is_empty():
		_aim_point = from + dir * 200.0
		aim_at_enemy = false
	else:
		_aim_point = hit.position
		aim_at_enemy = _is_hostile(hit.collider)
		# Hard lock owns assist — sticky old soft-targets must not fight look.
		if aim_at_enemy and hit.collider is Node3D:
			_assist_target = hit.collider as Node3D
	# Soft assist only when the ray is empty / on furniture — never while the
	# player is looking steeply (that was the "locked facing one spot" bug:
	# magnet kept yanking pitch back to a Chrome chest on the floor).
	if _wants_aim_lock():
		if not aim_at_enemy and absf(dir.y) <= 0.38:
			_apply_aim_assist(from, dir)
			if _assist_target != null and is_instance_valid(_assist_target):
				aim_at_enemy = true
		elif not aim_at_enemy:
			_assist_target = null
	else:
		_assist_target = null

func _aim_ray(from: Vector3, dir: Vector3, dist: float, excludes: Array[RID]) -> Dictionary:
	if get_world_3d() == null or dist <= 0.05:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * dist)
	query.collision_mask = 0b0111
	query.exclude = excludes
	return get_world_3d().direct_space_state.intersect_ray(query)

func _wants_aim_lock() -> bool:
	return Input.is_action_pressed("aim") or Input.is_action_pressed("fire")

func _is_hostile(c: Object) -> bool:
	if not (c is Node):
		return false
	var n := c as Node
	if n.is_in_group("enemies") or n.is_in_group("chrome_pods"):
		return true
	# Arena bots: anything on a faction hostile to ours.
	return n.is_in_group("combat_bots") and "faction" in n and n.faction != null \
		and faction.hostile_to(n.faction)

## Aim assist / lock. Campaign gets a sticky lock with mild camera magnetism;
## arenas stay lighter so PvE skirmish still rewards aim.
var _assist_target: Node3D = null
var _assist_scan_cd := 0.0
func _apply_aim_assist(from: Vector3, dir: Vector3) -> void:
	# Throttle full enemy scans — same stickiness, less web CPU while firing.
	_assist_scan_cd -= get_physics_process_delta_time()
	if _assist_scan_cd > 0.0 and _assist_target != null and is_instance_valid(_assist_target):
		_nudge_aim_to_target(from, dir, _assist_target)
		return
	_assist_scan_cd = 0.08 if Game.low_gfx() else 0.04
	var best: Node3D = null
	var campaign := Game.in_campaign()
	# Narrower cones — wide soft-lock was yanking you onto floor Chrome while
	# you tried to shoot down a ledge / up a shelf.
	var cone_deg := 10.0 if campaign else (7.0 if Game.is_touch() else 5.5)
	if campaign and Game.is_touch():
		cone_deg = 12.0
	var cone := deg_to_rad(cone_deg)
	var best_angle := cone
	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group("enemies"))
	candidates.append_array(get_tree().get_nodes_in_group("combat_bots"))
	for e in candidates:
		if e is Node3D and is_instance_valid(e) and _is_hostile(e) \
				and not (e.has_method("is_dead") and e.is_dead()):
			var chest: Vector3 = (e as Node3D).global_position + Vector3.UP * 0.8
			var to := chest - from
			var d := to.length()
			if d < 2.0 or d > (70.0 if campaign else 55.0):
				continue
			var to_n := to / d
			# Reject targets that sit at a very different pitch than look —
			# stops floor units stealing aim when you're looking up/down.
			if absf(to_n.y - dir.y) > 0.42:
				continue
			var angle := dir.angle_to(to_n)
			if e == _assist_target:
				angle *= 0.45 if campaign else 0.6
			if angle < best_angle:
				best_angle = angle
				best = e
	if best == null:
		_assist_target = null
		return
	var chest: Vector3 = best.global_position + Vector3.UP * 0.8
	var los := PhysicsRayQueryParameters3D.create(from, chest)
	los.collision_mask = 0b0001
	var block := get_world_3d().direct_space_state.intersect_ray(los)
	var blocked := not block.is_empty()
	if blocked and absf(dir.y) > 0.35 and from.distance_to(block.position) < 5.0:
		blocked = false
	if blocked:
		_assist_target = null
		return
	_assist_target = best
	_nudge_aim_to_target(from, dir, best, best_angle, cone)

func _nudge_aim_to_target(from: Vector3, dir: Vector3, best: Node3D,
		best_angle: float = -1.0, cone: float = 0.2) -> void:
	var chest: Vector3 = best.global_position + Vector3.UP * 0.8
	var to := chest - from
	var d := to.length()
	if d < 0.5:
		return
	var to_n := to / d
	if absf(to_n.y - dir.y) > 0.5:
		_assist_target = null
		return
	var campaign := Game.in_campaign()
	if best_angle < 0.0:
		best_angle = dir.angle_to(to_n)
	var strength: float = lerpf(
		0.78 if campaign else 0.55,
		0.4 if campaign else 0.28,
		clampf(best_angle / maxf(cone, 0.001), 0.0, 1.0))
	if best is CharacterBody3D:
		var travel: float = d / maxf(weapon.data.projectile_speed, 1.0)
		chest += (best as CharacterBody3D).velocity * travel * (0.7 if campaign else 0.5)
	_aim_point = _aim_point.lerp(chest, strength)

## Campaign soft lock: yaw-only magnet toward the locked target.
## Pitch stays fully player-owned — magnetizing pitch was the up/down lock.
func _apply_lock_magnet(delta: float) -> void:
	if not _wants_aim_lock():
		return
	if not Game.in_campaign() or _assist_target == null or not is_instance_valid(_assist_target):
		return
	if _camera == null:
		return
	var cam_fwd := -_camera.global_transform.basis.z
	# Looking steeply: no magnet at all — free vertical + horizontal aim.
	if absf(cam_fwd.y) > 0.38:
		return
	var chest: Vector3 = _assist_target.global_position + Vector3.UP * 0.85
	var to: Vector3 = chest - _camera.global_position
	if to.length_squared() < 0.01:
		return
	var want := to.normalized()
	# Bail if the lock sits at a different pitch than we're looking.
	if absf(want.y - cam_fwd.y) > 0.4:
		return
	var flat := Vector3(want.x, 0.0, want.z)
	if flat.length_squared() < 0.0001:
		return
	var pull := 2.0 * delta if Game.is_touch() else 1.6 * delta
	var want_yaw := atan2(-flat.x, -flat.z)
	var yaw_err := absf(wrapf(want_yaw - _yaw, -PI, PI))
	if yaw_err <= deg_to_rad(22.0):
		_yaw = lerp_angle(_yaw, want_yaw, pull)

func _update_camera(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Subtle strafe roll sells the camera as a physical thing.
	var target_roll := -input.x * 0.035
	_cam_pivot.rotation = Vector3(_pitch, _yaw, lerpf(_cam_pivot.rotation.z, target_roll, 8.0 * delta))
	var sprinting := Input.is_action_pressed("sprint") and not _aiming and input.length() > 0.1
	var target_len := 2.2 if _aiming else 4.2
	var target_fov := 55.0 if _aiming else (77.0 if sprinting else 70.0)
	_spring.spring_length = lerpf(_spring.spring_length, target_len, 12.0 * delta)
	_camera.fov = lerpf(_camera.fov, target_fov, 8.0 * delta)
	_land_dip = maxf(_land_dip - delta * 1.6, 0.0)
	var dip := -sin(minf(_land_dip * 4.0, PI)) * 0.22
	if _shake > 0.0:
		_shake = maxf(_shake - delta * 4.0, 0.0)
		_camera.h_offset = randf_range(-_shake, _shake) * 0.12
		_camera.v_offset = randf_range(-_shake, _shake) * 0.12 + dip
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = dip

func _update_movement(delta: float) -> void:
	# Jet burn cancels gravity so climb rate stays honest against tall decks.
	_update_jetpack(delta)
	if not _jet_burning:
		apply_gravity(delta)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := Basis(Vector3.UP, _yaw)
	var wish := (cam_basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := move_speed * (SPRINT_MULT if Input.is_action_pressed("sprint") and not _aiming else 1.0)
	if has_powerup("speed"):
		speed *= 1.45
	# Airborne jet: keep full air control so you can crest furniture tops.
	var accel := 40.0 if is_on_floor() else 28.0
	velocity.x = move_toward(velocity.x, wish.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, accel * delta)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = 13.0   # ~3.5 u apex: book-stair steps are jumpable
		Sfx.play("step", -18.0, 0.08)
		Fx.dust(self, global_position)
	move_and_slide()
	# Plant hard on decks — kill residual downward speed so we don't sink
	# a frame into couch cushions / mattress colliders.
	if is_on_floor():
		velocity.y = 0.0

	# Landing feedback: camera dip + dust kick.
	if is_on_floor() and not _was_on_floor:
		_land_dip = 1.0
		Fx.dust(self, global_position, true)
		Sfx.play("step", -16.0, 0.06)
	_was_on_floor = is_on_floor()

	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	# Airborne = flying pose (legs tucked); grounded = the usual gait.
	if not is_on_floor():
		play_anim("Jump_Idle", 0.2)
	else:
		animate_waddle(delta, moving)
	if moving and is_on_floor():
		_step_timer -= delta
		if _step_timer <= 0.0:
			var sprinting := Input.is_action_pressed("sprint")
			# Soft carpet taps, slower cadence — background, not a metronome.
			_step_timer = 0.38 if sprinting else 0.52
			Sfx.play("step", -15.0 if sprinting else -18.5, 0.1)
			if sprinting:
				Fx.dust(self, global_position)

	# Face movement direction, or camera direction while aiming/firing.
	# The fire-facing lingers briefly so single taps don't whip the body
	# back to the run direction between shots.
	if _aiming or Input.is_action_pressed("fire"):
		_face_cam_timer = 0.45
	_face_cam_timer = maxf(_face_cam_timer - delta, 0.0)
	if _aiming or _face_cam_timer > 0.0:
		face_direction(-cam_basis.z, delta, 30.0)
	elif moving:
		face_direction(wish, delta)
	# Lean the toy torso with look pitch so firing up/down reads on the body
	# (yaw-only facing made steep shots feel "locked horizontal").
	if body_rig != null:
		var want_lean := 0.0
		if _aiming or _face_cam_timer > 0.0 or not is_on_floor():
			want_lean = clampf(_pitch * 0.55, -0.55, 0.4)
		body_rig.rotation.x = lerpf(body_rig.rotation.x, want_lean, 12.0 * delta)

func _update_combat() -> void:
	# Web desktop: while the pointer isn't locked yet, the camera can't turn —
	# firing in that state is the "frozen camera, then boom" glitch. The first
	# click's only job is acquiring the lock.
	if OS.has_feature("web") and not Game.is_touch() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if Game.needs_landscape:
		return
	_aiming = Input.is_action_pressed("aim")
	# Auto-fire ONLY while ADS + reticle on a hostile — hip-fire stays manual.
	var auto := Game.is_touch() and Game.auto_fire_enabled and _aiming and aim_at_enemy
	var want_fire := Input.is_action_pressed("fire") or auto
	if want_fire if (weapon.data.automatic or auto) else Input.is_action_just_pressed("fire"):
		if weapon.try_fire(_aim_direction()):
			# Snap the body square to the shot the instant it fires — no
			# lerp lag frame where the soldier fires across his shoulder.
			# Pure vertical aims have no horizontal component; face camera yaw.
			var face := _aim_point - global_position
			face.y = 0.0
			if face.length_squared() < 0.04:
				face = -Basis(Vector3.UP, _yaw).z
			face_direction(face, 1.0, 999.0)
			_shake = minf(_shake + 0.35 * weapon.data.recoil, 2.0)
	if Input.is_action_just_pressed("reload"):
		weapon.reload()

## Fire along the camera. Mild pitch already trusts the lens; steeper look
## always does. Floor/furniture aim points must not flatten ledge shots.
func _aim_direction() -> Vector3:
	var cam_fwd := -_camera.global_transform.basis.z
	if absf(cam_fwd.y) > 0.28 or _aiming:
		return cam_fwd
	var dir := _aim_point - weapon.muzzle.global_position
	if dir.length_squared() < 0.0001:
		return cam_fwd
	dir = dir.normalized()
	# Blend toward camera so assist nudge helps horizontally without killing pitch.
	if dir.dot(cam_fwd) < 0.15:
		return cam_fwd
	return dir.lerp(cam_fwd, 0.35).normalized()

func _update_interactions() -> void:
	if Input.is_action_just_pressed("swap_weapon"):
		toggle_weapon()
	if Input.is_action_just_pressed("cmd_follow"):
		_command_squad("follow")
	elif Input.is_action_just_pressed("cmd_hold"):
		_command_squad("hold")
	elif Input.is_action_just_pressed("cmd_charge"):
		_command_squad("charge")

func _command_squad(mode: String) -> void:
	for mate in Game.squad:
		if is_instance_valid(mate):
			mate.set_command(mode)
	Events.squad_mode_changed.emit(mode)
	Sfx.play("click")

# ------------------------------------------------------------- POWERUPS

func apply_powerup(id: String, duration: float) -> void:
	_powerups[id] = duration
	Events.powerup_started.emit(id, duration)
	Events.notify.emit({"rapid": "RAPID FIRE!", "speed": "SUGAR RUSH!", "shield": "BUBBLE SHIELD!"}.get(id, id))
	if id == "shield":
		_set_shield_visible(true)

func has_powerup(id: String) -> bool:
	return _powerups.get(id, 0.0) > 0.0

func _update_powerups(delta: float) -> void:
	for id in _powerups.keys():
		if _powerups[id] > 0.0:
			_powerups[id] -= delta
			if _powerups[id] <= 0.0 and id == "shield":
				_set_shield_visible(false)
	weapon.rate_mult = 2.2 if has_powerup("rapid") else 1.0
	if _shield_bubble != null and _shield_bubble.visible:
		var t := Time.get_ticks_msec() * 0.004
		_shield_bubble.scale = Vector3.ONE * (1.0 + sin(t) * 0.04)

func _set_shield_visible(on: bool) -> void:
	if _shield_bubble == null:
		_shield_bubble = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.2
		sm.height = 2.4
		_shield_bubble.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.6, 1.0, 0.16)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.rim_enabled = true
		mat.rim = 1.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shield_bubble.material_override = mat
		_shield_bubble.position.y = 0.8
		add_child(_shield_bubble)
	_shield_bubble.visible = on

func take_damage(amount: float, attacker: Node = null) -> void:
	if has_powerup("shield"):
		# The bubble eats the hit entirely — sparks, no damage.
		Fx.impact(self, global_position + Vector3.UP, Color(0.5, 0.7, 1.0))
		Sfx.play("hit", -10.0)
		return
	super.take_damage(amount, attacker)
	_regen_delay = 4.0
	Events.player_damaged.emit()
	Sfx.play("hurt", -6.0)
	_shake = minf(_shake + 0.5, 2.0)

## Mission won: down weapon, spin to face the camera, and wave at the player.
## Runs during Main's victory breather before the menu appears.
var _celebrating := false
func celebrate() -> void:
	if _dying or _celebrating:
		return
	_celebrating = true
	# Winners are invincible — a stray last bullet must not ruin the moment.
	collision_layer = 0
	if body_rig != null:
		var tw := create_tween()
		tw.tween_property(body_rig, "rotation:y", _yaw + PI, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _anim != null and _anim.has_animation("Jump"):
		play_anim("Jump", 0.15)
	get_tree().create_timer(0.6).timeout.connect(func():
		if is_instance_valid(self) and _anim != null and _anim.has_animation("Wave"):
			play_anim("Wave", 0.2))

var _dying := false
func _on_died(_attacker: Node) -> void:
	# Toy-soldier death cinematic: the mold keels over in slow motion while
	# the camera lingers, THEN shatters. No more instant despawn.
	_dying = true
	_jet_burning = false
	_jet_was_burning = false
	Sfx.stop_loop("jet_loop")
	Sfx.stop_loop("jet_hum")
	Sfx.stop_loop("engine")
	collision_layer = 0
	velocity = Vector3.ZERO
	Sfx.play("death")
	Engine.time_scale = 0.35
	if _anim != null and _anim.has_animation("Death"):
		play_anim("Death", 0.1)
	elif body_rig != null:
		# Fallback rig has no Death clip: tip over sideways like a knocked toy.
		var tip := create_tween()
		tip.tween_property(body_rig, "rotation:z", PI / 2.0, 0.5) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# Real-time timer (ignores the slow-mo) ends the moment.
	get_tree().create_timer(1.1, true, false, true).timeout.connect(func():
		Engine.time_scale = 1.0
		Fx.plastic_shatter(self, global_position + Vector3.UP * 0.7, faction.primary_color)
		Events.unit_died.emit(self)
		Events.player_died.emit()
		queue_free())

func enter_vehicle(vehicle: Node) -> void:
	current_vehicle = vehicle
	visible = false
	collision_layer = 0
	Events.vehicle_entered.emit(vehicle)

func exit_vehicle(at: Vector3) -> void:
	current_vehicle = null
	visible = true
	collision_layer = 0b0010
	global_position = at
	_camera.make_current()
	Events.vehicle_exited.emit()

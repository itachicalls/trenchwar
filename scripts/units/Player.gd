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
const JET_DRAIN := 22.0        ## fuel per second of burn
const JET_LIFT := 9.5          ## target climb speed
var fuel := FUEL_MAX
var _jet_engaged := false
var _jet_flames: Array = []
var _jet_sfx_timer := 0.0
var _fuel_warned := false

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
	var burning := _jet_engaged and not is_on_floor() \
		and Input.is_action_pressed("jump") and fuel > 0.0
	# Ran the tank dry mid-air: tell the player what refills it (once).
	if _jet_engaged and fuel <= 0.0 and not _fuel_warned:
		_fuel_warned = true
		Events.notify.emit("JETPACK EMPTY — grab a GAS CAN to refuel!")
	if burning:
		velocity.y = move_toward(velocity.y, JET_LIFT, 55.0 * delta)
		fuel = maxf(fuel - JET_DRAIN * delta, 0.0)
		Events.fuel_changed.emit(fuel, FUEL_MAX)
		_jet_sfx_timer -= delta
		if _jet_sfx_timer <= 0.0:
			_jet_sfx_timer = 0.22
			Sfx.play_at("engine", global_position, -16.0)
	for f in _jet_flames:
		if f.emitting != burning:
			f.emitting = burning

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
	if not Game.is_playing() or current_vehicle != null:
		return
	# Web: first click captures the mouse (required by browsers). Touch
	# devices skip pointer lock entirely — TouchControls drives the look.
	if OS.has_feature("web") and not Game.is_touch() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			Game.capture_mouse()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Pointer-lock acquisition can deliver one giant bogus delta (the
		# browser reports the jump to screen center). Swallow it.
		if event.relative.length() > 250.0:
			return
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.2, 0.7)

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
	_pitch = clampf(_pitch - Game.touch_look.y, -1.2, 0.7)
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
	_pitch = clampf(_pitch - clampf(g.x, -4.0, 4.0) * GYRO_SENS * delta, -1.2, 0.7)

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
	_update_camera(delta)
	_update_movement(delta)
	_update_aim_probe()
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
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0)
	query.collision_mask = 0b0111
	# Squadmates crossing the reticle must not hijack the aim point.
	var excludes: Array[RID] = [get_rid()]
	for mate in Game.squad:
		if is_instance_valid(mate):
			excludes.append(mate.get_rid())
	query.exclude = excludes
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_aim_point = from + dir * 200.0
		aim_at_enemy = false
	else:
		_aim_point = hit.position
		var c: Object = hit.collider
		aim_at_enemy = _is_hostile(c)
	if not aim_at_enemy:
		_apply_aim_assist(from, dir)

func _is_hostile(c: Object) -> bool:
	if not (c is Node):
		return false
	var n := c as Node
	if n.is_in_group("enemies") or n.is_in_group("chrome_pods"):
		return true
	# Arena bots: anything on a faction hostile to ours.
	return n.is_in_group("combat_bots") and "faction" in n and n.faction != null \
		and faction.hostile_to(n.faction)

## Soft aim lock: if a hostile is within a ~7° cone of the crosshair (and
## visible), shots bend hard toward their chest. The camera never moves —
## only the fired projectile direction is helped — and it prefers to stay on
## the current target so the lock doesn't ping-pong between clustered enemies.
var _assist_target: Node3D = null
func _apply_aim_assist(from: Vector3, dir: Vector3) -> void:
	var best: Node3D = null
	# Thumbs are coarser than mice: touch gets a wider assist cone.
	var cone := deg_to_rad(10.0 if Game.is_touch() else 7.0)
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
			if d < 2.0 or d > 65.0:
				continue
			var angle := dir.angle_to(to / d)
			# Stickiness: the current target wins ties inside a wider cone,
			# so tracking one enemy through a crowd feels locked-on.
			if e == _assist_target:
				angle *= 0.55
			if angle < best_angle:
				best_angle = angle
				best = e
	if best == null:
		_assist_target = null
		return
	var chest: Vector3 = best.global_position + Vector3.UP * 0.8
	var los := PhysicsRayQueryParameters3D.create(from, chest)
	los.collision_mask = 0b0001   # only world geometry blocks the assist
	if get_world_3d().direct_space_state.intersect_ray(los).is_empty():
		_assist_target = best
		# Pull strength grows as the crosshair gets closer to the target:
		# near-misses become hits, wild shots still miss.
		var strength: float = lerpf(0.9, 0.45, clampf(best_angle / cone, 0.0, 1.0))
		# Lead moving targets so the assist works on strafing bots too.
		if best is CharacterBody3D:
			var travel: float = chest.distance_to(from) / maxf(weapon.data.projectile_speed, 1.0)
			chest += (best as CharacterBody3D).velocity * travel * 0.6
		_aim_point = _aim_point.lerp(chest, strength)
	else:
		_assist_target = null

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
	apply_gravity(delta)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := Basis(Vector3.UP, _yaw)
	var wish := (cam_basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := move_speed * (SPRINT_MULT if Input.is_action_pressed("sprint") and not _aiming else 1.0)
	if has_powerup("speed"):
		speed *= 1.45
	velocity.x = move_toward(velocity.x, wish.x * speed, 40.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z * speed, 40.0 * delta)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = 13.0   # ~3.5 u apex: book-stair steps are jumpable
		Sfx.play("step", -12.0)
		Fx.dust(self, global_position)
	_update_jetpack(delta)
	move_and_slide()

	# Landing feedback: camera dip + dust kick.
	if is_on_floor() and not _was_on_floor:
		_land_dip = 1.0
		Fx.dust(self, global_position, true)
		Sfx.play("step", -10.0)
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
			_step_timer = 0.32 / (SPRINT_MULT if sprinting else 1.0)
			Sfx.play("step", -18.0)
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
	# Auto-fire: when the reticle is on a hostile, keep shooting (mobile
	# default — frees the right thumb to look while the gun tracks).
	var auto := Game.is_touch() and Game.auto_fire_enabled and aim_at_enemy
	var want_fire := Input.is_action_pressed("fire") or auto
	if want_fire if (weapon.data.automatic or auto) else Input.is_action_just_pressed("fire"):
		if weapon.try_fire(_aim_direction()):
			# Snap the body square to the shot the instant it fires — no
			# lerp lag frame where the soldier fires across his shoulder.
			face_direction(_aim_point - global_position, 1.0, 999.0)
			_shake = minf(_shake + 0.35 * weapon.data.recoil, 2.0)
	if Input.is_action_just_pressed("reload"):
		weapon.reload()

## Fire toward whatever the crosshair probe hit this tick.
func _aim_direction() -> Vector3:
	var cam_fwd := -_camera.global_transform.basis.z
	var dir := _aim_point - weapon.muzzle.global_position
	# Hugging a wall can put the aim point BEHIND the muzzle, which would
	# invert the shot. Fall back to camera-forward in that case.
	if dir.dot(cam_fwd) < 0.2:
		return cam_fwd
	return dir.normalized()

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

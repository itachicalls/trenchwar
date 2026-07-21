class_name SquadMate
extends Unit
## Friendly Green Army AI. Starts as a rescuable prisoner ("stuck" pose);
## once freed, joins the player's squad and obeys commands:
##   follow — stay near the player, engage what they engage
##   hold   — defend current position
##   charge — hunt the nearest enemy aggressively

@export var starts_captive: bool = true

var command: String = "follow"
var captive: bool = true
var target: Node3D = null
var _nav: NavigationAgent3D
var _think_timer := 0.0
var _hold_position: Vector3
var _follow_offset: Vector3
var _prompt: Label3D
var _stuck_time := 0.0

func _unit_ready() -> void:
	add_to_group("green_allies")
	captive = starts_captive
	# Own layer: enemy fire still hits mates, but the player never collides
	# with them — a squadmate can never body-block your movement.
	collision_layer = 0b1000
	collision_mask = 0b1111   # still collides with world, units and each other
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.6
	_nav.target_desired_distance = 1.2
	add_child(_nav)
	_follow_offset = Vector3(randf_range(-2.2, 2.2), 0, randf_range(1.4, 3.0))
	if captive:
		if _anim != null:
			play_anim("Duck")   # crouched prisoner pose
		else:
			body_rig.rotation_degrees.x = 12.0   # slumped, waiting for rescue
		_prompt = Label3D.new()
		_prompt.text = "[E]  RESCUE"
		_prompt.font_size = 56
		_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_prompt.modulate = Color(0.6, 1.0, 0.6)
		_prompt.outline_size = 10
		_prompt.position.y = 2.3
		_prompt.visible = false
		add_child(_prompt)
		set_physics_process(true)

func rescue() -> void:
	if not captive:
		return
	captive = false
	body_rig.rotation_degrees.x = 0.0
	play_anim("Idle")
	if _prompt != null:
		_prompt.queue_free()
		_prompt = null
	Game.add_squad_member(self)
	Sfx.play("pickup")
	Events.notify.emit("Squadmate rescued! [1] Follow  [2] Hold  [3] Charge")
	Missions.progress("rescue")

func set_command(mode: String) -> void:
	command = mode
	if mode == "hold":
		_hold_position = global_position

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	if NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) == 0:
		return
	apply_gravity(delta)
	if captive:
		move_and_slide()
		_check_rescue()
		return
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.3
		_acquire_target()
	_act(delta)
	move_and_slide()
	animate_waddle(delta, Vector2(velocity.x, velocity.z).length() > 0.5)

func _check_rescue() -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	# Horizontal distance with a generous height tolerance: a captive on a
	# ledge or crate must still be rescuable from beside it.
	var delta3: Vector3 = p.global_position - global_position
	var near: bool = Vector2(delta3.x, delta3.z).length() < 3.2 and absf(delta3.y) < 3.0
	if _prompt != null:
		_prompt.visible = near
	if near and Input.is_action_just_pressed("interact"):
		rescue()

func _acquire_target() -> void:
	target = null
	var range_limit := 16.0 if command != "charge" else 40.0
	var best := range_limit
	# Duck-typed is_dead(): enemies group holds Units and bosses alike.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node3D and is_instance_valid(enemy) and not enemy.is_dead():
			var d := global_position.distance_to(enemy.global_position)
			if d < best:
				best = d
				target = enemy

func _act(delta: float) -> void:
	var speed := move_speed * faction.speed_multiplier
	# Engage if we can see the target.
	if target != null and _can_see(target):
		var dist := global_position.distance_to(target.global_position)
		face_direction(target.global_position - global_position, delta, 9.0)
		if dist < 14.0:
			var aim := target.global_position + Vector3.UP * 0.8
			aim += Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
			weapon.try_fire(aim_dir_at(aim))
		if command == "charge" and dist > 8.0:
			_move_toward_point(target.global_position, delta, speed)
			return
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		return
	# Otherwise obey stance.
	match command:
		"follow":
			if Game.player != null and is_instance_valid(Game.player):
				_do_follow(delta, speed)
		"hold":
			if global_position.distance_to(_hold_position) > 1.5:
				_move_toward_point(_hold_position, delta, speed)
			else:
				velocity.x = 0.0
				velocity.z = 0.0
		"charge":
			if target != null:
				_move_toward_point(target.global_position, delta, speed * 1.2)
			else:
				velocity.x = 0.0
				velocity.z = 0.0

## Formation slot BEHIND the player's facing (the player node never rotates —
## only its body_rig yaws — so the offset must use the rig's yaw, not the
## node basis, or mates end up standing in front of you).
func _do_follow(delta: float, speed: float) -> void:
	var p := Game.player
	var facing_yaw: float = p.body_rig.rotation.y if p.body_rig != null else 0.0
	var anchor: Vector3 = p.global_position + Basis(Vector3.UP, facing_yaw) * _follow_offset
	var dist_to_anchor := global_position.distance_to(anchor)
	var to_player: Vector3 = p.global_position - global_position
	var flat_to_player := Vector2(to_player.x, to_player.z)

	# Personal space: back out of the player's way instead of hugging them.
	if flat_to_player.length() < 1.1:
		var away := -Vector3(flat_to_player.x, 0, flat_to_player.y).normalized()
		velocity.x = away.x * speed * 0.8
		velocity.z = away.z * speed * 0.8
		return

	if dist_to_anchor > 2.0:
		_move_toward_point(anchor, delta, speed * 1.15)
		# Unstick: making no progress (or hopelessly far) → regroup teleport.
		var flat_speed := Vector2(velocity.x, velocity.z).length()
		_stuck_time = _stuck_time + delta if flat_speed < 0.6 else 0.0
		if _stuck_time > 2.5 or to_player.length() > 30.0:
			_stuck_time = 0.0
			# Snap onto the navmesh near the player — never inside furniture.
			var want: Vector3 = p.global_position + Basis(Vector3.UP, facing_yaw) \
				* Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(1.2, 2.2))
			var map := get_world_3d().navigation_map
			global_position = NavigationServer3D.map_get_closest_point(map, want) + Vector3.UP * 0.3
			Fx.dust(self, global_position)
	else:
		_stuck_time = 0.0
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)

func _can_see(node: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.1, node.global_position + Vector3.UP * 0.8)
	query.collision_mask = 0b0001
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _move_toward_point(point: Vector3, delta: float, speed: float) -> void:
	_nav.target_position = point
	if _nav.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var dir := _nav.get_next_path_position() - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	face_direction(dir, delta)

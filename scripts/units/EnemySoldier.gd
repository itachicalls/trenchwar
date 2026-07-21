class_name EnemySoldier
extends Unit
## Chrome Legion infantry AI: patrols a route, spots targets by line-of-sight,
## fights from strafing positions, and calls nearby allies when it engages.

enum AiState { PATROL, ALERT, COMBAT }

## Enemy variations, all one script + data. Set BEFORE add_child().
##   trooper — baseline SMG line infantry
##   scout   — fast, fragile, harassing pistol fire
##   heavy   — slow shotgun wall with double health, bigger model
##   sniper  — long-range single shots that force you to move
const VARIANTS := {
	"trooper": {"gun": "SMG", "weapon": "res://data/weapons/chrome_blaster.tres",
		"health": 100.0, "speed": 6.0, "scale": 1.0, "tint": Color.WHITE,
		"vision": 18.0, "attack": 14.0},
	"scout": {"gun": "Pistol", "weapon": "res://data/weapons/chrome_needler.tres",
		"health": 55.0, "speed": 8.5, "scale": 0.88, "tint": Color(1.15, 0.95, 0.8),
		"vision": 20.0, "attack": 12.0},
	"heavy": {"gun": "Shotgun", "weapon": "res://data/weapons/chrome_scatter.tres",
		"health": 240.0, "speed": 3.8, "scale": 1.22, "tint": Color(0.65, 0.7, 0.85),
		"vision": 16.0, "attack": 10.0},
	"sniper": {"gun": "Sniper", "weapon": "res://data/weapons/chrome_lance.tres",
		"health": 70.0, "speed": 5.0, "scale": 1.0, "tint": Color(0.9, 0.7, 0.75),
		"vision": 30.0, "attack": 26.0},
}

@export var patrol_points: Array[Vector3] = []
@export var vision_range: float = 18.0
@export var attack_range: float = 14.0
@export var alert_radius: float = 10.0

var variant: String = "trooper":
	set(v):
		variant = v if VARIANTS.has(v) else "trooper"
		var cfg: Dictionary = VARIANTS[variant]
		weapon_data = load(cfg.weapon)
		base_health = cfg.health
		move_speed = cfg.speed
		vision_range = cfg.vision
		attack_range = cfg.attack

var state: AiState = AiState.PATROL
var target: Node3D = null
var _nav: NavigationAgent3D
var _patrol_index := 0
var _think_timer := 0.0
var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _lost_sight_time := 0.0
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO

func _body_params() -> Dictionary:
	var cfg: Dictionary = VARIANTS[variant]
	return {"gun": cfg.gun, "tint": cfg.tint, "scale": cfg.scale}

func _unit_ready() -> void:
	add_to_group("enemies")
	# Full mask incl. squadmates (0b1000): enemies must not ghost through
	# friendly soldiers.
	collision_mask = 0b1111
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.6
	_nav.target_desired_distance = 0.8
	_nav.radius = 0.4
	add_child(_nav)
	if patrol_points.is_empty():
		patrol_points = [global_position]
	# Stagger AI ticks so a platoon doesn't think on the same frame.
	_think_timer = randf() * 0.3

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	# Nav map syncs on the first physics frame; querying earlier spams errors.
	if NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) == 0:
		return
	apply_gravity(delta)
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.25
		_think()
	match state:
		AiState.PATROL:
			_do_patrol(delta)
		AiState.ALERT:
			_do_move_to_target(delta, true)
		AiState.COMBAT:
			_do_combat(delta)
	move_and_slide()
	_detect_stuck(delta)
	animate_waddle(delta, Vector2(velocity.x, velocity.z).length() > 0.5)

## Wanting to move but going nowhere = wedged against furniture. After 1.5s,
## snap back onto the navmesh and path around whatever we ground against.
func _detect_stuck(delta: float) -> void:
	var wants_move := Vector2(velocity.x, velocity.z).length() > 1.0
	var progress := global_position.distance_to(_last_pos)
	_last_pos = global_position
	if wants_move and progress < 0.02:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time > 1.5:
		_stuck_time = 0.0
		var map := get_world_3d().navigation_map
		var jitter := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		var free_point := NavigationServer3D.map_get_closest_point(map, global_position + jitter)
		global_position = free_point + Vector3.UP * 0.2
		if state == AiState.COMBAT:
			state = AiState.ALERT   # re-path via the navmesh instead of beelining

## ---- decision layer (runs at 4 Hz) ----
func _think() -> void:
	target = _acquire_target()
	if target != null:
		if _has_line_of_sight(target):
			_lost_sight_time = 0.0
			if state != AiState.COMBAT:
				_enter_combat()
		else:
			_lost_sight_time += 0.25
			if state == AiState.COMBAT and _lost_sight_time > 3.0:
				state = AiState.ALERT   # chase last known position
			_nav.target_position = target.global_position
	else:
		state = AiState.PATROL

func _acquire_target() -> Node3D:
	var best: Node3D = null
	var best_dist := vision_range
	var candidates: Array[Node] = []
	if Game.player != null and is_instance_valid(Game.player):
		# A driven vehicle IS the player as far as the AI cares.
		if Game.player.current_vehicle != null and is_instance_valid(Game.player.current_vehicle):
			candidates.append(Game.player.current_vehicle)
		else:
			candidates.append(Game.player)
	candidates.append_array(get_tree().get_nodes_in_group("green_allies"))
	for c in candidates:
		if c is Node3D and is_instance_valid(c) and not (c.has_method("is_dead") and c.is_dead()):
			var d := global_position.distance_to(c.global_position)
			if d < best_dist:
				best_dist = d
				best = c
	return best

func _has_line_of_sight(node: Node3D) -> bool:
	var from := global_position + Vector3.UP * 1.1
	var to := node.global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b0001   # only world geometry blocks vision
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _enter_combat() -> void:
	state = AiState.COMBAT
	# Squad tactics: wake up everyone nearby.
	for ally in get_tree().get_nodes_in_group("enemies"):
		if ally != self and ally is EnemySoldier and global_position.distance_to(ally.global_position) < alert_radius:
			if ally.state == AiState.PATROL:
				ally.state = AiState.ALERT
				ally.target = target
				if ally._nav != null and target != null:
					ally._nav.target_position = target.global_position

## ---- behaviour layer ----
func _do_patrol(delta: float) -> void:
	var goal := patrol_points[_patrol_index]
	if global_position.distance_to(goal) < 1.0:
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		goal = patrol_points[_patrol_index]
	_nav.target_position = goal
	_move_along_path(delta, move_speed * faction.speed_multiplier * 0.5)

func _do_move_to_target(delta: float, chase: bool) -> void:
	if target == null or not is_instance_valid(target):
		state = AiState.PATROL
		return
	if chase:
		_nav.target_position = target.global_position
	_move_along_path(delta, move_speed * faction.speed_multiplier)
	if _has_line_of_sight(target) and global_position.distance_to(target.global_position) < attack_range:
		_enter_combat()

func _do_combat(delta: float) -> void:
	if target == null or not is_instance_valid(target) or (target.has_method("is_dead") and target.is_dead()):
		target = null
		state = AiState.PATROL
		return
	var dist := global_position.distance_to(target.global_position)
	var to_target := target.global_position - global_position

	if dist > attack_range * 0.85:
		# Approach through the navmesh — beelining into furniture was the
		# old "enemies grinding against objects" bug.
		_nav.target_position = target.global_position
		_move_along_path(delta, move_speed * faction.speed_multiplier * 0.9)
	else:
		# In range: strafe and keep spacing on open ground.
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = randf_range(0.8, 2.0)
			_strafe_dir = -_strafe_dir
		var side := to_target.cross(Vector3.UP).normalized() * _strafe_dir
		var wish := side * 0.6
		if dist < attack_range * 0.4:
			wish += -to_target.normalized()
		wish = wish.normalized()
		var speed := move_speed * faction.speed_multiplier * 0.8
		velocity.x = wish.x * speed
		velocity.z = wish.z * speed
	face_direction(to_target, delta, 8.0)

	if dist < attack_range and _has_line_of_sight(target):
		# Toy soldiers are not marksmen: aim error shrinks up close but never
		# reaches zero — point-blank enemies shouldn't be laser-accurate.
		var error: float = 0.4 + clampf(dist / attack_range, 0.0, 1.0) * 1.1
		var aim_point: Vector3 = target.global_position + Vector3.UP * 0.8 + Vector3(randf_range(-error, error), randf_range(-error * 0.5, error * 0.5), randf_range(-error, error))
		weapon.try_fire(aim_dir_at(aim_point))

func _move_along_path(delta: float, speed: float) -> void:
	if _nav.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		return
	var next := _nav.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	face_direction(dir, delta)

func take_damage(amount: float, attacker: Node = null) -> void:
	super.take_damage(amount, attacker)
	# Getting shot reveals the shooter even without line of sight.
	if attacker is Node3D and is_instance_valid(attacker) and target == null:
		target = attacker
		state = AiState.ALERT
		_nav.target_position = attacker.global_position

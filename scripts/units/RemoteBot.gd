class_name RemoteBot
extends CharacterBody3D
## Client-side puppet for a server-authoritative CombatBot. Position, health
## and gunfire are all relayed from the authority so the fight a client sees
## matches the one being simulated.

const SNAP_DISTANCE := 6.0
const EXTRAPOLATE_MAX := 0.2
const SMOOTHING := 14.0

var bot_id: int = 0
var faction: FactionData
var variant: String = "trooper"
var body_rig: Node3D
var health_bar: HealthBar3D
var muzzle: Node3D

var _yaw := 0.0
var _dead := false
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO
var _pose_age := 0.0
var _have_pose := false
var _anim: AnimationPlayer
var _last_weapon_path := ""
var _last_weapon: WeaponData = null

func _ready() -> void:
	collision_layer = 0b0010
	collision_mask = 0b0111
	add_to_group("combat_bots")
	add_to_group("net_bots")
	if faction == null:
		faction = load("res://data/factions/chrome_legion.tres")
	add_to_group("team_" + faction.id)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.4
	shape.shape = capsule
	shape.position.y = 0.7
	add_child(shape)
	body_rig = ModelLib.build_character(faction, faction.id == "chrome_legion", "AK")
	add_child(body_rig)
	if body_rig.has_meta("anim"):
		_anim = body_rig.get_meta("anim")
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -0.45)
	var mount := body_rig.get_node_or_null("WeaponMount")
	if mount != null:
		mount.add_child(muzzle)
	else:
		muzzle.position = Vector3(0, 1.35, -0.45)
		add_child(muzzle)
	health_bar = HealthBar3D.new()
	health_bar.position.y = 1.85
	add_child(health_bar)
	_net_pos = global_position

func _physics_process(delta: float) -> void:
	if not _have_pose or _dead:
		return
	_pose_age += delta
	var target := _net_pos + _net_vel * minf(_pose_age, EXTRAPOLATE_MAX)
	if global_position.distance_to(target) > SNAP_DISTANCE:
		global_position = target
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-SMOOTHING * delta))
	if body_rig != null:
		body_rig.rotation.y = lerp_angle(body_rig.rotation.y, _yaw, minf(SMOOTHING * delta, 1.0))
	if _anim != null:
		var want := "Run_Gun" if Vector2(_net_vel.x, _net_vel.z).length() > 0.8 else "Idle"
		if _anim.has_animation(want) and _anim.current_animation != want:
			_anim.play(want, 0.25)

## Bot poses carry no velocity, so estimate it from consecutive packets —
## that's what lets the puppet keep walking between updates instead of
## stuttering forward ten times a second.
func apply_net_pose(pos: Vector3, yaw: float, hp_ratio: float = -1.0) -> void:
	if _have_pose and _pose_age > 0.0001:
		var est := (pos - _net_pos) / _pose_age
		est.y = 0.0
		if est.length() < 20.0:
			_net_vel = _net_vel.lerp(est, 0.5)
	else:
		global_position = pos
	_net_pos = pos
	_yaw = yaw
	velocity = _net_vel
	_pose_age = 0.0
	_have_pose = true
	if hp_ratio >= 0.0 and health_bar != null:
		health_bar.update_ratio(hp_ratio)

func fire_visual(origin: Vector3, dir: Vector3, weapon_path: String) -> void:
	if _dead or dir.length_squared() < 0.0001:
		return
	var wd := _weapon_for(weapon_path)
	if wd == null:
		return
	Projectile.spawn_cosmetic(self, origin, dir.normalized(), wd, self, faction)
	if muzzle != null:
		Fx.muzzle_flash(muzzle, wd.projectile_color, 0.7 + wd.recoil * 0.45)
	Sfx.play_at(wd.sound, origin, -7.0)

func _weapon_for(weapon_path: String) -> WeaponData:
	if weapon_path == _last_weapon_path and _last_weapon != null:
		return _last_weapon
	if weapon_path == "" or not ResourceLoader.exists(weapon_path):
		weapon_path = "res://data/weapons/plastic_rifle.tres"
	var wd := load(weapon_path) as WeaponData
	if wd == null:
		return _last_weapon
	_last_weapon_path = weapon_path
	_last_weapon = wd
	return wd

func take_damage(amount: float, attacker: Node = null) -> void:
	if _dead:
		return
	Fx.impact(self, global_position + Vector3.UP, faction.primary_color)
	var net := get_node_or_null("/root/Net")
	if net != null and net.get("is_online"):
		net.report_bot_hit(bot_id, amount)

func is_dead() -> bool:
	return _dead

func mark_dead() -> void:
	_dead = true
	Events.unit_died.emit(self)
	Fx.plastic_shatter(self, global_position + Vector3.UP * 0.7, faction.primary_color)
	queue_free()

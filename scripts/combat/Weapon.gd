class_name Weapon
extends Node3D
## Mountable weapon driven entirely by a WeaponData resource.
## Used by the player, AI soldiers and vehicle turrets alike.

signal fired
signal ammo_updated(ammo: int, magazine: int)

@export var data: WeaponData
var owner_unit: Node3D
var faction: FactionData
var ammo: int
var _cooldown: float = 0.0
var _reloading: bool = false
var muzzle: Node3D

## Runtime multipliers: store upgrades and timed powerups hook in here.
var rate_mult := 1.0
var damage_mult := 1.0
var reload_mult := 1.0

func _ready() -> void:
	if data == null:
		data = load("res://data/weapons/plastic_rifle.tres")
	ammo = data.magazine_size
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -0.45)
	add_child(muzzle)

func set_data(new_data: WeaponData) -> void:
	data = new_data
	ammo = data.magazine_size
	_reloading = false
	_gun_prop = null   # gun model swaps with the loadout; re-find on next shot
	ammo_updated.emit(ammo, data.magazine_size)

func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)

func can_fire() -> bool:
	return _cooldown <= 0.0 and ammo > 0 and not _reloading

## direction is world-space. Returns true if a shot actually happened.
func try_fire(direction: Vector3) -> bool:
	if not can_fire():
		if ammo <= 0 and not _reloading:
			reload()
		return false
	_cooldown = 1.0 / (data.fire_rate * rate_mult)
	ammo -= 1
	var base := direction.normalized()
	for i in data.pellets:
		var spread := deg_to_rad(data.spread_degrees)
		# Cross(UP) collapses when firing nearly straight up/down — that used
		# to NaN the shot and force a horizontal "forward" feel on ledges.
		var yaw_axis := Vector3.UP
		var pitch_axis := base.cross(yaw_axis)
		if pitch_axis.length_squared() < 0.001:
			pitch_axis = base.cross(Vector3.RIGHT)
		if pitch_axis.length_squared() < 0.001:
			pitch_axis = Vector3.FORWARD
		pitch_axis = pitch_axis.normalized()
		var dir := base.rotated(yaw_axis, randf_range(-spread, spread))
		dir = dir.rotated(pitch_axis, randf_range(-spread, spread)).normalized()
		Projectile.spawn(self, muzzle.global_position, dir, data, owner_unit, faction, damage_mult)
	# Heavier weapons flash bigger and kick the in-hand gun model harder —
	# each gun gets its own visible firing personality from its recoil stat.
	Fx.muzzle_flash(muzzle, data.projectile_color, 0.7 + data.recoil * 0.45)
	_kick_gun_model()
	Sfx.play_at(data.sound, muzzle.global_position, -4.0)
	fired.emit()
	ammo_updated.emit(ammo, data.magazine_size)
	if ammo <= 0:
		reload()
	return true

## Per-shot recoil animation on the owner's visible gun prop: snap back and
## up, then ease home. BoneAttachment3D transforms are overwritten by the
## skeleton every frame, so the tween targets the mesh INSIDE the attachment.
var _gun_prop: Node3D = null
var _kick_tween: Tween = null

func _kick_gun_model() -> void:
	if _gun_prop == null or not is_instance_valid(_gun_prop):
		_gun_prop = null
		if owner_unit != null and "body_rig" in owner_unit and owner_unit.body_rig != null:
			for att in owner_unit.body_rig.find_children("*", "BoneAttachment3D", true, false):
				if att.visible and att.get_child_count() > 0:
					_gun_prop = att.get_child(0)
					break
	if _gun_prop == null:
		return
	# Rest pose comes from the glTF, not zero — remember it so repeated kicks
	# never walk the gun away from the hand.
	if not _gun_prop.has_meta("rest_z"):
		_gun_prop.set_meta("rest_z", _gun_prop.position.z)
		_gun_prop.set_meta("rest_rx", _gun_prop.rotation.x)
	var rest_z: float = _gun_prop.get_meta("rest_z")
	var rest_rx: float = _gun_prop.get_meta("rest_rx")
	if _kick_tween != null and _kick_tween.is_valid():
		_kick_tween.kill()
	var kick := 0.06 * data.recoil
	_gun_prop.position.z = rest_z + kick
	_gun_prop.rotation.x = rest_rx - kick * 1.2
	_kick_tween = _gun_prop.create_tween().set_parallel(true)
	_kick_tween.tween_property(_gun_prop, "position:z", rest_z, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_kick_tween.tween_property(_gun_prop, "rotation:x", rest_rx, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func reload() -> void:
	if _reloading or ammo == data.magazine_size:
		return
	_reloading = true
	Sfx.play_at("reload", global_position, -8.0)
	get_tree().create_timer(data.reload_time * reload_mult).timeout.connect(func():
		if not is_instance_valid(self):
			return
		_reloading = false
		ammo = data.magazine_size
		ammo_updated.emit(ammo, data.magazine_size))

func is_reloading() -> bool:
	return _reloading

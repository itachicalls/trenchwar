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
	for i in data.pellets:
		var spread := deg_to_rad(data.spread_degrees)
		var dir := direction.rotated(Vector3.UP, randf_range(-spread, spread))
		dir = dir.rotated(dir.cross(Vector3.UP).normalized(), randf_range(-spread, spread))
		Projectile.spawn(self, muzzle.global_position, dir, data, owner_unit, faction, damage_mult)
	Fx.muzzle_flash(muzzle, data.projectile_color)
	Sfx.play_at(data.sound, muzzle.global_position, -4.0)
	fired.emit()
	ammo_updated.emit(ammo, data.magazine_size)
	if ammo <= 0:
		reload()
	return true

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

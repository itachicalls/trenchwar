class_name Pickup
extends Area3D
## Collectible pickups with full presentation: unique toy mesh per type, a soft
## vertical light beam, a glowing ground ring, idle sparkles, bob + spin, and a
## magnet pull once the player gets close. Collecting pops a ring pulse.

enum Kind { PARTS, HEALTH, AMMO, COIN, RAPID, SPEED, SHIELD }

const COLORS := {
	Kind.PARTS: Color(0.45, 1.0, 0.55),
	Kind.HEALTH: Color(1.0, 0.4, 0.4),
	Kind.AMMO: Color(1.0, 0.85, 0.3),
	Kind.COIN: Color(1.0, 0.78, 0.2),
	Kind.RAPID: Color(1.0, 0.45, 0.1),
	Kind.SPEED: Color(0.3, 0.9, 1.0),
	Kind.SHIELD: Color(0.45, 0.6, 1.0),
}
## Powerup durations in seconds, by kind.
const POWERUP_TIME := {Kind.RAPID: 12.0, Kind.SPEED: 10.0, Kind.SHIELD: 8.0}
const POWERUP_IDS := {Kind.RAPID: "rapid", Kind.SPEED: "speed", Kind.SHIELD: "shield"}
const MAGNET_RANGE := 4.5
const MAGNET_SPEED := 9.0

var kind: Kind = Kind.PARTS
var amount: int = 1
var _spin: Node3D
var _base_y := 0.0
var _t := randf() * TAU
var _magnetized := false
var _light: OmniLight3D

static func spawn_parts(root: Node, position: Vector3, count: int) -> void:
	_place(root, _make(Kind.PARTS, count), position)

static func spawn_health(root: Node, position: Vector3, heal: int = 40) -> void:
	_place(root, _make(Kind.HEALTH, heal), position)

static func spawn_ammo(root: Node, position: Vector3) -> void:
	_place(root, _make(Kind.AMMO, 1), position)

static func spawn_coin(root: Node, position: Vector3, value: int = 1) -> void:
	_place(root, _make(Kind.COIN, value), position)

static func spawn_powerup(root: Node, position: Vector3, which: Kind) -> void:
	_place(root, _make(which, 1), position)

static func random_powerup() -> Kind:
	return [Kind.RAPID, Kind.SPEED, Kind.SHIELD][randi() % 3]

static func _place(root: Node, p: Pickup, position: Vector3) -> void:
	root.add_child(p)
	p.global_position = position + Vector3.UP * 0.55
	p._base_y = p.global_position.y

static func _make(kind_: Kind, amount_: int) -> Pickup:
	var p := Pickup.new()
	p.kind = kind_
	p.amount = amount_
	return p

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0b0010
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	shape.shape = sphere
	add_child(shape)

	var color: Color = COLORS[kind]
	_spin = Node3D.new()
	add_child(_spin)
	match kind:
		Kind.PARTS: _build_parts(color)
		Kind.HEALTH: _build_battery(color)
		Kind.AMMO: _build_ammo_crate(color)
		Kind.COIN: _build_coin(color)
		Kind.RAPID: _build_rapid(color)
		Kind.SPEED: _build_speed(color)
		Kind.SHIELD: _build_shield(color)
	_build_presentation(color)
	body_entered.connect(_on_body_entered)

# --- type-specific toy meshes ---

## A little stack of two offset toy bricks with studs.
func _build_parts(color: Color) -> void:
	var mat := ToyMaterials.plastic(color, 0.3)
	var mat2 := ToyMaterials.plastic(color.lightened(0.25), 0.3)
	for i in 2:
		var brick := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.34, 0.16, 0.22)
		brick.mesh = b
		brick.material_override = mat if i == 0 else mat2
		brick.position = Vector3(0.05 * i, 0.16 * i, 0.04 * i)
		brick.rotation_degrees.y = 18.0 * i
		_spin.add_child(brick)
		for sx in 2:
			var stud := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.05
			c.bottom_radius = 0.05
			c.height = 0.05
			stud.mesh = c
			stud.material_override = brick.material_override
			stud.position = brick.position + Vector3((sx - 0.5) * 0.15, 0.1, 0)
			stud.rotation_degrees.y = brick.rotation_degrees.y
			_spin.add_child(stud)

## AA battery with copper cap and glowing charge stripe = health.
func _build_battery(color: Color) -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.14
	cyl.height = 0.46
	body.mesh = cyl
	body.material_override = ToyMaterials.plastic(Color(0.16, 0.35, 0.2), 0.25)
	_spin.add_child(body)
	var stripe := MeshInstance3D.new()
	var s := CylinderMesh.new()
	s.top_radius = 0.145
	s.bottom_radius = 0.145
	s.height = 0.12
	stripe.mesh = s
	stripe.material_override = ToyMaterials.glow(color, 1.8)
	_spin.add_child(stripe)
	var cap := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.05
	c.bottom_radius = 0.05
	c.height = 0.06
	cap.mesh = c
	cap.material_override = ToyMaterials.metal(Color(0.85, 0.6, 0.3), 0.3)
	cap.position.y = 0.26
	_spin.add_child(cap)

## Tiny ammo crate with brass dart tips peeking out.
func _build_ammo_crate(color: Color) -> void:
	var crate := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.4, 0.22, 0.3)
	crate.mesh = b
	crate.material_override = ToyMaterials.plastic(Color(0.28, 0.32, 0.18), 0.5)
	_spin.add_child(crate)
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.42, 0.06, 0.32)
	band.mesh = bb
	band.material_override = ToyMaterials.glow(color, 1.2)
	_spin.add_child(band)
	for i in 3:
		var tip := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.045
		c.height = 0.14
		tip.mesh = c
		tip.material_override = ToyMaterials.metal(Color(0.85, 0.65, 0.3), 0.25)
		tip.position = Vector3(-0.1 + i * 0.1, 0.16, 0)
		_spin.add_child(tip)

# --- new pickup meshes ---

## Fat gold coin with an embossed star — the store currency.
func _build_coin(color: Color) -> void:
	var gold := ToyMaterials.metal(color, 0.22)
	var coin := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.26
	cyl.bottom_radius = 0.26
	cyl.height = 0.07
	coin.mesh = cyl
	coin.material_override = gold
	coin.rotation_degrees.x = 90.0
	_spin.add_child(coin)
	var boss := MeshInstance3D.new()
	var b := CylinderMesh.new()
	b.top_radius = 0.17
	b.bottom_radius = 0.17
	b.height = 0.1
	boss.mesh = b
	boss.material_override = ToyMaterials.glow(color.lightened(0.2), 1.1)
	boss.rotation_degrees.x = 90.0
	_spin.add_child(boss)

## Rapid fire: a trio of angry darts fanned upward.
func _build_rapid(color: Color) -> void:
	for i in 3:
		var dart := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.07
		c.height = 0.42
		dart.mesh = c
		dart.material_override = ToyMaterials.glow(color, 1.6)
		dart.position = Vector3(-0.16 + i * 0.16, 0.04 * absf(i - 1), 0)
		dart.rotation_degrees.z = -14 + i * 14.0
		_spin.add_child(dart)

## Speed: three swept chevrons.
func _build_speed(color: Color) -> void:
	for i in 3:
		var chev := MeshInstance3D.new()
		var p := PrismMesh.new()
		p.size = Vector3(0.34 - i * 0.07, 0.2, 0.1)
		chev.mesh = p
		chev.material_override = ToyMaterials.glow(color, 1.6)
		chev.position = Vector3(0, -0.14 + i * 0.2, 0)
		chev.rotation_degrees.z = 90.0
		_spin.add_child(chev)

## Shield: translucent bubble with a glowing core.
func _build_shield(color: Color) -> void:
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.14
	cm.height = 0.28
	core.mesh = cm
	core.material_override = ToyMaterials.glow(color, 2.2)
	_spin.add_child(core)
	var bubble := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.3
	bm.height = 0.6
	bubble.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.rim_enabled = true
	mat.rim = 1.0
	bubble.material_override = mat
	_spin.add_child(bubble)

# --- shared presentation: soft beam, glow disc, orbiters, pulsing light ---

func _build_presentation(color: Color) -> void:
	# Soft vertical beam: a crossed pair of textured quads (bright core,
	# feathered ends) — reads like volumetric light, not a hard cone.
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_texture = ToyMaterials.beam_tex(Color(color, 0.5))
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 3.4)
	var beam := MeshInstance3D.new()
	beam.mesh = quad
	beam.material_override = beam_mat
	beam.position.y = 1.2
	add_child(beam)

	# Ground glow disc (soft radial gradient) + thin bright ring.
	var disc := MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2(2.4, 2.4)
	disc.mesh = dq
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_texture = ToyMaterials.radial_glow_tex(Color(color, 0.55))
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = disc_mat
	disc.rotation_degrees.x = -90.0
	disc.position.y = -0.42
	add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.55
	torus.rings = 24
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = ToyMaterials.glow(color, 2.2)
	ring.name = "GlowRing"
	ring.position.y = -0.44
	ring.scale.y = 0.2
	add_child(ring)

	# Two tiny orbiting sparks — expensive-looking, costs nothing.
	for i in 2:
		var orb := MeshInstance3D.new()
		var om := SphereMesh.new()
		om.radius = 0.045
		om.height = 0.09
		om.radial_segments = 6
		om.rings = 3
		orb.mesh = om
		orb.material_override = ToyMaterials.glow(color.lightened(0.3), 3.0)
		orb.name = "Orb%d" % i
		add_child(orb)

	# Pulsing light (driven in _process).
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 0.9
	_light.omni_range = 3.5
	add_child(_light)

func _process(delta: float) -> void:
	_t += delta
	_spin.rotate_y(delta * (5.0 if kind == Kind.COIN else 2.2))
	_light.light_energy = 0.7 + sin(_t * 3.0) * 0.35
	var ring := get_node_or_null("GlowRing")
	if ring != null:
		ring.rotation.y += delta * 0.8
		var s := 1.0 + sin(_t * 2.6) * 0.08
		ring.scale = Vector3(s, 0.2, s)
	for i in 2:
		var orb := get_node_or_null("Orb%d" % i)
		if orb != null:
			var a := _t * 2.4 + i * PI
			orb.position = Vector3(cos(a) * 0.55, 0.15 + sin(_t * 1.7 + i) * 0.25, sin(a) * 0.55)
	var p := Game.player
	if _magnetized and p != null and is_instance_valid(p):
		global_position = global_position.lerp(p.global_position + Vector3.UP * 0.8, MAGNET_SPEED * delta)
		return
	global_position.y = _base_y + sin(_t * 2.4) * 0.14
	if p != null and is_instance_valid(p) and global_position.distance_to(p.global_position) < MAGNET_RANGE:
		_magnetized = true

func _on_body_entered(body: Node3D) -> void:
	if body != Game.player:
		return
	match kind:
		Kind.PARTS:
			Game.plastic_parts += amount
		Kind.HEALTH:
			body.heal(float(amount))
		Kind.AMMO:
			if body.weapon != null:
				body.weapon.ammo = body.weapon.data.magazine_size
				body.weapon.ammo_updated.emit(body.weapon.ammo, body.weapon.data.magazine_size)
		Kind.COIN:
			Game.coins += amount
			Sfx.play("pickup", 0.0)
		Kind.RAPID, Kind.SPEED, Kind.SHIELD:
			if body.has_method("apply_powerup"):
				body.apply_powerup(POWERUP_IDS[kind], POWERUP_TIME[kind])
	Fx.ring_pulse(self, global_position - Vector3.UP * 0.3, COLORS[kind], 1.8)
	Sfx.play("pickup", -4.0)
	queue_free()

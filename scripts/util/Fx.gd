class_name Fx
extends Object
## One-shot visual effects: impacts, muzzle flashes, explosions, plastic-shard deaths.
## Everything is fire-and-forget CPU particles so it costs nothing when idle
## and scales down to mobile.

static func _root(node: Node) -> Node:
	return node.get_tree().current_scene

static func impact(node: Node, position: Vector3, color: Color = Color(1, 0.9, 0.5)) -> void:
	_burst(_root(node), position, color, 8, 0.25, 3.0, 0.05)

static func explosion(node: Node, position: Vector3, radius: float = 2.5) -> void:
	var root := _root(node)
	_burst(root, position, Color(1.0, 0.6, 0.15), 26, 0.5, radius * 3.0, 0.14)
	_burst(root, position, Color(0.35, 0.32, 0.3), 16, 0.9, radius * 1.5, 0.3)
	_flash(root, position, Color(1.0, 0.7, 0.3), radius * 2.2)
	Sfx.play_at("explosion", position)

## Heavy ordnance (tank shells, mortars): fireball + smoke column + ground
## shockwave ring + tumbling debris + camera kick. The "oh THAT hit" tier.
static func ordnance_explosion(node: Node, position: Vector3, radius: float) -> void:
	var root := _root(node)
	_burst(root, position, Color(1.0, 0.65, 0.15), 34, 0.55, radius * 3.2, 0.2)
	_burst(root, position, Color(1.0, 0.9, 0.5), 14, 0.3, radius * 4.0, 0.12)
	_burst(root, position + Vector3.UP * 0.5, Color(0.3, 0.28, 0.26), 22, 1.4, radius * 1.4, 0.42)
	_burst(root, position, Color(0.55, 0.45, 0.3), 16, 1.0, radius * 2.4, 0.14, true)
	_flash(root, position, Color(1.0, 0.7, 0.3), radius * 3.0)
	ring_pulse(node, position + Vector3.UP * 0.25, Color(1.0, 0.75, 0.4), radius * 1.5, 0.5)
	shake_camera(node, clampf(radius * 0.06, 0.1, 0.4))
	Sfx.play_at("explosion", position)

## Kick the active camera around briefly. Distance-attenuated so far-away
## blasts only murmur.
static func shake_camera(node: Node, strength: float = 0.25, duration: float = 0.4) -> void:
	if node == null or not node.is_inside_tree():
		return
	var cam := node.get_viewport().get_camera_3d()
	if cam == null:
		return
	var tw := cam.create_tween()
	var steps := 6
	for i in steps:
		var falloff := 1.0 - float(i) / steps
		tw.tween_property(cam, "h_offset", randf_range(-strength, strength) * falloff, duration / steps)
		tw.parallel().tween_property(cam, "v_offset", randf_range(-strength, strength) * falloff, duration / steps)
	tw.tween_property(cam, "h_offset", 0.0, 0.08)
	tw.parallel().tween_property(cam, "v_offset", 0.0, 0.08)

## A toy doesn't bleed — it pops apart into bright plastic shards.
static func plastic_shatter(node: Node, position: Vector3, color: Color) -> void:
	_burst(_root(node), position, color, 22, 0.8, 5.0, 0.12, true)

## PERF: no per-shot OmniLight — allocating a light for every bullet was the
## single biggest frame spike with automatic weapons (each light re-renders
## nearby geometry, and web/Compatibility pays full price per light). The
## emissive star reads just as well at toy scale.
static func muzzle_flash(parent: Node3D, color: Color, size: float = 1.0) -> void:
	var flash := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	s.radial_segments = 8
	s.rings = 4
	flash.mesh = s
	flash.material_override = ToyMaterials.glow(color, 4.0)
	flash.scale = Vector3.ONE * randf_range(0.8, 1.3) * size
	parent.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "scale", Vector3.ONE * 0.05, 0.07)
	tw.tween_callback(flash.queue_free)

## Expanding, fading ring on the ground — pickups, spawns, objective pings.
static func ring_pulse(node: Node, position: Vector3, color: Color, radius: float = 1.5, duration: float = 0.45) -> void:
	var root := _root(node)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.scale = Vector3.ONE * 0.15
	root.add_child(ring)
	ring.global_position = position
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 0.4, radius), duration).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(ring.queue_free)

## Soft carpet-dust puff for footsteps and landings.
static func dust(node: Node, position: Vector3, big: bool = false) -> void:
	_burst(_root(node), position, Color(0.55, 0.5, 0.45, 0.8), 10 if big else 5, 0.5, 2.2 if big else 1.2, 0.09 if big else 0.055)

## Floating damage number that drifts up and fades. Red-orange on kill shots.
## Capped: with fast weapons, dozens of live Label3Ds tanked the frame rate.
static var _live_numbers := 0
static func damage_number(node: Node, position: Vector3, amount: float, killed: bool) -> void:
	if _live_numbers >= (6 if Game.low_gfx() else 12) and not killed:
		return
	_live_numbers += 1
	var root := _root(node)
	var label := Label3D.new()
	label.text = str(int(round(amount)))
	var f: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	if f != null:
		label.font = f
	label.font_size = 72 if killed else 52
	label.outline_size = 14
	label.modulate = Color(1.0, 0.35, 0.2) if killed else Color(1.0, 0.9, 0.5)
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.008
	root.add_child(label)
	label.global_position = position + Vector3(randf_range(-0.3, 0.3), randf_range(0.1, 0.4), randf_range(-0.3, 0.3))
	var tw := label.create_tween().set_parallel(true)
	tw.tween_property(label, "global_position:y", label.global_position.y + 1.4, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		_live_numbers = maxi(_live_numbers - 1, 0)
		label.queue_free())

static func _flash(root: Node, position: Vector3, color: Color, range_: float) -> void:
	# Explosion light bloom: desktop only — transient lights stutter the
	# Compatibility renderer, and the particle fireball carries the effect.
	if Game.low_gfx():
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = range_
	root.add_child(light)
	light.global_position = position
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.25)
	tween.tween_callback(light.queue_free)

## Capped: heavy firefights spawned unbounded particle nodes.
static var _live_bursts := 0
static func _burst(root: Node, position: Vector3, color: Color, count: int, life: float, speed: float, size: float, gravity_shards: bool = false) -> void:
	if _live_bursts >= (14 if Game.low_gfx() else 30):
		return
	_live_bursts += 1
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = count
	p.lifetime = life
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -22.0 if gravity_shards else -4.0, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = ToyMaterials.plastic(color)
	p.mesh = box
	root.add_child(p)
	p.global_position = position
	root.get_tree().create_timer(life + 0.3).timeout.connect(func():
		_live_bursts = maxi(_live_bursts - 1, 0)
		p.queue_free())

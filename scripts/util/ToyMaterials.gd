class_name ToyMaterials
extends Object
## Central material factory for the "everything is a collectible toy" art direction.
## All procedural placeholder meshes pull from here so swapping in real asset packs
## (Kenney / Quaternius / KayKit) later only means replacing meshes, not look-dev.

static var _cache: Dictionary = {}

## Near-white albedos + night exposure + bloom read as emissive lamps.
## Cap luminance on desaturated brights; leave saturated toy colors alone.
static func _tone_hot_white(color: Color, max_lum: float = 0.74) -> Color:
	var mx := maxf(color.r, maxf(color.g, color.b))
	var mn := minf(color.r, minf(color.g, color.b))
	var chroma := mx - mn
	var lum := color.get_luminance()
	if chroma > 0.14 or lum <= max_lum:
		return color
	var scale := max_lum / maxf(lum, 0.001)
	return Color(color.r * scale, color.g * scale, color.b * scale, color.a)

static func _is_hot_white(color: Color) -> bool:
	var mx := maxf(color.r, maxf(color.g, color.b))
	var mn := minf(color.r, minf(color.g, color.b))
	return (mx - mn) < 0.14 and color.get_luminance() > 0.62

## Glossy injection-molded plastic — the signature look.
static func plastic(color: Color, roughness: float = 0.32) -> StandardMaterial3D:
	var keyed := _tone_hot_white(color)
	var hot := _is_hot_white(keyed)
	if hot:
		roughness = maxf(roughness, 0.42)
	var key := "p_%s_%.2f" % [keyed.to_html(), roughness]
	if key in _cache:
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = keyed
	m.roughness = roughness
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.clearcoat_enabled = true
	# Hot whites: tame clearcoat/rim — those were the "shine lamp" edges.
	if hot:
		m.clearcoat = 0.18
		m.clearcoat_roughness = 0.5
		m.rim_enabled = false
		m.metallic_specular = 0.35
	else:
		m.clearcoat = 0.55
		m.clearcoat_roughness = 0.25
		# Rim highlight = the studio-photography edge light every toy photo has.
		# Keeps silhouettes readable even when a unit is fully backlit.
		m.rim_enabled = true
		m.rim = 0.4
		m.rim_tint = 0.6
	_cache[key] = m
	return m

## Matte porcelain / enamel (tubs, toilets, sinks, tile fixtures).
## Kept darker than "photo white" so night exposure does not read as a lamp.
static func porcelain(color: Color = Color(0.58, 0.61, 0.64), roughness: float = 0.55) -> StandardMaterial3D:
	return plastic(color, roughness)

## Room floors: looks like the glossy plastic but with the specular tamed.
## Full-gloss plastic() on a room-sized bright floor put a blinding white
## highlight under the camera in the tile rooms — floors need to read matte.
static func floor_mat(color: Color, roughness: float = 0.7) -> StandardMaterial3D:
	var keyed := _tone_hot_white(color, 0.7)
	var key := "f_%s_%.2f" % [keyed.to_html(), roughness]
	if key in _cache:
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = keyed
	m.roughness = maxf(roughness, 0.6)
	m.metallic = 0.0
	m.metallic_specular = 0.2
	_cache[key] = m
	return m

## Die-cast / chrome toys (Chrome Legion, tank treads, screws).
static func metal(color: Color, roughness: float = 0.25) -> StandardMaterial3D:
	var key := "m_%s_%.2f" % [color.to_html(), roughness]
	if key in _cache:
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	# Moderate metallic: full metal reflects only the (dark) night sky and
	# turns black without reflection probes. This keeps the die-cast look lit.
	m.metallic = 0.55
	m.rim_enabled = true
	m.rim = 0.5
	m.rim_tint = 0.3
	_cache[key] = m
	return m

## Soft matte surfaces: carpet, pillows, plush toys, curtains.
static func soft(color: Color) -> StandardMaterial3D:
	var keyed := _tone_hot_white(color, 0.78)
	var key := "s_" + keyed.to_html()
	if key in _cache:
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = keyed
	m.roughness = 0.95
	m.metallic = 0.0
	_cache[key] = m
	return m

## Emissive material for energy weapons, screens, LED eyes.
static func glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "g_%s_%.1f" % [color.to_html(), energy]
	if key in _cache:
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m

## Wood grain approximation for furniture.
static func wood(color: Color = Color(0.55, 0.38, 0.22)) -> StandardMaterial3D:
	return plank_floor(color)

# ---------------------------------------------------------------------------
# Procedural surface textures. Everything is generated once, cached, and uses
# triplanar mapping so the primitive-built rooms get real material detail
# without UV work.
# ---------------------------------------------------------------------------

## Wooden planks: rows with per-plank shade variation and dark seams.
static func plank_floor(base: Color, plank_px: int = 42) -> StandardMaterial3D:
	var key := "plank_" + base.to_html()
	if key in _cache:
		return _cache[key]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var y := 0
	var row := 0
	while y < size:
		var h := plank_px + rng.randi_range(-6, 6)
		var offset := rng.randi_range(0, size)
		var x := 0
		while x < size:
			var w := rng.randi_range(70, 130)
			var shade := 1.0 + rng.randf_range(-0.13, 0.13)
			var c := Color(base.r * shade, base.g * shade, base.b * shade)
			for px in range(x, mini(x + w, size)):
				for py in range(y, mini(y + h, size)):
					var v := c
					# grain streaks
					if (px + offset) % 17 == 0:
						v = v.darkened(0.08)
					# seams
					if py == y or px == x:
						v = v.darkened(0.35)
					img.set_pixel(px, py, v)
			x += w
		y += h
		row += 1
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = Color.WHITE
	m.roughness = 0.7
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.22
	_cache[key] = m
	return m

## Wallpaper: soft two-tone vertical stripes with paper noise.
static func wallpaper(base: Color, stripe: Color, stripe_px: int = 26) -> StandardMaterial3D:
	var key := "wall_%s_%s" % [base.to_html(), stripe.to_html()]
	if key in _cache:
		return _cache[key]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for x in size:
		var in_stripe := (x / stripe_px) % 2 == 1
		for y in size:
			var c := stripe if in_stripe else base
			var n := rng.randf_range(-0.025, 0.025)
			img.set_pixel(x, y, Color(c.r + n, c.g + n, c.b + n))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = Color.WHITE
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.16
	_cache[key] = m
	return m

## Carpet: dense speckle noise, deep and matte.
static func carpet(base: Color) -> StandardMaterial3D:
	var key := "carpet_" + base.to_html()
	if key in _cache:
		return _cache[key]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for x in size:
		for y in size:
			var n := rng.randf_range(-0.09, 0.09)
			var c := Color(base.r + n, base.g + n, base.b + n)
			if rng.randf() < 0.04:
				c = c.lightened(0.12)
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = Color.WHITE
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.55
	_cache[key] = m
	return m

## Concrete: blotchy patches + speckle, for garage floors and walls.
static func concrete(base: Color) -> StandardMaterial3D:
	var key := "conc_" + base.to_html()
	if key in _cache:
		return _cache[key]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = hash(key)
	noise.frequency = 0.02
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for x in size:
		for y in size:
			var blotch := noise.get_noise_2d(x, y) * 0.07
			var n := rng.randf_range(-0.03, 0.03)
			img.set_pixel(x, y, Color(base.r + blotch + n, base.g + blotch + n, base.b + blotch + n))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = Color.WHITE
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.12
	_cache[key] = m
	return m

## Radial soft-glow disc texture (pickup ground glow, light pools).
static func radial_glow_tex(color: Color) -> ImageTexture:
	var key := "rglow_" + color.to_html()
	if key in _cache:
		return _cache[key]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	for x in size:
		for y in size:
			var d := center.distance_to(Vector2(x, y)) / (size / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a * a * color.a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Vertical beam texture: bright core fading toward both ends and edges.
static func beam_tex(color: Color) -> ImageTexture:
	var key := "beam_" + color.to_html()
	if key in _cache:
		return _cache[key]
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for x in w:
		var edge := 1.0 - absf(x - w / 2.0) / (w / 2.0)
		for y in h:
			var tip := 1.0 - absf(y - h / 2.0) / (h / 2.0)
			var a := pow(edge, 2.2) * pow(tip, 1.4) * color.a
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

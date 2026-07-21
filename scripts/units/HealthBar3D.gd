class_name HealthBar3D
extends Node3D
## Tiny floating health bar shown above damaged units for a few seconds.
## Built from two billboarded sprites (shared white texture), so it costs
## almost nothing and needs no viewports or shaders.

const SHOW_TIME := 4.0

static var _white: ImageTexture = null

var _bg: Sprite3D
var _fill: Sprite3D
var _fill_pivot: Node3D
var _timer := 0.0

static func white_tex() -> ImageTexture:
	if _white == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white

func _ready() -> void:
	_bg = _sprite(Color(0.05, 0.05, 0.05, 0.75))
	_bg.scale = Vector3(1.0, 0.12, 1.0)
	add_child(_bg)
	_fill_pivot = Node3D.new()
	add_child(_fill_pivot)
	_fill = _sprite(Color(0.5, 0.9, 0.35))
	_fill.scale = Vector3(0.96, 0.08, 1.0)
	# Anchor fill's left edge at the bar's left edge; pivot scaling grows rightward.
	_fill.position.x = 0.48
	_fill_pivot.position.x = -0.48
	_fill_pivot.add_child(_fill)
	visible = false

func _sprite(color: Color) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = white_tex()
	s.modulate = color
	s.pixel_size = 0.25   # 4px texture → 1.0 world unit wide
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	return s

func update_ratio(ratio: float) -> void:
	_fill_pivot.scale.x = maxf(ratio, 0.001)
	_fill.modulate = Color(0.9, 0.25, 0.2).lerp(Color(0.5, 0.9, 0.35), ratio)
	_timer = SHOW_TIME
	visible = ratio < 0.999

func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		visible = false

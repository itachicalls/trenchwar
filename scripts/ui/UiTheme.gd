class_name UiTheme
extends Object
## Central visual identity for every menu and HUD element.
## Toy-box military: bright molded-plastic plates, punchy sticker colors,
## stencil headings with thick outlines — inviting, never murky.

const OLIVE_DARK := Color(0.1, 0.13, 0.07, 0.94)
const OLIVE := Color(0.2, 0.27, 0.12, 0.94)
const OLIVE_EDGE := Color(0.72, 0.8, 0.45)
const CREAM := Color(0.99, 0.97, 0.88)
const AMBER := Color(1.0, 0.82, 0.25)
const GREEN := Color(0.58, 0.9, 0.4)
const RED := Color(1.0, 0.42, 0.3)
const CYAN := Color(0.5, 0.92, 1.0)
const PURPLE := Color(0.78, 0.6, 1.0)
const ORANGE := Color(1.0, 0.62, 0.28)

static var _theme: Theme = null
static var _title: FontFile = null
static var _body: FontFile = null

static func title_font() -> Font:
	if _title == null:
		_title = load("res://assets/fonts/BlackOpsOne-Regular.ttf")
	return _title

static func body_font() -> Font:
	if _body == null:
		_body = load("res://assets/fonts/RussoOne-Regular.ttf")
	return _body

static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 16

	# --- Buttons: chunky molded-plastic plates that pop on hover ---
	t.set_stylebox("normal", "Button", _plate(OLIVE, OLIVE_EDGE, 2))
	t.set_stylebox("hover", "Button", _plate(Color(0.3, 0.4, 0.16, 0.98), AMBER, 3))
	t.set_stylebox("pressed", "Button", _plate(Color(0.12, 0.16, 0.07, 0.98), AMBER, 3))
	t.set_stylebox("focus", "Button", _plate(Color(0, 0, 0, 0), AMBER, 1))
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", AMBER)
	t.set_color("font_pressed_color", "Button", Color(0.85, 0.7, 0.22))
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.62, 0.55, 0.6))
	t.set_font("font", "Button", title_font())
	t.set_font_size("font_size", "Button", 19)

	# --- Panels ---
	t.set_stylebox("panel", "PanelContainer", _plate(OLIVE, OLIVE_EDGE, 2))

	# --- Labels: soft drop shadow everywhere for readability on 3D ---
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.65))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)

	# --- Progress bars ---
	var bg := _plate(Color(0.04, 0.05, 0.03, 0.9), Color(0.3, 0.34, 0.2), 1)
	t.set_stylebox("background", "ProgressBar", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GREEN
	fill.set_corner_radius_all(3)
	t.set_stylebox("fill", "ProgressBar", fill)

	_theme = t
	return t

static func _plate(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(9)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	# Slight skew = military stencil plate feel.
	s.skew = Vector2(-0.05, 0.0)
	# Soft drop shadow lifts plates off the 3D scene like stickers.
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s

## A radial gradient texture (transparent center → colored edge) for vignettes.
static func radial_tex(inner: Color, outer: Color, mid: float = 0.55) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([inner, inner, outer])
	g.offsets = PackedFloat32Array([0.0, mid, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 512
	tex.height = 512
	return tex

## Big stenciled heading: thick dark outline + drop shadow so titles read
## like stickers slapped on the screen, crisp on any background.
static func heading(text: String, size: int, color: Color = CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.03, 0.9))
	l.add_theme_constant_override("outline_size", maxi(4, size / 7))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

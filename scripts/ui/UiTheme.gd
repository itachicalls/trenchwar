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
const PINK := Color(1.0, 0.45, 0.72)
const SKY := Color(0.45, 0.85, 1.0)
const LIME := Color(0.55, 0.95, 0.35)
const GOLD := Color(1.0, 0.85, 0.2)

## Bright toy-box HUD plate (not the olive military menus).
static func hud_plate(fill: Color, border: Color, radius: int = 12, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad - 1
	s.content_margin_bottom = pad - 1
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	return s

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
	# Cache per compact mode so phone buttons get the larger type ramp.
	var want_compact := Game.compact_ui()
	if _theme != null and _theme.has_meta("compact") and bool(_theme.get_meta("compact")) == want_compact:
		return _theme
	var t := Theme.new()
	t.set_meta("compact", want_compact)
	t.default_font = body_font()
	t.default_font_size = 18 if want_compact else 16

	# --- Buttons: chunky molded-plastic plates that pop on hover ---
	var pad_x := 22 if want_compact else 18
	var pad_y := 16 if want_compact else 10
	t.set_stylebox("normal", "Button", _plate(OLIVE, OLIVE_EDGE, 2, pad_x, pad_y, want_compact))
	t.set_stylebox("hover", "Button", _plate(Color(0.3, 0.4, 0.16, 0.98), AMBER, 3, pad_x, pad_y, want_compact))
	t.set_stylebox("pressed", "Button", _plate(Color(0.12, 0.16, 0.07, 0.98), AMBER, 3, pad_x, pad_y, want_compact))
	t.set_stylebox("focus", "Button", _plate(Color(0, 0, 0, 0), AMBER, 1, pad_x, pad_y, want_compact))
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", AMBER)
	t.set_color("font_pressed_color", "Button", Color(0.85, 0.7, 0.22))
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.62, 0.55, 0.6))
	t.set_font("font", "Button", title_font())
	t.set_font_size("font_size", "Button", 22 if want_compact else 19)

	# --- Panels ---
	t.set_stylebox("panel", "PanelContainer", _plate(OLIVE, OLIVE_EDGE, 2, pad_x, pad_y, want_compact))

	# --- Labels: soft drop shadow everywhere for readability on 3D ---
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.65))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)

	# --- Progress bars ---
	var bg := _plate(Color(0.04, 0.05, 0.03, 0.9), Color(0.3, 0.34, 0.2), 1, 12, 8, want_compact)
	t.set_stylebox("background", "ProgressBar", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GREEN
	fill.set_corner_radius_all(3)
	t.set_stylebox("fill", "ProgressBar", fill)

	_theme = t
	return t

## Force theme rebuild after orientation / compact changes.
static func invalidate() -> void:
	_theme = null

static func _plate(bg: Color, border: Color, border_w: int, pad_x: int = 18, pad_y: int = 10, compact: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(12 if compact else 9)
	s.set_border_width_all(border_w)
	s.border_color = border
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	# Skew reads as "cheap sticker" on phone widths — keep it desktop-only.
	s.skew = Vector2.ZERO if compact else Vector2(-0.05, 0.0)
	s.shadow_color = Color(0, 0, 0, 0.4 if compact else 0.35)
	s.shadow_size = 8 if compact else 6
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

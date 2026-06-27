class_name UiTheme
extends RefCounted

## ──────────────────────────────────────────────────────────────────────────
## Colour palette (centralised)
## ──────────────────────────────────────────────────────────────────────────
const COL_PANEL   := Color(0.09, 0.11, 0.15, 0.92)  # card background
const COL_BTN_N   := Color(0.14, 0.17, 0.24, 0.95)  # button normal
const COL_BTN_H   := Color(0.20, 0.24, 0.34, 0.98)  # button hover
const COL_BTN_P   := Color(0.08, 0.10, 0.14, 1.00)  # button pressed
const COL_BTN_BRD := Color(0.32, 0.38, 0.55, 0.70)  # button border
const COL_GOLD    := Color(1.00, 0.85, 0.20, 1.00)
const COL_WHITE   := Color(1.00, 1.00, 1.00, 1.00)

## Rounded card background (dark translucent, soft corners).
static func card_style(radius: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.corner_radius_top_left     = radius
	s.corner_radius_top_right    = radius
	s.corner_radius_bottom_right = radius
	s.corner_radius_bottom_left  = radius
	s.content_margin_left   = 16.0
	s.content_margin_right  = 16.0
	s.content_margin_top    = 10.0
	s.content_margin_bottom = 10.0
	return s


## Rounded button styles — call once per state and cache.
static func btn_style(bg: Color, border: Color = COL_BTN_BRD, radius: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left     = radius
	s.corner_radius_top_right    = radius
	s.corner_radius_bottom_right = radius
	s.corner_radius_bottom_left  = radius
	return s


## Walk root and apply rounded StyleBox overrides to every Button.
## Call at the END of a screen's _ready() after all nodes are built.
static func apply_buttons(root: Node) -> void:
	var normal   := btn_style(COL_BTN_N)
	var hover    := btn_style(COL_BTN_H)
	var pressed  := btn_style(COL_BTN_P)
	var disabled := btn_style(Color(0.12, 0.13, 0.16, 0.70), Color(0.20, 0.20, 0.20, 0.40))
	_walk_buttons(root, normal, hover, pressed, disabled)


static func _walk_buttons(
		node: Node,
		normal: StyleBoxFlat, hover: StyleBoxFlat,
		pressed: StyleBoxFlat, disabled: StyleBoxFlat) -> void:
	if node is Button:
		var btn := node as Button
		btn.add_theme_stylebox_override("normal",   normal)
		btn.add_theme_stylebox_override("hover",    hover)
		btn.add_theme_stylebox_override("pressed",  pressed)
		btn.add_theme_stylebox_override("disabled", disabled)
		btn.add_theme_color_override("font_color",          COL_WHITE)
		btn.add_theme_color_override("font_hover_color",    COL_GOLD)
		btn.add_theme_color_override("font_pressed_color",  COL_WHITE)
		btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5, 0.7))
	for child in node.get_children():
		_walk_buttons(child, normal, hover, pressed, disabled)


## Walk root and apply card StyleBox overrides to every PanelContainer.
static func apply_panels(root: Node) -> void:
	var style := card_style()
	_walk_panels(root, style)


static func _walk_panels(node: Node, style: StyleBoxFlat) -> void:
	if node is PanelContainer:
		(node as PanelContainer).add_theme_stylebox_override("panel", style)
	for child in node.get_children():
		_walk_panels(child, style)

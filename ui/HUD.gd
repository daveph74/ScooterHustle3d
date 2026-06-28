extends CanvasLayer
## The in-game heads-up display.
##
## Shows three things at the top of the screen:
##   * run coins (left)   - coins collected this run
##   * score      (centre) - distance travelled (+ near-miss bonus)
##   * total coins (right) - the player's banked coins
##
## The whole UI is built in code so the prototype needs zero image files and
## the layout is easy to read in one place.

var _run_label: Label
var _score_label: Label
var _best_label: Label
var _near_miss_label: Label
var _combo_label: Label
var _powerup_box: VBoxContainer
var _powerup_rows := {}   # kind -> {row, bar}
var _event_banner: Label
var _pause_button: Button
var _pause_overlay: Control
var _debug_label: Label   # only used when Game.DEBUG_LANES is true
var _speedo: Control      # custom-drawn arc speedometer (bottom-right)
var _speed_label: Label   # the big km/h number inside the gauge
var _speed_kmh := 0       # last value, drives the needle
const _POWERUP_LABELS := {
	"magnet": "Magnet", "shield": "Shield", "multiplier": "x2 Coins", "speed": "Boost",
}
const SAFE_PAD := 18.0   # side inset from the screen edge (clears rounded corners)
const SAFE_TOP := 30.0   # top inset (clears notches / status bar)
const SPEEDO_MAX_KMH := 120.0   # full-scale of the dial (needle = kmh / this)
const _SPEEDO_SIZE := Vector2(168.0, 100.0)


func _ready() -> void:
	# Keep the HUD running while the tree is paused, so the pause button and
	# pause menu still respond (the gameplay nodes stay paused).
	process_mode = Node.PROCESS_MODE_ALWAYS

	# --- Top HUD badges (rounded, readable over the scene) -----------------
	# Built as three content-sized PanelContainers anchored to the top corners /
	# centre, with safe-area padding. They auto-scale with the project's
	# canvas_items stretch, so they're crisp on any portrait phone.

	# Top-left: coin icon + this-run coin count.
	var coin_badge := _make_badge()
	coin_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	coin_badge.position = Vector2(SAFE_PAD, SAFE_TOP)
	add_child(coin_badge)
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 8)
	coin_badge.add_child(coin_row)
	var coin_icon := TextureRect.new()
	coin_icon.texture = load("res://ui/icons/coin.svg")
	coin_icon.custom_minimum_size = Vector2(30, 30)
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_row.add_child(coin_icon)
	_run_label = _make_label("0", HORIZONTAL_ALIGNMENT_LEFT)
	_run_label.add_theme_font_size_override("font_size", 30)
	coin_row.add_child(_run_label)

	# Top-centre: the prominent run score (distance x combo, in metres).
	var score_badge := _make_badge()
	score_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score_badge.position.y = SAFE_TOP - 4
	add_child(score_badge)
	_score_label = _make_label("0 m", HORIZONTAL_ALIGNMENT_CENTER)
	_score_label.add_theme_font_size_override("font_size", 42)
	score_badge.add_child(_score_label)

	# Top-right: best score, sitting just left of the pause button.
	var best_badge := _make_badge()
	best_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	best_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	best_badge.offset_right = -96
	best_badge.offset_top = SAFE_TOP
	add_child(best_badge)
	_best_label = _make_label("Best: 0 m", HORIZONTAL_ALIGNMENT_RIGHT)
	_best_label.add_theme_font_size_override("font_size", 24)
	best_badge.add_child(_best_label)

	# A big "NEAR MISS!" flash in the centre of the screen, hidden until used.
	_near_miss_label = _make_label("NEAR MISS!", HORIZONTAL_ALIGNMENT_CENTER)
	_near_miss_label.add_theme_font_size_override("font_size", 44)
	_near_miss_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_near_miss_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_near_miss_label.offset_top = 220
	_near_miss_label.modulate.a = 0.0   # invisible to start
	add_child(_near_miss_label)

	# Combo / streak indicator, centred a bit lower, hidden when there's no combo.
	_combo_label = _make_label("", HORIZONTAL_ALIGNMENT_CENTER)
	_combo_label.add_theme_font_size_override("font_size", 40)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.15))
	_combo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_combo_label.offset_top = 300
	_combo_label.modulate.a = 0.0
	add_child(_combo_label)

	# Active power-up duration bars, stacked under the top bar on the right.
	_powerup_box = VBoxContainer.new()
	_powerup_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_powerup_box.offset_left = -260
	_powerup_box.offset_right = -24
	_powerup_box.offset_top = 90
	_powerup_box.add_theme_constant_override("separation", 6)
	add_child(_powerup_box)

	# Random-event banner, briefly shown near the top centre.
	_event_banner = _make_label("", HORIZONTAL_ALIGNMENT_CENTER)
	_event_banner.add_theme_font_size_override("font_size", 38)
	_event_banner.add_theme_color_override("font_color", Color(0.35, 1.0, 0.5))
	_event_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_event_banner.offset_top = 130
	_event_banner.modulate.a = 0.0
	add_child(_event_banner)

	_build_speedometer()
	_build_pause_ui()
	UiTheme.apply_buttons(self)


# --- Speedometer -----------------------------------------------------------

## A compact arc gauge in the bottom-right corner: a 180-degree dial with a
## colour-coded fill (green -> red), tick marks, a needle, and a big km/h
## number. Drawn by hand in _draw_speedo so it costs nothing but a few draw
## calls, and only redraws when the speed value actually changes.
func _build_speedometer() -> void:
	var badge := _make_badge()
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	badge.offset_right = -SAFE_PAD
	badge.offset_bottom = -SAFE_PAD
	add_child(badge)

	_speedo = Control.new()
	_speedo.custom_minimum_size = _SPEEDO_SIZE
	_speedo.draw.connect(_draw_speedo)
	badge.add_child(_speedo)

	# Big km/h number, sitting in the lower-centre of the arc.
	_speed_label = _make_label("0", HORIZONTAL_ALIGNMENT_CENTER)
	_speed_label.add_theme_font_size_override("font_size", 34)
	_speed_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_speed_label.offset_top = 40.0
	_speed_label.offset_bottom = 78.0
	_speedo.add_child(_speed_label)

	# Small "km/h" unit under the number.
	var unit := _make_label("km/h", HORIZONTAL_ALIGNMENT_CENTER)
	unit.add_theme_font_size_override("font_size", 14)
	unit.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	unit.set_anchors_preset(Control.PRESET_TOP_WIDE)
	unit.offset_top = 78.0
	unit.offset_bottom = 96.0
	_speedo.add_child(unit)


func _draw_speedo() -> void:
	var center := Vector2(_SPEEDO_SIZE.x * 0.5, _SPEEDO_SIZE.y - 14.0)
	var radius := 72.0
	var t := clampf(float(_speed_kmh) / SPEEDO_MAX_KMH, 0.0, 1.0)

	# Points along the top semicircle (PI on the left, 0 on the right).
	var track := PackedVector2Array()
	var fill := PackedVector2Array()
	var steps := 32
	for i in range(steps + 1):
		var f := float(i) / float(steps)
		var ang := PI - f * PI
		var p := center + Vector2(cos(ang), -sin(ang)) * radius
		track.append(p)
		if f <= t:
			fill.append(p)
	# Unfilled track first (dim), then the coloured fill on top.
	draw_polyline(track, Color(1, 1, 1, 0.18), 7.0, true)
	if fill.size() >= 2:
		draw_polyline(fill, _speed_color(t), 7.0, true)

	# Tick marks every 20 km/h.
	var ticks := int(SPEEDO_MAX_KMH / 20.0)
	for j in range(ticks + 1):
		var tf := float(j) / float(ticks)
		var tang := PI - tf * PI
		var tdir := Vector2(cos(tang), -sin(tang))
		draw_line(center + tdir * (radius - 9.0), center + tdir * (radius - 2.0),
			Color(1, 1, 1, 0.5), 2.0, true)

	# Needle + hub.
	var nang := PI - t * PI
	var ndir := Vector2(cos(nang), -sin(nang))
	draw_line(center, center + ndir * (radius - 6.0), Color(1.0, 0.95, 0.85), 3.0, true)
	draw_circle(center, 6.0, Color(0.95, 0.95, 0.95))
	draw_circle(center, 3.0, Color(0.2, 0.2, 0.22))


## Green at low speed, through yellow, to red near the top of the dial.
func _speed_color(t: float) -> Color:
	if t < 0.5:
		return Color(0.30, 0.90, 0.40).lerp(Color(1.0, 0.85, 0.20), t * 2.0)
	return Color(1.0, 0.85, 0.20).lerp(Color(1.0, 0.30, 0.25), (t - 0.5) * 2.0)


# --- Pause -----------------------------------------------------------------

func _build_pause_ui() -> void:
	# Pause button in the top-right corner (large tap target for phones).
	_pause_button = Button.new()
	_pause_button.text = "II"
	_pause_button.add_theme_font_size_override("font_size", 34)
	_pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_pause_button.offset_left = -84
	_pause_button.offset_right = -16
	_pause_button.offset_top = 28
	_pause_button.offset_bottom = 96
	_pause_button.pressed.connect(_on_pause)
	add_child(_pause_button)

	# Full-screen pause menu, hidden until used.
	_pause_overlay = Control.new()
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	box.add_child(title)

	box.add_child(_make_menu_button("RESUME", _on_resume))
	box.add_child(_make_menu_button("RESTART", _on_restart))
	box.add_child(_make_menu_button("MAIN MENU", _on_menu))


func _make_menu_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(340, 90)
	button.add_theme_font_size_override("font_size", 34)
	button.pressed.connect(handler)
	return button


## Hide the pause button once the run is over (so you can't pause on Game Over).
func hide_pause_button() -> void:
	if _pause_button:
		_pause_button.visible = false


# Escape (desktop) / on-screen button toggles pause.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if get_tree().paused:
			_on_resume()
		elif _pause_button.visible:
			_on_pause()


func _on_pause() -> void:
	if not _pause_button.visible:
		return
	AudioManager.play_sfx("click")
	AudioManager.set_engine_paused(true)   # hush the engine while paused
	get_tree().paused = true
	_pause_overlay.visible = true


func _on_resume() -> void:
	AudioManager.play_sfx("click")
	AudioManager.set_engine_paused(false)
	get_tree().paused = false
	_pause_overlay.visible = false


func _on_restart() -> void:
	AudioManager.play_sfx("click")
	AudioManager.stop_engine()             # the new run will start it again
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_menu() -> void:
	AudioManager.play_sfx("click")
	AudioManager.stop_engine()             # no engine on the menu
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")


## Helper that builds a readable label (white text with a dark outline so it
## stays legible over the bright road).
func _make_label(text: String, align: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## A rounded translucent badge (reuses UiTheme's card style) that sizes to its
## content - used behind each top-HUD counter so it reads over the scene.
func _make_badge() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.card_style(16))
	return p


# --- Public API used by Game.gd -------------------------------------------

func set_score(value: int) -> void:
	_score_label.text = str(value) + " m"


## Current speed in km/h. Updates the gauge number and redraws the needle
## (only when the value actually changes, so it's cheap).
func set_speed(kmh: int) -> void:
	if kmh == _speed_kmh:
		return
	_speed_kmh = kmh
	_speed_label.text = str(kmh)
	_speedo.queue_redraw()


func set_run_coins(value: int) -> void:
	# The coin icon already labels it, so just the number.
	_run_label.text = str(value)


## Best run score (metres). Shown top-right.
func set_best(value: int) -> void:
	_best_label.text = "Best: " + str(value) + " m"


## Kept for compatibility; the HUD now shows Best instead of banked coins.
func set_total_coins(_value: int) -> void:
	pass


## Quick colour pop on the coin counter when a coin is grabbed.
func pulse_coin() -> void:
	_run_label.modulate = Color(1.0, 0.9, 0.2)
	var tween := create_tween()
	tween.tween_property(_run_label, "modulate", Color.WHITE, 0.25)


## Flash the "NEAR MISS!" text and fade it out.
func flash_near_miss() -> void:
	_near_miss_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_near_miss_label, "modulate:a", 0.0, 0.6)


## Optional debug line (lane count / section). Created on first use so it costs
## nothing when DEBUG_LANES is off.
func set_debug(text: String) -> void:
	if _debug_label == null:
		_debug_label = Label.new()
		_debug_label.add_theme_font_size_override("font_size", 20)
		_debug_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		_debug_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		_debug_label.offset_left = 16
		_debug_label.offset_top = -44
		add_child(_debug_label)
	_debug_label.text = text


## Briefly announce a random event (fades in then out).
func show_event_banner(text: String) -> void:
	_event_banner.text = text
	var tween := create_tween()
	tween.tween_property(_event_banner, "modulate:a", 1.0, 0.2)
	tween.tween_interval(1.4)
	tween.tween_property(_event_banner, "modulate:a", 0.0, 0.6)


## Show/update a power-up duration bar. remaining <= 0 removes it.
func show_powerup_duration(kind: String, remaining: float, max_duration: float) -> void:
	if remaining <= 0.0:
		if _powerup_rows.has(kind):
			_powerup_rows[kind].row.queue_free()
			_powerup_rows.erase(kind)
		return
	if not _powerup_rows.has(kind):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := _make_label(_POWERUP_LABELS.get(kind, kind), HORIZONTAL_ALIGNMENT_LEFT)
		label.add_theme_font_size_override("font_size", 20)
		row.add_child(label)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(120, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		_powerup_box.add_child(row)
		_powerup_rows[kind] = {"row": row, "bar": bar}
	_powerup_rows[kind].bar.value = clampf(remaining / maxf(max_duration, 0.001), 0.0, 1.0)


## Update the combo indicator. count 0 hides it; "milestone" gives it a pop.
func set_combo(count: int, multiplier: int, milestone: bool = false) -> void:
	if count <= 0:
		_combo_label.modulate.a = 0.0
		return
	_combo_label.text = "x%d  COMBO %d" % [multiplier, count]
	_combo_label.modulate = Color(1.0, 0.45, 0.15, 1.0)
	if milestone:
		# Quick scale pop around the label's centre.
		_combo_label.pivot_offset = _combo_label.size * 0.5
		_combo_label.scale = Vector2(1.4, 1.4)
		var tween := create_tween()
		tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.2)

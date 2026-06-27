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
var _total_label: Label
var _near_miss_label: Label
var _combo_label: Label
var _powerup_box: VBoxContainer
var _powerup_rows := {}   # kind -> {row, bar}
var _event_banner: Label
var _pause_button: Button
var _pause_overlay: Control
var _debug_label: Label   # only used when Game.DEBUG_LANES is true
const _POWERUP_LABELS := {
	"magnet": "Magnet", "shield": "Shield", "multiplier": "x2 Coins", "speed": "Boost",
}


func _ready() -> void:
	# Keep the HUD running while the tree is paused, so the pause button and
	# pause menu still respond (the gameplay nodes stay paused).
	process_mode = Node.PROCESS_MODE_ALWAYS

	# A bar pinned across the top of the screen holding the three counters.
	# Right inset leaves room for the pause button in the top-right corner.
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_right = -100
	bar.offset_top = 36
	add_child(bar)

	_run_label = _make_label("Coins: 0", HORIZONTAL_ALIGNMENT_LEFT)
	_score_label = _make_label("0 m", HORIZONTAL_ALIGNMENT_CENTER)
	_total_label = _make_label("Total: 0", HORIZONTAL_ALIGNMENT_RIGHT)

	# Coin icon + run coins label wrapped in a small HBox.
	var coin_icon_row := HBoxContainer.new()
	coin_icon_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coin_icon_row.add_theme_constant_override("separation", 6)
	var coin_icon := TextureRect.new()
	coin_icon.texture = load("res://ui/icons/coin.svg")
	coin_icon.custom_minimum_size = Vector2(26, 26)
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon_row.add_child(coin_icon)
	_run_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coin_icon_row.add_child(_run_label)
	bar.add_child(coin_icon_row)

	# Distance icon + score label wrapped in a small HBox.
	var dist_icon_row := HBoxContainer.new()
	dist_icon_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dist_icon_row.add_theme_constant_override("separation", 6)
	var dist_icon := TextureRect.new()
	dist_icon.texture = load("res://ui/icons/distance.svg")
	dist_icon.custom_minimum_size = Vector2(22, 22)
	dist_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dist_icon_row.add_child(dist_icon)
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dist_icon_row.add_child(_score_label)
	bar.add_child(dist_icon_row)

	_total_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_total_label)

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

	_build_pause_ui()
	UiTheme.apply_buttons(self)


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
	return label


# --- Public API used by Game.gd -------------------------------------------

func set_score(value: int) -> void:
	_score_label.text = str(value) + " m"


func set_run_coins(value: int) -> void:
	_run_label.text = "Coins: " + str(value)


func set_total_coins(value: int) -> void:
	_total_label.text = "Total: " + str(value)


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

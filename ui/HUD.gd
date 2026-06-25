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


func _ready() -> void:
	# A bar pinned across the top of the screen holding the three counters.
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 24
	bar.offset_right = -24
	bar.offset_top = 36
	add_child(bar)

	_run_label = _make_label("Coins: 0", HORIZONTAL_ALIGNMENT_LEFT)
	_score_label = _make_label("0 m", HORIZONTAL_ALIGNMENT_CENTER)
	_total_label = _make_label("Total: 0", HORIZONTAL_ALIGNMENT_RIGHT)
	for label in [_run_label, _score_label, _total_label]:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(label)

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

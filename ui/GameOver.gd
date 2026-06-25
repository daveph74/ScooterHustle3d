extends CanvasLayer
## The "you crashed" screen.
##
## It shows the run results and offers two buttons: Retry (replay) and Menu
## (back to the main menu). Like the HUD, it is built entirely in code.

var _root: Control          # the panel we show/hide
var _score_label: Label
var _run_coins_label: Label
var _total_label: Label


func _ready() -> void:
	# A full-screen dim layer that holds everything.
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	# A CenterContainer fills the screen and keeps the column centred.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	# A centred column of text and buttons.
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	box.add_child(_make_title("GAME OVER"))
	_score_label = _make_text("Score: 0")
	_run_coins_label = _make_text("Coins this run: 0")
	_total_label = _make_text("Total coins: 0")
	box.add_child(_score_label)
	box.add_child(_run_coins_label)
	box.add_child(_total_label)

	var retry := _make_button("Retry")
	retry.pressed.connect(_on_retry)
	box.add_child(retry)

	var menu := _make_button("Main Menu")
	menu.pressed.connect(_on_menu)
	box.add_child(menu)


# --- Small UI builders ----------------------------------------------------

func _make_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 56)
	label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	return label


func _make_text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	return label


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 90)
	button.add_theme_font_size_override("font_size", 34)
	return button


# --- Public API -----------------------------------------------------------

func hide_screen() -> void:
	_root.visible = false


func show_screen(score: int, run_coins: int, total_coins: int) -> void:
	_score_label.text = "Score: %d m" % score
	_run_coins_label.text = "Coins this run: %d" % run_coins
	_total_label.text = "Total coins: %d" % total_coins
	_root.visible = true


# --- Buttons --------------------------------------------------------------

func _on_retry() -> void:
	AudioManager.play_sfx("click")
	# Reload the gameplay scene from scratch for a fresh run.
	get_tree().reload_current_scene()


func _on_menu() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")

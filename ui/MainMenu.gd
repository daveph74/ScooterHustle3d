extends Control
## The main menu - the first screen the player sees.
##
## It shows the title, the player's total coins, Play/Garage, and audio options
## (music on/off, change track, sfx on/off). Built in code, no image assets.

var _music_button: Button
var _track_button: Button
var _sfx_button: Button


func _ready() -> void:
	# Solid background.
	var background := ColorRect.new()
	background.color = Color(0.1, 0.12, 0.16)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# A CenterContainer fills the screen and keeps our column centred at its
	# natural size (this is the reliable way to centre UI in Godot).
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Centred column.
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	center.add_child(box)

	# Title.
	var title := Label.new()
	title.text = "SCOOTER HUSTLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	box.add_child(title)

	# Subtitle.
	var subtitle := Label.new()
	subtitle.text = "Beat the Philippine traffic!"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 28)
	box.add_child(subtitle)

	# Total coins owned.
	var coins := Label.new()
	coins.text = "Coins: %d" % GameData.total_coins
	coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins.add_theme_font_size_override("font_size", 30)
	coins.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	box.add_child(coins)

	# Spacer.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	box.add_child(spacer)

	# Buttons.
	var play := _make_button("PLAY")
	play.pressed.connect(_on_play)
	box.add_child(play)

	var garage := _make_button("GARAGE")
	garage.pressed.connect(_on_garage)
	box.add_child(garage)

	# --- Audio options ----------------------------------------------------
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 16)
	box.add_child(spacer2)

	_music_button = _make_small_button("")
	_music_button.pressed.connect(_on_toggle_music)
	box.add_child(_music_button)

	_track_button = _make_small_button("")
	_track_button.pressed.connect(_on_next_track)
	box.add_child(_track_button)

	_sfx_button = _make_small_button("")
	_sfx_button.pressed.connect(_on_toggle_sfx)
	box.add_child(_sfx_button)

	_refresh_audio_labels()


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 100)
	button.add_theme_font_size_override("font_size", 40)
	return button


func _make_small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 64)
	button.add_theme_font_size_override("font_size", 28)
	return button


## Update the audio button labels to reflect the current settings.
func _refresh_audio_labels() -> void:
	_music_button.text = "Music: On" if GameData.music_on else "Music: Off"
	_track_button.text = "Track: " + AudioManager.current_track_name()
	_sfx_button.text = "SFX: On" if GameData.sfx_on else "SFX: Off"


func _on_toggle_music() -> void:
	AudioManager.play_sfx("click")
	AudioManager.toggle_music()
	_refresh_audio_labels()


func _on_next_track() -> void:
	AudioManager.next_track()
	AudioManager.play_sfx("click")
	_refresh_audio_labels()


func _on_toggle_sfx() -> void:
	AudioManager.set_sfx_enabled(not GameData.sfx_on)
	AudioManager.play_sfx("click")   # plays only if SFX were just turned on
	_refresh_audio_labels()


func _on_play() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://scenes/Game.tscn")


func _on_garage() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://ui/Garage.tscn")

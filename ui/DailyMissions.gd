extends Control
## The Daily Missions screen.
##
## Lists the day's 3 missions with a progress bar and a claim button each.
## Built in code, mirroring the Garage layout. Mission state/logic lives in the
## MissionManager autoload; this screen just shows it and claims rewards.

var _coins_label: Label
var _list: VBoxContainer


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.1, 0.12, 0.16)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 30
	outer.offset_right = -30
	outer.offset_top = 40
	outer.offset_bottom = -40
	outer.add_theme_constant_override("separation", 18)
	add_child(outer)

	var title := Label.new()
	title.text = "DAILY MISSIONS"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	outer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "New missions every day. Claim your coins!"
	subtitle.add_theme_font_size_override("font_size", 24)
	outer.add_child(subtitle)

	_coins_label = Label.new()
	_coins_label.add_theme_font_size_override("font_size", 30)
	_coins_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	outer.add_child(_coins_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 16)
	scroll.add_child(_list)

	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(0, 90)
	back.add_theme_font_size_override("font_size", 34)
	back.pressed.connect(_on_back)
	outer.add_child(back)

	_refresh()


func _refresh() -> void:
	_coins_label.text = "Coins: %d" % GameData.total_coins
	for child in _list.get_children():
		child.queue_free()
	for mission in MissionManager.active_missions():
		_list.add_child(_make_mission_card(mission))


func _make_mission_card(mission: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	margin.add_child(row)
	panel.add_child(margin)

	# Name + reward.
	var name_label := Label.new()
	name_label.text = "%s   (+%d coins)" % [mission.name, mission.reward]
	name_label.add_theme_font_size_override("font_size", 30)
	row.add_child(name_label)

	# Progress bar.
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = mission.target
	bar.value = mission.progress
	bar.custom_minimum_size = Vector2(0, 28)
	bar.add_theme_font_size_override("font_size", 18)
	row.add_child(bar)

	var progress_label := Label.new()
	progress_label.text = "%d / %d" % [mission.progress, mission.target]
	progress_label.add_theme_font_size_override("font_size", 22)
	progress_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	row.add_child(progress_label)

	# Claim button.
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 64)
	button.add_theme_font_size_override("font_size", 26)
	if mission.claimed:
		button.text = "CLAIMED"
		button.disabled = true
	elif mission.completed:
		button.text = "CLAIM +%d" % mission.reward
		var mission_id: String = mission.id
		button.pressed.connect(func(): _on_claim(mission_id))
	else:
		button.text = "IN PROGRESS"
		button.disabled = true
	row.add_child(button)

	return panel


func _on_claim(mission_id: String) -> void:
	var reward := MissionManager.claim(mission_id)
	if reward > 0:
		AudioManager.play_sfx("coin")
	MissionManager.save_now()
	_refresh()


func _on_back() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")

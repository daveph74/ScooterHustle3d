extends Control
## The garage - where the player buys and selects scooters.
##
## For every scooter (loaded from GameData) we show one "card" with its name,
## description, stats and a button that is either:
##   * "Selected"  - already chosen (disabled)
##   * "Select"    - owned, tap to ride it
##   * "Buy (250)" - locked, tap to purchase if you have enough coins
##
## After any change we just rebuild the whole list, which keeps the code
## simple and always correct.

var _coins_label: Label
var _list: VBoxContainer
var _current_tab := "scooters"
var _cosmetics := Cosmetics.new()
const COSMETIC_SLOTS := ["paint", "helmet", "wheel"]
const SLOT_TITLES := {"paint": "PAINT", "helmet": "HELMETS", "wheel": "WHEELS"}


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.1, 0.12, 0.16)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	# Outer column: header + scrollable list + back button.
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 30
	outer.offset_right = -30
	outer.offset_top = 40
	outer.offset_bottom = -40
	outer.add_theme_constant_override("separation", 20)
	add_child(outer)

	# Header row: title + coin total.
	var title := Label.new()
	title.text = "GARAGE"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	outer.add_child(title)

	_coins_label = Label.new()
	_coins_label.add_theme_font_size_override("font_size", 30)
	_coins_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	outer.add_child(_coins_label)

	# Tab row: Scooters | Cosmetics.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	outer.add_child(tabs)
	var scooters_tab := _make_tab("SCOOTERS", "scooters")
	var cosmetics_tab := _make_tab("COSMETICS", "cosmetics")
	tabs.add_child(scooters_tab)
	tabs.add_child(cosmetics_tab)

	# Scrollable area so all four cards fit on any phone.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 16)
	scroll.add_child(_list)

	# Back button.
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(0, 90)
	back.add_theme_font_size_override("font_size", 34)
	back.pressed.connect(_on_back)
	outer.add_child(back)

	_refresh()


func _make_tab(text: String, tab_id: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 56)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 26)
	button.pressed.connect(func(): _show_tab(tab_id))
	return button


func _show_tab(tab_id: String) -> void:
	_current_tab = tab_id
	AudioManager.play_sfx("click")
	_refresh()


## Rebuild the current tab's list from current game data.
func _refresh() -> void:
	_coins_label.text = "Coins: %d" % GameData.total_coins

	# Clear old cards.
	for child in _list.get_children():
		child.queue_free()

	if _current_tab == "scooters":
		for scooter in GameData.all_scooters:
			_list.add_child(_make_card(scooter))
	else:
		for slot in COSMETIC_SLOTS:
			_list.add_child(_make_section_header(SLOT_TITLES[slot]))
			for entry in _cosmetics.list_for_slot(slot):
				_list.add_child(_make_cosmetic_card(entry))
	UiTheme.apply_buttons(self)
	UiTheme.apply_panels(self)


func _make_section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	return label


## Build one cosmetic "card" (paint / helmet / wheel option).
func _make_cosmetic_card(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	margin.add_child(row)
	panel.add_child(margin)

	# A colour swatch preview (or a neutral box for "keep stock"/"none").
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(48, 48)
	swatch.color = entry.color if entry.color != null else Color(0.4, 0.4, 0.45)
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = entry.name
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Action button: EQUIPPED / EQUIP / BUY (price).
	var button := Button.new()
	button.custom_minimum_size = Vector2(170, 60)
	button.add_theme_font_size_override("font_size", 24)
	var equipped: bool = GameData.get_equipped(entry.slot) == entry.id
	if equipped:
		button.text = "EQUIPPED"
		button.disabled = true
	elif GameData.is_cosmetic_owned(entry.id):
		button.text = "EQUIP"
		button.pressed.connect(func(): _on_equip_cosmetic(entry.slot, entry.id))
	else:
		button.text = "BUY (%d)" % entry.price
		button.disabled = GameData.total_coins < entry.price
		button.pressed.connect(func(): _on_buy_cosmetic(entry.slot, entry.id, entry.price))
	row.add_child(button)

	return panel


## Build one scooter "card".
func _make_card(scooter: ScooterData) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	# A little inner padding via a margin container.
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	margin.add_child(row)
	panel.add_child(margin)

	# Name.
	var name_label := Label.new()
	name_label.text = scooter.display_name
	name_label.add_theme_font_size_override("font_size", 34)
	row.add_child(name_label)

	# Description.
	var desc := Label.new()
	desc.text = scooter.description
	desc.add_theme_font_size_override("font_size", 22)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc)

	# Stats (shown as simple star bars).
	var stats := Label.new()
	stats.text = "Speed %s    Handling %s" % [_stars(scooter.speed), _stars(scooter.handling)]
	stats.add_theme_font_size_override("font_size", 24)
	stats.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	row.add_child(stats)

	# Action button (state depends on owned/selected/affordable).
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 70)
	button.add_theme_font_size_override("font_size", 28)

	if GameData.selected_id == scooter.id:
		button.text = "SELECTED"
		button.disabled = true
	elif GameData.is_unlocked(scooter.id):
		button.text = "SELECT"
		button.pressed.connect(func(): _on_select(scooter.id))
	else:
		button.text = "BUY (%d)" % scooter.price
		button.disabled = GameData.total_coins < scooter.price
		button.pressed.connect(func(): _on_buy(scooter.id))

	row.add_child(button)
	return panel


## Turn a stat multiplier (roughly 1.0 - 2.2) into a 1-5 star string.
func _stars(value: float) -> String:
	var filled: int = clampi(int(round(value * 2.0)), 1, 5)
	var result := ""
	for i in range(5):
		result += "★" if i < filled else "☆"
	return result


func _on_select(id: String) -> void:
	AudioManager.play_sfx("click")
	GameData.select(id)
	_refresh()


func _on_buy(id: String) -> void:
	if GameData.try_buy(id):
		AudioManager.play_sfx("coin")   # cha-ching on a successful purchase
		GameData.select(id)   # auto-ride the scooter you just bought
	else:
		AudioManager.play_sfx("click")
	_refresh()


func _on_equip_cosmetic(slot: String, id: String) -> void:
	AudioManager.play_sfx("click")
	GameData.equip_cosmetic(slot, id)
	_refresh()


func _on_buy_cosmetic(slot: String, id: String, price: int) -> void:
	if GameData.try_buy_cosmetic(id, price):
		AudioManager.play_sfx("coin")
		GameData.equip_cosmetic(slot, id)   # auto-equip what you just bought
	else:
		AudioManager.play_sfx("click")
	_refresh()


func _on_back() -> void:
	AudioManager.play_sfx("click")
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")

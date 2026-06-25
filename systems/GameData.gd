extends Node
## GameData - the global game state singleton (autoload).
##
## Because it is registered as an autoload in project.godot, you can reach it
## from ANY script just by typing "GameData.something". It keeps track of the
## player's coins, which scooters are unlocked, and which one is selected, and
## it saves/loads all of that to a local file.

## Where the save file lives. "user://" is a safe, writable folder that Godot
## maps to a per-user location on every platform (including Android).
const SAVE_PATH := "user://scooterhustle_save.json"

## Every scooter in the game, in display order. Loaded once at startup.
var all_scooters: Array[ScooterData] = []

## Persistent state (these three things get saved to disk):
var total_coins: int = 0
var unlocked_ids: Array = ["rusty"]   # the Rusty Scooter is always free
var selected_id: String = "rusty"

# Audio settings (read/written by AudioManager, saved with everything else).
var music_on: bool = true
var sfx_on: bool = true
var music_track: int = 0


func _ready() -> void:
	_load_scooter_defs()
	load_game()


## Load the scooter resources. Adding a new scooter later means creating a new
## .tres file and adding one line here.
func _load_scooter_defs() -> void:
	all_scooters = [
		preload("res://resources/rusty_scooter.tres"),
		preload("res://resources/daily_commuter.tres"),
		preload("res://resources/125cc_bike.tres"),
		preload("res://resources/sport_bike.tres"),
	]


## Find a scooter resource by its id. Returns null if not found.
func get_scooter(id: String) -> ScooterData:
	for s in all_scooters:
		if s.id == id:
			return s
	return null


## The scooter the player is currently riding.
func get_selected_scooter() -> ScooterData:
	return get_scooter(selected_id)


func is_unlocked(id: String) -> bool:
	return id in unlocked_ids


## Try to buy a scooter. Returns true on success.
func try_buy(id: String) -> bool:
	var s := get_scooter(id)
	if s == null or is_unlocked(id):
		return false
	if total_coins >= s.price:
		total_coins -= s.price
		unlocked_ids.append(id)
		save_game()
		return true
	return false


## Choose a scooter to ride (only if it is unlocked).
func select(id: String) -> void:
	if is_unlocked(id):
		selected_id = id
		save_game()


## Add coins earned in a run to the player's total, then save.
func add_coins(amount: int) -> void:
	total_coins += amount
	save_game()


# --- Saving and loading ---------------------------------------------------

func save_game() -> void:
	var data := {
		"total_coins": total_coins,
		"unlocked_ids": unlocked_ids,
		"selected_id": selected_id,
		"music_on": music_on,
		"sfx_on": sfx_on,
		"music_track": music_track,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return  # first launch - keep the defaults
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return  # corrupted / empty file - ignore and keep defaults
	total_coins = int(parsed.get("total_coins", 0))
	unlocked_ids = parsed.get("unlocked_ids", ["rusty"])
	selected_id = String(parsed.get("selected_id", "rusty"))
	music_on = bool(parsed.get("music_on", true))
	sfx_on = bool(parsed.get("sfx_on", true))
	music_track = int(parsed.get("music_track", 0))
	# Safety: make sure the rusty scooter is always owned.
	if not ("rusty" in unlocked_ids):
		unlocked_ids.append("rusty")

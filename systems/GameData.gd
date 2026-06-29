extends Node
## GameData - the global game state singleton (autoload).
##
## Because it is registered as an autoload in project.godot, you can reach it
## from ANY script just by typing "GameData.something". It keeps track of the
## player's coins, which scooters are unlocked, and which one is selected, and
## it saves/loads all of that to a local file.

## Visible build tag - shown on the main menu and HUD so you can confirm the
## web/phone build is the latest one (not a stale browser cache). BUMP THIS
## whenever there's something to verify on the phone.
const BUILD_TAG := "build 6 - split@50m"

## Where the save file lives. "user://" is a safe, writable folder that Godot
## maps to a per-user location on every platform (including Android).
const SAVE_PATH := "user://scooterhustle_save.json"

## Every scooter in the game, in display order. Loaded once at startup.
var all_scooters: Array[ScooterData] = []

## Persistent state (these things get saved to disk):
var total_coins: int = 0
var best_score: int = 0               # highest run score (metres) ever achieved
var unlocked_ids: Array = ["rusty"]   # the Rusty Scooter is always free
var selected_id: String = "rusty"

# Audio settings (read/written by AudioManager, saved with everything else).
var music_on: bool = true
var sfx_on: bool = true
var music_track: int = 0

## Save-file schema version. Bump when the saved shape changes; load_game()
## migrates older files simply by defaulting any missing keys (additive schema).
const SAVE_VERSION := 2
var version: int = SAVE_VERSION

# --- Daily missions (managed by MissionManager) ---------------------------
# Shape: { "date": "YYYY-MM-DD",
#          "missions": [ {id,type,name,target,progress,reward,completed,claimed}, ... ] }
var daily_missions: Dictionary = {}

# --- Cosmetics (managed via the garage + Cosmetics.gd) --------------------
# The "_default"/"_none" ids are free and always owned. Cosmetics are purely
# visual - they never affect gameplay stats.
var owned_cosmetics: Array = ["paint_default", "helmet_none", "wheel_default"]
var equipped_cosmetics: Dictionary = {
	"paint": "paint_default",
	"helmet": "helmet_none",
	"wheel": "wheel_default",
}


func _ready() -> void:
	# Force portrait at runtime on the device, belt-and-suspenders on top of the
	# project setting (covers a stale/landscape Android manifest from an old APK).
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
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


## Record a run's score as the new best if it beats the stored one. Returns true
## if it was a new record. Saving is left to the caller (it usually saves anyway).
func record_score(value: int) -> bool:
	if value > best_score:
		best_score = value
		return true
	return false


# --- Cosmetics ------------------------------------------------------------

func is_cosmetic_owned(id: String) -> bool:
	return id in owned_cosmetics


## Buy a cosmetic if affordable and not already owned. Returns true on success.
func try_buy_cosmetic(id: String, price: int) -> bool:
	if is_cosmetic_owned(id) or total_coins < price:
		return false
	total_coins -= price
	owned_cosmetics.append(id)
	save_game()
	return true


## Equip an owned cosmetic into its slot ("paint" / "helmet" / "wheel").
func equip_cosmetic(slot: String, id: String) -> void:
	if is_cosmetic_owned(id):
		equipped_cosmetics[slot] = id
		save_game()


func get_equipped(slot: String) -> String:
	return String(equipped_cosmetics.get(slot, ""))


# --- Saving and loading ---------------------------------------------------

func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"total_coins": total_coins,
		"best_score": best_score,
		"unlocked_ids": unlocked_ids,
		"selected_id": selected_id,
		"music_on": music_on,
		"sfx_on": sfx_on,
		"music_track": music_track,
		"daily_missions": daily_missions,
		"owned_cosmetics": owned_cosmetics,
		"equipped_cosmetics": equipped_cosmetics,
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
	# Older saves simply lack the newer keys; .get(..., default) migrates them.
	version = int(parsed.get("version", 1))
	total_coins = int(parsed.get("total_coins", 0))
	best_score = int(parsed.get("best_score", 0))
	unlocked_ids = parsed.get("unlocked_ids", ["rusty"])
	selected_id = String(parsed.get("selected_id", "rusty"))
	music_on = bool(parsed.get("music_on", true))
	sfx_on = bool(parsed.get("sfx_on", true))
	music_track = int(parsed.get("music_track", 0))
	daily_missions = parsed.get("daily_missions", {})
	owned_cosmetics = parsed.get("owned_cosmetics", ["paint_default", "helmet_none", "wheel_default"])
	equipped_cosmetics = parsed.get("equipped_cosmetics", {
		"paint": "paint_default", "helmet": "helmet_none", "wheel": "wheel_default",
	})
	version = SAVE_VERSION  # we have now migrated to the current schema

	# Safety: make sure the rusty scooter and the default cosmetics are owned.
	if not ("rusty" in unlocked_ids):
		unlocked_ids.append("rusty")
	for default_id in ["paint_default", "helmet_none", "wheel_default"]:
		if not (default_id in owned_cosmetics):
			owned_cosmetics.append(default_id)
	for slot in ["paint", "helmet", "wheel"]:
		if not equipped_cosmetics.has(slot):
			equipped_cosmetics[slot] = "%s_%s" % [slot, "default" if slot != "helmet" else "none"]

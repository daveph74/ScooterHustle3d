extends Node
## AudioManager - global sound singleton (autoload).
##
## Plays the background music (loopable, switchable, mutable) and one-shot sound
## effects. Reachable anywhere as "AudioManager". Settings (music on/off, sfx
## on/off, chosen track) live in GameData so they are saved with everything else.

# The three music loops and their menu-friendly names.
const MUSIC := [
	preload("res://audio/music/track1_cruise.wav"),
	preload("res://audio/music/track2_rush.wav"),
	preload("res://audio/music/track3_chill.wav"),
]
const MUSIC_NAMES := ["Cruise", "Rush", "Chill"]

# Sound effects, looked up by name.
const SFX := {
	"coin": preload("res://audio/sfx/coin.wav"),
	"crash": preload("res://audio/sfx/crash.wav"),
	"near_miss": preload("res://audio/sfx/near_miss.wav"),
	"click": preload("res://audio/sfx/click.wav"),
}

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_index := 0


func _ready() -> void:
	# Make every music loop actually loop.
	for stream in MUSIC:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)

	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -6.0
	add_child(_music_player)

	# A small pool of players so overlapping sound effects don't cut each other.
	# -6 dB halves the amplitude, i.e. sound effects at 50% volume.
	for i in range(6):
		var player := AudioStreamPlayer.new()
		player.volume_db = -6.0
		add_child(player)
		_sfx_players.append(player)

	_apply_music()


# --- Music ----------------------------------------------------------------

func _apply_music() -> void:
	if GameData.music_on:
		var index: int = clampi(GameData.music_track, 0, MUSIC.size() - 1)
		_music_player.stream = MUSIC[index]
		_music_player.play()
	else:
		_music_player.stop()


func set_music_enabled(on: bool) -> void:
	GameData.music_on = on
	GameData.save_game()
	_apply_music()


func toggle_music() -> void:
	set_music_enabled(not GameData.music_on)


## Switch to the next music track (wraps around).
func next_track() -> void:
	GameData.music_track = (GameData.music_track + 1) % MUSIC.size()
	GameData.save_game()
	if GameData.music_on:
		_apply_music()   # restart playing with the new track


func current_track_name() -> String:
	return MUSIC_NAMES[clampi(GameData.music_track, 0, MUSIC_NAMES.size() - 1)]


# --- Sound effects --------------------------------------------------------

func play_sfx(name: String) -> void:
	if not GameData.sfx_on or not SFX.has(name):
		return
	# Round-robin through the pool so a new effect never cuts off the last one.
	var player := _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_players.size()
	player.stream = SFX[name]
	player.play()


func set_sfx_enabled(on: bool) -> void:
	GameData.sfx_on = on
	GameData.save_game()

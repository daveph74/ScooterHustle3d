extends Node
## AudioManager - global sound singleton (autoload).
##
## Plays the background music (loopable, switchable, mutable) and one-shot sound
## effects. Reachable anywhere as "AudioManager". Settings (music on/off, sfx
## on/off, chosen track) live in GameData so they are saved with everything else.

# Music tracks: file path + menu-friendly name. Loaded at RUNTIME (not preloaded)
# so the game still runs if a file hasn't been added yet, and so MP3 / OGG / WAV
# looping is each handled correctly. To add or swap a track, just edit this list
# and drop the matching file into audio/music/.
const MUSIC_TRACKS := [
	{"path": "res://audio/music/Scooter-Rush.mp3", "name": "Scooter Rush"},
	{"path": "res://audio/music/Tropical-Rush.mp3", "name": "Tropical Rush"},
]

# Filled in _ready from whichever MUSIC_TRACKS files actually exist.
var _music: Array[AudioStream] = []
var _music_names: Array[String] = []

# Sound effects, looked up by name.
const SFX := {
	"coin": preload("res://audio/sfx/coin.wav"),
	"crash": preload("res://audio/sfx/crash.wav"),
	"near_miss": preload("res://audio/sfx/near_miss.wav"),
	"click": preload("res://audio/sfx/click.wav"),
	"powerup": preload("res://audio/sfx/powerup.wav"),
	"shield": preload("res://audio/sfx/shield.wav"),
	"scream": preload("res://audio/sfx/scream.wav"),
}

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_index := 0

# A continuous looping engine note whose pitch rises with the scooter's speed.
const ENGINE_STREAM := preload("res://audio/sfx/engine.wav")
var _engine_player: AudioStreamPlayer


func _ready() -> void:
	# Load whichever track files are present and make each one loop seamlessly.
	for t in MUSIC_TRACKS:
		if not ResourceLoader.exists(t.path):
			continue
		var stream: AudioStream = load(t.path)
		_enable_loop(stream)
		_music.append(stream)
		_music_names.append(t.name)

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

	# The engine loop: quieter than effects (it plays constantly) and set to loop.
	_enable_loop(ENGINE_STREAM)
	_engine_player = AudioStreamPlayer.new()
	_engine_player.stream = ENGINE_STREAM
	_engine_player.volume_db = -19.0   # -6 dB below the old -13 = ~50% quieter
	_engine_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_engine_player)

	_apply_music()


# --- Music ----------------------------------------------------------------

## Make a stream loop, whatever its format (MP3 / OGG / WAV).
func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)


func _apply_music() -> void:
	if GameData.music_on and not _music.is_empty():
		var index: int = clampi(GameData.music_track, 0, _music.size() - 1)
		_music_player.stream = _music[index]
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
	if _music.is_empty():
		return
	GameData.music_track = (GameData.music_track + 1) % _music.size()
	GameData.save_game()
	if GameData.music_on:
		_apply_music()   # restart playing with the new track


func current_track_name() -> String:
	if _music_names.is_empty():
		return "—"
	return _music_names[clampi(GameData.music_track, 0, _music_names.size() - 1)]


# --- Sound effects --------------------------------------------------------

## Play a sound effect. Optional pitch (1.0 = normal) lets callers raise the
## pitch for things like rising combo milestones.
func play_sfx(name: String, pitch: float = 1.0) -> void:
	if not GameData.sfx_on or not SFX.has(name):
		return
	# Round-robin through the pool so a new effect never cuts off the last one.
	var player := _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_players.size()
	player.stream = SFX[name]
	player.pitch_scale = pitch
	player.play()


func set_sfx_enabled(on: bool) -> void:
	GameData.sfx_on = on
	GameData.save_game()
	if not on:
		stop_engine()


# --- Engine loop ----------------------------------------------------------

## Called every gameplay frame with a 0..1 speed ratio. Keeps the engine looping
## (while SFX are on) and raises its pitch with speed. Stops it if SFX are muted.
func update_engine(speed_ratio: float) -> void:
	if not GameData.sfx_on:
		if _engine_player.playing:
			_engine_player.stop()
		return
	if not _engine_player.playing:
		_engine_player.play()
	_engine_player.stream_paused = false
	_engine_player.pitch_scale = lerpf(0.8, 1.7, clampf(speed_ratio, 0.0, 1.0))


func stop_engine() -> void:
	_engine_player.stop()


## Pause/unpause the engine without losing its place (used by the pause menu).
func set_engine_paused(paused: bool) -> void:
	_engine_player.stream_paused = paused

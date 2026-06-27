extends CanvasLayer

## Radial speed-line overlay that fades in at high speed.
## Game.gd calls set_speed_ratio(ratio) each frame.

var _speed_ratio: float = 0.0
var _lines: Array = []

const LINE_COUNT := 16
const LINE_LENGTH := 380.0
const LINE_WIDTH := 2.0
const SCREEN_CX := 540.0   # portrait 1080 / 2
const SCREEN_CY := 960.0   # portrait 1920 / 2


func _ready() -> void:
	layer = 0   # above 3D world, below HUD (HUD CanvasLayer uses default layer 1)
	_build_lines()


func _build_lines() -> void:
	for i in range(LINE_COUNT):
		var line := ColorRect.new()
		line.color = Color(1.0, 1.0, 1.0, 0.0)   # start invisible
		line.size = Vector2(LINE_WIDTH, LINE_LENGTH)
		line.pivot_offset = Vector2(LINE_WIDTH * 0.5, 0.0)
		_lines.append(line)
		add_child(line)
	_layout_lines()


func _layout_lines() -> void:
	for i in range(_lines.size()):
		var angle := (float(i) / float(LINE_COUNT)) * TAU
		var line: ColorRect = _lines[i]
		# Position at center of screen, pointing outward.
		line.position = Vector2(
			SCREEN_CX - LINE_WIDTH * 0.5,
			SCREEN_CY - LINE_LENGTH)
		line.rotation = angle


func set_speed_ratio(ratio: float) -> void:
	_speed_ratio = ratio
	# Lines only appear above 60% speed. Fade in smoothly, max alpha 0.12 (very subtle).
	var target_alpha: float = 0.0
	if ratio > 0.6:
		target_alpha = lerpf(0.0, 0.12, (ratio - 0.6) / 0.4)
	for line in _lines:
		(line as ColorRect).color.a = lerpf((line as ColorRect).color.a, target_alpha, 0.15)

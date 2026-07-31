extends HBoxContainer
class_name WaveHeading

# A heading rendered as one Label per letter, gently bobbing out of phase with
# its neighbors - reused across every screen's page title (Title, Options,
# Endless, Help, Scores) rather than copied per screen, so the wave's feel
# can't drift between them.
#
# The letters are laid out by this HBoxContainer for one initial pass, then
# animated directly via `position.y`. Containers only reposition children on
# structural changes (add/remove/resize), not every idle frame, so writing to
# position.y each frame afterward is safe and won't fight the layout.
#
# Drop-in replacement for a centered heading Label: add it to a VBoxContainer
# the same way, and it fills the column width and centers itself the same way
# a Label with horizontal_alignment = CENTER would.

const DEFAULT_AMPLITUDE := 6.0
const DEFAULT_SPEED := 2.4        # rad/sec
const DEFAULT_PHASE_STEP := 0.34  # rad of phase offset per letter index

var _letters: Array[Label] = []
var _base_y: Array[float] = []
var _time: float = 0.0
var _amplitude: float = DEFAULT_AMPLITUDE
var _speed: float = DEFAULT_SPEED
var _phase_step: float = DEFAULT_PHASE_STEP
# Index this heading's first letter would have had in a longer run of text.
# Splitting a heading across two lines (portrait's "PERFECT" / "ZERO") otherwise
# restarts the phase on the second line, so the two would bob in lockstep with
# each other instead of continuing the one travelling wave.
var _phase_start: int = 0

func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# outline_size = 0 skips the outline entirely (EndlessModeSelect's subtler
# secondary headings use this) rather than drawing a zero-width one.
func configure(text: String, font_size: int, fill: Color, outline: Color,
		outline_size: int = 5, phase_start: int = 0) -> void:
	_phase_start = phase_start
	for ch in text:
		var letter := Label.new()
		letter.text = ch
		letter.add_theme_font_size_override("font_size", font_size)
		letter.add_theme_color_override("font_color", fill)
		if outline_size > 0:
			letter.add_theme_color_override("font_outline_color", outline)
			letter.add_theme_constant_override("outline_size", outline_size)
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# A plain centered Label stretches to the container's full cross-axis
		# width and centers its text within that - matching that here needs the
		# same vertical_alignment once this row itself is stretched to a taller
		# parent's height.
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(letter)
		_letters.append(letter)

	# Deferred so this HBoxContainer has actually sorted its children once
	# before their starting y is captured - reading position.y this same frame
	# would still be the pre-layout 0.
	call_deferred("_capture_base_y")

func _capture_base_y() -> void:
	_base_y.clear()
	for letter in _letters:
		_base_y.append(letter.position.y)

func _process(delta: float) -> void:
	if _base_y.size() != _letters.size():
		return
	_time += delta
	for i in range(_letters.size()):
		_letters[i].position.y = _base_y[i] \
			+ sin(_time * _speed + (i + _phase_start) * _phase_step) * _amplitude

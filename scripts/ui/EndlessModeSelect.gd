extends Control
class_name EndlessModeSelect

const NEON := Color("22d3ff")
const RED := Color("ff2e5e")
const GOLD := Color("ffd23f")
const LOCKED_ACCENT := Color("8b90a8")
const TEXT_FILL := Color("dfe3ee")
const MUTED := Color("8b90a8")  # same hex as LOCKED_ACCENT - a different role (muted body text vs. a locked control's accent), so kept as its own name rather than reused across two meanings

@export var runner: EndlessRunner
@export var campaign_navigator: CampaignNavigator

var _hardcore_button: Button
var _normal_caption: Label
var _hardcore_caption: Label

const SCORE_KEY_NORMAL := "highscore_endless_normal"
const SCORE_KEY_HARDCORE := "highscore_endless_hardcore"
# The powerup primer's own CanvasLayer while it's up, else null. Tracked because
# a CanvasLayer isn't a CanvasItem: hiding this screen does not hide it, so any
# exit taken while it's open has to free it explicitly - the same reason
# TutorialManager tracks its own popup layer.
var _tutorial_layer: CanvasLayer


# Portrait is a 900-wide canvas rather than 1600, so this screen's landscape type
# sizes leave it reading as a small block adrift in the middle of a phone screen.
# One factor scales type, spacing and control footprints together, keeping the
# proportions intact. Chosen from the measured content: content measures 420 wide; 1.7 puts it at 714 of 900.
const PORTRAIT_SCALE := 1.7

# Matches every other screen's page-title size (CreditsScreen/OptionsPanel),
# confirmed with the user 2026-07-31 - this used to be its own smaller size and
# read inconsistent against screens reached from the same title-screen row.
const PAGE_HEADING_SIZE := 56

func _s() -> float:
	return PORTRAIT_SCALE if Layout.is_portrait() else 1.0

func _fs(base: int) -> int:
	return roundi(base * _s())

var _backdrop: ColorRect
var _center: CenterContainer
var _built_portrait: bool = false

func _ready() -> void:
	position = Vector2.ZERO
	size = Layout.canvas_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	GameManager.state_changed.connect(_on_state_changed)
	Layout.changed.connect(_apply_canvas)
	_apply_canvas()

func _on_state_changed(new_state: int) -> void:
	if new_state != GameManager.GameState.ENDLESS_MODE_SELECT:
		return
	# Re-evaluated on every visit (not just once at _ready) since campaign
	# progress made elsewhere can unlock this between visits to this screen.
	_style_hardcore_lock()
	# Refreshed for the same reason as the lock above - a run played since the
	# last visit here may have set a new record.
	if _normal_caption != null:
		_refresh_target_caption(_normal_caption, SCORE_KEY_NORMAL)
	if _hardcore_caption != null:
		_refresh_target_caption(_hardcore_caption, SCORE_KEY_HARDCORE)


# A plain resize is a re-measure; an orientation change rebuilds, because the
# portrait scale feeds every font size and a Label's is fixed once created.
func _apply_canvas() -> void:
	size = Layout.canvas_size
	if _built_portrait != Layout.is_portrait():
		_rebuild()
		return
	if _center != null:
		_center.size = Layout.canvas_size
	_apply_overscan()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_backdrop = null
	_center = null
	_build()
	_apply_overscan()

func _apply_overscan() -> void:
	ScreenLayout.cover(_backdrop)

func _build() -> void:
	_built_portrait = Layout.is_portrait()
	_backdrop = ColorRect.new()
	var backdrop := _backdrop
	backdrop.position = Layout.overscan_position
	backdrop.size = Layout.overscan_size
	backdrop.color = Color(0.03, 0.03, 0.05, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_center = CenterContainer.new()
	var center := _center
	center.position = Vector2.ZERO
	center.size = Layout.canvas_size
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(24))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := WaveHeading.new()
	col.add_child(title)
	title.configure("ENDLESS", _fs(PAGE_HEADING_SIZE), TEXT_FILL, NEON)

	# _fs(26), not a bare 26 - this was the one label on the screen that skipped
	# the portrait type scale, which at PORTRAIT_SCALE 1.7 left the subtitle
	# rendering SMALLER than the muted best-score caption below it (_fs(20) = 34)
	# and inverted against its own hierarchy.
	col.add_child(_heading("Choose your mode", _fs(26), GOLD))

	var normal := _mode_button("NORMAL", "3 lives", NEON)
	normal.pressed.connect(func(): _start(3))
	col.add_child(_wrap(normal))
	_normal_caption = _target_caption(SCORE_KEY_NORMAL)
	col.add_child(_normal_caption)

	_hardcore_button = _mode_button("HARDCORE", "1 life", RED)
	col.add_child(_wrap(_hardcore_button))
	_hardcore_caption = _target_caption(SCORE_KEY_HARDCORE)
	col.add_child(_hardcore_caption)

	# Sized and colored to match every other screen's BACK button (200x64,
	# same cyan as the title screen's ARCADE button) rather than the mode
	# buttons' own 420x76 - _button() is shared with those, so the size is
	# overridden after creation here.
	var back := _button("BACK", NEON)
	# 64 raw is only ~43.5dp effective at this screen's 1.7 scale - just under
	# Android's 48dp minimum. Bumped to 72 (~49dp) in portrait only; landscape
	# (desktop/web) keeps the original 64.
	var back_h: float = 72.0 if Layout.is_portrait() else 64.0
	back.custom_minimum_size = Vector2(200, back_h) * _s()
	# _button() sets font_size to _fs(30) for the mode buttons - the largest BACK
	# font of any screen in the game, and large enough to visually compete with
	# the mode buttons' own _fs(30) name/lives labels sitting right above it.
	# Overridden down to _fs(28), matching Help/Options' BACK.
	back.add_theme_font_size_override("font_size", _fs(28))
	back.pressed.connect(_on_back)
	col.add_child(_wrap(back))

# Android's system back (bridged to ui_cancel by MainScreenRouter) and desktop
# Escape both land on the same handler the on-screen BACK button uses. Guarded
# on the current state because hidden screens stay in the tree and would
# otherwise all answer the same press - see LevelSelect for the full note.
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.ENDLESS_MODE_SELECT:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	# With the powerup primer up, back closes the primer and stays here rather
	# than leaving the screen - that's the real "one level up" from a modal, and
	# it avoids stranding the primer's CanvasLayer over the title screen. The
	# run it was gating deliberately does not start, and it's left unmarked in
	# the save so it shows again next time instead of being silently skipped.
	if _tutorial_layer != null and is_instance_valid(_tutorial_layer):
		_tutorial_layer.queue_free()
		_tutorial_layer = null
		return
	GameManager.set_state(GameManager.GameState.MENU)

# A separate, later gate than the title screen's ENDLESS lock - reaching this
# screen at all already means Stage 3 is cleared; Hardcore specifically needs
# the *whole* campaign, tracked via CampaignNavigator.is_campaign_complete()
# rather than a second flag of its own.
func _style_hardcore_lock() -> void:
	if _hardcore_button == null:
		return
	if _hardcore_button.pressed.is_connected(_start_hardcore):
		_hardcore_button.pressed.disconnect(_start_hardcore)
	if _hardcore_button.pressed.is_connected(_on_locked_hardcore_tapped):
		_hardcore_button.pressed.disconnect(_on_locked_hardcore_tapped)

	if campaign_navigator != null and campaign_navigator.is_campaign_complete():
		_hardcore_button.modulate = Color.WHITE
		_style_button(_hardcore_button, RED)
		_restyle_mode_labels(_hardcore_button, RED)
		_hardcore_button.pressed.connect(_start_hardcore)
	else:
		_hardcore_button.modulate = Color(1, 1, 1, 0.45)
		_style_button(_hardcore_button, LOCKED_ACCENT)
		_restyle_mode_labels(_hardcore_button, LOCKED_ACCENT)
		# Left enabled (not .disabled) so it can still receive the tap that
		# shows the toast - a disabled Button eats input instead of firing
		# `pressed`, same reasoning as the title screen's locked ENDLESS button.
		_hardcore_button.pressed.connect(_on_locked_hardcore_tapped)

# _style_button only recolors the Button itself, but a mode button's name/lives
# text lives on two child Labels (see _mode_button) rather than the Button's
# own .text, so the lock/unlock re-skin has to reach those separately or they'd
# stay RED forever once locked.
func _restyle_mode_labels(button: Button, accent: Color) -> void:
	for child in button.get_children():
		if child is Label:
			child.add_theme_color_override("font_outline_color", accent)

func _start_hardcore() -> void:
	_start(1)

func _on_locked_hardcore_tapped() -> void:
	Toast.show(self, "Complete all Arcade stages to unlock", LOCKED_ACCENT)

# The powerup primer fires on the actual mode choice (Normal or Hardcore),
# never on merely opening this screen - so a player who backs out without
# picking either never sees it, and it always lands right before the run it's
# actually describing rather than ahead of a screen the player might bounce off.
func _start(lives: int) -> void:
	if PowerupTutorial.is_new():
		_tutorial_layer = PowerupTutorial.show_popup(self, _on_tutorial_dismissed.bind(lives))
	else:
		runner.start_run(lives)

func _on_tutorial_dismissed(lives: int) -> void:
	# PowerupTutorial frees its own layer on GOT IT; this just drops the handle
	# so _on_back() can't try to free it a second time.
	_tutorial_layer = null
	runner.start_run(lives)

func _wrap(c: Control) -> Control:
	var w := CenterContainer.new()
	w.add_child(c)
	return w

# Pre-run target (Reward brief §5) - sits under each mode button, muted so it
# reads as context rather than competing with the button's own accent color.
# First-run framing (no stored record) is a distinct message rather than
# "BEAT YOUR BEST: 0", which would read as a real, beatable target of zero.
func _target_caption(key: String) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", _fs(20))
	# MUTED, not TEXT_FILL@0.75 alpha - every other screen expresses "muted
	# supporting text" as the same MUTED colour rather than a faded TEXT_FILL, so
	# this was the one place "muted" meant something different from the rest of
	# the project. Alpha dropped since MUTED is already muted on its own.
	l.add_theme_color_override("font_color", MUTED)
	_refresh_target_caption(l, key)
	return l

func _refresh_target_caption(label: Label, key: String) -> void:
	var best: int = SaveManager.load_high_score(key)
	label.text = ("BEAT YOUR BEST: %s" % ScoreManager.thousands(best)) if best > 0 \
		else "NO RECORD YET"

func _heading(text: String, font_size: int, accent: Color, outline: int = 5) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_FILL)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", accent)
		l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 76) * _s()
	button.add_theme_font_size_override("font_size", _fs(30))
	_style_button(button, accent)
	PressFeedback.apply(button)
	return button

const MODE_BUTTON_SIZE := Vector2(420, 76)
const MODE_LABEL_MARGIN := 28.0

# Left-aligned mode name, right-aligned life count - a label/value pairing
# rather than one centered "NORMAL   -   3 lives" string, so the two ends of
# the button read as two distinct facts instead of one run-on line. The
# button's own .text stays empty; these are child Labels laid out over it with
# fixed pixel math, since MODE_BUTTON_SIZE is a constant rather than something
# that reflows.
func _mode_button(name_text: String, lives_text: String, accent: Color) -> Button:
	var button := Button.new()
	# The two labels are placed by hand rather than by a container, so every
	# measurement below has to come off the button's ACTUAL size - deriving them
	# from the unscaled constant left both labels inside the left 420 of a
	# 714-wide portrait button, printing "NORMAL3 lives" as one run-on string.
	var button_size := MODE_BUTTON_SIZE * _s()
	var margin := MODE_LABEL_MARGIN * _s()
	button.custom_minimum_size = button_size
	_style_button(button, accent)
	PressFeedback.apply(button)

	var half := button_size.x * 0.5
	var name_label := _mode_part_label(name_text, HORIZONTAL_ALIGNMENT_LEFT, accent)
	name_label.position = Vector2(margin, 0)
	name_label.size = Vector2(half - margin, button_size.y)
	button.add_child(name_label)

	var lives_label := _mode_part_label(lives_text, HORIZONTAL_ALIGNMENT_RIGHT, accent)
	lives_label.position = Vector2(half, 0)
	lives_label.size = Vector2(half - margin, button_size.y)
	button.add_child(lives_label)

	return button

# mouse_filter IGNORE so these never intercept the click meant for the Button
# underneath them - same reasoning as PauseMenu's pause-icon bars.
func _mode_part_label(text: String, align: int, accent: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", _fs(30))
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", accent)
	l.add_theme_constant_override("outline_size", 4)
	return l

# Split out from _button() so the Hardcore lock can re-skin an already-built
# button (accent swap between RED and LOCKED_ACCENT) without rebuilding it.
func _style_button(button: Button, accent: Color) -> void:
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_stylebox_override("normal", _box(accent, 0.85))
	button.add_theme_stylebox_override("hover", _box(accent, 0.7))
	button.add_theme_stylebox_override("pressed", _box(accent, 0.6))

func _box(accent: Color, darken: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(12)
	return sb


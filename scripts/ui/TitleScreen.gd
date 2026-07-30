extends Control
class_name TitleScreen

# Rebuilt procedurally (like every other screen) rather than the old
# fixed-offset flat button stack, since a flat single-column list of 7 buttons
# doesn't fit this canvas at all - the two-tier hierarchy below is the actual
# layout, not a restyle of the old one.

const VIEWPORT_SIZE := Vector2(1600, 900)
const NEON := Color("22d3ff")
const GOLD := Color("ffd23f")
const LOCKED_ACCENT := Color("8b90a8")
const TEXT_FILL := Color("dfe3ee")
const RED := Color("ff2e5e")  # same destructive-action red as OptionsPanel's reset confirm

@export var campaign_navigator: CampaignNavigator

# Editable per-build in the Inspector rather than hardcoded, so a build can be
# bumped without touching a script. ProjectSettings' own version field is read
# too, but only as a fallback reference - this exported field is the source of
# truth for what's actually displayed.
@export var build_version: String = "0.1.0"

var _endless_button: Button
var _quit_confirm: Control
var _version_label: Label
var _quit_link: Button  # null on mobile, where no quit link is built

# Authored (inset-free) corner positions; _apply_safe_area() offsets from these.
const VERSION_LABEL_POS := Vector2(VIEWPORT_SIZE.x - 220, VIEWPORT_SIZE.y - 40)
const QUIT_LINK_POS := Vector2(24, VIEWPORT_SIZE.y - 50)

func _ready() -> void:
	_build()
	GameManager.state_changed.connect(_on_state_changed)
	SafeArea.changed.connect(_apply_safe_area)
	_apply_safe_area()

# Only the two corner-pinned elements need insetting. The button rows are
# centred by a CenterContainer, so a side cutout or gesture bar can't clip
# them - they just sit in a slightly narrower box.
func _apply_safe_area() -> void:
	if _version_label != null:
		_version_label.position = VERSION_LABEL_POS + Vector2(-SafeArea.right, -SafeArea.bottom)
	if _quit_link != null:
		_quit_link.position = QUIT_LINK_POS + Vector2(SafeArea.left, -SafeArea.bottom)

# TitleScreen is built once and persists for the whole session (like every
# other screen), so a player who clears Stage 3 mid-session and later returns
# to the title would otherwise see it locked forever - _style_endless_lock()
# needs to run on every re-visit, not just at construction.
func _on_state_changed(new_state: int) -> void:
	if new_state == GameManager.GameState.MENU:
		_style_endless_lock()

func _build() -> void:
	position = Vector2.ZERO
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title_area := Control.new()
	title_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_area)
	_build_title_wave(title_area)

	# Sized to the band below the title (rather than the full canvas), so
	# centering this container can't pull the button block up into the title.
	var button_area := CenterContainer.new()
	button_area.position = Vector2(0, 300)
	button_area.size = Vector2(VIEWPORT_SIZE.x, VIEWPORT_SIZE.y - 300)
	add_child(button_area)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 28)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	button_area.add_child(col)

	# --- Primary row: the actual gameplay decision -----------------------
	var primary := HBoxContainer.new()
	primary.alignment = BoxContainer.ALIGNMENT_CENTER
	primary.add_theme_constant_override("separation", 28)
	col.add_child(primary)

	var arcade := _primary_button("ARCADE", NEON)
	arcade.pressed.connect(_on_arcade_pressed)
	primary.add_child(arcade)

	_endless_button = _primary_button("ENDLESS", NEON)
	primary.add_child(_endless_button)
	_style_endless_lock()

	# --- Secondary row: icon buttons, paired visually with the in-game "?" ---
	var secondary := HBoxContainer.new()
	secondary.alignment = BoxContainer.ALIGNMENT_CENTER
	secondary.add_theme_constant_override("separation", 18)
	col.add_child(secondary)

	secondary.add_child(_icon_button_texture("res://icons/title_gear.svg", GOLD,
		func(): GameManager.set_state(GameManager.GameState.OPTIONS)))
	secondary.add_child(_icon_button_texture("res://icons/title_question.svg", GOLD,
		func(): GameManager.set_state(GameManager.GameState.HELP)))
	secondary.add_child(_icon_button_texture("res://icons/title_trophy.svg", GOLD,
		func(): GameManager.set_state(GameManager.GameState.SCORES)))
	secondary.add_child(_icon_button_texture("res://icons/title_info.svg", GOLD,
		func(): GameManager.set_state(GameManager.GameState.CREDITS)))

	_build_version_label()
	_build_quit_link()
	# Added last so it layers over the title screen's own content.
	_build_quit_confirm()

# --- System back at the top of the stack -----------------------------------
#
# The title screen is the top of the navigation stack: there's nowhere left to
# go "up" to, so on Android a back press here means exiting the app. Android's
# back swipe is easy to trigger by accident, so that can't be a single
# unconfirmed press - hence the prompt. (project.godot's quit_on_go_back is
# disabled, so nothing quits unless this screen decides to.)
#
# Reuses OptionsPanel's existing reset-confirmation shape rather than
# introducing a second confirmation style: same full-rect dim, same centered
# column, same destructive-in-red / cancel-in-neon pairing.
#
# Desktop/web get the same prompt on Escape, which is the usual convention
# there anyway. The desktop Quit link is deliberately left as a direct quit -
# it's an explicit, deliberate click rather than a stray edge swipe, and
# nothing is at stake on the title screen.
func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.GameState.MENU:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _quit_confirm == null:  # a press landing before _build() finished
		return
	get_viewport().set_input_as_handled()
	# A second back press dismisses the prompt rather than confirming it: back
	# should never be the input that actually quits the game.
	_quit_confirm.visible = not _quit_confirm.visible

func _build_quit_confirm() -> void:
	_quit_confirm = ColorRect.new()
	_quit_confirm.position = Vector2.ZERO
	_quit_confirm.size = VIEWPORT_SIZE
	_quit_confirm.color = Color(0, 0, 0, 0.75)
	_quit_confirm.visible = false
	# STOP (not the screen's own IGNORE) so the title buttons underneath can't
	# be clicked through the prompt.
	_quit_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_quit_confirm)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quit_confirm.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var heading := Label.new()
	heading.text = "Quit Perfect Zero?"
	heading.add_theme_font_size_override("font_size", 40)
	heading.add_theme_color_override("font_color", TEXT_FILL)
	heading.add_theme_color_override("font_outline_color", RED)
	heading.add_theme_constant_override("outline_size", 5)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(heading)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var quit_button := _confirm_button("QUIT", RED)
	quit_button.pressed.connect(func(): get_tree().quit())
	row.add_child(quit_button)

	var cancel := _confirm_button("CANCEL", NEON)
	cancel.pressed.connect(func(): _quit_confirm.visible = false)
	row.add_child(cancel)

func _confirm_button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 64)  # matches every other screen's BACK button
	_style_button(button, accent)
	button.add_theme_font_size_override("font_size", 26)
	PressFeedback.apply(button)
	return button

# TitleLabel used to be a fixed-rect Label; title_area now plays that role -
# WaveHeading fills it via PRESET_FULL_RECT the same way it always did.
func _build_title_wave(title_area: Control) -> void:
	var wave := WaveHeading.new()
	wave.position = Vector2(0, 130)
	wave.size = Vector2(VIEWPORT_SIZE.x, 120)
	title_area.add_child(wave)
	wave.configure("PERFECT ZERO", 96, Color.WHITE, NEON, 16)

func _on_arcade_pressed() -> void:
	# Always through Level Select, first play included. LevelSelect already
	# locks everything past highest_stage_reached (0 for a first-time player),
	# so a new player sees Stage 1 unlocked and 11 more stages visibly locked
	# behind it - showing the scope of the campaign up front, rather than
	# dropping them straight into Stage 1 with no sense of how much game there
	# is to stick around for.
	GameManager.set_state(GameManager.GameState.LEVEL_SELECT)

# --- Endless unlock gate (title-screen layer) ------------------------------

func _style_endless_lock() -> void:
	# Called on every MENU visit, not just once - both connections need to be
	# torn down first so re-styling can't stack a second handler behind the one
	# from the last visit (e.g. unlocking mid-session and returning to title).
	if _endless_button.pressed.is_connected(_on_endless_pressed):
		_endless_button.pressed.disconnect(_on_endless_pressed)
	if _endless_button.pressed.is_connected(_on_locked_endless_tapped):
		_endless_button.pressed.disconnect(_on_locked_endless_tapped)

	if campaign_navigator != null and campaign_navigator.is_endless_unlocked():
		_endless_button.modulate = Color.WHITE
		_style_button(_endless_button, NEON)
		_endless_button.pressed.connect(_on_endless_pressed)
	else:
		# Same locked treatment LevelSelect already uses for a locked stage
		# button: dimmed modulate, muted accent - so a locked Endless reads as
		# the same "not yet" state everywhere in the game. Left enabled (not
		# .disabled) specifically so it can still receive the tap that shows
		# the toast below - a disabled Button eats input instead of firing
		# `pressed`.
		_endless_button.modulate = Color(1, 1, 1, 0.45)
		_style_button(_endless_button, LOCKED_ACCENT)
		_endless_button.pressed.connect(_on_locked_endless_tapped)

func _on_endless_pressed() -> void:
	GameManager.set_state(GameManager.GameState.ENDLESS_MODE_SELECT)

func _on_locked_endless_tapped() -> void:
	Toast.show(self,
		"Complete %d Arcade stages to unlock" % CampaignNavigator.ENDLESS_UNLOCK_STAGE,
		LOCKED_ACCENT)

# --- Build number -----------------------------------------------------------

func _build_version_label() -> void:
	var version_text := build_version
	if version_text.is_empty():
		version_text = str(ProjectSettings.get_setting("application/config/version", ""))
	var label := Label.new()
	label.text = "v%s" % version_text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(200, 30)
	label.position = VERSION_LABEL_POS
	_version_label = label
	add_child(label)

# --- Quit ------------------------------------------------------------------

func _build_quit_link() -> void:
	# Android convention discourages an explicit in-app quit (the back
	# button/gesture and the OS app-switcher already cover it) - only
	# meaningful on desktop, where there's no equivalent system-level exit.
	if OS.has_feature("mobile"):
		return
	var link := Button.new()
	link.text = "Quit"
	link.flat = true
	link.custom_minimum_size = Vector2(90, 36)
	link.position = QUIT_LINK_POS
	_quit_link = link
	link.add_theme_font_size_override("font_size", 18)
	link.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	link.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.7))
	link.pressed.connect(func(): get_tree().quit())
	add_child(link)

# --- Button styling ----------------------------------------------------------

func _primary_button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 84)
	_style_button(button, accent)
	button.add_theme_font_size_override("font_size", 36)
	PressFeedback.apply(button)
	return button

# All four secondary-row buttons share this square footprint so the row
# reads as a uniform set of icon tiles rather than a mix of shapes.
const ICON_BUTTON_SIZE := Vector2(64, 64)
const ICON_TEXTURE_HALF := 20.0

# Hand-authored SVGs (icons/title_*.svg) - same house style as the existing
# powerup icons (icons/powerup_*.svg): translucent accent fill + bold accent
# stroke with a glow filter. Loaded as a texture rather than drawn at runtime
# since resvg/thorvg's bezier rendering reads far cleaner at this size than
# hand-rolled polygon/arc approximations did.
func _icon_button_texture(texture_path: String, accent: Color, handler: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = ICON_BUTTON_SIZE
	_style_button(button, accent)
	button.pressed.connect(handler)
	PressFeedback.apply(button)

	var icon := TextureRect.new()
	icon.texture = load(texture_path)
	# Default expand_mode (EXPAND_KEEP_SIZE) forces the control's minimum size
	# to the texture's native 256x256, overriding the anchor offsets below and
	# blowing the icon up far past the button - EXPAND_IGNORE_SIZE is what the
	# rest of the codebase's TextureRects already use (e.g. Juice.gd) for
	# exactly this reason.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.anchor_left = 0.5
	icon.anchor_right = 0.5
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = -ICON_TEXTURE_HALF
	icon.offset_right = ICON_TEXTURE_HALF
	icon.offset_top = -ICON_TEXTURE_HALF
	icon.offset_bottom = ICON_TEXTURE_HALF
	button.add_child(icon)
	return button

# Just the theme overrides - deliberately excludes PressFeedback.apply(), which
# is a physical child node attached once at creation. _style_endless_lock()
# re-skins an already-built button (locked <-> unlocked accent swap) and would
# otherwise attach a second PressFeedback instance to the same button each time
# it re-styles it.
func _style_button(button: Button, accent: Color) -> void:
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	button.add_theme_stylebox_override("normal", _make_box(accent, 0.85, 0.35, 8))
	button.add_theme_stylebox_override("hover", _make_box(accent, 0.7, 0.5, 12))
	button.add_theme_stylebox_override("pressed", _make_box(accent, 0.6, 0.4, 6))
	button.add_theme_stylebox_override("disabled", _make_box(accent, 0.93, 0.15, 4))

func _make_box(accent: Color, darken: float, shadow_alpha: float, shadow_size: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(accent.r, accent.g, accent.b, shadow_alpha)
	sb.shadow_size = shadow_size
	sb.shadow_offset = Vector2.ZERO
	return sb

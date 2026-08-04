extends Control
class_name TitleScreen

# Rebuilt procedurally (like every other screen) rather than the old
# fixed-offset flat button stack, since a flat single-column list of 7 buttons
# doesn't fit this canvas at all - the two-tier hierarchy below is the actual
# layout, not a restyle of the old one.

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
var _title_area: Control
var _button_area: CenterContainer
var _backdrop: ColorRect
var _wave: WaveHeading
var _wave2: WaveHeading            # portrait only - the "ZERO" line
var _built_portrait: bool = false

# The band below the title that the button block centres itself in. Portrait
# starts it much lower: the canvas is 1600 tall there rather than 900, so the
# landscape value would centre the buttons over 600 units below the heading and
# leave the composition split in half by a void.
const BUTTON_AREA_TOP_LANDSCAPE := 300.0
# Set by the portrait heading's measured height: it runs 200..639, so the button
# band has to start below that or the CenterContainer pulls the stack up into it.
const BUTTON_AREA_TOP_PORTRAIT := 700.0

# --- Portrait title ---------------------------------------------------------
# Split across two lines. "PERFECT ZERO" on one line measures 709 units at font
# size 96, which fits the 900-wide portrait canvas but leaves the heading small
# against a canvas nearly twice as tall as it is wide. Two lines buy back the
# width for a much larger size: "PERFECT" is the longer line and measures 678
# units at font size 160, filling 75% of the canvas, with the pair standing 442
# tall - which is what sets BUTTON_AREA_TOP_PORTRAIT above.
const PORTRAIT_TITLE_TOP := 200.0
const PORTRAIT_TITLE_LINE_GAP := 4
const PORTRAIT_TITLE_FS := 160
const PORTRAIT_TITLE_OUTLINE := 24

# --- Portrait buttons -------------------------------------------------------
# Stacked rather than paired, and larger: a 900-wide canvas can't carry two
# 280-wide buttons side by side without them reading as cramped, and a stacked
# pair is the easier one-handed target anyway.
const PRIMARY_SIZE_LANDSCAPE := Vector2(280, 84)
# Height was 112 (~44.8dp) - just under Android's 48dp minimum. Bumped to 128
# (~51.2dp); landscape (desktop/web) is unaffected.
const PRIMARY_SIZE_PORTRAIT := Vector2(520, 128)
const PRIMARY_FS_LANDSCAPE := 36
const PRIMARY_FS_PORTRAIT := 56  # bumped by a lot on a further user request

# 64 units is 26dp - well under the 48dp minimum, and the one place on this
# screen where that was worth fixing while rearranging anyway. 132 units is 53dp.
const ICON_SIZE_LANDSCAPE := Vector2(64, 64)
const ICON_SIZE_PORTRAIT := Vector2(132, 132)
const ICON_TEXTURE_HALF_LANDSCAPE := 20.0
const ICON_TEXTURE_HALF_PORTRAIT := 42.0

# The quit prompt is the one part of this screen without its own portrait
# arrangement - it is a small centred column of the same shape as every other
# confirm dialog in the project, so it scales as a whole rather than being
# rebuilt into a different layout.
const QUIT_PROMPT_SCALE := 1.6

func _prompt_scale() -> float:
	return QUIT_PROMPT_SCALE if Layout.is_portrait() else 1.0

func _button_area_top() -> float:
	return BUTTON_AREA_TOP_PORTRAIT if Layout.is_portrait() else BUTTON_AREA_TOP_LANDSCAPE

# Authored (inset-free) corner positions; _apply_safe_area() offsets from these.
# Functions rather than consts now that the canvas they hang off transposes.
func _version_label_pos() -> Vector2:
	return Vector2(Layout.canvas_size.x - 220, Layout.canvas_size.y - 40)

func _quit_link_pos() -> Vector2:
	return Vector2(24, Layout.canvas_size.y - 50)

func _ready() -> void:
	_build()
	GameManager.state_changed.connect(_on_state_changed)
	SafeArea.changed.connect(_apply_safe_area)
	Layout.changed.connect(_apply_canvas)
	_apply_canvas()

# Portrait and landscape are genuinely different arrangements here - one heading
# line versus two, a button row versus a stack, a strip of icons versus a 2x2
# grid - so an orientation change rebuilds rather than reflows. Everything else
# (a plain window resize, which only moves the pillarbox bands) is a re-measure.
func _apply_canvas() -> void:
	size = Layout.canvas_size
	if _built_portrait != Layout.is_portrait():
		_rebuild()
		return
	if _button_area != null:
		_button_area.position = Vector2(0, _button_area_top())
		_button_area.size = Vector2(Layout.canvas_size.x,
			Layout.canvas_size.y - _button_area_top())
	_apply_overscan()
	_apply_safe_area()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_wave = null
	_wave2 = null
	_backdrop = null
	_endless_button = null
	_quit_confirm = null
	_version_label = null
	_quit_link = null
	_build()
	_apply_overscan()
	_apply_safe_area()

# Covers the pillarbox bands as well as the canvas - see Layout.overscan_size.
func _apply_overscan() -> void:
	if _backdrop != null:
		_backdrop.position = Layout.overscan_position
		_backdrop.size = Layout.overscan_size
	if _quit_confirm != null:
		_quit_confirm.position = Layout.overscan_position
		_quit_confirm.size = Layout.overscan_size

# Only the two corner-pinned elements need insetting. The button rows are
# centred by a CenterContainer, so a side cutout or gesture bar can't clip
# them - they just sit in a slightly narrower box.
func _apply_safe_area() -> void:
	if _version_label != null:
		_version_label.position = _version_label_pos() + Vector2(-SafeArea.right, -SafeArea.bottom)
	if _quit_link != null:
		_quit_link.position = _quit_link_pos() + Vector2(SafeArea.left, -SafeArea.bottom)

# TitleScreen is built once and persists for the whole session (like every
# other screen), so a player who clears Stage 3 mid-session and later returns
# to the title would otherwise see it locked forever - _style_endless_lock()
# needs to run on every re-visit, not just at construction.
func _on_state_changed(new_state: int) -> void:
	if new_state == GameManager.GameState.MENU:
		_style_endless_lock()

func _build() -> void:
	position = Vector2.ZERO
	size = Layout.canvas_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_built_portrait = Layout.is_portrait()

	# The title screen used to rely on the engine's clear colour showing through.
	# That reads as a different shade from every other screen's backdrop on any
	# aspect ratio with pillarbox bands, so it now paints its own.
	_backdrop = ColorRect.new()
	_backdrop.position = Layout.overscan_position
	_backdrop.size = Layout.overscan_size
	_backdrop.color = Color(0.03, 0.03, 0.05, 1.0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	_title_area = Control.new()
	_title_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_area)
	_build_title_wave(_title_area)

	# Sized to the band below the title (rather than the full canvas), so
	# centering this container can't pull the button block up into the title.
	_button_area = CenterContainer.new()
	_button_area.position = Vector2(0, _button_area_top())
	_button_area.size = Vector2(Layout.canvas_size.x,
		Layout.canvas_size.y - _button_area_top())
	add_child(_button_area)

	var portrait := Layout.is_portrait()

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 28 if not portrait else 40)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_area.add_child(col)

	# --- Primary: the actual gameplay decision ---------------------------
	# A row in landscape, a stack in portrait.
	var primary: BoxContainer = VBoxContainer.new() if portrait else HBoxContainer.new()
	primary.alignment = BoxContainer.ALIGNMENT_CENTER
	primary.add_theme_constant_override("separation", 24 if portrait else 28)
	col.add_child(primary)

	var arcade := _primary_button("ARCADE", NEON)
	arcade.pressed.connect(_on_arcade_pressed)
	primary.add_child(arcade)

	_endless_button = _primary_button("ENDLESS", NEON)
	primary.add_child(_endless_button)
	_style_endless_lock()

	# --- Secondary: icon buttons, paired visually with the in-game "?" ---
	# One strip of four in landscape; 2x2 in portrait, which keeps them large
	# enough to be a real touch target without running the full canvas width.
	var secondary: Container
	if portrait:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 24)
		secondary = grid
	else:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 18)
		secondary = row
	# A GridContainer has no `alignment`, so in portrait it is centred by a
	# wrapper instead of centring itself the way the HBox does.
	col.add_child(_wrap_centered(secondary) if portrait else secondary)

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
	_quit_confirm.size = Layout.canvas_size
	_quit_confirm.color = Color(0, 0, 0, 0.75)
	_quit_confirm.visible = false
	# STOP (not the screen's own IGNORE) so the title buttons underneath can't
	# be clicked through the prompt.
	_quit_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_quit_confirm)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quit_confirm.add_child(center)

	var s := _prompt_scale()

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", roundi(20 * s))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var heading := Label.new()
	heading.text = "Quit PERFECT ZERO?"
	heading.add_theme_font_size_override("font_size", roundi(40 * s))
	heading.add_theme_color_override("font_color", TEXT_FILL)
	heading.add_theme_color_override("font_outline_color", RED)
	heading.add_theme_constant_override("outline_size", roundi(5 * s))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(heading)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(24 * s))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	var quit_button := _confirm_button("QUIT", RED)
	quit_button.pressed.connect(func(): get_tree().quit())
	row.add_child(quit_button)

	var cancel := _confirm_button("CANCEL", NEON)
	cancel.pressed.connect(func(): _quit_confirm.visible = false)
	row.add_child(cancel)

func _confirm_button(text: String, accent: Color) -> Button:
	var s := _prompt_scale()
	var button := Button.new()
	button.text = text
	# 200x64 matches every other screen's BACK button in landscape. 64 raw is
	# only ~41dp effective at this prompt's 1.6 portrait scale - under Android's
	# 48dp minimum. Bumped to 76 (~48.6dp) in portrait only; landscape (desktop/
	# web, where _prompt_scale() is 1.0) keeps the original 64.
	var h: float = 76.0 if Layout.is_portrait() else 64.0
	button.custom_minimum_size = Vector2(200, h) * s
	_style_button(button, accent)
	# Base bumped 26 -> 34 by a lot on a further user request; still scaled by
	# the same _prompt_scale() as everything else on this prompt.
	button.add_theme_font_size_override("font_size", roundi(34 * s))
	PressFeedback.apply(button)
	return button

# TitleLabel used to be a fixed-rect Label; title_area now plays that role -
# WaveHeading fills it via PRESET_FULL_RECT the same way it always did.
func _wrap_centered(c: Control) -> CenterContainer:
	var w := CenterContainer.new()
	w.add_child(c)
	return w

func _build_title_wave(title_area: Control) -> void:
	if Layout.is_portrait():
		var stack := VBoxContainer.new()
		stack.position = Vector2(0, PORTRAIT_TITLE_TOP)
		stack.size = Vector2(Layout.canvas_size.x, 0)
		stack.add_theme_constant_override("separation", PORTRAIT_TITLE_LINE_GAP)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_area.add_child(stack)

		_wave = WaveHeading.new()
		stack.add_child(_wave)
		_wave.configure("PERFECT", PORTRAIT_TITLE_FS, Color.WHITE, NEON,
			PORTRAIT_TITLE_OUTLINE, 0)

		_wave2 = WaveHeading.new()
		stack.add_child(_wave2)
		# Phase picks up at index 8 - where "ZERO" starts in the one-line
		# "PERFECT ZERO" - so the two lines carry one continuous travelling wave
		# instead of bobbing in lockstep with each other.
		_wave2.configure("ZERO", PORTRAIT_TITLE_FS, Color.WHITE, NEON,
			PORTRAIT_TITLE_OUTLINE, 8)
		return

	_wave = WaveHeading.new()
	_wave.position = Vector2(0, 130)
	_wave.size = Vector2(Layout.canvas_size.x, 120)
	title_area.add_child(_wave)
	_wave.configure("PERFECT ZERO", 96, Color.WHITE, NEON, 16)

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

# 16 raw is ~6.4dp effective in landscape - fine at desktop viewing distance,
# and the ONLY unscaled size on this screen (everything else has an explicit
# _PORTRAIT constant). Left genuinely small in portrait too - this is
# deliberately the lowest-emphasis element on the screen, a build tag rather
# than content - but 16 was never revisited for a phone and read closer to
# invisible than "quiet" there. 24 keeps it clearly the smallest, least
# prominent text on the screen while no longer being illegible.
const VERSION_LABEL_FONT_LANDSCAPE := 16
const VERSION_LABEL_FONT_PORTRAIT := 24

func _build_version_label() -> void:
	var version_text := build_version
	if version_text.is_empty():
		version_text = str(ProjectSettings.get_setting("application/config/version", ""))
	var label := Label.new()
	label.text = "V%s" % version_text
	label.add_theme_font_size_override("font_size",
		VERSION_LABEL_FONT_PORTRAIT if Layout.is_portrait() else VERSION_LABEL_FONT_LANDSCAPE)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size = Vector2(200, 30)
	label.position = _version_label_pos()
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
	link.text = "QUIT"
	link.flat = true
	link.custom_minimum_size = Vector2(90, 36)
	link.position = _quit_link_pos()
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
	var portrait := Layout.is_portrait()
	button.custom_minimum_size = PRIMARY_SIZE_PORTRAIT if portrait else PRIMARY_SIZE_LANDSCAPE
	_style_button(button, accent)
	button.add_theme_font_size_override("font_size",
		PRIMARY_FS_PORTRAIT if portrait else PRIMARY_FS_LANDSCAPE)
	PressFeedback.apply(button)
	return button

# All four secondary buttons share one square footprint so they read as a
# uniform set of icon tiles rather than a mix of shapes. See
# ICON_SIZE_LANDSCAPE / ICON_SIZE_PORTRAIT for the two sizes.

# Hand-authored SVGs (icons/title_*.svg), in this project's icon house style:
# translucent accent fill plus a bold accent-coloured stroke, and NO glow
# filter. The glow comes from the button's own border/shadow underneath, not
# from the icon - Godot's runtime SVG rasterizer (thorvg) doesn't composite
# feGaussianBlur/feMerge the way a browser does, and blurs the whole shape
# instead of adding a halo behind a crisp one. (No <text> either, for the same
# family of reason - thorvg renders it blank.)
#
# This comment used to cite icons/powerup_*.svg as the reference "with a glow
# filter". Those three files really did carry one, were never loaded by
# anything, and have since been deleted - so the one note a contributor would
# read before authoring a new icon was recommending the broken pattern.
#
# Loaded as a texture rather than drawn at runtime since resvg/thorvg's bezier
# rendering reads far cleaner at this size than hand-rolled polygon/arc
# approximations did.
func _icon_button_texture(texture_path: String, accent: Color, handler: Callable) -> Button:
	var button := Button.new()
	var portrait := Layout.is_portrait()
	button.custom_minimum_size = ICON_SIZE_PORTRAIT if portrait else ICON_SIZE_LANDSCAPE
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
	var half: float = ICON_TEXTURE_HALF_PORTRAIT if portrait else ICON_TEXTURE_HALF_LANDSCAPE
	icon.offset_left = -half
	icon.offset_right = half
	icon.offset_top = -half
	icon.offset_bottom = half
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

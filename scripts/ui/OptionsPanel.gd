extends Control
class_name OptionsPanel

# Reusable options UI. Used two ways:
#  - as a full screen from Title (standalone = true -> Back returns to MENU)
#  - as an overlay from the Pause menu (standalone = false -> Back just emits closed)

signal closed

const NEON := Color("22d3ff")
const RED := Color("ff2e5e")
const GOLD := Color("ffd23f")
const BACK_ACCENT := NEON  # same cyan as the title screen's ARCADE button
const TEXT_FILL := Color("dfe3ee")
const MUTED := Color("8b90a8")

# Scales type and control footprints only - it no longer sets the screen's width.
# It used to: under the old label-left/control-right layout the binding constraint
# was the widest row (360 label + 20 + 320 slider = 700 raw), which at 1.4 came to
# 980 against a 900-unit canvas and ran off both edges on device, forcing 1.2.
# The single-column layout took that constraint away entirely - width is now set
# by _content_width() against the canvas directly, independent of this - so this
# is free to change on type-size grounds alone.
const PORTRAIT_SCALE := 1.2

# Touch targets. 1 canvas unit = 0.4dp, so Android's 48dp minimum is 120 units
# and the 56dp it recommends for a primary action is 140. At PORTRAIT_SCALE
# these come out of raw 100 and 120 respectively - different raw numbers to the
# Help screen's 80/96 only because that screen scales by 1.5, not 1.2; both land
# on the same dp.
#
# Measured on this screen before this pass: the two sliders and the checkbox
# were 14.4dp - the most-used controls here and the smallest things on the
# screen - and every button was 30.7dp. All under the minimum.
const TOUCH_MIN := 100.0    # x1.2 = 120 units = 48dp
const TOUCH_BACK := 120.0   # x1.2 = 144 units = 57.6dp, matching HelpScreen's BACK

# Body text. _fs(26) measured 12.5dp, under the 14sp floor for body copy; 30
# lands at 14.4dp. Each label now owns a full-width line of its own rather than a
# 360-unit cell beside its control, so there is no longer a width ceiling on it.
# Bumped by a lot (30 -> 42) on a further user request, matching the same pass
# applied to Stage Result/Endless End/Pause/Title/tutorial screens.
const FIELD_LABEL_SIZE := 42

# Uppercase eyebrows over each group. Deliberately below body size - the
# hierarchy here is carried by colour and case, not scale - and deliberately
# MUTED rather than gold: this project reserves gold for outcomes and records,
# and spending it on group scaffolding is the same mistake the Scores table
# header was making.
const SECTION_LABEL_SIZE := 36
# The one-line explanation under a toggle. "Reduce screen effects" said nothing
# about what it actually does, which is kill screen shake, camera punch,
# hit-stop and full-screen flashes outright for motion sensitivity.
#
# Deliberately smaller than SECTION_LABEL_SIZE (was equal to it, at 36) - the
# two are different roles that happened to share a number: SECTION_LABEL is an
# uppercase eyebrow that only needs to be found, this is a sentence that needs
# to be read. Case already separates them, but two labels the same size sitting
# both MUTED made the sentence read as a second, quieter eyebrow rather than
# actual explanatory copy underneath the toggle's own label.
const SUBTITLE_SIZE := 30

# --- Row icons ------------------------------------------------------------
# Hand-authored SVGs (icons/options_*.svg), same house style as icons/title_*.svg
# and icons/credits_heart.svg: a translucent accent fill/stroke pass plus a
# bold solid pass, no <text> elements and no feGaussianBlur/feMerge filter
# (thorvg, Godot's runtime SVG rasterizer, does not composite those into a
# soft halo - it blurs the whole shape instead). The "glow" behind a row icon
# here is a small drawn backing disc instead - see _icon()/IconGlow below -
# the same "soft wide disc under a solid bright one" trick NeonSlider's and
# NeonToggle's knobs already use, reused rather than reinvented.
const ICON_SFX := "res://icons/options_speaker.svg"
const ICON_MUSIC := "res://icons/options_note.svg"
const ICON_DISPLAY := "res://icons/options_eye.svg"
const ICON_DATA := "res://icons/options_trash.svg"
const ICON_DEBUG := "res://icons/options_debug.svg"

# Sized to sit comfortably inside a row's own existing tap-target height
# rather than grow it - every row this appears in already clears 48dp on its
# own control (the slider, the toggle row, the button), and this adds no
# height of its own to any of them.
const ROW_ICON_SIZE := 44.0

# Absolute canvas units, deliberately NOT multiplied by _s(): this is a width
# budget against a fixed-width canvas, so scaling it would just re-introduce the
# overflow the scale factor exists to avoid. Portrait spends nearly the whole
# 900-unit canvas (40 either side) now that nothing sits beside the controls;
# landscape stays a centred column rather than stretching a slider across 1600
# units, which is neither readable nor pleasant to drag.
func _content_width() -> float:
	return 820.0 if Layout.is_portrait() else 700.0

# The touch padding is portrait-only. Landscape is desktop/web with a mouse,
# where an invisible hit area three times taller than the slider it wraps would
# only make stray clicks near the row start dragging it.
func _touch_pad() -> bool:
	return Layout.is_portrait()

# The dp floors are portrait-only, the same split ScoresScreen already uses:
# landscape is desktop/web with a mouse, where they do not apply - and it is the
# tight axis on a stacked screen, so spending 100 units on a button there buys
# nothing and costs layout. Measured, applying them to both overflowed landscape.
const BUTTON_HEIGHT_LANDSCAPE := 64.0

func _button_h() -> float:
	return TOUCH_MIN if Layout.is_portrait() else BUTTON_HEIGHT_LANDSCAPE

func _back_h() -> float:
	return TOUCH_BACK if Layout.is_portrait() else BUTTON_HEIGHT_LANDSCAPE

func _s() -> float:
	return PORTRAIT_SCALE if Layout.is_portrait() else 1.0

func _fs(base: int) -> int:
	return roundi(base * _s())

@export var standalone: bool = false  # true when used as a Title screen

var _confirm_overlay: Control
var _backdrop: ColorRect
var _scroll: ScrollContainer
var _built_portrait: bool = false

func _ready() -> void:
	position = Vector2.ZERO
	size = Layout.canvas_size
	mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so it works as an overlay too
	_build()
	Layout.changed.connect(_apply_canvas)
	# Ends the Music slider's live preview (see AudioManager.preview_music_volume)
	# the moment this panel stops being shown, by whichever of its several close
	# paths actually did it - the on-screen BACK button's _on_back(), PauseMenu's
	# own ui_cancel handler calling _close_options() directly, or the standalone
	# screen's own state-driven hide. All of them end in `visible` going false,
	# so this is the one place that has to know about it rather than three.
	visibility_changed.connect(func() -> void:
		if not visible:
			AudioManager.cancel_music_preview())
	# Deferred, not called directly, only for this first call: a Control's size
	# setter always clamps up to its current get_combined_minimum_size(), and on
	# the very first synchronous frame - before any Container has run its own
	# (also-deferred) sort_children pass even once - an AUTOWRAP_WORD_SMART
	# label's width is still 0, so its wrap-height computation degenerates to a
	# huge placeholder value instead of the real ~2-line height. That bogus
	# number gets baked into the scroll container's own size right here and
	# nothing ever shrinks it back down afterward, which is exactly the
	# symptom reported on-device: a
	# ~350dp dead zone above the title with the bottom of the panel clipped off
	# screen. Deferring this one call runs it after every add_child() queued
	# during _build() has had its own deferred sort resolve real widths, so the
	# label's minimum height is already correct by the time this reads it.
	call_deferred("_apply_canvas")

# A plain resize is a re-measure; an orientation change is a rebuild, because
# _s() feeds every font size and a Label's font size is fixed once created.
func _apply_canvas() -> void:
	size = Layout.canvas_size
	if _built_portrait != Layout.is_portrait():
		_rebuild()
		return
	if _scroll != null:
		_scroll.size = Layout.canvas_size
	_apply_overscan()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_backdrop = null
	_scroll = null
	_confirm_overlay = null
	_build()
	_apply_overscan()

func _apply_overscan() -> void:
	ScreenLayout.cover_all([_backdrop, _confirm_overlay])

func _build() -> void:
	_built_portrait = Layout.is_portrait()

	_backdrop = ColorRect.new()
	_backdrop.position = Layout.overscan_position
	_backdrop.size = Layout.overscan_size
	_backdrop.color = Color(0.03, 0.03, 0.05, 0.96)
	add_child(_backdrop)

	# A ScrollContainer, not the plain CenterContainer this screen used before
	# this pass - three separate cards (AUDIO+DISPLAY, DATA, and debug builds'
	# DEBUG) plus the Display section's before/after preview measure taller
	# than a 9:16 portrait canvas (1920 into 1600, confirmed headlessly, and
	# worse again at Layout.PORTRAIT_HEIGHT_MIN). Kept on in landscape too
	# rather than branched by orientation - a ScrollContainer with nothing to
	# scroll draws identically to a plain container, so there is no cost to
	# leaving it on unconditionally, and no separate landscape code path to
	# verify or let drift.
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2.ZERO
	_scroll.size = Layout.canvas_size
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	# Centres the fixed-width column within the ScrollContainer's own (wider)
	# viewport on the one axis that doesn't scroll. A bare CenterContainer as
	# the ScrollContainer's direct child doesn't do this - a ScrollContainer
	# only stretches a direct child to its own viewport width at all when that
	# child's own size flags ask to EXPAND (SIZE_FILL alone isn't enough), and
	# a CenterContainer's *job* is centering a child at that child's OWN
	# natural size, which is the opposite of asking to expand - so with no
	# extra width ever handed to it to center within, it just sits flush at
	# the origin. Confirmed headlessly.
	#
	# An HBoxContainer that itself DOES request SIZE_EXPAND_FILL, holding
	# `outer` between two SIZE_EXPAND_FILL spacer Controls, sidesteps this:
	# the row gets the full viewport width for the reason above, and the two
	# spacers then split whatever's left of it around `outer` equally - the
	# same well-worn distribution math this project already leans on
	# everywhere else two things need to share space evenly.
	var center_row := HBoxContainer.new()
	center_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_row.add_theme_constant_override("separation", 0)
	var spacer_l := Control.new()
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spacer_r := Control.new()
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_row.add_child(spacer_l)
	_scroll.add_child(center_row)

	# Every gap on this screen is an explicit spacer and the containers'
	# separation is zeroed. A container separation PLUS spacer children between
	# the same items double-counts every gap - the bug already hit and fixed on
	# EndlessEndScreen, PauseMenu and CreditsScreen - so the pixel value written
	# here is the actual pixel gap.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	outer.custom_minimum_size = Vector2(_content_width(), 0)
	center_row.add_child(outer)
	center_row.add_child(spacer_r)

	var title := WaveHeading.new()
	outer.add_child(title)
	title.configure("OPTIONS", _fs(72), TEXT_FILL, NEON)
	outer.add_child(_gap(18))

	# Three independent cards now, not three sections sharing one. AUDIO/DISPLAY
	# stay on the original neutral card; DATA and (debug builds only) DEBUG each
	# get their own, with their own distinct treatment - see _build_data_card()/
	# _build_debug_card() for why a shared card wasn't enough to make RESET
	# PROGRESS read as dangerous before it's even tapped.
	outer.add_child(_build_audio_display_card())

	outer.add_child(_gap(20))
	outer.add_child(_build_data_card())

	# Wrapped together so release genuinely has nothing here - not a hidden
	# node, not a reserved gap, no DEBUG card and no gap before it either.
	if OS.is_debug_build():
		outer.add_child(_gap(20))
		outer.add_child(_build_debug_card())

	# Back stays bottom-centred at the size every other screen's BACK uses,
	# rather than becoming a top-left arrow: six screens share that treatment,
	# and the top-left corner is the hardest place on a phone to reach one-handed
	# for the control a player uses most on this screen.
	outer.add_child(_gap(18))
	var back := _button("BACK", BACK_ACCENT)
	back.custom_minimum_size = Vector2(200, _back_h()) * _s()
	back.pressed.connect(_on_back)
	outer.add_child(_wrap(back))

	_build_confirm_overlay()

# --- AUDIO + DISPLAY card ---------------------------------------------------

func _build_audio_display_card() -> Control:
	var card := _card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)

	col.add_child(_section_label("AUDIO"))
	col.add_child(_gap(8))
	col.add_child(_rule(0.22))
	col.add_child(_gap(14))

	# Two independent sliders on two separate audio buses. The SFX one is the
	# original "Volume" control, relabelled - its saved key is unchanged, so
	# existing players keep the level they set.
	#
	# Both already apply their bus volume continuously while being dragged
	# (NeonSlider._set_value emits value_changed on every snapped step of a
	# drag, not just release, and Settings.set_volume()/set_music_volume() are
	# wired straight to it) - the gap was never "when", it was that neither bus
	# has anything actually sounding on it during a drag for that live change
	# to be heard against. AudioManager.play_volume_preview_tick()/
	# preview_music_volume() are what give each slider something to hear; see
	# their own comments in AudioManager.gd.
	var sfx_slider := NeonSlider.new()
	sfx_slider.scale_by(_s(), _touch_pad())
	sfx_slider.value = Settings.volume
	sfx_slider.value_changed.connect(func(v: float) -> void:
		Settings.set_volume(v)
		AudioManager.play_volume_preview_tick())
	col.add_child(_field("SFX volume", sfx_slider, true, ICON_SFX, NEON))

	col.add_child(_gap(12))
	col.add_child(_rule(0.12))
	col.add_child(_gap(12))

	var music_slider := NeonSlider.new()
	music_slider.scale_by(_s(), _touch_pad())
	music_slider.value = Settings.music_volume
	music_slider.value_changed.connect(func(v: float) -> void:
		Settings.set_music_volume(v)
		AudioManager.preview_music_volume(v))
	col.add_child(_field("Music volume", music_slider, true, ICON_MUSIC, NEON))

	col.add_child(_gap(26))
	col.add_child(_section_label("DISPLAY"))
	col.add_child(_gap(8))
	col.add_child(_rule(0.22))

	# Reduce screen effects - turns off screen shake, camera punch, hit-stop and
	# every full-screen flash or wash outright (scaling those down still shakes
	# and still flashes). Localized effects, the powerup state overlays and audio
	# are left alone.
	var reduce := NeonToggle.new()
	reduce.scale_by(_s())
	reduce.set_initial(Settings.reduce_intensity)
	reduce.toggled.connect(func(on): Settings.set_reduce_intensity(on))
	# The subtitle has to describe what the toggle ACTUALLY does. It previously
	# read "Fewer particles, no screen shake", which was wrong on the first half:
	# particle bursts are deliberately left alone (see the comment above, GDD §9,
	# and Settings.motion_effects_enabled()'s own note - effect_scale() reaches
	# label pops and glow strength, never a burst or particle count). A player
	# reading that would turn this on to reduce visual clutter and get none of
	# what it promised. The label carries "screen" for the same reason: without
	# it, "Reduce effects" reads as a global effects switch, which is exactly the
	# misreading the old subtitle then confirmed.
	col.add_child(_toggle_field("Reduce screen effects",
		"No screen shake, flashes or camera punch", reduce, ICON_DISPLAY, NEON))

	col.add_child(_gap(14))
	col.add_child(_build_effect_preview())

	return card

# --- DATA card ---------------------------------------------------------------
# A separate card, not a third section on the neutral one above - the point is
# for RESET PROGRESS to read as dangerous before it's even tapped, which a
# shared background can't do regardless of how the button itself is coloured.
# Reuses OptionsPanel.RED - the same destructive/FAIL/Hardcore red already used
# everywhere else in the game (EndlessModeSelect's Hardcore button, every
# grade's FAIL colour, TitleScreen's own comment ties it back to this exact
# screen) - rather than a new danger colour invented for this one card.
func _build_data_card() -> Control:
	var card := _danger_card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)

	col.add_child(_section_label("DATA", RED))
	col.add_child(_gap(8))
	col.add_child(_rule(0.32, RED))
	col.add_child(_gap(14))

	# Named for exactly what it clears now (progress, not preferences) - see
	# _on_confirm_reset() for why that split needed its own fix, not just a
	# relabel.
	var reset := _button("RESET PROGRESS", RED)
	reset.pressed.connect(_on_reset_pressed)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _fs(14))
	row.add_child(_icon(ICON_DATA, RED))
	row.add_child(reset)
	col.add_child(_wrap(row))
	return card

# --- DEBUG card (debug builds only) ------------------------------------------
# Wrapped in OS.is_debug_build() at the CALL site in _build() above, not just
# here - the same pattern this control's own cycler already used before this
# pass (see the comment that used to sit on it: "never present in a release
# export"). A debug export template reports is_debug_build() == false the same
# as a release one; only the editor and a debug export template report true -
# so this genuinely never enters the scene tree in a shipped build, rather
# than existing there hidden or disabled.
func _build_debug_card() -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.06, 1.0)
	sb.set_corner_radius_all(roundi(10 * _s()))
	# The border itself is drawn by DashedBorder below, not this stylebox - a
	# StyleBoxFlat border is always a solid line, and "reads as machinery" is
	# the whole point of this card.
	sb.set_content_margin_all(_fs(18) if Layout.is_portrait() else 10)
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var dashed := DashedBorder.new()
	dashed.set_anchors_preset(Control.PRESET_FULL_RECT)
	dashed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dashed)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", _fs(12))
	header.add_child(_icon(ICON_DEBUG, MUTED, false))
	# No monospace font asset exists anywhere in this project (every screen
	# uses the theme's default), so "technical-looking" is reached with a
	# built-in FontVariation letter-spacing bump instead of adding a new font
	# file just for one label - see _technical_font().
	var label := Label.new()
	label.text = "DEBUG - NOT SHIPPED"
	label.add_theme_font_size_override("font_size", _fs(SECTION_LABEL_SIZE - 4))
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_font_override("font", _technical_font())
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Without this, the letter-spacing _technical_font() adds pushes the
	# label's unwrapped natural width past this screen's own content column on
	# a portrait canvas (confirmed headlessly: 839 measured against an 820
	# budget) - the same class of overflow the confirm modal's warning label
	# already guards against with the same property.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(label)
	col.add_child(header)
	col.add_child(_gap(16))

	# Cycles OFF -> PERFECT -> GOOD -> OFF; while non-OFF, every click on any
	# timer grades as that grade instead of its real timing, for testing
	# scoring/UI reactions without needing precise clicks. MUTED rather than
	# GOLD now - a highlight colour on a control meant to look unpolished works
	# against the point of this whole card.
	var dev_cycle := _button(_dev_grade_label(Settings.dev_force_grade), MUTED)
	dev_cycle.custom_minimum_size = Vector2(200, _button_h()) * _s()
	dev_cycle.pressed.connect(func():
		Settings.set_dev_force_grade(_next_dev_grade(Settings.dev_force_grade))
		dev_cycle.text = _dev_grade_label(Settings.dev_force_grade))
	col.add_child(_field("Dev: force grade", dev_cycle, false, "", MUTED, false))

	return card

# A FontVariation wrapping the theme's own default font with extra glyph
# spacing - the built-in engine mechanism for this, not a second font asset.
# base_font is fetched from the control itself (get_theme_default_font()
# requires the node to already be in the tree, which a builder function isn't
# yet) via ThemeDB's own fallback instead.
func _technical_font() -> FontVariation:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.spacing_glyph = roundi(4 * _s())
	return f

# Segmented rectangle outline - StyleBoxFlat borders are always solid lines,
# and a dashed one is what makes the debug card read as machinery rather than
# a plainly-bordered fifth section. Deliberately its own tiny draw loop rather
# than a StyleBox trick.
class DashedBorder extends Control:
	const DASH := 10.0
	const GAP := 7.0
	const WIDTH := 2.0
	var accent: Color = Color(0.545, 0.565, 0.66, 0.55)  # OptionsPanel.MUTED @ 0.55

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		_dashed_line(r.position, Vector2(r.position.x + r.size.x, r.position.y))
		_dashed_line(Vector2(r.position.x + r.size.x, r.position.y), r.position + r.size)
		_dashed_line(r.position + r.size, Vector2(r.position.x, r.position.y + r.size.y))
		_dashed_line(Vector2(r.position.x, r.position.y + r.size.y), r.position)

	func _dashed_line(a: Vector2, b: Vector2) -> void:
		var d: Vector2 = b - a
		var length: float = d.length()
		if length <= 0.0:
			return
		var dir: Vector2 = d / length
		var step: float = DASH + GAP
		var t: float = 0.0
		while t < length:
			var seg_end: float = minf(t + DASH, length)
			draw_line(a + dir * t, a + dir * seg_end, accent, WIDTH)
			t += step

func _danger_card() -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var base := Color(0.075, 0.082, 0.105, 1.0)
	# A visible red wash over the same base fill _card() uses, not a flat
	# saturated block - stays inside the neon-on-black family instead of
	# reading as a different app.
	sb.bg_color = base.lerp(RED, 0.14)
	sb.set_corner_radius_all(roundi(18 * _s()))
	sb.set_border_width_all(maxi(roundi(2.5 * _s()), 2))
	sb.border_color = RED
	sb.shadow_color = Color(RED.r, RED.g, RED.b, 0.4)
	sb.shadow_size = roundi(10 * _s())
	sb.set_content_margin_all(_fs(20) if Layout.is_portrait() else 12)
	card.add_theme_stylebox_override("panel", sb)
	return card

# --- Display section: before/after screen-effects preview --------------------
# A small always-looping visual so "Reduce screen effects" is SHOWN, not just
# described. Reuses the real FAIL flash's own colour and duration
# (Juice.ABERRATION_COLOR/ABERRATION_MS) rather than inventing new preview
# constants - "reuse whatever screen-effect assets already exist" taken
# literally. The REDUCED swatch shows the flash fully ABSENT rather than a
# softened fake of one, because that is what the real toggle does:
# Settings.motion_effects_enabled() (and GDD §9) are explicit that this is a
# hard on/off, not a fader - screen shake, camera punch and every full-screen
# flash are skipped outright, not dimmed. A preview that faked a "softened"
# version would be showing the player a behaviour that does not exist.
func _build_effect_preview() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _fs(28))
	row.add_child(_effect_preview_swatch("NORMAL", true))
	row.add_child(_effect_preview_swatch("REDUCED", false))
	var wrap := CenterContainer.new()
	wrap.add_child(row)
	return wrap

const PREVIEW_SWATCH_SIZE := 56.0

func _effect_preview_swatch(caption: String, flashes: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(6))
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var swatch := ScreenEffectSwatch.new()
	swatch.flashes = flashes
	swatch.custom_minimum_size = Vector2(PREVIEW_SWATCH_SIZE, PREVIEW_SWATCH_SIZE) * _s()
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(swatch)

	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", _fs(18))
	label.add_theme_color_override("font_color", MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)
	return col

# Loops once a second, always - it's a clarifying aid the player glances at
# while reading the toggle beside it, not something that needs their input to
# start. Small and unobtrusive per the brief: a single flat swatch, no attempt
# to replicate the real flash's full-screen scale.
class ScreenEffectSwatch extends Control:
	const LOOP_SEC := 1.0
	var flashes: bool = true
	var _t: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_t = fmod(_t + delta, LOOP_SEC)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.09, 1.0), true)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08), false, 2.0)
		if not flashes:
			return
		var flash_sec: float = Juice.ABERRATION_MS / 1000.0
		if _t > flash_sec:
			return
		var a: float = 1.0 - (_t / flash_sec)
		var c: Color = Juice.ABERRATION_COLOR
		draw_rect(Rect2(Vector2.ZERO, size), Color(c.r, c.g, c.b, c.a * a), true)
# Android's system back (bridged to ui_cancel by MainScreenRouter) and desktop
# Escape. Two OptionsPanel instances exist in the tree at once - the standalone
# title-screen one and the pause menu's overlay copy - so this has to work out
# which (if either) is actually live before answering a press.
#
# Ownership is deliberately split with PauseMenu rather than duplicated: the
# overlay copy is a *child* of PauseMenu, and _unhandled_input runs children
# first, so this gets first refusal on the press and hands the rest back.
#   - Confirm prompt open (either mode): this closes the prompt and consumes
#     the press, so back can never blow past a destructive "erase everything?"
#     step straight out of the panel.
#   - Otherwise, standalone: closes the panel via the same _on_back() the
#     on-screen BACK button uses.
#   - Otherwise, overlay mode: deliberately left unconsumed for PauseMenu's own
#     handler, which already owns closing options back to the pause menu.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if standalone:
		if GameManager.current_state != GameManager.GameState.OPTIONS:
			return
	elif not visible:
		return

	if _confirm_overlay.visible:
		_confirm_overlay.visible = false
		get_viewport().set_input_as_handled()
		return

	if standalone:
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	closed.emit()
	if standalone:
		GameManager.set_state(GameManager.GameState.MENU)
	# Overlay mode's actual close (PauseMenu's own ui_cancel handler, or its
	# OPTIONS button being pressed a second time) doesn't route through this
	# function at all - covered by the visibility_changed hook in _ready()
	# instead, which is the one place that sees every close path.

# --- Reset confirmation ---------------------------------------------------

func _on_reset_pressed() -> void:
	_confirm_overlay.visible = true

func _build_confirm_overlay() -> void:
	_confirm_overlay = ColorRect.new()
	_confirm_overlay.position = Layout.overscan_position
	_confirm_overlay.size = Layout.overscan_size
	_confirm_overlay.color = Color(0, 0, 0, 0.75)
	_confirm_overlay.visible = false
	add_child(_confirm_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(center)

	# The danger treatment now carries all the way to the tap that actually
	# erases something, not just as far as the button that opens this - a
	# red-bordered card, not bare text floating on the dimmed backdrop.
	var panel := PanelContainer.new()
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.075, 0.06, 0.07, 1.0).lerp(RED, 0.10)
	panel_sb.set_corner_radius_all(roundi(20 * _s()))
	panel_sb.set_border_width_all(maxi(roundi(3 * _s()), 2))
	panel_sb.border_color = RED
	panel_sb.shadow_color = Color(RED.r, RED.g, RED.b, 0.4)
	panel_sb.shadow_size = roundi(14 * _s())
	panel_sb.set_content_margin_all(_fs(32))
	panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(20))
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	col.add_child(_heading("Are you sure?", _fs(52), RED))
	# Wrapped rather than leaning on the hard newline alone: at the larger body
	# size the first sentence no longer fits one line on a 900-unit portrait
	# canvas, and an unwrapped Label would just run off both edges.
	#
	# Scoped explicitly to progress, not settings - preferences (volume,
	# Reduce effects) are deliberately kept, per the same reasoning Reduce
	# effects itself exists for: wiping an accessibility toggle as a side
	# effect of replaying the campaign would be a hostile surprise, not a
	# clean slate.
	var warning := _line("This erases all high scores, unlocks, and progress.\n" +
		"Your audio and display settings are kept.\nThis can't be undone.",
		_fs(FIELD_LABEL_SIZE))
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size = Vector2(700 * _s(), 0)
	col.add_child(warning)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _fs(24))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	# CANCEL first and full weight - the safe default a thumb lands on without
	# having to read anything. ERASE second and deliberately lighter-weight
	# (outline only, narrower - but the SAME touch-target height as CANCEL;
	# see _button_secondary()) so an accidental double-tap right after RESET
	# PROGRESS lands on the button that does nothing.
	var cancel := _button("CANCEL", NEON)
	cancel.pressed.connect(func(): _confirm_overlay.visible = false)
	row.add_child(cancel)
	var yes := _button_secondary("ERASE", RED)
	yes.pressed.connect(_on_confirm_reset)
	row.add_child(yes)

func _on_confirm_reset() -> void:
	SaveManager.clear_all()
	# clear_all() wipes the ENTIRE save file - it has no notion of "progress"
	# vs. "preferences". This reset is deliberately scoped to progress only
	# (see the confirm prompt's own copy above), so the player's current
	# settings are written straight back in - see Settings.persist_current_values()
	# for why this has to happen here rather than being left to look
	# "already correct" for the rest of the session.
	Settings.persist_current_values()
	_confirm_overlay.visible = false

# --- Builders -------------------------------------------------------------

# --- layout helpers ---------------------------------------------------------

func _card() -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.082, 0.105, 1.0)
	sb.set_corner_radius_all(roundi(18 * _s()))
	sb.set_border_width_all(maxi(roundi(_s()), 1))
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.set_content_margin_all(_fs(20) if Layout.is_portrait() else 12)
	card.add_theme_stylebox_override("panel", sb)
	return card

# Every gap is written as a portrait value. Landscape is the SHORTER canvas here
# (900 against portrait's 1600), so the same raw number eats about 1.5x as much
# of it - measured, the portrait rhythm overflowed landscape by 136 units. This
# is the same trap the Scores screen hit: on a stacked screen, landscape is the
# tight axis, not the roomy one.
func _gap_scale() -> float:
	return _s() if Layout.is_portrait() else 0.55

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h * _gap_scale())
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _rule(alpha: float, color: Color = MUTED) -> Control:
	var line := ColorRect.new()
	line.color = Color(color.r, color.g, color.b, alpha)
	line.custom_minimum_size = Vector2(0, maxf(_s(), 1.0))
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

func _section_label(text: String, color: Color = MUTED) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _fs(SECTION_LABEL_SIZE))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# A small backing disc behind a flat SVG icon - the same "soft wide disc under
# a solid bright one" trick NeonSlider's and NeonToggle's knobs already draw,
# reused here rather than a second glow technique. `glow` is off for the debug
# icon only: it should not read as a polished, glowing feature the way the
# other four do (see _build_debug_card()).
func _icon(path: String, accent: Color, glow: bool = true) -> Control:
	var s: float = ROW_ICON_SIZE * _s()
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(s, s)
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if glow:
		var g := IconGlow.new()
		g.accent = accent
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(g)
	var tex := TextureRect.new()
	tex.texture = load(path)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	if not glow:
		# The debug icon is already drawn muted/flat in the SVG itself; dropping
		# it a touch further here is what keeps it reading as deliberately
		# recessive rather than "just another icon that happens to be grey".
		tex.modulate.a = 0.8
	wrap.add_child(tex)
	return wrap

class IconGlow extends Control:
	var accent: Color = Color.WHITE
	func _draw() -> void:
		var r: float = size.x * 0.5
		draw_circle(size * 0.5, r, Color(accent.r, accent.g, accent.b, 0.20))

# A toggle is a row, not a stacked block: label and its explanation on the left,
# the switch on the right. Sliders stack because they need the full width to be
# draggable; a switch does not, and putting it inline is what mobile settings
# screens do.
#
# The whole row is the target, not just the switch - which is what makes this
# comfortably clear 48dp even though the switch itself is smaller than that.
func _toggle_field(label_text: String, subtitle: String, toggle: NeonToggle,
		icon_path: String = "", icon_accent: Color = TEXT_FILL) -> Control:
	var row := PanelContainer.new()
	# Input is no longer owned by the row itself - see the `tap` Button added as
	# a second child below - so this stays IGNORE and never competes with it.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Layout.is_portrait():
		row.custom_minimum_size = Vector2(0, TOUCH_MIN * _s())
	var sb := StyleBoxEmpty.new()
	sb.content_margin_top = _fs(10)
	sb.content_margin_bottom = _fs(10)
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", _fs(16))
	row.add_child(h)

	if not icon_path.is_empty():
		h.add_child(_icon(icon_path, icon_accent))

	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", _fs(2))
	h.add_child(texts)

	var l := _line(label_text, _fs(FIELD_LABEL_SIZE))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(l)

	if not subtitle.is_empty():
		var sub := _line(subtitle, _fs(SUBTITLE_SIZE))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		sub.add_theme_color_override("font_color", MUTED)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(sub)

	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(toggle)

	# A real Button laid over the row (PanelContainer fits every direct child to
	# its own content rect, so this ends up pixel-identical to `row`'s bounds
	# without a second measurement pass) rather than a hand-rolled
	# row.gui_input listener. The listener parsed InputEventMouseButton /
	# InputEventScreenTouch release events directly and matched the same
	# pattern HelpScreen._on_caption_input uses successfully - but that one
	# only ever dismisses a caption, where a missed or double-fired event has
	# no lasting consequence. Here it silently failed to register taps at all
	# on a real Android device, and a stateful settings toggle has no
	# "try again, no harm done" quality to mask that with. Routing through
	# Button reuses Godot's own touch/mouse capture and drag-cancel handling -
	# the same machinery every other tappable control in this project (every
	# _button() instance) already relies on and is known to work on-device.
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_ALL
	tap.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty_sb := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		tap.add_theme_stylebox_override(state, empty_sb)
	# button_up rather than the `pressed` signal: fires unconditionally on
	# release regardless of action_mode, which is what "release rather than
	# press, matching every other tap handler in this project" actually means -
	# pressed's own release-vs-cancel distinction is a further refinement, not
	# the point.
	tap.button_up.connect(func(): toggle.toggle())
	row.add_child(tap)
	return row

func _dev_grade_label(value: String) -> String:
	return value if value != "" else "OFF"

func _next_dev_grade(value: String) -> String:
	match value:
		"":
			return "PERFECT"
		"PERFECT":
			return "GOOD"
		_:
			return ""

# One setting per full-width block, label above its own control, rather than the
# old label-left / control-right pair.
#
# Two columns were what pinned this screen's width: the label cell (360) plus the
# slider (320) came to 840 of a 900-unit portrait canvas with 30 units either
# side and nothing to spare, and the slider was squeezed into well under half the
# screen while the label sat in dead space beside it. Stacking hands the control
# the whole column, which is both the mobile-settings convention and a much wider
# drag target on the one control that needs one.
#
# `fill` is off only for controls that shouldn't stretch to the full column - the
# dev grade cycler, which is a plain button and reads as broken at 820 wide.
#
# The label is left-aligned now, not centred - every field can carry a leading
# icon since this pass, and a centred label next to an icon sitting at the
# row's left edge read as two things disagreeing about where the row starts.
# This also brings sliders in line with the toggle row, which was already
# left-aligned for the same reason.
func _field(label_text: String, control: Control, fill: bool = true,
		icon_path: String = "", icon_accent: Color = TEXT_FILL, icon_glow: bool = true) -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", _fs(8))

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", _fs(12))
	header.alignment = BoxContainer.ALIGNMENT_BEGIN
	if not icon_path.is_empty():
		header.add_child(_icon(icon_path, icon_accent, icon_glow))
	var l := _line(label_text, _fs(FIELD_LABEL_SIZE))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(l)
	block.add_child(header)

	if fill:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.add_child(control)
	else:
		var wrap := CenterContainer.new()
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrap.add_child(control)
		block.add_child(wrap)
	return block

func _wrap(c: Control) -> Control:
	var w := CenterContainer.new()
	w.add_child(c)
	return w

func _heading(text: String, font_size: int, accent: Color) -> Label:
	var l := _line(text, font_size)
	l.add_theme_color_override("font_outline_color", accent)
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _line(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_FILL)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, _button_h()) * _s()
	# Bumped by a lot (28 -> 38 base, ~46 effective at this screen's 1.2 scale)
	# on a further user request, matching the other redesigned buttons.
	button.add_theme_font_size_override("font_size", _fs(38))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", accent)
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_stylebox_override("normal", _box(accent, 0.85))
	button.add_theme_stylebox_override("hover", _box(accent, 0.7))
	button.add_theme_stylebox_override("pressed", _box(accent, 0.6))
	PressFeedback.apply(button)
	return button

# The confirm modal's ERASE button. Same touch-target HEIGHT as _button() -
# _button_h() unmodified - visual weight comes from outline-only fill and a
# narrower width, never from shrinking a tap target under the 48dp floor.
func _button_secondary(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(170, _button_h()) * _s()
	button.add_theme_font_size_override("font_size", _fs(30))
	button.add_theme_color_override("font_color", accent)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.08)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.set_content_margin_all(10)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, sb)
	PressFeedback.apply(button)
	return button

func _box(accent: Color, darken: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(darken)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(3)
	sb.border_color = accent
	sb.set_content_margin_all(10)
	return sb

# An on/off switch rather than a checkbox, for two reasons. A checkbox states
# its value only by whether a small mark is present, which is the weakest signal
# available on a dark panel; and the box this replaces drew at 21dp inside a
# full-width row, reading as unfinished next to sliders that visually fill their
# line. A pill switch states its value by position AND colour, and carries the
# same visual weight as a slider.
#
# Godot's built-in CheckBox/CheckButton draw their states as faint default-theme
# icons tuned for a light editor background - on this project's near-black panels
# the unchecked state was effectively invisible, which is the same reason the
# slider below is hand-drawn too.
#
# Input is owned by the row (see _toggle_field), not by this control, so the
# whole row is the touch target - hence MOUSE_FILTER_IGNORE here.
class NeonToggle extends Control:
	const SIZE := Vector2(78, 42)
	# Was its own Color("22d3ff") literal, duplicating OptionsPanel.NEON rather
	# than referencing it - harmless while both happened to agree, but one more
	# place for cyan to silently drift if either is ever repainted.
	const ACCENT := OptionsPanel.NEON
	const OFF_TRACK := Color("3a4050")

	signal toggled(on: bool)

	var checked: bool = false

	var _scale: float = 1.0
	# Visual position of the knob, 0 = off. Kept separate from `checked` so the
	# knob can slide between them instead of the state snapping the drawing.
	var _knob_t: float = 0.0
	var _tween: Tween

	# Called before the control is parented - see NeonSlider.scale_by.
	func scale_by(s: float) -> void:
		_scale = s
		custom_minimum_size = SIZE * s
		size = custom_minimum_size
		queue_redraw()

	func _ready() -> void:
		custom_minimum_size = SIZE * _scale
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	# Settles at a state without animating - for the value loaded from Settings.
	func set_initial(on: bool) -> void:
		checked = on
		_knob_t = 1.0 if on else 0.0
		queue_redraw()

	func toggle() -> void:
		checked = not checked
		var target: float = 1.0 if checked else 0.0
		if _tween != null and _tween.is_valid():
			_tween.kill()
		if is_inside_tree():
			_tween = create_tween()
			_tween.tween_method(_set_knob, _knob_t, target, 0.16) 				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			_set_knob(target)
		toggled.emit(checked)

	func _set_knob(v: float) -> void:
		_knob_t = v
		queue_redraw()

	# draw_rect has no corner radius, so the pill is two end circles plus the bar
	# between them - exact at any scale, and cheaper than a StyleBox round-trip.
	func _pill(rect: Rect2, col: Color) -> void:
		var r: float = rect.size.y * 0.5
		var cy: float = rect.position.y + r
		draw_circle(Vector2(rect.position.x + r, cy), r, col)
		draw_circle(Vector2(rect.position.x + rect.size.x - r, cy), r, col)
		draw_rect(Rect2(rect.position.x + r, rect.position.y,
			rect.size.x - r * 2.0, rect.size.y), col, true)

	func _draw() -> void:
		var box := SIZE * _scale
		# Centred in whatever the row gave this control, not pinned top-left.
		var origin := (size - box) * 0.5
		var border: float = 3.0 * _scale

		# Outer pill doubles as the border: drawn full size in the border colour,
		# then the fill inset by `border`.
		_pill(Rect2(origin, box), OFF_TRACK.lerp(ACCENT, _knob_t))
		_pill(Rect2(origin + Vector2(border, border), box - Vector2(border, border) * 2.0),
			Color(0.06, 0.07, 0.09).lerp(ACCENT.darkened(0.55), _knob_t))

		var r: float = box.y * 0.5
		var cy: float = origin.y + r
		var kr: float = r - border - 3.0 * _scale
		var kx: float = lerpf(origin.x + r, origin.x + box.x - r, _knob_t)
		# Same "soft wide disc under a solid bright one" glow the slider knob uses.
		if _knob_t > 0.01:
			draw_circle(Vector2(kx, cy), kr * 1.7,
				Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25 * _knob_t))
		draw_circle(Vector2(kx, cy), kr, Color.WHITE)

# Same reasoning as NeonToggle: the default HSlider's grip/track icons are
# tuned for a light theme and read as a near-invisible sliver against this
# project's dark panels. Drawn here instead - filled track, bright fill up to
# the value, and a glowing grip knob that's unmistakable at a glance.
class NeonSlider extends Control:
	const SIZE := Vector2(320, 30)
	# Hit height in portrait - see OptionsPanel.TOUCH_MIN. The track and knob keep
	# their own dimensions and centre inside it, so the control is 48dp tall to a
	# finger while looking exactly as it did before.
	const TOUCH_HEIGHT := 100.0
	const TRACK_HEIGHT := 8.0
	const KNOB_RADIUS := 11.0
	# Was its own Color("22d3ff") literal - see NeonToggle.ACCENT's comment above,
	# same duplication, same fix.
	const ACCENT := OptionsPanel.NEON

	signal value_changed(v: float)

	# Range, snap and fill origin are configurable so the Help screen's signed
	# distance slider can be THIS control rather than a second slider class that
	# would have to be kept looking like this one by hand. The defaults are
	# exactly the old hardcoded behaviour (0..1, 0.05 steps, filling from the
	# left end), so both Options sliders are untouched by this.
	var min_value: float = 0.0
	var max_value: float = 1.0
	var snap_step: float = 0.05
	# The value the filled portion of the track is drawn FROM. Left at min_value
	# this is "fill from the left", which is what a volume slider wants; set to
	# 0.0 on a slider whose range straddles zero it becomes "fill from the
	# centre outward", which is what reading a signed distance wants.
	var fill_from: float = 0.0

	var value: float = 1.0:
		set(v):
			value = clampf(v, min_value, max_value)
			queue_redraw()

	var _dragging: bool = false
	var _scale: float = 1.0
	var _height: float = SIZE.y

	# Called before the value is ever set, so the clamp in the setter above is
	# already working against the real range.
	func set_range(lo: float, hi: float, step: float) -> void:
		min_value = lo
		max_value = hi
		snap_step = step
		value = clampf(value, lo, hi)

	# --- Track geometry, exposed ----------------------------------------------
	# A zone bar drawn ABOVE this slider has to line its bands up with the track
	# underneath, and the track is inset by the knob radius at both ends so the
	# knob never overhangs. Anything that needs to agree with the track's
	# geometry asks for it here instead of re-deriving KNOB_RADIUS * _scale and
	# silently drifting the first time the knob is resized.
	func track_inset() -> float:
		return KNOB_RADIUS * _scale

	# Where a given value sits, as a 0..1 fraction of the usable track.
	func ratio_of(v: float) -> float:
		var span: float = max_value - min_value
		if absf(span) < 0.0001:
			return 0.0
		return clampf((v - min_value) / span, 0.0, 1.0)

	# Where a given value sits, in this control's own x coordinates.
	func track_x(v: float) -> float:
		var inset := track_inset()
		return lerpf(inset, size.x - inset, ratio_of(v))

	# SIZE.x is only a minimum now - the single-column layout stretches this to the
	# full content width, and both _draw and _set_from_x read `size` so the track,
	# the knob position and the value a click maps to all follow the real width
	# rather than the declared one.
	#
	# Called before the control is parented - see NeonToggle.scale_by.
	func scale_by(s: float, touch: bool = false) -> void:
		_scale = s
		_height = TOUCH_HEIGHT if touch else SIZE.y
		custom_minimum_size = Vector2(SIZE.x, _height) * s
		size = custom_minimum_size
		queue_redraw()

	func _ready() -> void:
		custom_minimum_size = Vector2(SIZE.x, _height) * _scale
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				_set_from_x(event.position.x)
			accept_event()
		elif event is InputEventMouseMotion and _dragging:
			_set_from_x(event.position.x)
			accept_event()
		elif event.is_action_pressed("ui_left") and has_focus():
			_set_value(value - snap_step)
		elif event.is_action_pressed("ui_right") and has_focus():
			_set_value(value + snap_step)

	func _set_from_x(x: float) -> void:
		var knob := KNOB_RADIUS * _scale
		var usable := size.x - knob * 2.0
		var t: float = (x - knob) / maxf(usable, 0.0001)
		_set_value(lerpf(min_value, max_value, t))

	func _set_value(v: float) -> void:
		var snapped := snappedf(clampf(v, min_value, max_value), snap_step)
		if is_equal_approx(snapped, value):
			return
		value = snapped
		value_changed.emit(value)

	func _draw() -> void:
		var knob := KNOB_RADIUS * _scale
		var track := TRACK_HEIGHT * _scale
		var y := _height * _scale * 0.5
		var x0 := knob
		var x1 := size.x - knob
		var knob_x := lerpf(x0, x1, ratio_of(value))
		# Where the fill starts. Identical to x0 for a 0..1 slider filling from
		# min_value; the centre of the track for a signed one.
		var fill_x := lerpf(x0, x1, ratio_of(fill_from))

		# Empty track, always visible regardless of value.
		draw_rect(Rect2(x0, y - track * 0.5, x1 - x0, track),
			Color(1, 1, 1, 0.08), true)
		# Filled portion, from the fill origin to the current value - drawn from
		# whichever of the two is smaller, so it works in both directions.
		if absf(knob_x - fill_x) > 0.5:
			draw_rect(Rect2(minf(fill_x, knob_x), y - track * 0.5,
				absf(knob_x - fill_x), track), ACCENT, true)

		# Glowing knob: a soft wide translucent disc under a solid bright one,
		# the same "shadow reads as neon glow" trick used on the timer panels.
		draw_circle(Vector2(knob_x, y), knob * 1.7, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25))
		draw_circle(Vector2(knob_x, y), knob, ACCENT)
		draw_circle(Vector2(knob_x, y), knob * 0.5, Color.WHITE)


extends Node

# Procedural SFX synthesizer.
#
# Sounds are built from sine math at runtime into AudioStreamWAV streams and
# played fire-and-forget through a small pool of AudioStreamPlayers.
#
# Full WAV streams are built up front instead of feeding an AudioStreamGenerator,
# so playback can't underrun mid-sound.

const MIX_RATE := 44100.0

# --- Buses ------------------------------------------------------------------
# The low-pass/compressor/limiter chain sits on SFX, not Master, so the music
# track doesn't get run through a 12kHz low-pass meant for synth sounds.
const BUS_SFX := "SFX"
const BUS_MUSIC := "Music"

# --- Menu music -------------------------------------------------------------
# The only external asset in the project. Needs crediting on the itch.io page:
#
#   Music: "Synthwave Retro 80s" by arpmedia - Pixabay
#   https://pixabay.com/music/synthwave-synthwave-retro-80s-569468/
#
# load()ed instead of preload()ed so a missing file just warns and runs silent.
const MENU_MUSIC_PATH := "res://audio/menu_theme.mp3"
# The track is much louder than the synth SFX, so it's turned down to sit in the
# mix. The player's Music slider scales this, so 100% means this level.
const MENU_MUSIC_BASE_LINEAR := 0.2
const MENU_MUSIC_FADE := 0.6
const SILENT_DB := -80.0
const NYQUIST := MIX_RATE * 0.5
const POOL_SIZE := 12
const MIN_FREQ := 20.0          # below this is inaudible rumble
const MAX_FREQ := NYQUIST - 500.0  # stay clear of Nyquist to avoid aliasing
const MAX_DURATION := 5.0        # hard cap so a bad arg can't allocate huge buffers
const CACHE_LIMIT := 128         # bound cache growth for the arbitrary-arg path

# --- Tick ------------------------------------------------------------------
# The tick fires once per second per running timer, so it's the sound that
# decides whether the audio wears on you over a session.
#
# It's a percussive blip: instant attack, fast decay. A symmetric fade-in/out
# envelope (what _make_chord uses) reads as a soft "pinch" instead of a click.
#
# USE_SAMPLE_TICK swaps in a recorded sample from TICK_SAMPLE_PATH instead.
const USE_SAMPLE_TICK := false
const TICK_SAMPLE_PATH := "res://audio/tick.wav"
const TICK_BASE_DB := -7.0
const TICK_PITCH_MIN := 0.90     # sample path only: fresh timer ...
const TICK_PITCH_MAX := 1.85     # ... about to hit zero
const TICK_PITCH_JITTER := 0.03  # +/- per play, so simultaneous ticks don't phase
const TICK_DUCK_WINDOW := 0.12   # how long one tick counts toward ducking

const TICK_BLIP_BASE_HZ := 480.0 # x1.0 fresh -> x2.5 as it nears zero
const TICK_BLIP_DURATION := 0.07
const TICK_BLIP_VOLUME := 0.4
const BLIP_SWEEP_START := 1.6    # starts this far above the target pitch ...
const BLIP_SWEEP_TIME := 0.35    # ... and settles onto it this far in
const BLIP_DECAY := 5.5          # exponential decay rate (higher = snappier)
const BLIP_HARMONIC := 0.3       # 2nd-harmonic mix, so it isn't a naked sine

# --- Punchy one-shot SFX (grade stops, Blackout heartbeat, reveal stingers) --
# These share the tick's instant-attack/exponential-decay engine, with decay and
# harmonic content tuned per sound.
#
# Set true to route all of them through the older _make_chord/_make_arpeggio
# fade envelope instead.
const USE_LEGACY_ONESHOT_SFX := false

# Blackout's heartbeat fires every ~1s per blacked-out timer, so it gets the
# same anti-fatigue ducking and jitter the tick does.
const BLACKOUT_DUCK_WINDOW := 0.15
const BLACKOUT_PITCH_JITTER := 0.04

# --- Ambient bed ----------------------------------------------------------
# A looping drone that thickens as difficulty escalates, built as complete
# looping WAVs and crossfaded between tiers.
#
# Every partial and pulse rate is a whole multiple of 0.5 Hz, so each tier
# completes a whole number of cycles in AMBIENT_LOOP_SECONDS and loops seamlessly.
const AMBIENT_LOOP_SECONDS := 2.0
const AMBIENT_FADE := 0.9         # seconds for a full crossfade between tiers
const AMBIENT_MAX_DB := -14.0     # ceiling, so the bed never masks the ticks
const AMBIENT_MIN_DB := -34.0
const AMBIENT_SILENT_DB := -80.0
const AMBIENT_RAMP := 0.5         # how fast intensity chases its target
const CAMPAIGN_AMBIENT_MAX := 0.5 # Campaign's streak-driven bed stays subtler

const AMBIENT_FREQS := [
	[55.0, 82.5],
	[55.0, 82.5, 110.0],
	[55.0, 82.5, 110.0, 165.0],
]
const AMBIENT_PULSE_HZ := [1.0, 1.5, 2.0]

# --- Tick priority falloff -------------------------------------------------
# Two separate attenuations, and they multiply:
#   _tick_voice_count ducking (below) handles ticks landing in the same instant.
#   This handles a crowded board: timers are ranked by how soon they expire, and
#   ones further out play quieter, keeping the urgent timer on top of the mix.
const TICK_RANK_FALLOFF_ENABLED := true
# Indexed by rank (0 = soonest to expire). Ranks past the end hold the last
# value. Never 0.0, or voices would pop in and out as ranks shuffle.
const TICK_RANK_FALLOFF := [1.0, 0.6, 0.35, 0.2, 0.14, 0.1]
# A slot freed without _exit_tree firing would leave a stuck entry that
# mis-ranks every later tick, so entries expire on their own.
const URGENCY_STALE_SEC := 2.0

var _players: Array[AudioStreamPlayer] = []
var _next_player_index: int = 0
var _cache: Dictionary = {}
var _tick_voice_count: int = 0
var _tick_sample: AudioStream
var _blackout_voice_count: int = 0
var _live_grade: String = ""
var _live_grade_streak: int = 0
# instance_id -> {remaining: float, at: float}. Only live, unfrozen, expiring
# timers are in here; see report_tick_urgency().
var _tick_urgency: Dictionary = {}

var _ambient_players: Array[AudioStreamPlayer] = []
var _ambient_streams: Array = []
var _ambient_active: int = -1     # which player currently carries the bed
var _ambient_tier: int = -1
var _ambient_intensity: float = 0.0
var _ambient_target: float = 0.0
var _ambient_boost: float = 0.0    # additive, owned by Overclock
var _ambient_on: bool = false

var _menu_music: AudioStreamPlayer
var _menu_music_tween: Tween
var _audio_unlocked: bool = false

func _ready() -> void:
	# Only the web build has to wait for a user gesture before it may start
	# audio. Everywhere else this is already unlocked, so the menu music starts
	# at boot as normal. Set before anything can trigger _update_menu_music.
	var on_web := OS.has_feature("web")
	_audio_unlocked = not on_web
	set_process_input(on_web)

	# Buses first: everything built below routes onto them.
	_setup_buses()

	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_players.append(player)

	_load_tick_sample()
	_build_ambient()
	_build_menu_music()
	_setup_sfx_chain()
	_connect_events()
	GameManager.state_changed.connect(_on_state_changed)
	EventBus.heat_changed.connect(_on_heat_changed)

# SFX and Music are child buses of Master, so the two volume sliders are
# independent. They're declared in default_bus_layout.tres and normally already
# exist by the time this runs; this only rebuilds them if that layout is missing,
# so a stale or unexported layout degrades to working audio instead of silence.
func _setup_buses() -> void:
	_ensure_bus(BUS_SFX)
	_ensure_bus(BUS_MUSIC)

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	push_warning("AudioManager: bus '%s' missing from the layout - creating it." % bus_name)
	AudioServer.add_bus()          # -1/no arg appends; passing bus_count is out of range
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

func _load_tick_sample() -> void:
	if not USE_SAMPLE_TICK:
		return  # procedural blip in use - don't load the sample at all
	if ResourceLoader.exists(TICK_SAMPLE_PATH):
		_tick_sample = load(TICK_SAMPLE_PATH)
	else:
		push_warning("AudioManager: %s not found - using the synthesized tick."
			% TICK_SAMPLE_PATH)

# Raw sine bursts have no natural dynamics, so several stacking at once turns
# harsh. One chain on the bus handles it for every sound at once:
#   - low-pass: rounds off the brittle top end of a pure sine
#   - compressor: keeps loudness even instead of spiky when sounds overlap
#   - limiter: hard ceiling so overlapping sounds can't clip
func _setup_sfx_chain() -> void:
	var idx := AudioServer.get_bus_index(BUS_SFX)
	if idx < 0 or AudioServer.get_bus_effect_count(idx) > 0:
		return  # already configured (e.g. scene reload) - don't stack effects

	# Shaves the piercing "air" band without dulling the tick's snap. Raise
	# toward 16000 if things start sounding muffled.
	var lowpass := AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 12000.0
	AudioServer.add_bus_effect(idx, lowpass)

	var compressor := AudioEffectCompressor.new()
	compressor.threshold = -18.0
	compressor.ratio = 3.0
	compressor.attack_us = 300.0
	compressor.release_ms = 80.0
	compressor.gain = 2.0
	AudioServer.add_bus_effect(idx, compressor)

	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(idx, limiter)

# --- Menu music -------------------------------------------------------------

func _build_menu_music() -> void:
	# Checked first because load() on a missing path logs an engine error even
	# though it returns null.
	if not ResourceLoader.exists(MENU_MUSIC_PATH):
		push_warning("AudioManager: menu music missing at %s - running silent."
			% MENU_MUSIC_PATH)
		return
	var stream: AudioStream = load(MENU_MUSIC_PATH)
	if stream == null:
		return
	if stream is AudioStreamMP3:
		stream.loop = true

	_menu_music = AudioStreamPlayer.new()
	_menu_music.stream = stream
	_menu_music.bus = BUS_MUSIC
	_menu_music.volume_db = linear_to_db(MENU_MUSIC_BASE_LINEAR)
	# Music only plays in menus and the tree is only paused during gameplay, so
	# these shouldn't overlap. Set anyway so a pause can't freeze a track mid-bar.
	_menu_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_menu_music)

# Menus only. Gameplay is excluded because the ticks are the game, and the
# results screens because the Campaign reveal opens on a silence beat and closes
# on a single stinger, both of which a music bed would bury.
#
# Pausing doesn't change GameState, so a paused run is still PLAYING here and
# stays silent without a special case.
func _music_wanted_for(state: int) -> bool:
	match state:
		GameManager.GameState.MENU, \
		GameManager.GameState.LEVEL_SELECT, \
		GameManager.GameState.HELP, \
		GameManager.GameState.SCORES, \
		GameManager.GameState.ENDLESS_MODE_SELECT, \
		GameManager.GameState.OPTIONS, \
		GameManager.GameState.CREDITS:
			return true
	return false

func _update_menu_music(state: int) -> void:
	if _menu_music == null:
		return
	var want := _music_wanted_for(state)

	# Menu-to-menu moves land here too. Restarting the fade every time kills any
	# fade-out still in flight, which would otherwise silence a track that
	# should be staying up.
	if _menu_music_tween != null and _menu_music_tween.is_valid():
		_menu_music_tween.kill()

	# Stopped on the way out, so the next menu starts the track from the top
	# rather than dropping in partway through it. Gameplay keeps the ambient
	# drone bed instead, which has no pulse to fight the ticks.
	#
	# On the web build only, hold off until the page has seen a real user gesture
	# (see _input) - calling play() on a suspended AudioContext is the one thing
	# worth avoiding there. _audio_unlocked is true from the start everywhere
	# else, so desktop starts the track immediately.
	if want and not _menu_music.playing:
		if not _audio_unlocked:
			return
		_menu_music.volume_db = SILENT_DB
		_menu_music.play()
	elif not want and not _menu_music.playing:
		return  # already stopped, nothing to fade

	var target_db: float = linear_to_db(MENU_MUSIC_BASE_LINEAR) if want else SILENT_DB
	_menu_music_tween = create_tween()
	_menu_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_menu_music_tween.tween_property(_menu_music, "volume_db", target_db, MENU_MUSIC_FADE)
	if not want:
		_menu_music_tween.tween_callback(_menu_music.stop)

# Web only: browsers block audio until the page has seen a real user gesture,
# and on itch.io the "Run game" click lands on itch's own page rather than the
# iframe the game runs in, so it doesn't count for this document. The first
# press to reach here is genuinely the first this frame has seen.
#
# _input, not _unhandled_input: a click on a menu Button is consumed by the GUI
# and never reaches the unhandled pass, so the unlock would miss every ordinary
# menu click and only fire on presses that hit empty space.
func _input(event: InputEvent) -> void:
	if _audio_unlocked:
		return
	if not (event is InputEventMouseButton or event is InputEventScreenTouch
			or event is InputEventKey):
		return
	if not event.pressed:
		return
	_audio_unlocked = true
	set_process_input(false)  # one-shot; nothing left to watch for
	_update_menu_music(GameManager.current_state)

func _connect_events() -> void:
	if not EventBus.timer_stopped.is_connected(_on_timer_stopped):
		EventBus.timer_stopped.connect(_on_timer_stopped)
	if not EventBus.timer_expired.is_connected(_on_timer_expired):
		EventBus.timer_expired.connect(_on_timer_expired)
	# Not connected to EventBus.stage_cleared on purpose: it fires the same frame
	# the result screen starts its silence beat, so anything played here lands on
	# top of that and steps on play_final_slam() a moment later.

# --- EventBus reactions ---------------------------------------------------

func _on_timer_stopped(_source: Node, grade: String, _type: int, _distance: float) -> void:
	# Any grade repeating back-to-back climbs in pitch a little and breaks on a
	# change of grade. Separate from PERFECT's own multiplier-driven pitch.
	if grade == _live_grade:
		_live_grade_streak += 1
	else:
		_live_grade_streak = 0
		_live_grade = grade

	match grade:
		"PERFECT":
			play_perfect(ScoreManager.multiplier)
		"GOOD":
			play_good(_live_grade_streak)
		"OKAY":
			play_ok(_live_grade_streak)
		"MISS":
			play_miss(_live_grade_streak)
		"FAIL":
			play_expire()

func _on_timer_expired(_source: Node) -> void:
	play_expire()

# --- Tick priority ---------------------------------------------------------

# Called every frame by each live TimerSlot with its own time-to-expiry.
#
# Two kinds of timer never call this, so they hold no rank:
#   - GOLDEN, which has no expiry to rank by (and never ticks).
#   - Timers frozen by a Blue reaction, whose remaining time isn't moving.
#
# BLACKOUT ranks normally. Worth watching in playtests: audio is its main
# feedback channel, so if one goes inaudible on a busy board it may need a rank
# boost or a volume floor.
func report_tick_urgency(id: int, remaining: float) -> void:
	_tick_urgency[id] = {"remaining": remaining, "at": _now()}

func clear_tick_urgency(id: int) -> void:
	_tick_urgency.erase(id)

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

# Rank of `id` among all live timers by time-to-expiry, soonest first. Computed
# on demand (once per tick played, ~once a second per timer) rather than kept
# sorted every frame.
func _tick_rank(id: int) -> int:
	if not _tick_urgency.has(id):
		return 0
	var now := _now()
	var mine: float = _tick_urgency[id]["remaining"]
	var rank := 0
	for other_id in _tick_urgency:
		if other_id == id:
			continue
		var entry: Dictionary = _tick_urgency[other_id]
		if now - float(entry["at"]) > URGENCY_STALE_SEC:
			continue
		if float(entry["remaining"]) < mine:
			rank += 1
	return rank

func _rank_falloff_db(id: int) -> float:
	if not TICK_RANK_FALLOFF_ENABLED:
		return 0.0
	var rank := _tick_rank(id)
	var mult: float = TICK_RANK_FALLOFF[mini(rank, TICK_RANK_FALLOFF.size() - 1)]
	return linear_to_db(mult)

# --- Public API -----------------------------------------------------------

func play_tone(freq: float, duration: float, volume: float = 0.3) -> void:
	_play(_get_chord([freq], duration, volume))

# pitch_factor arrives from TimerSlot as 1.0 (fresh) -> 2.5 (about to hit zero).
func play_tick(pitch_factor: float, slot_id: int = 0) -> void:
	var factor: float = clampf(pitch_factor, 0.25, 6.0)

	# Duck each tick by how many are already sounding, so N timers don't stack N
	# ticks at full volume every second.
	var duck_db: float = linear_to_db(1.0 / sqrt(1.0 + float(_tick_voice_count)))
	duck_db += _rank_falloff_db(slot_id)

	# Jitter either way, so ticks on the same frame don't phase into one harsh
	# doubled transient.
	var jitter: float = randf_range(1.0 - TICK_PITCH_JITTER, 1.0 + TICK_PITCH_JITTER)

	if USE_SAMPLE_TICK and _tick_sample != null:
		# A recorded sample chipmunks well before 2.5x, so the urgency curve
		# maps onto a gentler pitch range here than on the synth path.
		var t: float = clampf(inverse_lerp(1.0, 2.5, factor), 0.0, 1.0)
		_play(_tick_sample, lerpf(TICK_PITCH_MIN, TICK_PITCH_MAX, t) * jitter,
			TICK_BASE_DB + duck_db)
	else:
		# Quantized so ticks at similar urgency reuse one cached stream instead
		# of re-synthesizing every second.
		var freq: float = snappedf(TICK_BLIP_BASE_HZ * factor, 10.0)
		_play(_get_punchy([freq], TICK_BLIP_DURATION, TICK_BLIP_VOLUME,
			BLIP_DECAY, BLIP_HARMONIC, BLIP_SWEEP_START, BLIP_SWEEP_TIME),
			jitter, TICK_BASE_DB + duck_db)

	_tick_voice_count += 1
	# process_always + ignore_time_scale, or a pause or hit-stop could strand the
	# voice count high and duck every later tick forever.
	get_tree().create_timer(TICK_DUCK_WINDOW, true, false, true).timeout.connect(
		func(): _tick_voice_count = maxi(_tick_voice_count - 1, 0))

func play_perfect(streak_multiplier: float) -> void:
	# Multipliers can pass 4.0 in an uncapped run, so the pitch needs room to
	# keep rising through a stage's best stretch.
	var streak: float = clampf(streak_multiplier, 1.0, 6.0)
	# Quantized to 10 Hz steps: MISS halves the multiplier, so this arrives as
	# arbitrary floats (1.75, 3.375, ...), and caching every distinct value would
	# churn past CACHE_LIMIT over a long run and flush the whole cache repeatedly.
	var base_freq: float = snappedf(1046.5 + (streak - 1.0) * 150.0, 10.0)
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_chord([base_freq, base_freq * 1.5], 0.25, 0.35))
	else:
		# Bright and rich - the reward sound gets the most harmonic content.
		_play(_get_punchy([base_freq, base_freq * 1.5], 0.25, 0.35, 4.0, 0.4))

func play_good(streak: int = 0) -> void:
	# A brighter two-note blip, between perfect and okay.
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_chord([784.0, 988.0], 0.16, 0.28))
	else:
		var step: int = clampi(streak, 0, 6)
		var offset: float = step * 45.0
		_play(_get_punchy([784.0 + offset, 988.0 + offset], 0.16, 0.28, 4.5, 0.3))

func play_ok(streak: int = 0) -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_chord([660.0], 0.15, 0.25))
	else:
		var step: int = clampi(streak, 0, 6)
		_play(_get_punchy([660.0 + step * 40.0], 0.15, 0.25, 5.0, 0.25))

func play_miss(streak: int = 0) -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_chord([220.0, 233.0], 0.3, 0.3))
	else:
		# Lower harmonic content and a slower decay than the positive grades -
		# duller and heavier rather than bright, matching the negative feedback.
		# Still climbs on a repeat - a mounting "this isn't going well" cue.
		var step: int = clampi(streak, 0, 5)
		var offset: float = step * 30.0
		_play(_get_punchy([220.0 + offset, 233.0 + offset], 0.3, 0.3, 3.0, 0.15))

func play_expire() -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_chord([150.0, 141.0], 0.6, 0.35))
	else:
		# Longest, slowest decay in the set - a moan rather than a blip, fitting
		# the stage-ending weight of a FAIL.
		_play(_get_punchy([150.0, 141.0], 0.6, 0.35, 2.2, 0.15))

# Endless losing a life. Reserved for that event alone - deliberately NOT reused
# from play_expire()/play_miss(), because the whole point of the life-loss beat
# is that it lands as a second, distinct thing after the FAIL the player already
# heard. Lower than play_expire's moan and bending hard downward rather than
# sitting flat, so it reads as something being taken rather than something
# merely going wrong.
const LIFE_LOST_CHORD := [98.0, 130.81, 155.56]

func play_life_lost() -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_chord(LIFE_LOST_CHORD, 0.55, 0.42))
	else:
		_play(_get_punchy(LIFE_LOST_CHORD, 0.55, 0.42, 2.6, 0.2, 1.45, 0.28))

# Endless beating a stored personal best. Higher and brighter than
# play_stage_clear()'s fanfare (which tops out at 1046.5) so the two don't blur
# together, and fired at most once per run - the flourish is combined across
# whichever stats improved rather than repeating per stat.
const NEW_BEST_RUN := [659.25, 880.0, 1046.5, 1318.51]

func play_new_best() -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_arpeggio(NEW_BEST_RUN, 0.1, 0.4))
	else:
		_play(_get_punchy_sequence(NEW_BEST_RUN, 0.1, 0.4, 4.5, 0.4))

# Unlocking a whole mode (Endless at Stage 3, Hardcore at full completion) is a
# different kind of news from a personal best - "new content available" rather
# than "you beat your own record" - so it gets its own sound rather than reusing
# play_new_best(). A wide, rising open-fifth-plus-octave sweep, brighter/more
# expansive than the tighter run-of-notes NEW_BEST_RUN uses.
const UNLOCK_CHORD := [392.0, 587.33, 784.0, 1046.5]

# Clearing an Arcade stage with every timer PERFECT. A third distinct kind of
# news again - "you played it clean", not "you beat your own record" and not
# "new content available" - and it can land on the same clear as play_new_best(),
# so it has to be told apart from it by ear as well as on screen.
#
# A pure major triad spanning an octave, pitched above NEW_BEST_RUN and left to
# ring far longer (decay 3.0 against its 4.5, harmonic 0.55 against its 0.4): the
# record sound is a tight run of notes, this one shimmers.
const ALL_PERFECT_RUN := [783.99, 987.77, 1174.66, 1567.98]

func play_all_perfect() -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_arpeggio(ALL_PERFECT_RUN, 0.11, 0.42))
	else:
		_play(_get_punchy_sequence(ALL_PERFECT_RUN, 0.11, 0.42, 3.0, 0.55))

func play_unlock() -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_chord(UNLOCK_CHORD, 0.8, 0.42))
	else:
		_play(_get_punchy(UNLOCK_CHORD, 0.8, 0.42, 2.2, 0.3, 1.4, 0.3))

func play_stage_clear() -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_arpeggio([523.25, 659.25, 783.99, 1046.5], 0.12, 0.3))
	else:
		# Some ring rather than a hard cutoff - a fanfare, not a blip - but each
		# note still has a real attack instead of fading in.
		_play(_get_punchy_sequence([523.25, 659.25, 783.99, 1046.5], 0.12, 0.3, 4.0, 0.35))

# Reserved for Campaign's final multiplier slam - the one payoff moment in a
# mode whose scoring is otherwise entirely deferred. Not reused anywhere else.
#
# Six stacked voices spanning C2-G4 (everything else uses 1-4), so it's fuller
# by construction, not just louder. The downward bend gives it weight.
const FINAL_SLAM_CHORD := [65.41, 130.81, 196.0, 261.63, 329.63, 392.0]

func play_final_slam() -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_chord(FINAL_SLAM_CHORD, 1.1, 0.5))
	else:
		_play(_get_punchy(FINAL_SLAM_CHORD, 1.1, 0.5, 1.6, 0.35, 1.06, 0.15))

func play_big_score(intensity: float) -> void:
	# A fast rising flourish that climbs higher and brighter with intensity.
	var base: float = lerp(523.25, 784.0, clampf(intensity, 0.0, 1.0))
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_arpeggio([base, base * 1.25, base * 1.5, base * 2.0], 0.08, 0.4))
	else:
		# Notes are short (0.08s each), so a snappier decay than the fanfare above.
		_play(_get_punchy_sequence(
			[base, base * 1.25, base * 1.5, base * 2.0], 0.08, 0.4, 5.0, 0.35))

# Blackout's digits are gone, so it gets a low "lub-dub" instead of the standard
# rising-pitch tick - the cue that this timer wants listening to, not watching.
# Just as repetitive as the tick (fires every ~1s per blacked-out timer), so it
# gets the same anti-fatigue ducking/jitter treatment, tracked separately since
# it's a different cadence/sound than the regular tick.
func play_blackout_tick(slot_id: int = 0) -> void:
	var duck_db: float = linear_to_db(1.0 / sqrt(1.0 + float(_blackout_voice_count)))
	duck_db += _rank_falloff_db(slot_id)
	var jitter: float = randf_range(1.0 - BLACKOUT_PITCH_JITTER, 1.0 + BLACKOUT_PITCH_JITTER)

	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_arpeggio([150.0, 104.0], 0.085, 0.32), jitter, duck_db)
	else:
		_play(_get_punchy_sequence([150.0, 104.0], 0.085, 0.32, 6.0, 0.15), jitter, duck_db)

	_blackout_voice_count += 1
	get_tree().create_timer(BLACKOUT_DUCK_WINDOW, true, false, true).timeout.connect(
		func(): _blackout_voice_count = maxi(_blackout_voice_count - 1, 0))

# Powerup activation. Each of the three gets its own stacked chord rather than
# one flourish repitched three ways - powerups are rare enough to earn a fuller
# sound than the single tones used elsewhere. Exempt from the tick priority
# falloff, so one always plays at full volume regardless of board noise.
#
# Separated by register, chord voicing, and pitch-bend direction, so they stay
# distinguishable even if all three are popped in quick succession.
func play_powerup_activate(kind: int) -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_arpeggio([392.0, 523.25, 659.25], 0.07, 0.38))
		return
	match kind:
		PowerupSystem.Kind.SHIELD:
			# High, open fifth+octave bending upward - bright and protective.
			_play(_get_punchy([523.25, 783.99, 1046.5], 0.45, 0.34, 3.2, 0.2, 0.85, 0.25))
		PowerupSystem.Kind.CLEAR_ALL:
			# Low, heavy stack bending down - a charge being set, not a win. The
			# rising payoff is the cascade arpeggio that follows it.
			_play(_get_punchy([130.81, 196.0, 261.63], 0.5, 0.42, 2.4, 0.3, 1.25, 0.3))
		PowerupSystem.Kind.OVERCLOCK:
			# Mid, tense major triad with a hard bend up - engine spinning up.
			_play(_get_punchy([220.0, 277.18, 329.63], 0.42, 0.38, 3.0, 0.35, 0.7, 0.35))

# One note per timer resolving in Nuke's cascade. This is the primary "combo"
# feeling of the whole powerup, so it's a real arpeggio rather than a repitched
# tick: the notes walk up a pentatonic scale (no semitones, so any number of
# them lands consonant) and the *last* one snaps to the octave, meaning a
# cascade of two and a cascade of eight both resolve rather than one of them
# stopping partway up a run. Deliberately exempt from the tick falloff - the
# whole point is that the sequence is heard.
const NUKE_SCALE := [261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25]

const NUKE_RESOLVE_CHORD := [261.63, 329.63, 392.0, 523.25]   # C major, root+octave

func play_nuke_note(index: int, total: int) -> void:
	if index >= total - 1:
		# The final timer doesn't get another single note - it lands the whole
		# chord, so the run of notes resolves rather than just stopping. Firing a
		# separate "completion" sound alongside a last note would stack two
		# things on the same beat and read as mud. Long decay so it rings out
		# under the completion flash instead of clipping short.
		if USE_LEGACY_ONESHOT_SFX:
			_play(_get_chord(NUKE_RESOLVE_CHORD, 0.7, 0.4))
		else:
			_play(_get_punchy(NUKE_RESOLVE_CHORD, 0.75, 0.4, 2.0, 0.3))
		return

	# Walk the scale by however much is needed to span it in `total` steps, so a
	# short cascade still climbs the full range instead of creeping up two notes.
	var step: float = float(index) / float(maxi(total - 1, 1))
	var pos: int = clampi(int(step * float(NUKE_SCALE.size() - 1)), 0,
		NUKE_SCALE.size() - 1)
	var freq: float = NUKE_SCALE[pos]

	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_chord([freq], 0.16, 0.3))
	else:
		_play(_get_punchy([freq, freq * 2.0], 0.18, 0.3, 5.5, 0.25))

# Overclock's window closing. The mirror of its activation sound - the same
# tense triad, but bending *down* and settling instead of winding up, so the end
# of the window is as legible as the start. Deliberately not alarming: nothing
# bad happened, the boost simply ran out.
func play_overclock_end() -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_arpeggio([329.63, 277.18, 220.0], 0.09, 0.3))
	else:
		_play(_get_punchy([220.0, 277.18, 329.63], 0.5, 0.3, 3.0, 0.25, 1.3, 0.4))

# A powerup finishing its cooldown. Deliberately small and high - this fires
# unprompted, up to three times a run each, so it has to register without
# competing with the activation sounds above or the grade stingers.
func play_powerup_ready() -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_arpeggio([880.0, 1174.66], 0.05, 0.16))
	else:
		_play(_get_punchy_sequence([880.0, 1174.66], 0.05, 0.16, 7.0, 0.2))

# Shield catching a FAIL. Glassy and bright - this has to read as *intercepted*,
# which means sounding like neither of the two things it sits between: not the
# low moan of a FAIL, not the dull clunk of a MISS. It's the one sound in the
# game whose job is to say "that hit something and stopped".
#
# The heavy 2nd-harmonic content is what makes it glassy rather than a plain
# tone, and the slight downward bend gives it the character of a deflection
# rather than a note being played.
func play_shield_block() -> void:
	if USE_LEGACY_ONESHOT_SFX:
		_play(_get_arpeggio([880.0, 1318.51], 0.1, 0.32))
	else:
		_play(_get_punchy([880.0, 1318.51, 1760.0], 0.55, 0.32, 3.0, 0.5, 1.12, 0.1))

# One short stinger per stop counted during the Campaign reveal. PERFECTs climb
# in pitch as the streak builds; MISS lands as a dull clunk.
#
# `intensity` (0..1) is a separate axis from `streak_index`: the streak drives
# *pitch* and breaks whenever the grade changes, while intensity drives
# *loudness* and accumulates across the whole stage. A stage full of PERFECTs
# therefore keeps getting weightier even where the run of them is interrupted,
# which a pitch climb alone can't express.
const REVEAL_INTENSITY_DB := 5.0

func play_reveal_step(grade: String, streak_index: int = 0, intensity: float = 0.0) -> void:
	var gain_db: float = clampf(intensity, 0.0, 1.0) * REVEAL_INTENSITY_DB
	if USE_LEGACY_ONESHOT_SFX:
		match grade:
			"PERFECT":
				var step: int = clampi(streak_index, 0, 7)
				_play(_get_chord([880.0 + step * 90.0], 0.12, 0.3))
			"GOOD":
				_play(_get_chord([700.0], 0.11, 0.26))
			"OKAY":
				_play(_get_chord([560.0], 0.11, 0.24))
			"MISS":
				_play(_get_chord([190.0, 170.0], 0.2, 0.3))
			_:
				_play(_get_chord([140.0], 0.25, 0.3))
		return

	match grade:
		"PERFECT":
			# Wider range and steeper per-step climb than the legacy branch above -
			# a longer, more dramatic build for stages with lots of PERFECTs to
			# chain (e.g. Stage 6/9), so the streak actually feels like it's paying
			# off rather than plateauing after a handful of stops.
			var step: int = clampi(streak_index, 0, 9)
			# Harmonic content rises with intensity too, so a late PERFECT is
			# brighter and not merely louder than an early one.
			var bright: float = 0.35 + clampf(intensity, 0.0, 1.0) * 0.3
			_play(_get_punchy([880.0 + step * 115.0], 0.12, 0.3, 4.5, bright), 1.0, gain_db)
		"GOOD":
			var g_step: int = clampi(streak_index, 0, 6)
			_play(_get_punchy([700.0 + g_step * 45.0], 0.11, 0.26, 4.5, 0.3), 1.0, gain_db)
		"OKAY":
			var o_step: int = clampi(streak_index, 0, 6)
			_play(_get_punchy([560.0 + o_step * 40.0], 0.11, 0.24, 4.5, 0.25), 1.0, gain_db)
		"MISS":
			var m_step: int = clampi(streak_index, 0, 5)
			var m_offset: float = m_step * 30.0
			# No intensity gain - a MISS shouldn't get louder just because the
			# stage was going well up to that point.
			_play(_get_punchy([190.0 + m_offset, 170.0 + m_offset], 0.2, 0.3, 3.0, 0.15))
		_:
			_play(_get_punchy([140.0], 0.25, 0.3, 2.5, 0.15))

# --- Ambient bed ----------------------------------------------------------

func set_ambient_intensity(value: float) -> void:
	_ambient_target = clampf(value, 0.0, 1.0)

# Additive lift on top of whatever the run's escalation is already asking for.
# Has to be separate from set_ambient_intensity() rather than just calling it
# with a bigger number, because EndlessRunner rewrites the base every frame from
# elapsed_time - a direct set would be stomped before it was ever heard.
func set_ambient_boost(value: float) -> void:
	_ambient_boost = clampf(value, 0.0, 1.0)

func start_ambient() -> void:
	if _ambient_on:
		return
	_ambient_on = true
	_ambient_intensity = 0.0
	_ambient_target = 0.0
	_ambient_tier = -1
	_switch_ambient_tier(0)

func stop_ambient() -> void:
	_ambient_on = false
	_ambient_tier = -1
	_ambient_active = -1
	_ambient_boost = 0.0   # a run abandoned mid-Overclock must not lift the next one
	for player in _ambient_players:
		player.stop()
		player.volume_db = AMBIENT_SILENT_DB

# Cuts any in-flight one-shot SFX (grade calls, ticks, catch sounds) from the
# fire-and-forget pool. Godot doesn't pause AudioStreamPlayer playback just
# because the tree is paused, so a PERFECT sound still playing when the pause
# menu opens keeps sounding right through it - and a same-state restart
# (ENDLESS_PLAYING/PLAYING -> itself, since pausing never touches
# GameManager.current_state) never naturally cuts it either. Called from
# Juice.reset_run_effects(), the same "fresh run" reset point the leftover
# ring-burst fix uses, so a restart doesn't hand the old run's tail sound to
# the new one.
func stop_all_sfx() -> void:
	for player in _players:
		player.stop()

func _on_state_changed(new_state: int) -> void:
	var in_game := (new_state == GameManager.GameState.PLAYING
		or new_state == GameManager.GameState.ENDLESS_PLAYING)
	if in_game:
		start_ambient()
	else:
		stop_ambient()
	_update_menu_music(new_state)
	# Don't carry a same-grade pitch climb across a stage/run boundary - a stage
	# ending on two GOODs shouldn't start the next one mid-climb.
	_live_grade = ""
	_live_grade_streak = 0
	# Same reasoning for the priority registry: leaving a run mass-frees its
	# slots, and any entry that outlived its timer would mis-rank the next one.
	if not in_game:
		_tick_urgency.clear()

func _on_heat_changed(heat: float) -> void:
	# Campaign has no escalation curve, so its bed follows the PERFECT streak.
	# Endless drives intensity from EndlessRunner's own ramp instead.
	if GameManager.current_state == GameManager.GameState.PLAYING:
		set_ambient_intensity(heat * CAMPAIGN_AMBIENT_MAX)

func _process(delta: float) -> void:
	if not _ambient_on or _ambient_players.is_empty():
		return

	var goal: float = clampf(_ambient_target + _ambient_boost, 0.0, 1.0)
	_ambient_intensity = move_toward(_ambient_intensity, goal, delta * AMBIENT_RAMP)

	var tier: int = clampi(int(_ambient_intensity * AMBIENT_FREQS.size()), 0, AMBIENT_FREQS.size() - 1)
	if tier != _ambient_tier:
		_switch_ambient_tier(tier)

	# The active player rises to the intensity-mapped level; any player left over
	# from the previous tier falls away, which is the crossfade.
	var live_db := lerpf(AMBIENT_MIN_DB, AMBIENT_MAX_DB, _ambient_intensity)
	var step := delta * (abs(AMBIENT_SILENT_DB) / AMBIENT_FADE)
	for i in range(_ambient_players.size()):
		var player: AudioStreamPlayer = _ambient_players[i]
		var target_db := live_db if i == _ambient_active else AMBIENT_SILENT_DB
		player.volume_db = move_toward(player.volume_db, target_db, step)

func _switch_ambient_tier(tier: int) -> void:
	_ambient_tier = tier
	var next: int = 0 if _ambient_active != 0 else 1
	var player: AudioStreamPlayer = _ambient_players[next]
	player.stream = _ambient_streams[tier]
	player.volume_db = AMBIENT_SILENT_DB
	player.play()
	_ambient_active = next

func _build_ambient() -> void:
	for i in range(2):  # two players so tiers can crossfade
		var player := AudioStreamPlayer.new()
		player.volume_db = AMBIENT_SILENT_DB
		# SFX, not Music: the bed is a gameplay cue driven by the run's own
		# escalation ramp, so it belongs with the sounds it escalates alongside
		# and should follow the SFX slider rather than the music one.
		player.bus = BUS_SFX
		add_child(player)
		_ambient_players.append(player)
	for tier in range(AMBIENT_FREQS.size()):
		_ambient_streams.append(_make_ambient(tier))

func _make_ambient(tier: int) -> AudioStreamWAV:
	var freqs: Array = AMBIENT_FREQS[tier]
	var pulse_hz: float = AMBIENT_PULSE_HZ[tier]
	var frame_count := int(MIX_RATE * AMBIENT_LOOP_SECONDS)
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	for i in range(frame_count):
		var t: float = i / MIX_RATE
		var sample: float = 0.0
		for freq in freqs:
			sample += sin(TAU * float(freq) * t)
		sample /= float(freqs.size())
		# Pulse stays above zero so the loop seam never clicks.
		var pulse: float = 0.75 + 0.25 * sin(TAU * pulse_hz * t)
		samples[i] = sample * pulse * 0.5

	var wav := _samples_to_wav(samples)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frame_count - 1
	return wav

# --- Playback -------------------------------------------------------------

# pitch/volume are reset on every call: pool players are reused round-robin, so
# a tick's pitch_scale would otherwise leak into whatever sound borrows that
# player next.
func _play(stream: AudioStream, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if stream == null or _players.is_empty():
		return
	var player := _players[_next_player_index]
	_next_player_index = (_next_player_index + 1) % _players.size()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()

# --- Synthesis (cached) ---------------------------------------------------

func _get_chord(freqs: Array, duration: float, volume: float) -> AudioStreamWAV:
	var key := "c|%s|%.4f|%.4f" % [str(freqs), duration, volume]
	if _cache.has(key):
		return _cache[key]
	var stream := _make_chord(freqs, duration, volume)
	_store_in_cache(key, stream)
	return stream

func _get_punchy(freqs: Array, duration: float, volume: float, decay: float,
		harmonic: float, sweep_start: float = 1.0, sweep_time: float = 0.3) -> AudioStreamWAV:
	var key := "p|%s|%.4f|%.4f|%.2f|%.2f|%.2f|%.2f" \
		% [str(freqs), duration, volume, decay, harmonic, sweep_start, sweep_time]
	if _cache.has(key):
		return _cache[key]
	var stream := _make_punchy(freqs, duration, volume, decay, harmonic, sweep_start, sweep_time)
	_store_in_cache(key, stream)
	return stream

func _get_punchy_sequence(freqs: Array, note_duration: float, volume: float,
		decay: float, harmonic: float) -> AudioStreamWAV:
	var key := "ps|%s|%.4f|%.4f|%.2f|%.2f" \
		% [str(freqs), note_duration, volume, decay, harmonic]
	if _cache.has(key):
		return _cache[key]
	var stream := _make_punchy_sequence(freqs, note_duration, volume, decay, harmonic)
	_store_in_cache(key, stream)
	return stream

func _get_arpeggio(freqs: Array, note_duration: float, volume: float) -> AudioStreamWAV:
	var key := "a|%s|%.4f|%.4f" % [str(freqs), note_duration, volume]
	if _cache.has(key):
		return _cache[key]
	var stream := _make_arpeggio(freqs, note_duration, volume)
	_store_in_cache(key, stream)
	return stream

func _store_in_cache(key: String, stream: AudioStreamWAV) -> void:
	# Simple bound: if the cache fills up (e.g. many distinct play_tone calls),
	# drop everything and start over rather than leaking memory indefinitely.
	if _cache.size() >= CACHE_LIMIT:
		_cache.clear()
	_cache[key] = stream

func _make_chord(freqs: Array, duration: float, volume: float) -> AudioStreamWAV:
	var clean_freqs := _sanitize_freqs(freqs)
	var dur: float = clampf(duration, 0.0, MAX_DURATION)
	if clean_freqs.is_empty() or dur <= 0.0:
		return null
	var frame_count := int(MIX_RATE * dur)
	if frame_count <= 0:
		return null

	var vol: float = clampf(volume, 0.0, 1.0)
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	for i in range(frame_count):
		var t: float = i / MIX_RATE
		var envelope: float = sin(PI * t / dur)  # 0 at both ends -> no click
		var sample: float = 0.0
		for freq in clean_freqs:
			sample += sin(TAU * freq * t)
		samples[i] = (sample / clean_freqs.size()) * envelope * vol
	return _samples_to_wav(samples)

# Percussive arcade chord: instant attack, exponential decay, an optional fast
# downward pitch sweep, and light 2nd-harmonic warmth. Deliberately does NOT
# use _make_chord()'s symmetric fade-in/fade-out envelope - see the tick
# constants above for why that shape reads as mushy rather than punchy.
# Generalized from the original tick-only blip to support multiple simultaneous
# frequencies (a "chord") and per-sound decay/harmonic, so each grade's sound
# can keep its own character while sharing one impact-shaped envelope.
func _make_punchy(freqs: Array, duration: float, volume: float, decay: float,
		harmonic: float, sweep_start: float = 1.0, sweep_time: float = 0.3) -> AudioStreamWAV:
	var clean_freqs := _sanitize_freqs(freqs)
	var dur: float = clampf(duration, 0.0, MAX_DURATION)
	if clean_freqs.is_empty() or dur <= 0.0:
		return null
	var frame_count := int(MIX_RATE * dur)
	if frame_count <= 0:
		return null

	var vol: float = clampf(volume, 0.0, 1.0)
	var sweep_t: float = maxf(sweep_time, 0.001)
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	# Phase is accumulated per-note rather than computed from t, because the
	# frequency changes during the sweep - sin(TAU * f * t) with a moving f
	# would jump. All notes share the same sweep multiplier so a chord stays
	# in tune with itself while bending.
	var phases := PackedFloat32Array()
	phases.resize(clean_freqs.size())
	for i in range(frame_count):
		var u: float = float(i) / float(frame_count)  # 0..1 through the sound
		var sweep: float = lerpf(sweep_start, 1.0, minf(u / sweep_t, 1.0))

		var sample: float = 0.0
		for n in range(clean_freqs.size()):
			var current_freq: float = clampf(float(clean_freqs[n]) * sweep, MIN_FREQ, MAX_FREQ)
			phases[n] += TAU * current_freq / MIX_RATE
			var wave: float = sin(phases[n]) + harmonic * sin(phases[n] * 2.0)
			sample += wave / (1.0 + harmonic)
		sample /= float(clean_freqs.size())

		var envelope: float = exp(-u * decay)
		# Taper the last sliver to zero so the buffer can't end mid-cycle and pop.
		if u > 0.92:
			envelope *= (1.0 - u) / 0.08
		samples[i] = sample * envelope * vol
	return _samples_to_wav(samples)

# Sequential punchy notes (each with its own attack/decay, not a fade) - for
# things like Blackout's "lub-dub" that need a thump per note, not a smear.
func _make_punchy_sequence(freqs: Array, note_duration: float, volume: float,
		decay: float, harmonic: float) -> AudioStreamWAV:
	var clean_freqs := _sanitize_freqs(freqs)
	var note_dur: float = clampf(note_duration, 0.0, MAX_DURATION)
	if clean_freqs.is_empty() or note_dur <= 0.0:
		return null
	var total_duration: float = minf(note_dur * clean_freqs.size(), MAX_DURATION)
	var frame_count := int(MIX_RATE * total_duration)
	if frame_count <= 0:
		return null

	var vol: float = clampf(volume, 0.0, 1.0)
	var frames_per_note := int(MIX_RATE * note_dur)
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	var phase: float = 0.0
	for i in range(frame_count):
		var note_index: int = clampi(i / maxi(frames_per_note, 1), 0, clean_freqs.size() - 1)
		var freq: float = clampf(float(clean_freqs[note_index]), MIN_FREQ, MAX_FREQ)
		phase += TAU * freq / MIX_RATE

		var wave: float = sin(phase) + harmonic * sin(phase * 2.0)
		wave /= 1.0 + harmonic

		var u_in_note: float = float(i % frames_per_note) / float(frames_per_note)
		var envelope: float = exp(-u_in_note * decay)
		samples[i] = wave * envelope * vol
	return _samples_to_wav(samples)

func _make_arpeggio(freqs: Array, note_duration: float, volume: float) -> AudioStreamWAV:
	var clean_freqs := _sanitize_freqs(freqs)
	var note_dur: float = clampf(note_duration, 0.0, MAX_DURATION)
	if clean_freqs.is_empty() or note_dur <= 0.0:
		return null
	var total_duration: float = min(note_dur * clean_freqs.size(), MAX_DURATION)
	var frame_count := int(MIX_RATE * total_duration)
	if frame_count <= 0:
		return null

	var vol: float = clampf(volume, 0.0, 1.0)
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	for i in range(frame_count):
		var t: float = i / MIX_RATE
		var note_index: int = clampi(int(t / note_dur), 0, clean_freqs.size() - 1)
		var t_in_note: float = t - note_index * note_dur
		var envelope: float = sin(PI * t_in_note / note_dur)
		var freq: float = clean_freqs[note_index]
		samples[i] = sin(TAU * freq * t) * envelope * vol
	return _samples_to_wav(samples)

# --- Helpers --------------------------------------------------------------

func _sanitize_freqs(freqs: Array) -> Array:
	# Drop non-finite/out-of-range frequencies and clamp the rest into the
	# audible, non-aliasing band. Returns a plain float Array.
	var result: Array = []
	for f in freqs:
		var freq: float = float(f)
		if not is_finite(freq) or freq <= 0.0:
			continue
		result.append(clampf(freq, MIN_FREQ, MAX_FREQ))
	return result

func _samples_to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED

	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var s: float = clampf(samples[i], -1.0, 1.0)
		data.encode_s16(i * 2, int(round(s * 32767.0)))
	wav.data = data
	return wav

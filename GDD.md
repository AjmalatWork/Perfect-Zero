# Perfect Zero — Game Design Document

*Current state as of this build. Engine: Godot 4.7 (GL Compatibility renderer). Made for GMTK Game Jam 2026, theme "Countdown."*

---

## 1. Concept

Perfect Zero is an arcade-reflex game about stopping countdown timers at exactly 0.00. Multiple timers run at once; the player clicks each one at the moment they judge it to be at (or nearest to) zero. Accuracy is graded continuously and converted into points and a score multiplier. Missing badly enough ends the run.

Two modes:
- **Arcade** — a fixed 12-stage campaign with hand-authored timer layouts, escalating in complexity and introducing new timer types one at a time.
- **Endless** — an infinite single 3×3 grid that continuously spawns timers, escalating in speed and density over time, with a lives system and three activatable powerups.

## 2. Visual and audio identity

- **1600×900 fixed canvas**, `canvas_items` stretch mode (UI scales to fit any window/resolution).
- **Neon-on-black** aesthetic: near-black backgrounds (`#0a0a11`-ish), bright saturated accents per system (cyan, gold, red, purple, grey), glowing borders and outlined text.
- **Almost everything is still drawn at runtime, not imported.** Timer panels, buttons, particle-like bursts, checkboxes, sliders, and most icons are procedural — Godot `_draw()` calls and `GradientTexture2D`s, not image files. This avoids raster blur under the canvas's stretch scaling. The jam's AI-art-asset ban that originally drove this is no longer in force (jam submission is done; this is a proper release now), so this is a stylistic/technical preference going forward, not a hard constraint.
- **A small, deliberate set of hand-authored SVG icon files now exists** (`icons/title_*.svg` — title screen's Options/Help/Scores/Credits row; `icons/android_icon_*.svg` and root `icon.svg` — app/launcher icons; `icons/credits_heart.svg` — the Credits screen's thank-you heart). All hand-drawn vector paths, not generated images. Two rendering gotchas learned the hard way: Godot's runtime SVG rasterizer (thorvg) does not render `<text>` elements at all (renders blank) and does not correctly composite `<feGaussianBlur>`/`<feMerge>` glow filters (blurs the whole shape instead of adding a halo) — every icon in this project is built from plain paths/circles with no `<text>` and no filter, each one a translucent accent fill plus a bold accent-colored stroke boundary.
- **Zero external SFX.** All sound effects and the ambient drone bed are synthesized at runtime from sine-wave math into `AudioStreamWAV` buffers, played through a pool of `AudioStreamPlayer`s.
- **One external non-visual asset**: a licensed music track (`audio/menu_theme.mp3`, "Synthwave Retro 80s" by arpmedia, via Pixabay) used as menu music.
- Audio runs on two independent buses, **SFX** and **Music**, both under Master, so the two have separate volume controls. SFX carries a light low-pass/compressor/limiter chain to keep stacked synthesized tones from turning harsh.

## 3. Core loop: grading a stop

Every timer (except Golden and Decay, see below) counts down from a `start_time` toward 0.00. Clicking it stops it and grades the stop by **distance** — how far `current_time` is from zero at the moment of the click:

| Grade | Distance from 0.00 |
|---|---|
| PERFECT | ≤ 0.05 |
| GOOD | ≤ 0.30 |
| OKAY | ≤ 0.50 |
| MISS | ≤ 1.00 |
| FAIL | > 1.00, or the timer runs past zero unclicked |

Thresholds are inclusive on the upper bound (exactly 0.05 grades PERFECT, not GOOD). Distance is rounded to 2 decimal places before grading, matching what the digit display shows, so a value like 0.051 can't grade worse than what the player visually saw ("0.05").

A **FAIL** ends the run immediately in Arcade (the stage is lost) and costs a life in Endless.

## 4. Scoring

Two independent scoring models exist for the two modes, sharing the same base formula.

**Base points per stop:**
```
base_points(distance) = floor(200 × (1 − min(distance, 1))²)
```
Continuous and quadratic — a dead-on 0.00 is worth 200, falling off smoothly to 0 at distance 1.0. No cliff between grade tiers.

**Multiplier**, evolves per stop:
- PERFECT: +1.0
- GOOD: +0.5
- OKAY: unchanged
- MISS: halved (floored at 1.0)
- FAIL: reset to 1.0 (Arcade ends the run here anyway; Endless resets the segment)

**Arcade (Campaign) scoring — fully deferred:** nothing is shown to the player during play. Every stop is recorded silently (`grade`, `distance`, a per-stop `bonus_factor` — see below). At the end of the stage, the whole sequence replays in a scripted reveal (see §8) that visibly builds the tally and multiplier stop-by-stop, then multiplies them together for the final stage score. The multiplier is applied once, at the very end, not compounded per stop.

**Endless scoring — fully live:** each stop immediately adds to a running `stage_tally` and updates a live `multiplier`, both shown on the HUD as they happen. A FAIL banks `tally × multiplier` into the run's total, costs a life, and resets the segment to 0/1.0×. The run total is the sum of every banked segment. Endless multiplier is uncapped in both sub-modes currently (`multiplier_cap = -1`, i.e. no cap set at runtime — see EndlessRunner).

**Bonus factor** (multiplies base points, computed from the timer's type and stacked Red boosts):
- Golden: ×2.0 if the grade is PERFECT (it always is — see below)
- Blackout: ×2.5 on any scoring grade (PERFECT/GOOD/OKAY)
- Every Red-reaction boost a timer has received before it stops: ×(1 + 0.25 per stack), on any scoring grade
- All other types/grades: ×1.0

## 5. Timer types

Six types exist. All spawn at a fixed size, colored panel with a live digit readout.

| Type | Color | Behavior |
|---|---|---|
| **Normal** | pale lavender | Counts down plainly. No special rule. |
| **Red** | red | On stop, every *other* still-running timer on the board gets permanently sped up (+0.25× speed, additive, stacks with repeats) and its bonus-factor stack count +1 (worth +25% more points per stack when it eventually stops). |
| **Blue** | cyan | On stop, every other still-running timer is frozen (paused, no countdown) for 1 second. Multiple Blue stops stack the freeze duration additively. Frozen timers show a translucent blue overlay. |
| **Golden** | gold | Never counts down. Displays a fast-cycling random-digit blur instead of a real countdown, so the player can't "aim for 0.00" — any click is a guaranteed PERFECT worth 2× base points. Because it never expires on its own, a Golden left unclicked will stall a stage indefinitely in Arcade (by design — no forced auto-resolve). |
| **Blackout** | slate grey | Counts down normally but its digits go blank ("??.??") once inside its `blackout_duration` (default 1.5s) of zero — the player has to time it by ear/feel rather than by reading the number. Worth 2.5× base points on any scoring grade. Gets its own low "heartbeat" tick sound instead of the standard rising-pitch tick, for its whole life. |
| **Decay** | purple | The one type that counts *up* from 0.00, not down. Graded against its own four sequential windows (Perfect/Good/Okay/Miss durations, defaults 0.6/1.2/1.8/2.4s) rather than the global distance thresholds — whichever window the elapsed time currently falls in is the grade. Running out of all four windows resolves it as a MISS (never a FAIL — Decay can't cost a life/end a run by expiring). Border color steps through a purple gradient as it drains from bright to dim, most vivid at spawn to win attention immediately. Score uses the same base-points curve, driven by elapsed-time-normalized-to-total-lifetime as its "distance." |

Every stopped or expired timer holds fully visible for 0.4s, then fades out over another 0.4s before its slot is actually freed, so the outcome (color flash, grade sign, particle burst) has time to read.

## 6. Arcade (Campaign) mode

- **12 fixed stages**, each a hand-authored list of timers (type + start_time) laid out in centered rows (up to 3 per row).
- Stages 3 and 6 are **bonus stages**: all-Golden (5 and 9 timers respectively), so they cannot be failed — only completed.
- Progression is gated: `Level Select` shows every stage, but only up to the player's furthest-reached stage (+1) is clickable; the rest are visibly locked and greyed out.
- First time playing, pressing **ARCADE** goes to Level Select (not straight into Stage 1), so a new player sees the full 12-stage roster with only Stage 1 unlocked — communicating the game's scope up front.
- A stage ends the instant every timer on the board is stopped (clear) or the instant one is FAILed (loss). A stage clear/fail waits a short pause (0.7s) after the last stop before cutting to the result screen, so the final stop's flash/tick has time to land.
- **Per-stage best score** is tracked and persisted (`highscore_stage_N`). Retrying a stage keeps the campaign's running total anchored to the *best* of any attempt, not the latest.
- **First-seen-type tutorial popups**: the first time a stage introduces a timer type the player's save has never seen, a one-time modal explains it before the stage's timers spawn. Data-driven off stage contents, so reordering stages needs no extra wiring.
- **One-time first-ever intro demo**: before a brand-new player's very first stage, a ghost cursor glides onto a live practice timer (visually identical to a real one) as it counts down, then the countdown eases to a dead stop just short of 0.00 and waits — unclickable until then, so no premature click can grade as anything but the PERFECT it settles into. The player has to click it themselves to proceed. This replaces relying on read text to teach "stop it as close to 0.00 as you can": it's shown once ever, then never again.
- **No powerups in Arcade.** Powerups are Endless-exclusive.

### The stage-clear reveal sequence

Because Arcade scoring is deferred, the payoff is a full scripted "reveal" on the result screen, structured as:

1. **Holding-breath beat**: screen dims slightly (~0.38 alpha), audio ambient bed is already silent (stops automatically leaving PLAYING), holds for a short beat (~0.1s fade-in + hold) before anything moves — a deliberate silence right before the payoff. Alongside this beat, a single **quality signal** for the whole stage (the same aggregate the finale's tier is computed from — see step 3) sets a quiet background glow/tint for the rest of the reveal, so a strong clear reads differently from the very first frame rather than only once the finale lands. Deliberately subordinate to the finale's own colour wash — a soft persistent tint, not a flash — and scaled down (not removed) by "Reduce screen effects."
2. **Stop-by-stop tally**: each recorded stop counts up onto the tally display in sequence, each landing with: a grade sign popup (squash-and-stretch entrance) at a fixed on-screen anchor, a radial particle burst sized/colored by grade (reusing the game's normal click-burst effect), a one-shot audio stinger that climbs in pitch on same-grade streaks, a secondary particle "ring" thrown outward from the grade sign (skipped below OKAY grade to avoid visual mush on long stages), and — during the stretch of the reveal — a running "intensity" value that escalates with consecutive PERFECTs, brightening/growing every subsequent effect (burst size, ring size, stinger loudness) so a clean stage visibly and audibly builds momentum. **Skippable**, for replaying a stage to chase a better score: a tap jumps straight to the finale with the tally instantly settled at its true final values (no partial/interpolated numbers ever shown); holding compresses the pacing instead of jumping, so the per-stop effects still play, just faster. Works with mouse click or the keyboard confirm key.
3. **The finale**: after a beat, the multiplier "slams" into the tally to produce the final stage score — with the single biggest hit-stop and camera-punch in the entire game (deliberately bigger than anything in live play, since this is Arcade's only payoff moment), a dedicated six-voice "final slam" stinger reserved exclusively for this moment, and a full-screen colour wash whose color and particle-burst scale depend on a computed stage-quality tier (derived from the average grade quality across all recorded stops — not from the optional/often-unset `target_score` field). **Never skippable** — regardless of how the tally beat was skipped or fast-forwarded, the finale always plays in full; it's the one moment this deferred-scoring mode is never allowed to truncate.
4. The settled final score gets a slow, shallow idle pulse so the result screen doesn't go completely static while the player reads it. If this attempt beat the stage's stored best score, a **separate "NEW BEST!" flourish** fires alongside — its own sound (not the finale stinger) and a glowing badge positioned directly above the score (rather than floating beside it), which also permanently brightens the score's own outline for the rest of the screen — deliberately kept out of the finale's hit-stop/punch/wash package so it reads as its own secondary "oh, and also" beat rather than being folded into the slam. Below the score, one supporting line reports whichever fact is actually new information — the previous record on a fresh best, or the standing record otherwise — rather than repeating the score that's already the biggest thing on screen.
5. Buttons: **RETRY** and **NEXT STAGE** (or a campaign-complete message + **BACK TO TITLE** on the last stage). Both RETRY and RETRY-from-Endless-end-screen and PauseMenu's RESTART share a common fade-to-black-and-back screen transition before restarting, so retrying always reads as one consistent beat regardless of entry point. **Leaving** the result screen via NEXT STAGE or BACK TO TITLE (including the campaign-complete screen) instead plays a **tier-matched outro wipe** — brighter and faster for a strong clear, plainer and slower for a scrape-by one — reusing the same stage-quality tier from step 3 rather than a second metric. RETRY's transition is untouched by this and stays identical regardless of how the stage went.

A FAIL skips the tally/finale entirely and shows a plain FAILED summary with only a RETRY option (no skip, and no outro wipe on its RETRY).

## 7. Endless mode

- **Progression-gated in two independent stages.** The title screen's ENDLESS button is locked until Stage 3 is cleared (tapping it while locked shows a short fading toast, no modal); clearing Stage 3 fires a one-time celebratory unlock notice — a closable popup (its own "NICE!" dismiss button), not an auto-fading banner, shown after that stage's own clear reveal rather than overlapping it. Once past that gate, the Mode Select screen is reachable and **Normal is immediately playable** — **Hardcore** stays independently locked *within that screen* until the full 12-stage campaign is cleared (its own toast on tap, and its own closable unlock popup on the campaign-complete screen). Hardcore's gate is deliberately later and separate from Endless's own gate, not the same flag.
- Chosen from a **mode-select screen** offering **Normal** (3 lives) or **Hardcore** (1 life).
- **3×3 grid** (9 cells). Timers spawn continuously into empty cells; the type, start value, and pacing all escalate with elapsed run time.
- **Spawn scheduler**: a new timer spawns when either (a) an already-running timer crosses below a low-time threshold (2.0s) for the first time, or (b) a fallback interval (2.0s, tuned in the scene) passes with no spawn at all — whichever comes first. This keeps the board from ever going empty or over-stuffed.
- **Simultaneous-timer soft cap** ramps from 2 timers at run start up to the full 9-cell grid by 90 seconds elapsed.
- **Start-value range** (how much time a fresh Normal-family timer counts down from) shrinks from a 5–7s window at the start down to a 1–3s floor by 60 seconds elapsed — timers get less generous as the run goes on. Blackout is deliberately exempt from this shrink, holding a fixed 7–8s range throughout, since its whole point is training the player to react to it by ear rather than a shrinking visible number.
- **Collision avoidance**: a new timer's spawn value is resampled (up to 20 tries) to keep its natural zero-moment at least 1.5s clear of any other currently-running timer's zero-moment, so two timers are never forced to hit zero in the same instant.
- **Type unlock schedule** (colored types become eligible to spawn over time, then compete by weight against whatever else is already unlocked):
  - Normal: available from the start, weight 72
  - Red: unlocks at 10s, weight 10
  - Blue: unlocks at 15s, weight 10
  - Golden: unlocks at 20s, weight 5
  - Blackout: unlocks at 30s, weight 3
  - Decay: unlocks at 40s, weight 6
- **Pity timer**: if 10 seconds pass with no colored (non-Normal) type spawning, the next spawn is forced to be a colored type.
- **Per-type concurrent caps** on the board at once: Red ≤2, Blue ≤1, Golden effectively uncapped (≤9), Blackout ≤1, Decay ≤2.
- **Lives**: a FAIL costs one life (banking the current segment's tally × multiplier into the run total first) and shows an X in the lives row; hitting 0 lives ends the run. Hardcore's single life shows no lives row at all (nothing to ever see filled). Losing a life gets its own distinct beat, sequenced *after* the FAIL's own shake/flash so the two read as "I failed" and then, separately, "and that cost me a life": the specific life icon just spent flashes bright and punches outward before settling into its spent-red state, paired with a life-loss sound reserved for this event alone (not reused from any FAIL audio).
- **Low-life ambient warning**: once remaining lives drop to or below a threshold (default: last life), a slow-pulsing deep-red vignette creeps in at the screen edges for as long as that state holds — the danger counterpart to the streak-heat glow below, built the same way but distinguished by both colour and behaviour (heat is a steady warm bloom; this never sits still). Deliberately calm rather than alarming: a slow breathing pulse, not a flash. Clears immediately on the run ending. **Suppressed entirely in Hardcore** — a one-life mode is always at the threshold, so an always-on danger signal would just be wallpaper rather than information.
- **Combo meter**: a HUD bar visualizing the live segment's value on a square-root curve (so its super-linear growth stays legible), color-shifting cyan → gold → red as it climbs, that visibly drains to nothing whenever a FAIL banks the segment.
- **Streak popups**: "Nx PERFECT!" appears at 2+ consecutive PERFECTs.
- **Ambient ducking**: a synthesized drone bed's intensity tracks elapsed-time escalation directly (not a separate timeline), so the audio thickens in step with actual difficulty.
- **First-seen-type callouts**: the same first-seen-type flag Arcade's tutorial popups use also drives a lightweight, non-blocking callout the first time a type spawns in Endless with no flag set yet (regardless of whether it was first seen here or in Arcade) — a small label anchored to that timer for a few seconds, then it dismisses itself. Deliberately non-freezing: unlike Arcade's modal (which gates a stage that hasn't started) or the in-game Help bubble (an explicit request to pause and read), this fires on a board that's already live, so the clock keeps running through it.
- **End of run**: losing the final life plays its life-loss beat exactly like any other, then a distinct **stillness beat** (screen dims, ambient drops, board holds frozen) marks the transition into the summary rather than cutting straight from live play to a UI screen. The **summary reveal** counts up final score, best streak reached, and survival time in sequence — each landing with a punch, reusing the same digit-countup/pop technique as the Arcade reveal — with the whole reveal's intensity (punch size, burst presence, sound) scaled to how the run compares against the stored record it was chasing. The two supporting stats (best streak, survived) and the one record-comparison line beneath the score are presented as an aligned label/value table rather than freeform sentences, so all three lines' values line up on a shared column. Score, best streak, and survival time are each tracked as separate persisted bests per sub-mode; beating any of them fires one **combined** "NEW BEST" flourish naming whichever stat(s) improved (never one flourish per stat) — on a record, the flourish is layered with a full-screen colour wash, a brief freeze-frame, a second staggered particle burst on the score itself, and a slow idle shimmer on the score for as long as the summary stays on screen. RETRY available, sharing the same fade-to-black transition as PauseMenu's RESTART.

### Endless powerups

Three activatable abilities, Endless-exclusive, arranged in a column of buttons to the left of the grid. All three:
- Start every run already on a shared, flat 5-second cooldown (so they read as a mid-run relief valve, not an opening move).
- Have **no mutual exclusion** — any combination can be active at once.
- Are bound to keyboard shortcuts **A / S / D** in addition to clicking — the on-screen `[key]` hints are shown only on desktop/web; touch-only (mobile) builds omit them entirely rather than displaying a hint for a keyboard that doesn't exist.
- Have a distinct activation sound, a brief anticipatory "wind-up" visual at the button before the effect fires (the underlying mechanic itself is not delayed by this), and a small pulse/flash the instant they come off cooldown.

| Powerup | Cooldown | Effect |
|---|---|---|
| **Shield** | 20s | Arms a 10-second window. The very next FAIL anywhere on the board inside that window (from a mistimed click *or* an unclicked expiry) is silently downgraded to a MISS instead — no life lost. The window closes the instant it catches one, or when it times out unused. Visually: a calm cool-toned board-edge glow while armed; catching a FAIL triggers a distinct interrupt sequence (the FAIL's harsh feedback visibly begins, then is cut off and absorbed at the board edge) plus a unique "block" sound, clearly different depending on whether it actually caught something versus just expiring quietly. |
| **Nuke** ("Clear All" internally) | 30s | Instantly resolves every currently-live timer on the board as a PERFECT, staggered into a fast visual cascade (~0.34s total, ordered outward from the button) rather than all at once — each resolution gets its own particle burst and a note of a rising musical run, landing on a resolving chord at the end alongside a full-screen gold flash. Camera punch scales with how many timers were actually cleared. |
| **Overclock** | 25s | For 10 seconds, every timer on the board runs 1.5× faster **and** scores 2× as many points (the multiplier folds into the same bonus-factor pipeline as Red stacks/type bonuses). Visually: a persistent warm red screen-edge treatment for the whole window (distinct in both color and shape from the ambient "streak heat" glow, so the two never get confused even when both are active), plus a depletion bar on its own button showing the window closing (visually distinct from the normal cooldown ring). A clear (non-alarming) audio/visual cue marks the window ending. |

If both Overclock and Shield are active simultaneously, their two screen-edge treatments blend into a distinct combined visual state rather than just layering independently.

A **one-time tutorial popup** explaining all three powerups appears the first time the player actually commits to a run — right after pressing NORMAL or HARDCORE on the Mode Select screen, not merely on opening that screen — so a player who backs out without choosing either never sees it, and the run itself starts only once the popup is dismissed.

## 8. Screens and navigation

All screens are procedurally-built `Control` trees inside one single scene (`Main.tscn`); a router shows/hides them by game state with a short cross-fade.

- **Title screen**: game logo (animated with a gentle per-letter sine-wave bob, synced loosely to the ambient menu music playing underneath), restructured into two tiers rather than one flat list: a **primary row** (ARCADE, ENDLESS — the actual gameplay decision, ENDLESS shown locked/greyed per §7 until unlocked), a **secondary row** of four square icon buttons (Options, Help, Scores, Credits), and a de-emphasized **Quit** text link (desktop-only — hidden on mobile, where the OS back-gesture/app-switcher already covers it; on Android specifically, back at the title screen instead prompts a confirm-to-exit dialog rather than quitting silently). A low-emphasis build-number label sits in the bottom-right corner, editable per-build via an Inspector-exported field rather than hardcoded. The four secondary-row icons are hand-authored SVGs (gear/question-mark/trophy/info, all gold-accented) rather than drawn primitives or text glyphs — see §2's icon note.
- **Level Select**: grid of 12 stage buttons, locked/unlocked as described in §6.
- **Endless Mode Select**: Normal / Hardcore choice (Hardcore locked per §7), plus the powerup tutorial on first visit. Each mode button shows its name left-aligned and its life count right-aligned within the button, rather than a single centered "NORMAL - 3 lives" string.
- **Help** (3 pages, paginated): (1) How To Play + a legend of all 6 timer types with their descriptions, (2) the 3 Endless powerups with descriptions and cooldowns, (3) the scoring/grading rules.
- **In-game Help bubble**: a "?" icon, top-right during live play in both modes (clear of the pause button), opening a compact reference panel without leaving the stage — one page (timer types) in Arcade, two (timer types, then powerups) in Endless, paginated with the same nav component the Help screen uses, its heading swapping between "TIMER TYPES" and "POWERUPS" to match whichever page is showing. Opening freezes every gameplay clock (timers, Endless's spawn scheduler and unlock schedule, powerup cooldowns) the same way Nuke's cascade does, closing via the same wipe transition the Pause Menu's RESUME uses. Shows a subtle pulsing badge whenever a spawn-eligible timer type hasn't been seen yet (meaningful mainly in Endless, since Arcade's tutorial popups already flag every type before this icon is ever visible) — opening the bubble itself marks every currently-eligible type as seen, since its own page 1 is exactly the information the badge was flagging, rather than waiting on that type to separately spawn and trigger Endless's live callout.
- **Scores**: a single-column table of all 12 stages' best score vs. their (optional, hand-authored) target, plus Endless Normal/Hardcore bests.
- **Options**: SFX volume slider, Music volume slider, a "Reduce screen effects" toggle, and a Reset Save Data button (with a confirmation step).
- **Credits**: one flowing composition rather than a flat labeled list, built around a single emotional focal point instead of several equally-weighted facts. A hero credit block ("Designed & Developed by MAKSTER", a small heart icon, and one merged thank-you/jam-origin statement) is followed by a divider, then a quiet "colophon" row of two peers (the licensed music track's attribution, the engine credit) each with one highlighted line and plain supporting detail, then a second divider, then a feedback block ending in a real **EMAIL US** button (opening a pre-filled mail draft) rather than an in-page hyperlink. Reachable from the title screen's secondary row.
- **Pause menu** (in-game, both modes): three tiers rather than four equally-weighted buttons. **RESUME** is the largest and only glowing button — the entire reason to open this menu. **RESTART** (fades to black, restarts) shares RESUME's colour family at a lighter weight, since it's a real but secondary choice. **OPTIONS** (as an overlay) and **BACK TO TITLE** — neither of which touches the run itself — are demoted into one small paired row beneath both. RESUME dissolves the whole pause overlay via a shared ~0.5s wipe rather than a numeric countdown — the same transition the in-game Help bubble's close uses, so both read as one consistent "overlay lifts, board becomes interactive again" beat; the pause icon itself fades back in across that same beat rather than reappearing only once the wipe finishes.

Every heading title across Options/Endless-select/Help/Scores uses the same animated per-letter wave text as the title screen, for visual consistency. Every plain **BACK** button (Scores, Help, Credits, Level Select, Endless Mode Select, Options) is likewise unified: same size (200×64) and the same cyan as the title screen's ARCADE button, centered as the last item of that screen's own content column rather than pinned to a corner. ("BACK TO TITLE" buttons that sit in a row alongside RETRY/RESTART/NEXT STAGE — Pause Menu, Stage Result, Endless End — are a separate case and keep their row's own sizing.)

## 9. Accessibility / settings

- **SFX volume** and **Music volume** are independent, each persisted, each driving its own audio bus.
- **Reduce screen effects** toggle: hard-disables (not merely softens) screen shake, camera punch/pull, hit-stop, and every full-screen flash or color wash — these are treated as motion-sickness triggers that can't be "softened" into comfort. Explicitly does *not* touch: localized particle bursts, click-point effects, label pops, or persistent state-indicator glows (Overclock/Shield edge treatments, the streak-heat glow, and the Endless low-life vignette all stay at reduced-but-nonzero visibility, since the player still needs to know those states are active). The Arcade reveal's pre-tally anticipation tint sits between the two conventions and is scaled down (not removed) — a persistent background tint like the state-indicator glows above, but full-screen like the washes/flashes the toggle otherwise kills outright.
- Save data (all high scores, unlock progress, settings, first-seen-type/tutorial flags, Endless best score/streak/survival-time per sub-mode) lives in a single generic key/value store, degrading gracefully (warning + "not saved," not a crash) if the save file can't be opened.

## 10. Android platform support

The game targets landscape on all platforms including Android (no portrait-specific layout exists or is currently planned as committed work — a portrait rework was scoped as a separate, larger effort and is not yet decided on).

- **App lifecycle**: losing focus (backgrounding, an incoming call, split-screen, alt-tab on desktop) auto-triggers the same pause-freeze the Pause Menu button uses. It deliberately does not auto-resume on refocus — the player has to explicitly press RESUME, so a run can't silently keep ticking while the screen was elsewhere.
- **System back button**: mapped per-context rather than left to Android's default (which would otherwise quit the app instantly from any screen). In-game, back opens the Pause Menu; in any menu, it triggers that screen's own existing BACK handler; at the title screen, it prompts a confirm-to-exit dialog. Implemented as a single bridge (Android's back gesture is republished as the same `ui_cancel` action every screen's Escape-key handler already listens for), not a second parallel input system.
- **Viewport centering (pillarboxing)**: the game's UI is built entirely with fixed 1600×900 pixel positions, not anchors. On a real device whose aspect ratio is wider than 16:9, this used to leave content pinned to the left edge with dead space on the right. Fixed once, at the shared scene root (`Main`, a `Node2D` every screen is a child of), by centering that root's position within the actual expanded viewport — not a per-screen fix, and not a change to any individual layout.
- **Safe-area handling**: corner-pinned UI (the in-game Help icon, the Pause button, the title screen's version label and Quit link, Endless's bottom fail-crosses row) insets itself away from notches/gesture-nav-bars/rounded corners, queried via the display's actual safe-area rect and converted into the game's canvas coordinate space.
- **Crash/error logging and save safety**: a lightweight local error log now exists for conditions the game degrades from gracefully (corrupt save, failed write) but that previously vanished silently with no way to see them on a device with no attached console. Save reads are now cached in memory rather than re-opening the file on every check (a real stutter/ANR risk that existed on the hot path of a per-frame UI check), and settings writes (e.g. a dragged volume slider) are debounced rather than writing to disk on every intermediate value.
- **Touch target sizing**: gameplay-critical elements (Endless's timer grid, Level Select's stage buttons) comfortably clear Android's ~48dp minimum recommended touch target on a small phone screen. Most of the game's menu chrome (title screen buttons, BACK buttons, pause menu buttons) does not — it was built to a desktop-first scale and sits closer to ~26dp tall on a 360dp-wide phone. Flagged, not yet resized, since a sizing pass has real knock-on effects on screen composition.
- **Export/build status**: an Android export preset exists (package `com.makster.perfectzero`, `armeabi-v7a` + `arm64-v8a`), debug deploys work end-to-end via Godot's Remote Deploy (build + install + launch + live debugger, tested on a real device over USB). Launcher icons (a flat legacy icon plus adaptive foreground/background/monochrome layers) are hand-authored SVGs following the same no-`<text>`/no-glow-filter rules as the title screen's icons. **Not yet done**: Min/Target SDK haven't been deliberately checked against Google Play's current policy (still on Godot's defaults), no release keystore exists yet, and no signed release AAB has been built — all of this is release-side work, separate from the debug/testing loop, which is fully working.

## 11. Known accepted design limits

- Stages 3 and 6 (all-Golden) cannot be failed by design.
- An unclicked Golden timer in Arcade can stall a stage indefinitely — no forced auto-resolve exists; this is an accepted risk rather than a bug.
- Endless's Nuke can be activated mid-cascade-of-another-Nuke or during other transient animations; the game freezes all gameplay clocks (timer countdowns, powerup cooldowns/windows) for the duration of any such scripted animation, so none of this can desync scoring — nothing "runs" behind a frozen screen.

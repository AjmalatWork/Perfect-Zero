# Visual / Theme Consistency Audit — Perfect Zero

**Date:** 2026-08-04 · **Scope:** read-only, no changes made
**Method:** static audit of every `scripts/ui/*`, `scripts/gameplay/*`, `scripts/autoload/*` source and every SVG in `icons/` + `icon.svg`, checked against GDD §2, §6–§10.
**Limits:** this is a source audit, not an on-device screenshot pass. Findings are things provable from the code (a wrong constant, an ungated ternary, a string that contradicts its own implementation). Anything whose only failure mode is "looks slightly off at runtime" is called out as needing a device check rather than asserted.

---

## 0. Status — fix pass APPLIED 2026-08-04

The audit below was written first and is preserved as-written. Every finding in it has since been actioned. Verified by a full headless project import (`godot --headless --import`), which compiles every script in autoload context — exit 0, no errors, no warnings.

| # | Finding | Resolution |
|---|---|---|
| 6.1, 6.2 | Toggle subtitle stated the opposite of what the setting does | **Fixed** — now "Reduce screen effects" / "No screen shake, flashes or camera punch" |
| 11.1, 11.2 | Endless End mid-tier green | **Fixed** — `TIER_COLORS` mid step → `22d3ff`, matching Stage Result; unused `GREEN` const removed |
| 15.1 | `Toast` had no portrait handling at all | **Fixed** — bottom margin measured up from `Layout.canvas_size.y`, `SafeArea.bottom` inset, 24/36 font pair |
| 4.1 | Help's BACK 200×96 in landscape | **Fixed** — height ternary gated to portrait like the other five screens |
| 4.3 | "TIMERS" vs "TIMER TYPES" | **Fixed** — tab renamed; `TAB_SIZE` comment updated with the new width arithmetic |
| Q3 | Overclock and low-life the same red | **Fixed** — `LOW_LIFE_COLOR` → `8c0f3c` (burgundy), `LOW_LIFE_ALPHA` → `0.32` to hold presence |
| 3.1 | "Choose your mode" skipped the portrait type scale | **Fixed** — `26` → `_fs(26)` |
| 10.1 | Three HUD readouts missed the portrait bump | **Fixed** — landscape/portrait pairs added for streak popup, streak counter, milestone (÷ the same ~1.39 ratio), counter box grown to match |
| 10.2 | Streak counter corner-pinned with no safe-area inset | **Fixed** — `_streak_counter_pos()` insets by `SafeArea.right`; the incorrect comment corrected |
| 3.3, 10.3, 11.4 | Scores was the only screen separating thousands | **Fixed** — `_thousands()` lifted to `ScoreManager.thousands()`; applied across Endless HUD (tally + TOTAL + milestone), Endless End, Stage Result (final + record lines + `DigitCounter`), Mode Select, Arcade HUD |
| 14.1 | Overclock button red ≠ Overclock edge red | **Fixed** — `PowerupSystem.COLORS[OVERCLOCK]` → `ff1040`, matching `Juice.OVERCLOCK_COLOR`; both sides cross-commented |
| 8.1, 8.2 | Four "uniform" pause buttons, four font sizes | **Fixed** — all four → `PORTRAIT_BUTTON_FONT` 46, matching the other four screens sharing the 380×140 box |
| 3.1 (x-cut), 1.1 | Three dead rule-violating SVGs; comment citing them as house style | **Fixed** — files deleted (`git rm`, recoverable from history); `TitleScreen.gd` comment rewritten to state the actual rule |
| 2.2 | Level Select `outline_size` 5 | **Fixed** — → 4, matching every other screen |
| 4.2 | Help dots not colour-coded | **Closed, not a bug** — design call Q1; GDD §8 reworded instead |
| 2.4 | Bonus-stage gold vs badge contrast | **Closed, accepted** — design call Q2; no change |
| 11.3 | Reveal screens' tier cuts differ | **Closed, deliberate** — Q4; a comment now records *why* so it isn't re-flagged |
| 6.3 | Options' toggle subtitle same size as the section eyebrows | **Fixed** — `SUBTITLE_SIZE` 36 → 30 |
| 6.4 | `NeonToggle`/`NeonSlider` redeclare `Color("22d3ff")` instead of referencing `NEON` | **Fixed** — both now `OptionsPanel.NEON` |
| 4.4 | Help's inactive tabs outline in black, the only black outline in the game | **Fixed** — → `MUTED @ 0.6` |
| 3.5 | Endless Mode Select's caption uses `TEXT_FILL @ 0.75` instead of `MUTED` | **Fixed** — `MUTED` const added, caption uses it |
| 3.4 | Endless Mode Select's BACK font (`_fs(30)`) was the largest of six screens | **Fixed** — overridden to `_fs(28)`, matching Help/Options |
| 1.2 | Title's version label had no portrait size at all (fixed `16` ≈ 6.4dp) | **Fixed** — `_PORTRAIT` pair added, 16/24 |
| 4.5 | Help's dots (10/26/28) vs Scores' (8/22/20) — same component, two sizes | **Fixed** — dot geometry moved to absolute canvas units and Scores now references `HelpScreen`'s definitions. See note below |
| 15.2 | Router/clear-colour background a shade lighter than every screen's own backdrop | **Fixed** — router *and* `default_clear_color` → `Color(0.03, 0.03, 0.05)`. See note below |
| 1.3, 3.6 | Quit-prompt case; mixed case convention | **Not actioned** — 1.3 closed as already consistent with Options' own confirm dialog; 3.6 deprioritized as high-effort/subjective, left documented in §3.6 |

**Note on 4.5 — this was not the finding it looked like.** The raw constants were close (10 vs 8, a 25% gap that could plausibly have been chosen). The *effective* sizes were not: Help scales by 1.5 and Scores by 1.2, which pulled them to 15 vs 9.6 — a 56% difference that was an artifact of two unrelated `PORTRAIT_SCALE` values, not a design decision. Fixed by holding the dot geometry in absolute canvas units (the call `OptionsPanel._content_width()` already makes for the same class of reason) at 14/36/40 + 12 separation, and having `ScoresScreen` reference `HelpScreen`'s constants rather than declare its own — the same cross-screen reuse pattern as `LevelSelect.AllPerfectMark`. Net effect: Help's portrait dots barely move (15 → 14), Scores' grow meaningfully (9.6 → 14), both orientations now match by construction.

**Note on 15.2 — the cross-fade was a red herring; gameplay was the real exposure.** Computed the cross-fade artifact at roughly 1/255 at the midpoint, i.e. imperceptible. But `PLAYING` and `ENDLESS_PLAYING` paint no full-bleed backdrop of their own (`gameplay_nodes` is just `TimerContainer` + `Hud`), so the router's rect *is* the live background for the whole screen during a stage — meaning the background stepped slightly lighter on every menu→board transition and back. Fixed by moving both the router rect and `project.godot`'s `default_clear_color` to the same `Color(0.03, 0.03, 0.05)` the screens use, which preserves the router's documented "matches the clear colour exactly" invariant while removing the step. Both old and new values sit inside GDD §2's "near-black (`#0a0a11`-ish)".

**GDD edits made:** §8 page-dot wording (per Q1), §8 BACK sizing (records the deliberate 220 class), §10 the "effective dp unified" claim (was never true — corrected to "every screen clears the floor").

**Wants a device check:** the two changes that alter live gameplay — `LOW_LIFE_COLOR`/`ALPHA` (the value is a reasoned starting point, not a measured one; judge it with Overclock active on the last life) and the Overclock button red. Also worth a glance: Help's tab row at the new longer label, and the thousands separators mid-countup.

---

## 1. Executive summary

Overall consistency is **high**. The palette is genuinely shared (`22d3ff` / `ffd23f` / `ff2e5e` / `8b90a8` / `dfe3ee` appear as the same five roles across all twelve screens), `TimerSlot.TYPE_COLORS` and `TimerTypeInfo.COLORS` are byte-identical so the board and the Help legend cannot disagree, every heading uses `WaveHeading`, the All-PERFECT mark is one class instanced by both Level Select and Scores, and the 380×140 portrait row-button treatment really is shared by all four screens that need it (Pause / Stage Result / Endless End / both tutorials).

The drift that exists is concentrated in three places: **components that were added before the portrait pass and never revisited**, **one screen that didn't receive a fix its sibling did**, and **one UI string that is simply wrong**.

Most conspicuous issues, in order:

1. **Options' "Reduce effects" subtitle states the opposite of what the setting does.** It reads "Fewer particles, no screen shake", but particle bursts are explicitly and deliberately *untouched* by the toggle — per GDD §9, per `Settings.motion_effects_enabled()`'s own doc comment, and per the comment three lines above the string itself. *(Jarring — wrong information on an accessibility control.)*
2. **Endless End still uses green for its mid-quality tier.** Stage Result was deliberately moved off green to cyan, with the reason written into the code ("read as a third colour language on a screen that only has two"). The identical fix was never applied to the sibling reveal screen, which claims parity with it in its own header comment. *(Jarring.)*
3. **`Toast` never received the portrait pass at all.** It is the shared component behind every locked-gate message ("Complete 3 Arcade stages to unlock"), and it hardcodes a landscape y-position and a 24pt font with no reference to `Layout` anywhere in the file. On Android it lands mid-screen rather than bottom-centre, at ~9.6sp — the smallest type in the game. *(Jarring on mobile.)*
4. **The "unified BACK button" has drifted on both axes.** Help's BACK is 200×**96** in landscape because its height bump was never gated to portrait like the other five screens' were; portrait effective sizes split into two classes (~49dp vs 57.6dp) despite GDD §10 claiming effective dp is unified; and the font size on the same button ranges 33.6→51 effective across six screens. *(Noticeable.)*
5. **Three dead `icons/powerup_*.svg` files violate the thorvg no-filter rule** — and `TitleScreen.gd` cites them, by name, as the house style the title icons follow. *(Minor on its own; the comment is the actual hazard.)*

---

## 2. Findings by screen

### 1. Title screen

| # | Finding | Severity |
|---|---|---|
| 1.1 | **`TitleScreen.gd:464-468` documents the wrong house style.** The comment above `_icon_button_texture()` reads: hand-authored SVGs "same house style as the existing powerup icons (`icons/powerup_*.svg`): translucent accent fill + bold accent stroke **with a glow filter**." GDD §2 states the exact opposite — no `<feGaussianBlur>`/`<feMerge>`, glow comes from the accent stroke alone. The four `title_*.svg` files it describes are correctly filter-free; the comment is describing the three broken files instead. Should read "…bold accent stroke, no glow filter". | Minor (but see 3.1) |
| 1.2 | **Version label is unscaled in portrait.** `_build_version_label()` hardcodes `font_size 16` with no portrait branch, on a screen where every other element has an explicit `*_PORTRAIT` constant (title 160, buttons 128/56, icons 132). At ~6.4sp it is comfortably the smallest text on the screen. It is deliberately low-emphasis, so this is a judgement call rather than a clear bug — but 16 is a landscape number that was never revisited. | Minor |
| 1.3 | **Quit prompt heading is sentence case** — "Quit PERFECT ZERO?" — where every other string on this screen is uppercase. Consistent with Options' own "Are you sure?", so the two confirm dialogs at least agree with each other. | Minor |

**Correct:** two-tier structure, ENDLESS locked treatment (dimmed modulate + `LOCKED_ACCENT`, matching Level Select's locked stages exactly), four gold SVG icon buttons, Quit link desktop-gated via `OS.has_feature("mobile")`, build number bottom-right and Inspector-exported, safe-area insets applied to both corner-pinned elements.

---

### 2. Level Select

| # | Finding | Severity |
|---|---|---|
| 2.1 | **BACK is 220×64, not the 200×64 GDD §8 specifies.** The code comment openly declares this an intentional deviation ("Base matches CreditsScreen's BACK specifically … rather than the 200x64/font-28 convention most other screens' BACK buttons share — an explicit call"). So this is a documented divergence, but it means the GDD's "same size" claim is false for two of six screens. Either the GDD or these two screens should move. | Minor |
| 2.2 | **`outline_size` is 5 on this screen's buttons; every other screen uses 4.** `LevelSelect._style_button()` sets 5, vs 4 in Title / Credits / Scores / Help / Options / Endless Mode Select. | Minor |
| 2.3 | **The heading, BACK button and grid separations are built once in `_ready()` and never rebuilt on `Layout.changed`** — unlike Credits / Options / Scores / Help / Endless Mode Select, which all `_rebuild()` on an orientation flip. `_populate()` re-scales the stage buttons on every visit, so only the chrome goes stale. Unreachable in a shipping build (Android is portrait-locked, desktop landscape-only), but it makes the dev `--portrait` flag misrepresent this one screen. | Minor |
| 2.4 | **Bonus stages 3 and 6 carry `BONUS_ACCENT` gold, and the All-PERFECT mark is bronze-gold `c8862e`.** On those two buttons a bronze-gold ring sits on a gold-accented, gold-outlined face, which is the weakest possible contrast for the badge. Compounded by the fact that all-Golden stages auto-earn All-PERFECT on any clear, so both bonus stages will *always* display the mark in its least legible context. Needs a device check to judge severity. | Noticeable |

**Correct:** three-state badge logic is exactly per GDD — filled `AllPerfectMark(fill=1)` for earned, hollow grey ring (`HOLLOW_ACCENT`, lerped not alpha-faded, with the reason written down) for unlocked-unearned, no mark at all for locked. Staggered pending reveal with `ALL_PERFECT_REVEAL_DELAY`/`_STAGGER` and correct guards against a mid-sequence back-out.

---

### 3. Endless Mode Select

| # | Finding | Severity |
|---|---|---|
| 3.1 | **"Choose your mode" is the one label on this screen that skips the portrait type scale.** `col.add_child(_heading("Choose your mode", 26, GOLD))` passes a raw `26` where every other size on the screen goes through `_fs()` (heading `_fs(56)`, buttons `_fs(30)`, caption `_fs(20)`). At `PORTRAIT_SCALE = 1.7` this subtitle renders at 26 while the caption *below* it renders at 34 — the subtitle is smaller than the muted best-score line it introduces, and inverted against its own hierarchy. This is a straightforward missing `_fs()`. | **Noticeable** |
| 3.2 | **`"BEAT YOUR BEST: %d"` has no thousands separator.** GDD §7 writes this string as "BEAT YOUR BEST: 17,240". `ScoresScreen._thousands()` exists and produces exactly that format — it just isn't reachable from here. See 3.3 in cross-cutting. | Noticeable |
| 3.3 | **"Choose your mode" is sentence case and gold-accented.** Every other string on the screen is uppercase, and gold is reserved by GDD §6/§8 for outcomes and records — spending it on a wayfinding subtitle is the same misuse `OptionsPanel.SECTION_LABEL_SIZE`'s comment and `ScoresScreen._header_row()`'s comment both explicitly avoided ("gold is the outcome/record role in this project's colour system, and spending it on column scaffolding is what left nothing to mark the actual achievement with"). | Minor |
| 3.4 | **BACK's font is `_fs(30)` — the largest of the six.** Effective portrait size 51, vs Scores/Level Select at ~34. The height override is applied after `_button()` but the font is not. | Minor |
| 3.5 | **The muted caption uses `TEXT_FILL @ 0.75 alpha` rather than `MUTED`.** Every other screen's muted supporting text uses `8b90a8`; this screen doesn't declare `MUTED` at all. Visually similar, but it means "muted" is expressed two different ways. | Minor |

**Correct:** name-left / lives-right label pairing measured off the button's *actual* scaled size, Hardcore's independent lock with its own toast, `"NO RECORD YET"` rather than a bare zero, powerup primer gated on the mode choice not the screen open, BACK 200-wide and last in the column.

---

### 4. Help screen

| # | Finding | Severity |
|---|---|---|
| 4.1 | **BACK is 200×96 in landscape — the height bump was never gated to portrait.** `back.custom_minimum_size = Vector2(200, 96) * _s()`. Every other screen writes the ternary (`96.0 if Layout.is_portrait() else 64.0` in Level Select, `72.0 if … else 64.0` in Credits/Endless Mode Select, `_back_h()` in Options/Scores). The comment attached to the line only justifies the portrait value ("96 raw -> 144 canvas units in portrait"), which strongly suggests the landscape case was overlooked rather than chosen. Result: on desktop/web this screen's BACK is 50% taller than the other five. | **Noticeable** |
| 4.2 | **Page dots are not colour-coded.** `_style_dots()` sets `bg_color = NEON if active else MUTED@0.45` — all three active states are the same cyan. GDD §8 describes them as "colour-coded and stretching to a pill on the active page, **mirrored by the Scores screen's own hero-card dots**", and `ScoresScreen._style_hero_dots()` genuinely does carry a per-page accent ("Each dot carries its own page's accent rather than one neutral hue for both"). The pill-stretch behaviour matches; the colour-coding does not. See Open Questions Q1. | Noticeable |
| 4.3 | **Page 1's tab reads "TIMERS"; the in-game Help bubble's page 1 heading reads "TIMER TYPES".** Same page, same content, two names — and GDD §8 calls it "Timer Types" in both places. `HelpScreen._build_tab_row()` uses `["TIMERS", "POWERUPS", "SCORING"]`; `HelpBubble.PAGE_TITLES` uses `["TIMER TYPES", "POWERUPS"]`. | Noticeable |
| 4.4 | **Inactive tabs outline in black,** `Color(0, 0, 0, 0.6)`, where every other outlined text in the project outlines in an accent. Deliberate de-emphasis, but it is the only black outline in the codebase. | Minor |
| 4.5 | **Dot geometry differs from the Scores hero dots it's said to mirror.** Help: size 10 / active 26 / row 28. Scores: 8 / 22 / 20. After each screen's own `PORTRAIT_SCALE` (1.5 vs 1.2) the effective sizes are 15/39 vs 9.6/26.4 — Help's dots are ~1.5× larger. Never seen side by side, so low impact. | Minor |

**Correct:** grade windows read live off `TimerSlot.PERFECT_MAX`/`GOOD_MAX`/`OKAY_MAX`/`MISS_MAX` rather than transcribed, so page 3 cannot disagree with the board. Caption body text is `TEXT_FILL` with the type accent on the panel border rather than on the glyph — the documented fix for Blackout's 3.19:1 contrast failure, correctly applied. Tile sizes match the real board's cell size. Bystander row reserves its space. Caption flips above/below. Chips/tabs/BACK all clear 48–57.6dp in portrait.

---

### 5. In-game Help bubble

No visual findings. Icon is portrait-sized (120×120 ≈ 48dp), shares `PAUSE_ICON_TOP_MARGIN_PORTRAIT` with the pause button so both sit on one line, insets by `SafeArea.right`/`.top`, and the unseen-type badge rides along with it. Heading swaps correctly between the two page titles.

One note, carried up to 4.3: this screen's "TIMER TYPES" is the string that matches the GDD; the Help screen's "TIMERS" is the outlier.

---

### 6. Options

| # | Finding | Severity |
|---|---|---|
| 6.1 | **The toggle's one-line explanation is factually wrong.** `_toggle_field("Reduce effects", "Fewer particles, no screen shake", reduce)`. Particles are *not* reduced. Three independent sources say so: GDD §9 ("Explicitly does *not* touch: localized particle bursts, click-point effects, label pops"); `Settings.motion_effects_enabled()`'s own comment ("Deliberately does NOT gate localized effects (click bursts, particles, label pops)"); and the comment eight lines above the string in this very file ("Localized effects, the powerup state overlays and audio are left alone"). Verified against every call site — `Settings.effect_scale()` is consumed only by label pops (`TimerSlot:653`, `HelpDemoTile:508`), glow/breath strength (`Juice:842,850`), the outro band (`Juice:1144`) and sign-ring strength (`StageResultScreen:450,1138`). No burst or particle-count path reads it. The subtitle exists specifically to tell the player what the setting does, and it is the one string in the game that misdescribes its own feature. **Suggested:** "No screen shake, flashes or camera punch". | **Jarring** |
| 6.2 | **The toggle is labelled "Reduce effects"; the GDD names it "Reduce screen effects"** (§8, §9, and the audit brief throughout). The word "screen" is what scopes it — without it the label reads as a global effects reduction, which is precisely the misreading 6.1 then confirms. | Noticeable |
| 6.3 | **`SUBTITLE_SIZE` (36) equals `SECTION_LABEL_SIZE` (36).** The section eyebrows ("AUDIO", "DISPLAY", "DATA") are documented as "deliberately below body size", and the toggle subtitle now matches them exactly, so two different roles share one size. Both are `MUTED`, so only case and position separate them. | Minor |
| 6.4 | **`NeonToggle.ACCENT` and `NeonSlider.ACCENT` each re-declare `Color("22d3ff")`** inside the inner classes rather than referencing the file's own `NEON`. Same value today; two more places for cyan to drift. | Minor |

**Correct:** single-column card, grouped AUDIO/DISPLAY/dev/DATA sections, full-width sliders, whole toggle row as one 48dp target (`TOUCH_MIN * _s()` = 120 units), confirmation step whose copy correctly scopes the wipe to progress and explicitly promises settings survive — matched by `Settings.persist_current_values()` actually doing it. RESET PROGRESS in `RED`, matching Title's QUIT confirm.

---

### 7. Credits

| # | Finding | Severity |
|---|---|---|
| 7.1 | **BACK is 220×64, not 200×64.** Same divergence as Level Select (2.1) — Level Select's comment names this screen as the thing it is matching, so the two are consistent with each other and both differ from the GDD and from the other four. | Minor |

**Music attribution verified correct.** `MUSIC_LINES = ["\"Synthwave Retro 80s\"", "by arpmedia", "via Pixabay"]` matches GDD §2 exactly (track, artist, source). Engine credit present. Zero-external-SFX claim is not asserted anywhere in UI text, which is correct — there is nothing to get wrong.

**Correct:** hero block → divider → two-peer colophon → divider → feedback block → real `EMAIL US` button via `OS.shell_open(mailto:)` rather than a hyperlink. Gold reserved for `MAKSTER` alone with every other accent in cyan, enforced deliberately (`GMTK_LINE` is cyan even sitting right beside the gold name). `UNIT`-multiple spacing with container separation zeroed to avoid the double-counted-gap bug. Fading-hairline dividers clamped to `0.78 × canvas` so they keep their fade in portrait.

---

### 8. Pause menu

| # | Finding | Severity |
|---|---|---|
| 8.1 | **Four "uniform" portrait buttons carry four different font sizes.** All four share `Vector2(380, 140)` and the same lit-glow box, but the fonts are RESUME 52, RESTART 50, OPTIONS 48, BACK TO TITLE 48. GDD §8 says they "share one uniform footprint and glow treatment … Accent colour is still what distinguishes them" — i.e. the whole point of the portrait layout was to drop the size hierarchy and let colour carry it. A 52/50/48 spread is too small to read as deliberate rank and too large to read as uniform; it reads as three leftovers from the pre-uniform sizes. | Noticeable |
| 8.2 | **Pause is 52/50/48 where Stage Result and Endless End are both 46,** on the identical 380×140 box. The three screens' `PORTRAIT_BUTTON_SIZE` agree; their `PORTRAIT_BUTTON_FONT` does not (46 / 46 / 48–52). Both tutorials also use 46, so Pause is the sole outlier among five screens sharing one button treatment. | Noticeable |

**Correct:** desktop/web keeps the three-tier hierarchy untouched (correct per GDD — a deliberate platform difference, not drift). Accents correct on both layouts (RESUME/RESTART/OPTIONS `NEON`, BACK TO TITLE `GREY` = `8b90a8`, the same hex Endless End's flat BACK TO TITLE uses). `GREY`-on-`GREY` font override applied so box and text match. Pause icon 120×120 portrait with a documented corner-curve cushion beyond what the safe-area API reports.

---

### 9. Stage Result / Arcade reveal

No findings. This screen is the cleanest in the project against its own spec.

Verified: `TIER_COLORS = [6b7080, 22d3ff, ffd23f]` — grey→cyan→gold, **no green** (§6.6), with the reason for dropping green written into the code. `GOLD = ffd23f` for NEW BEST vs `FLAWLESS = c8862e` for ALL PERFECT — genuinely darker and richer, not a paler/brighter variant, exactly as §6.5 requires, and the same `c8862e` Level Select's `AllPerfectMark.ACCENT` uses so the badge and the celebration are one colour. `FLOURISH_STAGGER = 0.55` matches the GDD's "~0.55s". Near-miss line names the specific grade when the attempt missed on one kind (`"%d %s AWAY FROM ALL PERFECT"`) and falls back to `"%d STOPS AWAY FROM ALL PERFECT"` on a mix. Headline `"STAGE CLEAR!"` cyan / `"FAILED"` red. `HEAT` documented "never text".

---

### 10. Endless HUD (live play)

| # | Finding | Severity |
|---|---|---|
| 10.1 | **The portrait type bump reached only two of five HUD readouts.** `_equation` (56→78) and `_total` (26→36) have `*_LANDSCAPE`/`*_PORTRAIT` pairs. `_streak_popup` (38), `_milestone_label` (34) and `_streak_counter` (24) are hardcoded landscape values with no portrait branch. GDD §7 describes the mobile HUD as sitting "at a bumped type scale" — the live streak counter, at 24 units ≈ 9.6sp, ends up the smallest text in live play and roughly a third the size of the TOTAL directly above it. | **Noticeable** |
| 10.2 | **`_streak_counter` is corner-pinned but gets no safe-area inset.** It sits at `x = canvas.x - 190`, width 170 — i.e. 20 units (~8dp) from the right edge — while `_apply_safe_area()` only ever moves `_bottom_row`. The comment above it asserts the opposite of what the code does: "The top-of-screen readouts (equation, total, streak popup/counter, milestone) are horizontally centred and sit well inside the vertical extents, so a side cutout can't reach them." The equation, total and milestone labels genuinely are full-width and centred; the streak counter is the one exception, and it is the one the comment's conclusion doesn't hold for. GDD §10 lists corner-pinned UI as requiring insets. Needs a device check on a phone with a right-edge curve or cutout. | **Noticeable** |
| 10.3 | **Milestone stingers print unseparated** — `"%d!"` yields `25000!`. GDD §7 writes this exact progression as "10,000 → 25,000 → 50,000 → 100,000 → 250,000", i.e. the one place the doc formats these numbers, it formats them with commas. Same root cause as 3.2 / cross-cutting 3.3. | Minor |

**Correct:** live streak counter separate from the growth popup and hidden below 2 (§7). Milestone in its own label so it can't collide with a streak pop on the same frame. Overtake pulse is a warm-white flash (`Color(1.4, 1.3, 0.9)`) on both the equation and TOTAL, fired off the live projected total on every click. Fail crosses drawn as `Line2D` pairs rather than a "✕" glyph (documented Web-font tofu avoidance). Crosses row hidden entirely in Hardcore. Bottom row lifted by `SafeArea.bottom`. Combo meter genuinely removed.

---

### 11. Endless End / summary reveal

| # | Finding | Severity |
|---|---|---|
| 11.1 | **Mid-tier is still green.** `EndlessEndScreen.TIER_COLORS = [Color("6b7080"), Color("39ff9e"), Color("ffd23f")]` — grey → **green** → gold. `StageResultScreen.TIER_COLORS = [Color("6b7080"), Color("22d3ff"), Color("ffd23f")]` — grey → **cyan** → gold, with the fix documented in place: *"The middle step was green, which read as a third colour language on a screen that only has two, and tinted the anticipation wash green-black over this game's dark blue-black backdrop."* The identical reasoning applies here — this screen's palette comment lists exactly the same five roles and explicitly says "Same five-role split as StageResultScreen", and its tier comment says "mirroring the stage-end reveal's approach". It mirrors the mechanism but not the colour. Consumed at `_tint_dividers(TIER_COLORS[tier])`, so on a mid-quality run the settled summary's dividers sit green for as long as the screen is up. Per GDD §6.6 green should survive only as the transient GOOD grade sign colour. | **Jarring** |
| 11.2 | **`const GREEN := Color("39ff9e")` is declared and never used.** The green actually rendered comes from the inline literal in `TIER_COLORS`. Harmless today, but it means a search-and-replace on `GREEN` would miss the real one. | Minor |
| 11.3 | **Tier cuts differ between the two reveal screens** — Stage Result `[0.55, 0.85]`, Endless End `[0.45, 0.9]`. Defensible (different quality distributions: an Endless run's average grade and an Arcade stage's are not the same statistic), but worth confirming it was chosen rather than inherited. | Minor / verify |
| 11.4 | **Final score and record lines print unseparated** — `"%d" % runner.best_score`, `"PREVIOUS BEST %d"`. This screen's headline number is the one the player will go and compare against the Scores screen, which *does* separate it. See cross-cutting 3.3. | Noticeable |

**Correct:** stillness beat before the state change, aligned label/value table with a fixed `STAT_CAPTION_WIDTH` sized to the longest real caption (measured via `Font.get_string_size`, and the comment records that 270 was wrong and 320 is right), one combined NEW BEST flourish naming whichever stats improved rather than one per stat, `FAIL_RED` kept headline-only, `MUTED` on the supporting stats so gold arrives unshared at the score.

---

### 12. Scores

No findings. Hero card is cyan/red matched to `EndlessModeSelect.NEON`/`RED` by the same hex with the reasoning documented, opens on the higher of the two scores, page-dot pair carries per-page accents and pill-stretches. Summary line is `"%d OF %d STAGES PERFECTED"` with a `"NO STAGES PERFECTED YET"` zero-state (never a bare zero) and a `"NO RUN YET"` empty state on the hero number for the same reason. Stage rows are dark-tinted-plate-plus-border, reuse `LevelSelect.AllPerfectMark` as an instance rather than a redrawn shape, and the target column is genuinely gone. `_thousands()` applied to both the hero number and every row's best.

This screen is the only one that formats scores with separators, which is what makes cross-cutting 3.3 visible.

---

### 13. Timer board (both modes)

No findings. `TimerSlot.TYPE_COLORS` and `TimerTypeInfo.COLORS` are identical maps (`e6e9ff` / `ff2e5e` / `22d3ff` / `ffd23f` / `5a5f70` / `b06bff`), so the board, the Help legend, the tutorial popups and the Endless callouts cannot render a type differently. Decay's `DECAY_TIER_COLORS` ramp holds saturation the whole way down with the reason written down — specifically so a drained Decay is never misread as a Blackout — and tier 0 (`e0a5ff`) is deliberately the brightest thing on the board. Blackout gets a deeper fill and dimmed glow on top of its darker accent. Blue's `FROST_COLOR` (`d8f4ff`) is shared verbatim with `HelpDemoTile`.

Blackout's heartbeat tick being *audibly* distinct is outside a source audit's reach and needs a listen on device; `TimerTypeInfo.AUDIO_CUE_TYPES` correctly contains only `BLACKOUT`, so the wiring is right.

---

### 14. Powerup visuals

| # | Finding | Severity |
|---|---|---|
| 14.1 | **Overclock is two different reds depending on which part of it you're looking at.** `Powerups.COLORS[OVERCLOCK] = Color("ff2e5e")` drives the button, its icon (`PowerupIcon._draw_overclock` reads `PowerupSystem.color_of`) and its wind-up flash. `Juice.OVERCLOCK_COLOR = Color("ff1040")` drives the screen-edge bands, the combined Overclock+Shield state and `MULTIPLIER_BURST_TINT`. So the button the player presses and the effect that fires are not the same red — and `MULTIPLIER_BURST_TINT`'s comment ("Matches Overclock's edge treatment so the two read as one state") is true of the edge and false of the button. One of the two should reference the other. | Noticeable |
| 14.2 | **`LOW_LIFE_COLOR` (`ff1030`) and `OVERCLOCK_COLOR` (`ff1040`) differ by 16/255 on one channel** — visually the same red. Both are ambient screen-edge states in Endless and can be on simultaneously (Overclock on your last life). The code anticipates this and separates them by geometry (radial vignette vs hard edge bands) and pulse rate (0.55Hz breathing vs 3.4Hz throb), which is a real and documented distinction — but hue contributes nothing, so the entire burden is on motion. Worth a device check with both active; see Open Questions Q3. | Minor / verify |

**Correct:** Shield cyan / Nuke gold / Overclock red as a button set. Combined Overclock+Shield has its own dedicated state (`SHIELD_CONTAIN_COLOR` `b8f4ff`, bands dimmed by `OVERCLOCK_COMBINED_DIM` so the containment rim reads) rather than naive alpha layering, exactly per GDD §7. Overclock's depletion bar is separate from the cooldown ring. `HEAT_COLOR` (`ff5a1e`, orange bloom) is genuinely distinct from both reds in hue *and* geometry.

---

### 15. Android-specific rendering

| # | Finding | Severity |
|---|---|---|
| 15.1 | **`Toast` is the one shared UI component with no portrait handling whatsoever.** The file contains no reference to `Layout`, `_s()`, `PORTRAIT_SCALE` or `SafeArea`. Two consequences: (a) `POSITION_Y := 800.0` is a landscape number — the comment calls it "Bottom-center", which is true on a 1600×900 canvas (100 units from the bottom) and false on portrait's 900×~2000, where it lands roughly 40% down the screen. On the title screen in portrait that puts the toast in the gap *above* the ARCADE/ENDLESS stack rather than below it, and well away from the locked ENDLESS button that triggered it. (b) `font_size 24` unscaled ≈ 9.6sp on device — below the 14sp body floor this project measured and fixed everywhere else (`ScoresScreen`: "_fs(24) measured 11.6dp on device, well under the 14sp floor"). This is the message that explains why a button didn't do anything, so it is a poor place to be the smallest text in the game. Both locked-gate paths that use it (`TitleScreen._on_locked_endless_tapped`, `EndlessModeSelect._on_locked_hardcore_tapped`) are ones a mobile player will hit early. | **Jarring** |
| 15.2 | **The full-bleed router background and every screen's own backdrop are different shades.** `MainScreenRouter._background.color = Color(0.043137, 0.043137, 0.070588)` = `#0B0B12`, which matches GDD §2's "`#0a0a11`-ish". Every screen backdrop is `Color(0.03, 0.03, 0.05)` = `#08080D`, noticeably darker. Screen backdrops are sized to `Layout.overscan_*` so they cover the bands and the router colour is normally hidden — but it is what shows during the router's cross-fade between screens, so a transition dips through a lighter shade. Low impact; needs a device check to judge whether it's perceptible. | Minor / verify |

**Correct:** `Layout._compute_portrait_size()` derives canvas height from real device aspect with a documented 1200–2400 clamp and the reasons (split-screen, foldables, DeX) written down. `ScreenLayout.cover()` centralises the overscan stretch and every screen with a backdrop uses it or inlines the same two lines. `SafeArea` conversion re-runs on dynamic-height changes and translates display-space to window-space before intersecting. Corner-pinned UI is inset on Title (version + quit), Pause (icon), Help bubble (icon + badge) and Endless HUD's bottom row — with the single exception at 10.2.

---

### 16. Accessibility toggle correctness

The **implementation** is correct and matches GDD §9 precisely. `Settings` exposes two deliberately separate gates:

- `motion_effects_enabled()` → hard off for shake, camera punch/pull, hit-stop, full-screen flashes and washes.
- `effect_scale()` → `0.4`, non-zero, for things that can legitimately be softened.

Verified every consumer. `effect_scale()` reaches label pops (`TimerSlot:653`, `HelpDemoTile:508`), glow/breath strength and legibility floor (`Juice:842`, `Juice:850` — `maxf(effect_scale(), 0.7)`, so state-indicator glows stay well above zero), the Arcade outro band (`Juice:1144`), and sign-ring strength (`StageResultScreen:450, 1138`). Nothing gates particle bursts or click-point effects, which is exactly what §9 specifies.

The Arcade reveal's pre-tally tint is correctly scaled rather than removed.

**The only defect here is the label describing it** — see 6.1 and 6.2. The setting does the right thing and tells the player the wrong thing.

---

## 3. Cross-cutting findings

### 3.1 — Three dead SVGs violate the thorvg rules, and are cited as the house style · *Minor*

`icons/powerup_shield.svg`, `icons/powerup_clear_all.svg` and `icons/powerup_overclock.svg` each contain a real `<filter id="glow">` with `feGaussianBlur` + a five-node `feMerge`, applied via `filter="url(#glow)"` on their stroke and check paths — the exact construct GDD §2 identifies as broken under thorvg ("blurs the whole shape instead of adding a halo").

They are **not referenced anywhere** — no `.gd`, `.tscn` or `.tres` loads them; the powerup icons are drawn procedurally in `PowerupIcon.gd`. They date from the initial commit and are not in the GDD's list of sanctioned hand-authored SVGs.

Two reasons this still matters: (1) they are the only files in `icons/` that would render wrong if anyone wired them up, and (2) `TitleScreen.gd:464-468` points at them by path as the style the *working* icons follow, including the phrase "with a glow filter" — so the one comment a future contributor would read before authoring a new icon actively recommends the broken pattern.

**All seven sanctioned icons are clean** — verified with comments stripped, since every one of them carries a prose explanation of the two rules that trips a naive grep. `icon.svg`, `android_icon_{main,foreground,background,monochrome}.svg`, `credits_heart.svg` and all four `title_*.svg` contain no `<text>`, no filter, and build glow from a translucent accent fill plus a bold accent stroke exactly as specified.

### 3.2 — The "unified BACK button" is unified in name only · *Noticeable*

GDD §8: "same size (200×64 landscape/desktop; bumped per-screen in Android portrait to clear 48dp)". GDD §10 adds: "with the *effective* dp unified across screens even though each screen's own `PORTRAIT_SCALE` means the raw pre-scale constant differs."

Measured across all six:

| Screen | Scale | Landscape | Portrait h (units → dp) | Portrait w | Font base → effective |
|---|---|---|---|---|---|
| Options | 1.2 | 200×64 | 144 → **57.6dp** | 240 | 38 → **45.6** |
| Scores | 1.2 | 200×64 | 144 → **57.6dp** | 240 | 28 → **33.6** |
| Help | 1.5 | 200×**96** | 144 → **57.6dp** | 300 | 28 → **42** |
| Level Select | 1.3 | **220**×64 | 124.8 → **49.9dp** | 286 | 26 → **33.8** |
| Credits | 1.7 | **220**×64 | 122.4 → **49.0dp** | 374 | 26 → **44.2** |
| Endless Mode Select | 1.7 | 200×64 | 122.4 → **49.0dp** | 340 | 30 → **51** |

Three separate drifts:
- **Landscape height:** Help is 96 where all five others are 64 (finding 4.1 — an ungated ternary, almost certainly unintentional).
- **Landscape width:** 220 on Level Select and Credits vs 200 on the other four (findings 2.1 / 7.1 — documented as deliberate, but contradicts the GDD).
- **Portrait effective dp splits into two classes**, ~49dp and 57.6dp, so §10's "effective dp unified" claim does not hold. And portrait *width* ranges 240→374, a 56% spread on a button the GDD calls one size.
- **Font on the same button ranges 33.6→51 effective** — a 1.5× spread, with no relationship to the height class (Endless Mode Select has the smallest box height class and the largest font).

None of these is individually jarring, but a player moving Title → Scores → back → Help → back sees the same button at three different sizes.

### 3.3 — Score numbers are separated on exactly one screen · *Noticeable*

`ScoresScreen._thousands()` is a `static func` producing `"36,000"`, with a good reason recorded ("five unbroken digits are measurably slower to read"). It is called twice, both inside `ScoresScreen`.

Every other score in the game prints raw `%d`:

| Location | String | Renders |
|---|---|---|
| `EndlessModeSelect:244` | `"BEAT YOUR BEST: %d"` | `BEAT YOUR BEST: 17240` |
| `EndlessHUD:272` | `"TOTAL   %d"` | `TOTAL   17240` |
| `EndlessHUD:344` | `"%d!"` (milestone) | `25000!` |
| `EndlessEndScreen:221,332,335` | final score, `PREVIOUS BEST`, `best_score` | `17240` |
| `StageResultScreen:953,955,1068` | `PREVIOUS BEST %d`, `BEST %d`, final | `17240` |
| `HUD:88` | `"SCORE  %d"` | `SCORE 17240` |

The GDD writes these with commas in both places it shows one — "BEAT YOUR BEST: 17,240" (§7) and the milestone ladder "10,000 → 25,000 → 50,000 → 100,000 → 250,000" (§7). The sharpest instance is a player finishing an Endless run, reading `17240` on the summary, then opening Scores and seeing `17,240` — the same number, two formats, two taps apart.

`_thousands()` is already `static`, so it is callable as `ScoresScreen._thousands(n)` from anywhere; the cleanest fix is probably to lift it somewhere neutral rather than have five screens reach into a sibling screen's class.

### 3.4 — Portrait type scaling has three isolated gaps · *Noticeable*

The `PORTRAIT_SCALE`/`_s()`/`_fs()` idiom is applied consistently and well on the six screens that adopted it. Three things sit outside it:

1. `Toast` — entirely (3.1 / 15.1), the only *shared* component affected.
2. `EndlessModeSelect`'s "Choose your mode" — a single missing `_fs()` on an otherwise fully-scaled screen (3.1).
3. `EndlessHUD`'s streak popup / streak counter / milestone label — the screen uses explicit `*_LANDSCAPE`/`*_PORTRAIT` pairs rather than a scale factor, and three of five readouts never got their pair (10.1).

Common signature: all three are elements added at different times to screens whose *other* elements were scaled in a dedicated pass. Worth a grep for bare integer `font_size` overrides as a standing check.

### 3.5 — Palette constants are copy-pasted, not shared · *Minor*

`Color("22d3ff")` appears 25 times, `ffd23f` 19, `dfe3ee` 19, `ff2e5e` 16, `8b90a8` 13 — each re-declared per file (usually as `NEON`/`GOLD`/`TEXT_FILL`/`RED`/`MUTED`, occasionally under a different name: `NORMAL_ACCENT`, `BONUS_ACCENT`, `LOCKED_ACCENT`, `GREY`, `BACK_ACCENT`, `FAIL_RED`, `CLEAR_COLOR`, `FAIL_COLOR`).

Today every value agrees — this audit found no wrong hex among them, and several files carry comments explaining that they deliberately match a named sibling. So this is a latent risk, not a present defect. But it is the mechanism by which findings 11.1 (`TIER_COLORS` green) and 14.1 (two Overclock reds) happened: both are cases where one copy was fixed and its twin wasn't. A shared `Palette` class with the five roles, plus `Powerups.COLORS` referencing it, would make the next one impossible.

### 3.6 — Case convention is mixed · *Minor*

Uppercase dominates (all buttons, all headings, all section labels, all HUD readouts). Sentence case appears in: Options' field labels ("SFX volume", "Music volume", "Reduce effects", "Dev: force grade"), both confirm-dialog headings ("Are you sure?", "Quit PERFECT ZERO?"), Endless Mode Select's "Choose your mode", and every `TimerTypeInfo` name/description ("Normal", "Counts down to zero…").

Most of this is defensible — settings rows and body copy reading as sentences while chrome shouts is a normal convention, and the two dialogs agree with each other. "Choose your mode" is the one that sits alone: it is a heading, in a heading slot, in gold, in sentence case, on a screen where everything else is uppercase.

---

## 4. Open questions — RESOLVED 2026-08-04

All four design calls were made by the project owner. Recorded here so a later pass doesn't reopen them.

**Q1 — Should the Help screen's page dots be colour-coded per page? → NO. Amend the GDD.**
*Decision:* keep `_style_dots()` as-is (active = cyan, inactive = muted). Reword GDD §8 so "colour-coded" reads as "the active dot carries the accent, the inactive ones are muted" — which is what the code does. Scores keeps its per-page cyan/red because its pages genuinely *are* modes with established colours; Help's three pages have no canonical colour to reuse, so per-page tinting would invent three new colour meanings rather than reuse existing ones.
*Action:* GDD wording only. **Finding 4.2 is closed as not-a-bug.**

**Q2 — Are Level Select's bonus stages meant to carry gold? → LEAVE AS-IS.**
*Decision:* no change. The bonus accent stays gold, the badge plate stays as it is. Treated as accepted rather than deferred — if it reads badly on device it can be revisited, but it is not to be re-flagged as a finding.
*Action:* none. **Finding 2.4 is closed as verified-accepted.**

**Q3 — Is 16/255 of blue enough separation between Overclock and the low-life vignette? → NO. Darken low-life so hue separates too.**
*Decision:* move `LOW_LIFE_COLOR` to a deeper, blue-leaning crimson so the pair differs in hue as well as geometry and pulse rate. Overclock stays at `ff1040` — it cannot move toward orange without colliding with streak heat's `ff5a1e`.

*Implementation note — the non-obvious part.* The vignette is a `TextureRect` holding a radial `GradientTexture2D`, composited with **normal alpha blending** at `LOW_LIFE_ALPHA = 0.26` (times the breath pulse) over a near-black `#0B0B12` backdrop. That means simply picking a darker colour at the same alpha will mostly reduce *intensity*, and two colours differing chiefly in value read as "same red, dimmer" — precisely the failure mode this change exists to avoid. To get a genuine hue read, the channel *ratio* has to change, not just its scale, and the alpha needs raising to hold perceived presence.

Proposed starting point, to be judged on device rather than taken as final:
- `LOW_LIFE_COLOR`: `ff1030` → **`8c0f3c`** — a deep wine/burgundy. Clear blue lean against Overclock's hot near-pure red, and far enough from `ff5a1e` (heat) and `ff2e5e` (Hardcore/FAIL) not to trade one collision for another. Burgundy also suits the GDD's brief for this state better than a brick red would: "calm rather than alarming… a slow breathing pulse, not a flash."
- `LOW_LIFE_ALPHA`: `0.26` → **`~0.32`**, compensating for the darker source so the vignette holds roughly its current presence.

Both values want a look with Overclock active on the last life before being locked in.

**Q4 — Are the two reveal screens' tier cuts meant to differ? → Not asked; treated as deliberate.**
Stage Result `[0.55, 0.85]` vs Endless End `[0.45, 0.9]`. An Arcade stage's average grade quality and an Endless run's are different distributions, so identical cuts would not produce comparable tier frequencies — the divergence is defensible on its face and no evidence suggests it was accidental. Left alone; a one-line comment in each file recording *why* they differ would stop the next reader filing it as drift. **No code change.**

**Q5 — GDD or code as source of truth for the small divergences? → SPLIT, by whether it was a choice.**
*Decision:* fix what was accidental, document what was deliberate.

*Conform the code (accidental):*
- Help's BACK at `200×96` in landscape — an ungated ternary, not a decision (finding 4.1).
- Help's page-1 tab `"TIMERS"` → `"TIMER TYPES"`, matching both the GDD and the in-game Help bubble, which already agree with each other (finding 4.3).

*Conform the GDD (deliberate):*
- BACK at 220 wide on Credits + Level Select — Level Select's own comment records this as an explicit call (findings 2.1, 7.1). GDD §8's "same size (200×64)" should acknowledge the two-width reality.
- GDD §10's claim that "the *effective* dp [is] unified across screens" — this was never true (49dp vs 57.6dp classes). Either restate it as "every screen clears 48dp" or unify the classes; the claim as written should not survive either way.

---

## Appendix — verified-correct, no action

Recorded so a future pass doesn't re-audit them:

- All seven sanctioned SVG icons: no `<text>`, no filters, accent-fill-plus-stroke construction.
- `TimerSlot.TYPE_COLORS` ≡ `TimerTypeInfo.COLORS` (all six types, exact hex).
- Every screen heading uses `WaveHeading` (Title ×2, Level Select, Endless Mode Select, Help, Options, Scores, Credits).
- `AllPerfectMark` instanced by both Level Select and Scores — one class, one verdict, one reveal animation, `take_pending_all_perfect()` consumed by whichever screen is visited first.
- `380×140` portrait row-button footprint shared by Pause / Stage Result / Endless End / TutorialManager / PowerupTutorial (fonts differ — see 8.2).
- Stage Result's grey→cyan→gold tier ramp, gold-vs-bronze-gold NEW BEST/ALL PERFECT split, no green.
- Credits' music attribution matches GDD §2 exactly.
- `"BACK TO TITLE"` used 5× with no `"MAIN MENU"` variant anywhere.
- Zero-state strings avoid bare zeros throughout: `"NO RECORD YET"`, `"NO RUN YET"`, `"NO STAGES PERFECTED YET"`, `"-"` for an unplayed stage row.
- `Settings`' two-gate accessibility model and all seven of its consumers.
- `ScreenLayout.cover()` / `Layout.overscan_*` used by every screen that paints a backdrop.
- Locked-state treatment identical on Title's ENDLESS, Level Select's stages and Endless Mode Select's HARDCORE (dimmed modulate + `LOCKED_ACCENT`, left enabled so the toast can fire).

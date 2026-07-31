class_name ScreenLayout

# Shared helpers for the screens' responsive layout, so the same three lines
# aren't written out (and allowed to drift) in a dozen places.
#
# Not an autoload and never instantiated - Layout already owns the state, this
# only owns the handful of operations every screen performs against it.

# Stretches a rect over the whole display, pillarbox bands included.
#
# A backdrop sized to Layout.canvas_size stops at the design canvas, and on any
# aspect ratio that isn't the canvas's own that leaves the engine's clear colour
# showing beyond it - lighter strips above and below the content in portrait, or
# to either side in landscape. Anything meant to cover the screen (a backdrop, a
# modal dim, a full-screen flash) goes through here instead.
static func cover(rect: Control) -> void:
	if rect == null:
		return
	rect.position = Layout.overscan_position
	rect.size = Layout.overscan_size

# Same, for the several screens that own more than one full-screen rect.
static func cover_all(rects: Array) -> void:
	for rect in rects:
		if rect is Control:
			cover(rect)

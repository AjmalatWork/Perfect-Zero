extends Node
class_name PressFeedback

# Reusable "snooze-button" press feel. Attach to any Control (or call
# PressFeedback.apply(control)) - on press it dips + shrinks slightly; on release
# it springs back. Works for Buttons (button_down/up) and plain Controls
# (gui_input), including TimerSlot.

const DIP := 3.0
const SHRINK := Vector2(0.96, 0.96)

var _target: Control
var _base_pos: Vector2
var _has_base: bool = false

static func apply(target: Control) -> PressFeedback:
	var pf := PressFeedback.new()
	target.add_child(pf)
	pf.attach(target)
	return pf

func attach(target: Control) -> void:
	_target = target
	if _target is Button:
		_target.button_down.connect(_press)
		_target.button_up.connect(_release)
	else:
		_target.gui_input.connect(_on_gui_input)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press()
		else:
			_release()

func _press() -> void:
	if not _has_base:
		_base_pos = _target.position
		_has_base = true
	_target.pivot_offset = _target.size * 0.5
	var tween := _target.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_target, "scale", SHRINK, 0.06)
	tween.tween_property(_target, "position:y", _base_pos.y + DIP, 0.06)

func _release() -> void:
	if not _has_base:
		return
	var tween := _target.create_tween()
	tween.set_parallel(true)
	tween.tween_property(_target, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_target, "position:y", _base_pos.y, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

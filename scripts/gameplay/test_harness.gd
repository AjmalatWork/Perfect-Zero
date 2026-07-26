extends Node2D	

@onready var slot: TimerSlot = $TimerSlot

func _ready() -> void:
	var td := TimerData.new()
	td.start_time = 5.0
	slot.setup(td)
	EventBus.timer_stopped.connect(_on_timer_stopped)
	EventBus.timer_expired.connect(_on_timer_expired)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_select"): # spacebar by default
		slot.stop()

func _on_timer_stopped(source: Node, grade: String, type: int, distance: float) -> void:
	print("Stopped! Grade: ", grade, " Type: ", type, " Distance: ", distance)

func _on_timer_expired(source: Node) -> void:
	print("Timer expired unstopped!")
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

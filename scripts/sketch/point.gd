extends Point

signal clicked(point: Point)
signal position_updated()

func _ready():
	SignalBus.sketch_solved.connect(_update_position)
		
func _on_button_pressed() -> void:
	print("point clicked")
	clicked.emit(self)
	
func _update_position():
	update_position()
	print("point pos updated")
	position_updated.emit()

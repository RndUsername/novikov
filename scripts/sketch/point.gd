class_name SketchPoint extends Point

signal clicked(point: Point)

func _on_button_pressed() -> void:
	print("point clicked")
	clicked.emit(self)

extends Sketch


var entityIsLine = false
var pointScene = preload("res://scenes/sketchPoint.tscn")
var lineScene = preload("res://scenes/sketchLine.tscn")

var lineBeingDrawn: Line

func _on_entity_type_toggled(toggled_on):
	entityIsLine = toggled_on

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if entityIsLine:
			pass
		else:
			addPoint(event.position)
		
func addPoint(pos: Vector2):
	var point: Point = pointScene.instantiate()
	point.position = pos
	point.clicked.connect(onPointClicked)
	add_child(point)

func onPointClicked(point: Point):
	if lineBeingDrawn == null:
		lineBeingDrawn = lineScene.instantiate()
		add_child(lineBeingDrawn)
		
	lineBeingDrawn.addPoint(point)
	
	if !lineBeingDrawn.isBeingDrawn:
		lineBeingDrawn.add_constraint_vertical()
		lineBeingDrawn = null

func _on_solve_button_pressed():
	solve()
	SignalBus.sketch_solved.emit()

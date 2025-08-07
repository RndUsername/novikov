extends Line

@export var line2DNode: Line2D

var isBeingDrawn = false
	
func addPoint(point: Point):
	if line2DNode.get_point_count() == 0:
		line2DNode.add_point(point.position)
		line2DNode.add_point(get_local_mouse_position())
		pointA = point
		point.position_updated.connect(update_positionA)
		isBeingDrawn = true
	elif line2DNode.get_point_count() == 2:
		isBeingDrawn = false
		line2DNode.set_point_position(1, point.position)
		pointB = point
		point.position_updated.connect(update_positionB)
		construct()

func _input(event):
	if event is InputEventMouseMotion and isBeingDrawn:
		line2DNode.set_point_position(1, event.position)

func update_positionA():
	line2DNode.set_point_position(0, pointA.position)

func update_positionB():
	line2DNode.set_point_position(1, pointB.position)

class_name SketchLine extends Line

@export var path3d: Path3D


func add_first_point(point: SketchPoint):
	assert(pointA == null)
	assert(pointB == null)

	pointA = point
	point.moved.connect(_redraw)
	position = point.position
	path3d.curve.add_point(Vector3.ZERO)

func add_second_point(point: SketchPoint):
	assert(pointA != null)
	assert(path3d.curve.point_count == 2)

	pointB = point
	point.moved.connect(_redraw)
	path3d.curve.set_point_position(1, point.position - position)

func _redraw():
	position = pointA.position
	if pointB != null:
		path3d.curve.set_point_position(1, pointB.position - position)

func get_endpoints() -> Array:
	if path3d.curve.point_count < 2:
		return []
	return [
		position + path3d.curve.get_point_position(0),
		position + path3d.curve.get_point_position(1),
	]

func draw_proposal_line(to_pos: Vector3):
	assert(path3d.curve.point_count in range(1,3), "Curve has %s points." % path3d.curve.point_count)
	assert(pointB == null)

	var local_pos := to_pos - position

	if path3d.curve.point_count == 2:
		path3d.curve.set_point_position(1, local_pos)
	else:
		path3d.curve.add_point(local_pos)

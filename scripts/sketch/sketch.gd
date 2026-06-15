extends Sketch

var pointScene = preload("res://scenes/sketchPoint.tscn")
var lineScene = preload("res://scenes/sketchLine.tscn")

var lineBeingDrawn: SketchLine
var lastCompletedLine: SketchLine

const MAX_LINES := 256
const MAX_POINTS := 512
const HOVER_RADIUS_PX := 12.0
const HOVER_COLOR := Color(1.0, 0.55, 0.1)

var hoveredPoint: SketchPoint = null
var loops: Array = [] # each entry: Array of SketchPoint forming a closed polygon

var extrudingBody: Body = null
var extrudeLoop: Array = []
var extrudeProfile := PackedVector2Array()
var lastBody: Body = null

@onready var lineRibbons: MultiMeshInstance3D = $LineRibbons
@onready var pointDots: MultiMeshInstance3D = $PointDots
@onready var loopFills: MeshInstance3D = $LoopFills

func _ready():
	solved.connect(_update_visuals)
	solved.connect(_rebuild_loop_fills)
	lineRibbons.multimesh.instance_count = MAX_LINES
	lineRibbons.multimesh.visible_instance_count = 0
	pointDots.multimesh.use_colors = true # must be set before instance_count
	pointDots.multimesh.instance_count = MAX_POINTS
	pointDots.multimesh.visible_instance_count = 0

func addPoint(pos: Vector3) -> SketchPoint:
	var point: SketchPoint = pointScene.instantiate()
	point.position = pos
	point.clicked.connect(onPointClicked)
	add_child(point)
	return point

func addLine(startingPoint: SketchPoint) -> SketchLine:
	var line: SketchLine = lineScene.instantiate()
	add_child(line)
	line.add_first_point(startingPoint)
	return line

func onPointClicked(point: SketchPoint):
	pass # TODO

func _on_solve_button_pressed():
	solve()


func _on_vertical_button_pressed():
	if lastCompletedLine == null:
		print("No line to constrain yet.")
		return
	lastCompletedLine.vertical = true
	print("Vertical constraint added to last line.")


func _on_chamfer_button_pressed():
	if lastBody == null:
		print("No body to chamfer yet.")
		return
	lastBody.chamfer_all_edges(0.1)


func _on_fillet_button_pressed():
	if lastBody == null:
		print("No body to fillet yet.")
		return
	lastBody.fillet_all_edges(0.1)


func _on_sketch_plane_input(_camera, event: InputEvent, event_position: Vector3, _normal, _shape_idx) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if extrudingBody != null:
			# Second click: apply the extrusion. The loop's area is consumed
			# by the body; lines and points stay.
			loops.erase(extrudeLoop)
			lastBody = extrudingBody
			extrudingBody = null
			extrudeLoop = []
			_rebuild_loop_fills()
			return
		if lineBeingDrawn == null and hoveredPoint == null:
			var loop := _loop_at(event_position)
			if not loop.is_empty():
				_start_extrusion(loop)
				return
		var closes_onto_existing := lineBeingDrawn != null and hoveredPoint != null
		var point: SketchPoint = hoveredPoint if hoveredPoint != null else addPoint(event_position)
		if lineBeingDrawn != null:
			lineBeingDrawn.add_second_point(point)
			lastCompletedLine = lineBeingDrawn
			lineBeingDrawn = null
			if closes_onto_existing:
				_detect_loop(lastCompletedLine)
		if not closes_onto_existing:
			# Keep drawing: the next segment starts where this one ended,
			# until the user presses Esc or closes onto an existing point.
			lineBeingDrawn = addLine(point)
		_update_visuals()

	elif event is InputEventMouseMotion:
		if extrudingBody != null:
			_update_extrusion_height()
			return
		_update_hover()
		if lineBeingDrawn != null:
			# Snap the proposal line to a hovered point.
			var target: Vector3 = event_position if hoveredPoint == null else hoveredPoint.position
			lineBeingDrawn.draw_proposal_line(target)
			_update_visuals()


func _update_hover():
	var cam := get_viewport().get_camera_3d()
	var mouse := get_viewport().get_mouse_position()
	var nearest: SketchPoint = null
	var nearest_d := HOVER_RADIUS_PX
	for child in get_children():
		if child is SketchPoint and not child.is_queued_for_deletion():
			# Never snap onto the current segment's own start, nor onto any
			# point already linked to it — that would put a line on top of
			# an existing line.
			if lineBeingDrawn != null and (child == lineBeingDrawn.pointA
					or _points_connected(child, lineBeingDrawn.pointA)):
				continue
			if cam.is_position_behind(child.global_position):
				continue
			var d := cam.unproject_position(child.global_position).distance_to(mouse)
			if d < nearest_d:
				nearest_d = d
				nearest = child
	if nearest != hoveredPoint:
		hoveredPoint = nearest
		_update_visuals()


func _loop_at(world_pos: Vector3) -> Array:
	var pt := Vector2(world_pos.x, world_pos.z)
	for loop in loops:
		var pts := SketchGeometry.loop_to_polygon(loop)
		if pts.size() >= 3 and Geometry2D.is_point_in_polygon(pt, pts):
			return loop
	return []


func _start_extrusion(loop: Array):
	extrudeLoop = loop
	extrudeProfile = SketchGeometry.loop_to_polygon(loop)
	extrudingBody = Body.new()
	add_child(extrudingBody)
	extrudingBody.build_extrusion(extrudeProfile, 0.05)


func _update_extrusion_height():
	var cam := get_viewport().get_camera_3d()
	var mouse := get_viewport().get_mouse_position()
	var ray_o := cam.project_ray_origin(mouse)
	var ray_d := cam.project_ray_normal(mouse)
	var centroid := Vector3.ZERO
	for v in extrudeProfile:
		centroid += Vector3(v.x, 0.0, v.y)
	centroid /= extrudeProfile.size()
	# Height = the point on the vertical axis through the profile centroid
	# that lies closest to the mouse ray.
	var b := Vector3.UP.dot(ray_d)
	var denom := 1.0 - b * b
	if absf(denom) < 1e-6:
		return # looking straight along the axis; keep the current height
	var w := centroid - ray_o
	var t := (b * ray_d.dot(w) - Vector3.UP.dot(w)) / denom
	extrudingBody.build_extrusion(extrudeProfile, maxf(t, 0.05))


func _points_connected(p1: Point, p2: Point) -> bool:
	for child in get_children():
		if child is SketchLine and not child.is_queued_for_deletion():
			var a = child.pointA
			var b = child.pointB
			if (a == p1 and b == p2) or (a == p2 and b == p1):
				return true
	return false


func _detect_loop(new_line: SketchLine):
	# The new line closed a loop if its endpoints were already connected
	# through other lines; that path plus the new line is the polygon.
	var adj := {}
	for child in get_children():
		if child is SketchLine and child != new_line and not child.is_queued_for_deletion():
			var a = child.pointA
			var b = child.pointB
			if a == null or b == null:
				continue
			adj.get_or_add(a, []).append(b)
			adj.get_or_add(b, []).append(a)
	var start = new_line.pointA
	var goal = new_line.pointB
	if not adj.has(start) or not adj.has(goal):
		return
	var prev := {start: null}
	var queue := [start]
	while not queue.is_empty():
		var current = queue.pop_front()
		if current == goal:
			break
		for neighbor in adj[current]:
			if not prev.has(neighbor):
				prev[neighbor] = current
				queue.append(neighbor)
	if not prev.has(goal):
		return
	var path := []
	var walk = goal
	while walk != null:
		path.append(walk)
		walk = prev[walk]
	if path.size() >= 3:
		loops.append(path)
		_rebuild_loop_fills()


func _rebuild_loop_fills():
	loopFills.mesh = SketchGeometry.build_loop_fills(loops)


func _update_visuals():
	var lines := lineRibbons.multimesh
	var dots := pointDots.multimesh
	var line_count := 0
	var point_count := 0
	for child in get_children():
		if child.is_queued_for_deletion():
			continue
		if child is SketchLine:
			var ends: Array = child.get_endpoints()
			if ends.size() == 2 and line_count < MAX_LINES:
				var a: Vector3 = ends[0]
				var b: Vector3 = ends[1]
				# The shader reads the endpoints from the instance transform:
				# origin = midpoint, X column = B - A.
				lines.set_instance_transform(line_count,
					Transform3D(Basis(b - a, Vector3.UP, Vector3.BACK), (a + b) * 0.5))
				line_count += 1
		elif child is SketchPoint and point_count < MAX_POINTS:
			dots.set_instance_transform(point_count,
				Transform3D(Basis.IDENTITY, child.position))
			dots.set_instance_color(point_count,
				HOVER_COLOR if child == hoveredPoint else Color.WHITE)
			point_count += 1
	lines.visible_instance_count = line_count
	dots.visible_instance_count = point_count


func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		if lineBeingDrawn != null:
			lineBeingDrawn.queue_free()
			lineBeingDrawn = null
			_update_visuals()
		if extrudingBody != null:
			extrudingBody.queue_free()
			extrudingBody = null
			extrudeLoop = []

extends Sketch

var pointScene = preload("res://scenes/sketchPoint.tscn")
var lineScene = preload("res://scenes/sketchLine.tscn")

var lineBeingDrawn: SketchLine
var lastCompletedLine: SketchLine
var circleBeingDrawn: SketchCircle

# Active sketch tool. With a tool on, clicking the plane draws that primitive;
# with no tool on, a click instead picks a face to extrude. At most one is on
# at a time (enforced by a shared ButtonGroup in the UI).
var lineToolActive := false
var circleToolActive := false

# Circle outlines are drawn as their polygon segments in the same ribbon
# multimesh as the lines, so the budget has to cover both (a close-up circle can
# use a few hundred segments).
const MAX_LINES := 4096

# View-adaptive circle smoothness: each outline segment is aimed at roughly
# CIRCLE_TARGET_SEG_PX pixels on screen, evaluated per vertex from its own
# camera distance (SketchCircle.outline), so the arc nearest the camera is
# subdivided finest. Outlines are rebuilt only once the camera moves past
# OUTLINE_CAM_EPS world units, so a still camera costs nothing.
const CIRCLE_TARGET_SEG_PX := 6.0
const OUTLINE_CAM_EPS := 0.01

# Max boundary edges the analytic fill shader can hold (its buffer is 2 slots
# per edge). Beyond this, the fill falls back to a triangulated mesh.
const MAX_FILL_EDGES := 128
const MAX_POINTS := 512
const HOVER_RADIUS_PX := 12.0
const HOVER_COLOR := Color(1.0, 0.55, 0.1)

var hoveredPoint: SketchPoint = null
# Bounded faces of the planar arrangement of all completed lines, recomputed
# whenever the lines change. Each entry is a CCW polygon (PackedVector2Array)
# in sketch-plane (x, z) coordinates.
var faces: Array = []

var extrudingBody: Body = null
var extrudeProfile := PackedVector2Array()
# Set while extruding a clean circle, so height updates rebuild a true cylinder
# instead of the polygon profile.
var extrudingCircle := false
var extrudeCenter := Vector2.ZERO
var extrudeRadius := 0.0
# Mixed line/arc contour (see SketchGeometry.face_to_contour) for the current
# face extrusion; empty when the face is a plain polygon.
var extrudeContour: Array = []
var lastBody: Body = null

# Camera position the circle outlines were last rebuilt for; used to skip work
# while the camera is still.
var _last_outline_cam := Vector3(1e20, 1e20, 1e20)

# Tag -> { center: Vector2, radius: float } for the circles in the current
# arrangement, so the fill and extrusion can snap arrangement points back onto
# the true circle (the arrangement itself runs on each circle's polygon).
var _circle_data: Dictionary = {}

@onready var lineRibbons: MultiMeshInstance3D = $LineRibbons
@onready var pointDots: MultiMeshInstance3D = $PointDots
@onready var loopFills: MeshInstance3D = $LoopFills

func _ready():
	solved.connect(_update_visuals)
	solved.connect(_rebuild_faces)
	GfxSettings.changed.connect(_on_gfx_settings_changed)
	# Render-only knobs (outline detail/mode) don't touch the arrangement, so a
	# cheap visual refresh is enough — no face rebuild while dragging the slider.
	GfxSettings.render_changed.connect(_update_visuals)
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

func addCircle(center: Vector3) -> SketchCircle:
	var circle := SketchCircle.new()
	circle.position = center
	circle.radius = 0.0
	add_child(circle)
	return circle

func onPointClicked(point: SketchPoint):
	pass # TODO

func _on_solve_button_pressed():
	solve()


func _on_line_button_toggled(pressed: bool):
	lineToolActive = pressed
	# Leaving the tool abandons any half-drawn segment.
	if not pressed:
		_cancel_line()


func _on_circle_button_toggled(pressed: bool):
	circleToolActive = pressed
	# Leaving the tool abandons any half-drawn circle.
	if not pressed:
		_cancel_circle()


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
			# Second click: commit the extrusion. Lines and points stay, so
			# the face stays in the arrangement and keeps its fill.
			lastBody = extrudingBody
			extrudingBody = null
			extrudingCircle = false
			return
		if lineToolActive:
			_line_tool_click(event_position)
		elif circleToolActive:
			_circle_tool_click(event_position)
		else:
			# No tool: a click on a face starts an extrusion instead. A clean
			# circle extrudes as a true cylinder; anything else as its polygon.
			var circle := _circle_face_at(event_position)
			if circle != null:
				_start_circle_extrusion(circle)
			else:
				var face := _face_at(event_position)
				if not face.is_empty():
					_start_face_extrusion(face)

	elif event is InputEventMouseMotion:
		if extrudingBody != null:
			_update_extrusion_height()
		elif lineToolActive:
			_update_hover()
			if lineBeingDrawn != null:
				# Snap the proposal line to a hovered point.
				var target: Vector3 = event_position if hoveredPoint == null else hoveredPoint.position
				lineBeingDrawn.draw_proposal_line(target)
				_update_visuals()
		elif circleToolActive and circleBeingDrawn != null:
			_update_circle_radius(event_position)


func _line_tool_click(event_position: Vector3) -> void:
	var closes_onto_existing := lineBeingDrawn != null and hoveredPoint != null
	var point: SketchPoint = hoveredPoint if hoveredPoint != null else addPoint(event_position)
	if lineBeingDrawn != null:
		lineBeingDrawn.add_second_point(point)
		lastCompletedLine = lineBeingDrawn
		lineBeingDrawn = null
		# A new segment can split or close off regions anywhere it crosses
		# other lines, so recompute the whole arrangement.
		_rebuild_faces()
	if not closes_onto_existing:
		# Keep drawing: the next segment starts where this one ended,
		# until the user presses Esc or closes onto an existing point.
		lineBeingDrawn = addLine(point)
	_update_visuals()


func _circle_tool_click(event_position: Vector3) -> void:
	if circleBeingDrawn == null:
		# First click: place the centre; the radius follows the mouse.
		circleBeingDrawn = addCircle(event_position)
	else:
		# Second click: commit. The circle now bounds a face.
		circleBeingDrawn = null
		_rebuild_faces()
	_update_visuals()


func _update_circle_radius(world_pos: Vector3) -> void:
	var c := circleBeingDrawn.position
	circleBeingDrawn.radius = Vector2(world_pos.x - c.x, world_pos.z - c.z).length()
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


func _face_at(world_pos: Vector3) -> Dictionary:
	var pt := Vector2(world_pos.x, world_pos.z)
	for face in faces:
		var poly: PackedVector2Array = face["points"]
		if poly.size() >= 3 and Geometry2D.is_point_in_polygon(pt, poly):
			return face
	return {}


# A SketchCircle whose disk contains world_pos and that still forms a whole,
# uncrossed face (its face has exactly the circle's polygon vertices). Returns
# null otherwise, so a circle split by lines falls back to polygon extrusion.
func _circle_face_at(world_pos: Vector3) -> SketchCircle:
	# The face under the cursor is independent of which circle owns it, so find
	# it once; a circle is "clean" only if that face is exactly its own polygon.
	var face := _face_at(world_pos)
	if face.is_empty():
		return null
	var face_size := (face["points"] as PackedVector2Array).size()
	var pt := Vector2(world_pos.x, world_pos.z)
	for child in get_children():
		if child is SketchCircle and child != circleBeingDrawn and not child.is_queued_for_deletion():
			var c := Vector2(child.position.x, child.position.z)
			if child.radius > 0.0 and pt.distance_to(c) < child.radius and face_size == _face_segments(child):
				return child
	return null


func _start_face_extrusion(face: Dictionary):
	extrudingCircle = false
	extrudeProfile = face["points"]
	# A contour with true arcs where the face follows circles; empty for a plain
	# polygon (then we extrude extrudeProfile directly).
	extrudeContour = SketchGeometry.face_to_contour(face["points"], face["tags"], _circle_data)
	_begin_extrusion(0.05)


func _start_circle_extrusion(circle: SketchCircle):
	extrudingCircle = true
	extrudeCenter = Vector2(circle.position.x, circle.position.z)
	extrudeRadius = circle.radius
	_begin_extrusion(0.05)


func _begin_extrusion(height: float):
	extrudingBody = Body.new()
	add_child(extrudingBody)
	_rebuild_extrusion(height)


func _rebuild_extrusion(height: float):
	if extrudingCircle:
		extrudingBody.build_circle_extrusion(extrudeCenter, extrudeRadius, height)
	elif not extrudeContour.is_empty():
		extrudingBody.build_profile_extrusion(extrudeContour, height)
	else:
		extrudingBody.build_extrusion(extrudeProfile, height)


func _update_extrusion_height():
	var cam := get_viewport().get_camera_3d()
	var mouse := get_viewport().get_mouse_position()
	var ray_o := cam.project_ray_origin(mouse)
	var ray_d := cam.project_ray_normal(mouse)
	# Vertical axis through the profile/circle centre.
	var centroid := Vector3(extrudeCenter.x, 0.0, extrudeCenter.y)
	if not extrudingCircle:
		centroid = Vector3.ZERO
		for v in extrudeProfile:
			centroid += Vector3(v.x, 0.0, v.y)
		centroid /= extrudeProfile.size()
	# Height = the point on that axis that lies closest to the mouse ray.
	var b := Vector3.UP.dot(ray_d)
	var denom := 1.0 - b * b
	if absf(denom) < 1e-6:
		return # looking straight along the axis; keep the current height
	var w := centroid - ray_o
	var t := (b * ray_d.dot(w) - Vector3.UP.dot(w)) / denom
	_rebuild_extrusion(maxf(t, 0.05))


func _points_connected(p1: Point, p2: Point) -> bool:
	for child in get_children():
		if child is SketchLine and not child.is_queued_for_deletion():
			var a = child.pointA
			var b = child.pointB
			if (a == p1 and b == p2) or (a == p2 and b == p1):
				return true
	return false


func _rebuild_faces():
	# Recompute the bounded faces of all completed lines and circles from
	# scratch. Segments are split at their intersections and the minimal
	# enclosed regions become faces (see SketchGeometry.compute_faces); a circle
	# contributes its polygon edges, so it crosses lines like any other segment.
	# Each segment carries a source tag: -1 for lines, or a unique id per circle
	# so the face's circular arcs can be rebuilt as true arcs when extruding.
	var segments := []
	var next_circle_tag := 0
	_circle_data = {}
	for child in get_children():
		if child.is_queued_for_deletion():
			continue
		if child is SketchLine and child.pointB != null:
			var ends: Array = child.get_endpoints()
			if ends.size() == 2:
				var a: Vector3 = ends[0]
				var b: Vector3 = ends[1]
				segments.append([Vector2(a.x, a.z), Vector2(b.x, b.z), -1])
		elif child is SketchCircle and child != circleBeingDrawn:
			var poly: PackedVector2Array = child.polygon(_face_segments(child))
			var tag := next_circle_tag
			next_circle_tag += 1
			_circle_data[tag] = {"center": Vector2(child.position.x, child.position.z), "radius": child.radius}
			for s in poly.size():
				segments.append([poly[s], poly[(s + 1) % poly.size()], tag])
	faces = SketchGeometry.compute_faces(segments)
	_rebuild_fill()


# Segment count a circle contributes to the arrangement (and thus the
# tessellated fill). With the analytic fill on, a fixed resolution is enough
# (the fill is exact regardless); with it off, the size-based static count drives
# the tessellated fill's smoothness.
func _face_segments(circle: SketchCircle) -> int:
	if GfxSettings.analytic_fill:
		return SketchCircle.SEGMENTS
	return GfxSettings.static_circle_segments(circle.radius)


func _on_gfx_settings_changed():
	_rebuild_faces()
	_update_visuals()


# Rebuild the face fill. With the analytic option on, a quad over the faces'
# bounding box is drawn and the boundary edges handed to sketch_fill.gdshader,
# which keeps circular fills smooth at any zoom. With it off (or when a face has
# more edges than the shader buffer holds), a triangulated mesh is used at the
# size-based polygon resolution, and fill_edge_count = 0 tells the shader to fill
# the mesh as-is.
func _rebuild_fill():
	var mat := loopFills.material_override as ShaderMaterial
	if faces.is_empty():
		loopFills.mesh = null
		if mat != null:
			mat.set_shader_parameter("fill_edge_count", 0)
		return
	if GfxSettings.analytic_fill:
		var fill := SketchGeometry.faces_to_fill_edges(faces, _circle_data)
		# count == 0 would leave fill_edge_count at 0, which tells the shader to
		# fill the whole quad as-is — fall through to the mesh fill instead.
		if fill.count > 0 and fill.count <= MAX_FILL_EDGES:
			loopFills.mesh = SketchGeometry.fill_quad(fill.min, fill.max)
			if mat != null:
				mat.set_shader_parameter("fill_edges", fill.edges)
				mat.set_shader_parameter("fill_edge_count", fill.count)
			return
	# Static / fallback: triangulated mesh (faces already use the size-based
	# circle resolution, so big circles get smoother fills).
	loopFills.mesh = SketchGeometry.build_face_fills(faces)
	if mat != null:
		mat.set_shader_parameter("fill_edge_count", 0)


func _update_visuals():
	var lines := lineRibbons.multimesh
	var dots := pointDots.multimesh
	var line_count := 0
	var point_count := 0
	# Camera factors for the view-adaptive circle outlines (pixels per world unit
	# at unit distance is k / distance).
	var cam := get_viewport().get_camera_3d()
	var cam_pos := Vector3.ZERO
	var cam_k := 0.0
	if cam != null:
		cam_pos = cam.global_position
		var vp_h := float(get_viewport().get_visible_rect().size.y)
		cam_k = vp_h / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
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
		elif child is SketchCircle:
			# Draw the circle outline in the same ribbon mesh. View-adaptive
			# (dense near the camera) when enabled, else a fixed size-based
			# polygon (static LOD).
			var poly: PackedVector2Array
			if GfxSettings.adaptive_outline and cam != null and child.radius > 0.0:
				poly = child.outline(cam_pos, cam_k, GfxSettings.outline_target_px, OUTLINE_CAM_EPS)
			else:
				poly = child.polygon(GfxSettings.static_circle_segments(child.radius))
			for s in poly.size():
				if line_count >= MAX_LINES:
					break
				var p := poly[s]
				var q := poly[(s + 1) % poly.size()]
				var a := Vector3(p.x, 0.0, p.y)
				var b := Vector3(q.x, 0.0, q.y)
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
		_cancel_line()
		_cancel_circle()
		if extrudingBody != null:
			extrudingBody.queue_free()
			extrudingBody = null
			extrudingCircle = false
	# With the adaptive outline on, refresh when the camera has moved enough
	# (SketchCircle.outline() caches per camera position, so a still camera is
	# free). With static LOD the outline doesn't depend on the camera, so skip.
	if GfxSettings.adaptive_outline:
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam.global_position.distance_to(_last_outline_cam) > OUTLINE_CAM_EPS:
			_last_outline_cam = cam.global_position
			_update_visuals()


# Abandon the segment currently being drawn (if any) and clear hover state.
func _cancel_line():
	if lineBeingDrawn != null:
		lineBeingDrawn.queue_free()
		lineBeingDrawn = null
	if hoveredPoint != null:
		hoveredPoint = null
	_update_visuals()


# Abandon the circle currently being drawn (if any).
func _cancel_circle():
	if circleBeingDrawn != null:
		circleBeingDrawn.queue_free()
		circleBeingDrawn = null
	_update_visuals()

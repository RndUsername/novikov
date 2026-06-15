class_name BodyEdges extends MultiMeshInstance3D

# Renders and selects the edges of a parent Body. Each OCCT edge is drawn as a
# constant-pixel-width ribbon (edge_ribbons.gdshader); hovering or selecting an
# edge fattens it and turns it orange, like the sketch vertices. Selection is
# multi-select and reported through SignalBus.edge_selection_changed.
#
# `edges` holds one polyline (PackedVector3Array, in this node's local space)
# per OCCT edge; its index is the edge id used by `_selected` and the signal.

const EDGE_SHADER := preload("res://shaders/edge_ribbons.gdshader")
const EDGE_COLOR := Color(0.9, 0.9, 0.9)
const HIGHLIGHT_COLOR := Color(0.85, 0.33, 0.0)
const EDGE_WIDTH := 2.0
const HIGHLIGHT_WIDTH := 4.5
const PICK_THRESHOLD_PX := 8.0

var _occt: OcctBody
var edges: Array = []
var _selected: Dictionary = {}        # edge index -> true
var _hovered: int = -1
var _seg_to_edge: PackedInt32Array = [] # multimesh instance index -> edge index


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0 # ribbons are positioned in the vertex shader
	var mat := ShaderMaterial.new()
	mat.shader = EDGE_SHADER
	mat.render_priority = 3
	var quad := QuadMesh.new()
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true        # must be set before instance_count
	mm.use_custom_data = true   # .x carries per-edge stroke width
	mm.mesh = quad
	multimesh = mm


# Rebuild the edge display from a body. Selection/hover that no longer maps to
# a valid edge (topology changed after a modeling op) is dropped.
func rebuild(p_occt: OcctBody) -> void:
	_occt = p_occt
	edges = _occt.get_edges() if _occt != null else []
	_hovered = -1
	for idx in _selected.keys():
		if idx >= edges.size():
			_selected.erase(idx)
	_rebuild_geometry()


func clear() -> void:
	_occt = null
	edges = []
	_clear_selection()
	_rebuild_geometry()


func selected_edges() -> Array:
	return _selected.keys()


# Rebuild instance transforms (one per polyline segment) plus the
# instance->edge map. Call when the geometry changes; colors follow.
func _rebuild_geometry() -> void:
	var mm := multimesh
	var seg_count := 0
	for poly in edges:
		seg_count += maxi(0, (poly as PackedVector3Array).size() - 1)
	_seg_to_edge = PackedInt32Array()
	_seg_to_edge.resize(seg_count)
	mm.instance_count = seg_count
	mm.visible_instance_count = seg_count
	var inst := 0
	for i in edges.size():
		var poly: PackedVector3Array = edges[i]
		for s in poly.size() - 1:
			var a := poly[s]
			var b := poly[s + 1]
			# Shader reads: origin = midpoint, X column = B - A.
			mm.set_instance_transform(inst,
				Transform3D(Basis(b - a, Vector3.UP, Vector3.BACK), (a + b) * 0.5))
			_seg_to_edge[inst] = i
			inst += 1
	_refresh_colors()


# Light update: recolor and re-width instances by edge state (default vs
# highlight). No transforms touched, so it is cheap enough for mouse-move.
func _refresh_colors() -> void:
	var mm := multimesh
	for inst in _seg_to_edge.size():
		var e := _seg_to_edge[inst]
		var highlit: bool = _selected.has(e) or e == _hovered
		mm.set_instance_color(inst, HIGHLIGHT_COLOR if highlit else EDGE_COLOR)
		mm.set_instance_custom_data(inst,
			Color(HIGHLIGHT_WIDTH if highlit else EDGE_WIDTH, 0.0, 0.0, 0.0))


func _clear_selection() -> void:
	if _selected.is_empty():
		return
	_selected.clear()
	SignalBus.edge_selection_changed.emit(get_parent(), [])


func _unhandled_input(event: InputEvent) -> void:
	if edges.is_empty():
		return
	if event is InputEventMouseMotion:
		var hit := _pick_edge(event.position)
		if hit != _hovered:
			_hovered = hit
			_refresh_colors()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _pick_edge(event.position)
		if hit >= 0:
			if _selected.has(hit):
				_selected.erase(hit)
			else:
				_selected[hit] = true
			_refresh_colors()
			SignalBus.edge_selection_changed.emit(get_parent(), _selected.keys())
			get_viewport().set_input_as_handled()
		elif not _selected.is_empty():
			# Clicked empty space: clear the selection.
			_clear_selection()
			_refresh_colors()


# Screen-space pick: the edge whose projected polyline passes closest to the
# mouse, within PICK_THRESHOLD_PX. Thin lines are hard to hit with a ray, so we
# measure distance in pixels and break ties by depth (nearest wins). Edges
# hidden behind the solid are rejected via an occlusion ray.
func _pick_edge(mouse: Vector2) -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return -1
	var ray_o := cam.project_ray_origin(mouse)
	var ray_d := cam.project_ray_normal(mouse)
	var best := -1
	var best_d := PICK_THRESHOLD_PX
	var best_depth := INF
	for i in edges.size():
		var poly: PackedVector3Array = edges[i]
		if poly.size() < 2:
			continue
		for s in poly.size() - 1:
			var a3 := to_global(poly[s])
			var b3 := to_global(poly[s + 1])
			if cam.is_position_behind(a3) or cam.is_position_behind(b3):
				continue
			var a := cam.unproject_position(a3)
			var b := cam.unproject_position(b3)
			var t := _closest_t(mouse, a, b)
			var d := mouse.distance_to(a.lerp(b, t))
			if d > PICK_THRESHOLD_PX:
				continue
			# 3D point on this segment under the cursor, and its view-ray depth.
			var p3 := a3.lerp(b3, t)
			var depth: float = (p3 - ray_o).dot(ray_d)
			var better := d < best_d - 1.0 or (d < best_d + 1.0 and depth < best_depth)
			if not better:
				continue
			# Aim the occlusion ray at the edge point itself (not the offset
			# cursor ray), so the test does not depend on where in the pick
			# radius the cursor sits.
			if _is_occluded(ray_o, p3):
				continue
			best = i
			best_d = d
			best_depth = depth
	return best


# True if the body's surface lies in front of `point` as seen from `ray_o`.
func _is_occluded(ray_o: Vector3, point: Vector3) -> bool:
	if _occt == null:
		return false
	var to_point := point - ray_o
	var dist := to_point.length()
	if dist < 1e-6:
		return false
	var hit: float = _occt.ray_hit_distance(ray_o, to_point / dist)
	if hit < 0.0:
		return false
	# Edges sit on the surface, so the bounding face is at ~the same distance;
	# only count it occluded when a face is clearly closer.
	var bias: float = maxf(1e-4, dist * 0.01)
	return hit < dist - bias


func _closest_t(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1e-9:
		return 0.0
	return clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)

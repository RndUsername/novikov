class_name Body extends MeshInstance3D

# A solid body in the scene. The actual geometry lives in an OcctBody
# (Open CASCADE B-rep kernel, provided by the occt extension); this node
# only displays it. All modeling operations go through set_body(), so the
# displayed mesh is always derived data. Edge display and selection are
# handled by a BodyEdges child (see edge_selection.gd).
var occt: OcctBody

var _edges := BodyEdges.new()


func _init() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.81, 0.84)
	mat.roughness = 0.45
	material_override = mat
	add_child(_edges)


func build_extrusion(profile: PackedVector2Array, height: float) -> void:
	set_body(OcctBody.extrude_polygon(profile, height))


# Extrude a true circle into a smooth cylinder (one cylindrical face), instead
# of a faceted prism of the circle's polygon approximation.
func build_circle_extrusion(center: Vector2, radius: float, height: float) -> void:
	set_body(OcctBody.extrude_circle(center, radius, height))


# Extrude a mixed line/arc contour (see SketchGeometry.face_to_contour), so a
# face bounded partly by a circle (e.g. a half-disc) keeps a smooth curved side.
func build_profile_extrusion(contour: Array, height: float) -> void:
	set_body(OcctBody.extrude_profile(contour, height))


func set_body(body: OcctBody) -> void:
	if body == null or body.is_empty():
		return # failed operation: keep the previous state, error is in the log
	occt = body
	_rebuild_mesh()


func fillet_all_edges(radius: float) -> void:
	set_body(occt.fillet_all_edges(radius))


func chamfer_all_edges(distance: float) -> void:
	set_body(occt.chamfer_all_edges(distance))


func fuse_with(other: Body) -> void:
	set_body(occt.fuse(other.occt))


func cut_with(other: Body) -> void:
	set_body(occt.cut(other.occt))


func selected_edges() -> Array:
	return _edges.selected_edges()


func _rebuild_mesh() -> void:
	if occt == null or occt.is_empty():
		mesh = null
		_edges.clear()
		return
	var data: Dictionary = occt.triangulate(0.05)
	var vertices: PackedVector3Array = data["vertices"]
	if vertices.is_empty():
		mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = array_mesh
	_edges.rebuild(occt)

class_name SketchGeometry

# Pure geometry helpers for the sketch plane. The sketch lives in the X/Z plane
# (y = 0), so loops map to 2D polygons. No node state, so these are static and
# easy to reason about / test in isolation.


# Project a loop of SketchPoints onto the sketch plane. Returns an empty array
# if any point has been freed (the loop is then stale).
static func loop_to_polygon(loop: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in loop:
		if not is_instance_valid(p):
			return PackedVector2Array()
		pts.append(Vector2(p.position.x, p.position.z))
	return pts


# Build a filled mesh (one triangulated surface per loop) for the given loops.
static func build_loop_fills(loops: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for loop in loops:
		var pts := loop_to_polygon(loop)
		if pts.size() < 3:
			continue
		var indices := Geometry2D.triangulate_polygon(pts)
		if indices.is_empty():
			continue
		var verts := PackedVector3Array()
		for v in pts:
			verts.append(Vector3(v.x, 0.0, v.y))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

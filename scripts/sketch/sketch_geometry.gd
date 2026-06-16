class_name SketchGeometry

# Pure geometry helpers for the sketch plane. The sketch lives in the X/Z plane
# (y = 0), so line segments map to 2D (x, z) and the regions they bound map to
# 2D polygons. No node state, so these are static and easy to test in isolation.

const EPS := 1e-5
const SNAP := 1e-4 # vertices closer than this are treated as one


# Compute the bounded faces of the planar arrangement of a set of segments.
#
# Segments may cross; each crossing (and T-junction) splits the segments into
# sub-segments, and the minimal closed regions enclosed by those sub-segments
# are returned as polygons. Two crossing lines therefore yield up to four
# faces, one per quadrant that is actually closed off. The unbounded outer
# region and any dangling (non-enclosing) edges are discarded.
#
# `segments` is an Array of [Vector2, Vector2] or [Vector2, Vector2, tag],
# where `tag` is an arbitrary int identifying the source curve (e.g. a circle
# id; lines pass -1). Returns an Array of Dictionaries, one per bounded face:
#   { "points": PackedVector2Array (CCW), "tags": PackedInt32Array }
# where tags[k] is the source tag of the edge points[k] -> points[k + 1].
static func compute_faces(segments: Array) -> Array:
	var sub := _split_at_intersections(segments)
	if sub.is_empty():
		return []

	# Build the planar graph: dedupe near-coincident endpoints into vertices,
	# record each vertex's neighbours (an undirected adjacency set) and the
	# source tag of each undirected edge.
	var verts := PackedVector2Array()
	var vert_ids := {}            # quantized key (Vector2i) -> vertex index
	var adjacency := {}           # vertex index -> { neighbour index: true }
	var edge_tag := {}            # Vector2i(u, v) -> source tag (both directions)
	for seg in sub:
		var u := _vertex_id(seg[0], verts, vert_ids, adjacency)
		var v := _vertex_id(seg[1], verts, vert_ids, adjacency)
		if u == v:
			continue
		adjacency[u][v] = true
		adjacency[v][u] = true
		edge_tag[Vector2i(u, v)] = seg[2]
		edge_tag[Vector2i(v, u)] = seg[2]

	# Order each vertex's neighbours by angle so we can walk faces by always
	# turning the same way around a vertex.
	var ordered := {}             # vertex index -> Array of neighbour indices, CCW
	for v in adjacency:
		var ns: Array = adjacency[v].keys()
		var origin := verts[v]
		ns.sort_custom(func(a, b):
			return (verts[a] - origin).angle() < (verts[b] - origin).angle())
		ordered[v] = ns

	# Trace faces. Each directed half-edge (u -> v) belongs to exactly one
	# face; the next half-edge is the one immediately clockwise from the twin
	# (v -> u) around v. With this rule bounded faces come out counter-clockwise
	# (positive area) and the single outer face clockwise.
	var visited := {}             # Vector2i(u, v) -> true
	var faces := []
	for u in ordered:
		for v in ordered[u]:
			var start := Vector2i(u, v)
			if visited.has(start):
				continue
			var poly := PackedVector2Array()
			var tags := PackedInt32Array()
			var cu: int = u
			var cv: int = v
			while not visited.has(Vector2i(cu, cv)):
				visited[Vector2i(cu, cv)] = true
				poly.append(verts[cu])
				tags.append(edge_tag.get(Vector2i(cu, cv), -1))
				var nb: Array = ordered[cv]
				var i: int = nb.find(cu)
				var nxt: int = nb[(i - 1 + nb.size()) % nb.size()]
				cu = cv
				cv = nxt
			if _signed_area(poly) > EPS:
				faces.append({"points": poly, "tags": tags})
	return faces


# Project vertices that lie on a circle back onto the true circle. The planar
# arrangement runs on each circle's polygon, so intersection points sit on a
# chord slightly inside the real circle; `circle_data` maps a tag to its true
# {center, radius}. Snapping makes reconstructed arcs match the circle exactly
# (so the fill and the analytic outline line up at any zoom).
static func snap_to_circles(points: PackedVector2Array, tags: PackedInt32Array, circle_data: Dictionary) -> PackedVector2Array:
	if circle_data.is_empty():
		return points
	var n := points.size()
	var out := points.duplicate()
	for j in n:
		var tag: int = tags[j] if tags[j] >= 0 else tags[(j - 1 + n) % n]
		if tag >= 0 and circle_data.has(tag):
			var cd: Dictionary = circle_data[tag]
			var center: Vector2 = cd["center"]
			var dir := out[j] - center
			if dir.length() > 1e-9:
				out[j] = center + dir.normalized() * float(cd["radius"])
	return out


# Turn one face (its CCW points and per-edge source tags) into an ordered
# contour of line/arc edges suitable for OcctBody.extrude_profile. Consecutive
# edges sharing the same tag >= 0 (i.e. belonging to one circle) become a single
# 3-point arc; everything else stays a straight line. Returns [] when the face
# has no arc edges (the caller can then extrude the polygon directly), or when
# the whole boundary is a single curve (a clean circle, handled elsewhere).
static func face_to_contour(points: PackedVector2Array, tags: PackedInt32Array, circle_data: Dictionary = {}) -> Array:
	points = snap_to_circles(points, tags, circle_data)
	var n := points.size()
	if n < 3:
		return []
	var has_arc := false
	for t in tags:
		if t >= 0:
			has_arc = true
			break
	if not has_arc:
		return []

	# Start at an edge that begins a run (its tag differs from the previous
	# edge's), so runs don't get split across the array wrap-around.
	var start := -1
	for k in n:
		if tags[k] != tags[(k - 1 + n) % n]:
			start = k
			break
	if start == -1:
		return [] # every edge shares one tag: a closed single curve

	var contour := []
	var k := 0
	while k < n:
		var e := (start + k) % n
		var tag := tags[e]
		if tag < 0:
			contour.append({"type": "line",
				"pts": PackedVector2Array([points[e], points[(e + 1) % n]])})
			k += 1
			continue
		# Maximal run of edges sharing this circle's tag.
		var run := 1
		while k + run < n and tags[(start + k + run) % n] == tag:
			run += 1
		if run >= 2:
			var i0 := (start + k) % n
			var i_mid := (start + k + run / 2) % n
			var i_end := (start + k + run) % n
			contour.append({"type": "arc",
				"pts": PackedVector2Array([points[i0], points[i_mid], points[i_end]])})
		else:
			var i0 := (start + k) % n
			contour.append({"type": "line",
				"pts": PackedVector2Array([points[i0], points[(i0 + 1) % n]])})
		k += run
	return contour


# Pack every face's boundary into analytic edges for the fill shader (see
# sketch_fill.gdshader). Returns:
#   { "edges": PackedVector4Array (2 slots per edge), "count": int,
#     "min": Vector2, "max": Vector2 (bounding box of all faces) }
# Straight boundaries become line edges; runs of one circle become a single arc;
# a whole circle becomes one circle primitive. Curves stay exact (no vertices).
static func faces_to_fill_edges(faces: Array, circle_data: Dictionary = {}) -> Dictionary:
	var edges := PackedVector4Array()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for face in faces:
		var tags: PackedInt32Array = face["tags"]
		var points := snap_to_circles(face["points"], tags, circle_data)
		if points.size() < 3:
			continue
		for p in points:
			mn.x = minf(mn.x, p.x)
			mn.y = minf(mn.y, p.y)
			mx.x = maxf(mx.x, p.x)
			mx.y = maxf(mx.y, p.y)
		_append_fill_edges(points, tags, edges)
	return {"edges": edges, "count": edges.size() / 2, "min": mn, "max": mx}


static func _append_fill_edges(points: PackedVector2Array, tags: PackedInt32Array, out: PackedVector4Array) -> void:
	var n := points.size()
	# A face whose every edge shares one circle's tag is that whole circle.
	var all_same := true
	for t in tags:
		if t != tags[0]:
			all_same = false
			break
	if all_same and tags[0] >= 0:
		var cc := _circumcenter(points[0], points[n / 3], points[2 * n / 3])
		out.append(Vector4(2.0, cc.x, cc.y, cc.distance_to(points[0])))
		out.append(Vector4(0.0, 0.0, 0.0, 0.0))
		return
	# Otherwise walk the boundary, grouping circle runs into arcs (start at a
	# tag boundary so a run never straddles the array wrap-around).
	var start := 0
	for k in n:
		if tags[k] != tags[(k - 1 + n) % n]:
			start = k
			break
	var k := 0
	while k < n:
		var e := (start + k) % n
		if tags[e] < 0:
			_emit_line(out, points[e], points[(e + 1) % n])
			k += 1
			continue
		var run := 1
		while k + run < n and tags[(start + k + run) % n] == tags[e]:
			run += 1
		if run >= 2:
			_emit_arc(out, points[(start + k) % n], points[(start + k + run / 2) % n], points[(start + k + run) % n])
		else:
			_emit_line(out, points[(start + k) % n], points[(start + k + 1) % n])
		k += run


static func _emit_line(out: PackedVector4Array, a: Vector2, b: Vector2) -> void:
	out.append(Vector4(0.0, a.x, a.y, 0.0))
	out.append(Vector4(b.x, b.y, 0.0, 0.0))


static func _emit_arc(out: PackedVector4Array, p0: Vector2, pm: Vector2, p1: Vector2) -> void:
	var c := _circumcenter(p0, pm, p1)
	var a0 := (p0 - c).angle()
	var am := (pm - c).angle()
	var a1 := (p1 - c).angle()
	# CCW if, sweeping from a0 in the +angle direction, the mid point is reached
	# before the end point.
	var off_mid := fposmod(am - a0, TAU)
	var off_end := fposmod(a1 - a0, TAU)
	var ccw := 1.0 if (off_end > 0.0 and off_mid <= off_end) else -1.0
	out.append(Vector4(1.0, c.x, c.y, c.distance_to(p0)))
	out.append(Vector4(a0, a1, ccw, 0.0))


static func _circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-12:
		return (a + c) * 0.5 # near-collinear; degenerate
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	return Vector2(
		(a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)


# Build a single flat quad covering [mn, mx] (with a small margin) in the sketch
# plane, for the analytic fill shader to test per fragment.
static func fill_quad(mn: Vector2, mx: Vector2) -> ArrayMesh:
	var m := 0.05
	var verts := PackedVector3Array([
		Vector3(mn.x - m, 0.0, mn.y - m), Vector3(mx.x + m, 0.0, mn.y - m),
		Vector3(mx.x + m, 0.0, mx.y + m), Vector3(mn.x - m, 0.0, mx.y + m)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Build a filled mesh (one triangulated surface per face) for the given faces
# (as returned by compute_faces). Fallback when there are too many edges for the
# analytic shader.
static func build_face_fills(faces: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for face in faces:
		var poly: PackedVector2Array = face["points"]
		if poly.size() < 3:
			continue
		var indices := Geometry2D.triangulate_polygon(poly)
		if indices.is_empty():
			continue
		var verts := PackedVector3Array()
		for v in poly:
			verts.append(Vector3(v.x, 0.0, v.y))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Split every segment at the points where it meets any other segment, returning
# the resulting sub-segments as an Array of [Vector2, Vector2].
static func _split_at_intersections(segments: Array) -> Array:
	var sub := []
	for i in segments.size():
		var a: Vector2 = segments[i][0]
		var b: Vector2 = segments[i][1]
		var tag: int = segments[i][2] if segments[i].size() > 2 else -1
		var ab := b - a
		var len_sq := ab.length_squared()
		if len_sq < EPS * EPS:
			continue
		# Parameters along a->b at which to split (always the endpoints, plus
		# every intersection with another segment).
		var ts := [0.0, 1.0]
		for j in segments.size():
			if j == i:
				continue
			var hit = Geometry2D.segment_intersects_segment(a, b, segments[j][0], segments[j][1])
			if hit == null:
				continue
			ts.append(clampf((hit - a).dot(ab) / len_sq, 0.0, 1.0))
		ts.sort()
		var prev: float = ts[0]
		for k in range(1, ts.size()):
			var t: float = ts[k]
			if t - prev > EPS:
				sub.append([a + ab * prev, a + ab * t, tag])
				prev = t
	return sub


# Find (or create) the vertex index for a point, merging points within SNAP.
static func _vertex_id(p: Vector2, verts: PackedVector2Array, ids: Dictionary, adjacency: Dictionary) -> int:
	var key := Vector2i(roundi(p.x / SNAP), roundi(p.y / SNAP))
	if ids.has(key):
		return ids[key]
	var idx := verts.size()
	verts.append(p)
	ids[key] = idx
	adjacency[idx] = {}
	return idx


static func _signed_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		area += p.x * q.y - q.x * p.y
	return area * 0.5

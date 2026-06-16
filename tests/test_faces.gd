extends SceneTree

# Headless test for the planar-arrangement face computation in SketchGeometry.

func _seg(ax, ay, bx, by) -> Array:
	return [Vector2(ax, ay), Vector2(bx, by)]

func _init():
	# A single closed square -> one face.
	var square := [
		_seg(0, 0, 2, 0), _seg(2, 0, 2, 2), _seg(2, 2, 0, 2), _seg(0, 2, 0, 0),
	]
	print("square faces (expect 1): ", SketchGeometry.compute_faces(square).size())

	# Two diagonals crossing inside the square -> 4 triangular faces.
	# (the square edges + the two diagonals, all crossing at the centre)
	var crossed := square.duplicate()
	crossed.append(_seg(0, 0, 2, 2))
	crossed.append(_seg(2, 0, 0, 2))
	var faces: Array = SketchGeometry.compute_faces(crossed)
	print("crossed-square faces (expect 4): ", faces.size())
	var total := 0.0
	for f in faces:
		total += SketchGeometry._signed_area(f["points"])
	print("crossed-square total area (expect ~4.0): ", snappedf(total, 0.001))

	# Two crossing line segments with no outer boundary -> no bounded face.
	var open_cross := [_seg(-1, 0, 1, 0), _seg(0, -1, 0, 1)]
	print("open cross faces (expect 0): ", SketchGeometry.compute_faces(open_cross).size())

	# A dangling tail off a closed triangle must not create an extra face.
	var triangle_with_tail := [
		_seg(0, 0, 2, 0), _seg(2, 0, 1, 2), _seg(1, 2, 0, 0), _seg(1, 2, 1, 4),
	]
	print("triangle+tail faces (expect 1): ", SketchGeometry.compute_faces(triangle_with_tail).size())

	# A circle's polygon approximation (as SketchCircle builds it) -> one face
	# whose area ~= pi r^2. Built inline so the test does not depend on the
	# SketchCircle class being registered in the global cache.
	var segs := 48
	var poly := PackedVector2Array()
	for i in segs:
		var ang := TAU * i / float(segs)
		poly.append(Vector2(cos(ang), sin(ang)))
	var ring := []
	for i in poly.size():
		ring.append([poly[i], poly[(i + 1) % poly.size()], 7]) # tag 7 = "circle"
	var circle_faces: Array = SketchGeometry.compute_faces(ring)
	print("circle faces (expect 1): ", circle_faces.size())
	if circle_faces.size() == 1:
		print("circle area (expect ~3.14): ", snappedf(SketchGeometry._signed_area(circle_faces[0]["points"]), 0.01))

	# Circle crossed by a horizontal line through its centre -> 2 half-disc
	# faces, each a run of arc edges (tag 7) plus one chord line (tag -1).
	var half := ring.duplicate()
	half.append([Vector2(-2, 0), Vector2(2, 0), -1])
	var halves: Array = SketchGeometry.compute_faces(half)
	print("half-circle faces (expect 2): ", halves.size())
	var circle_data := {7: {"center": Vector2(0, 0), "radius": 1.0}}
	if halves.size() >= 1:
		var contour := SketchGeometry.face_to_contour(halves[0]["points"], halves[0]["tags"], circle_data)
		var n_arc := 0
		var n_line := 0
		for e in contour:
			if e["type"] == "arc": n_arc += 1
			else: n_line += 1
		print("half-disc contour (expect 1 arc, 1 line): ", n_arc, " arc, ", n_line, " line")

	# Analytic fill edges: a clean circle -> 1 circle primitive (type 2); the two
	# half-discs -> arc + line each (the shared chord appears in both).
	var circle_fill: Dictionary = SketchGeometry.faces_to_fill_edges(circle_faces, circle_data)
	print("circle fill edges (expect 1): ", circle_fill.count,
		" type (expect 2.0=circle): ", circle_fill.edges[0].x if circle_fill.count > 0 else -1)
	# Arc centre/radius should be the true circle after snapping (expect (0,0), r 1).
	var half_fill: Dictionary = SketchGeometry.faces_to_fill_edges(halves, circle_data)
	for i in half_fill.count:
		if half_fill.edges[2 * i].x > 0.5 and half_fill.edges[2 * i].x < 1.5:
			var s0: Vector4 = half_fill.edges[2 * i]
			print("arc center (expect ~0,0): (", snappedf(s0.y, 0.001), ",", snappedf(s0.z, 0.001),
				")  radius (expect ~1): ", snappedf(s0.w, 0.001))
			break
	var n_arcs := 0
	var n_lines := 0
	var n_circles := 0
	for i in half_fill.count:
		var t: float = half_fill.edges[2 * i].x
		if t < 0.5: n_lines += 1
		elif t < 1.5: n_arcs += 1
		else: n_circles += 1
	print("half-disc fill edges (expect 2 arc, 2 line): ", n_arcs, " arc, ", n_lines, " line, ", n_circles, " circle")

	quit()

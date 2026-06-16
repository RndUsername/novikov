extends SceneTree

# Headless smoke test for the occt extension.
func _init():
	var profile := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 1), Vector2(0, 1)])
	var body: OcctBody = OcctBody.extrude_polygon(profile, 1.0)
	print("extrude ok: ", body != null and not body.is_empty())
	print("face count (expect 6): ", body.get_face_count())

	var cylinder: OcctBody = OcctBody.extrude_circle(Vector2(0, 0), 1.0, 2.0)
	print("cylinder ok: ", cylinder != null and not cylinder.is_empty())
	print("cylinder face count (expect 3: top, bottom, side): ", cylinder.get_face_count())
	var visible_edges := 0
	for e in cylinder.get_edges():
		if (e as PackedVector3Array).size() > 0:
			visible_edges += 1
	print("cylinder visible edges (expect 2, seam hidden): ", visible_edges)

	# A half-disc (semicircle arc + diameter) extruded keeps a smooth curved side.
	var contour := [
		{"type": "arc", "pts": PackedVector2Array([Vector2(-1, 0), Vector2(0, 1), Vector2(1, 0)])},
		{"type": "line", "pts": PackedVector2Array([Vector2(1, 0), Vector2(-1, 0)])},
	]
	var half_cyl: OcctBody = OcctBody.extrude_profile(contour, 1.0)
	print("half-cylinder ok: ", half_cyl != null and not half_cyl.is_empty())
	print("half-cylinder face count (expect 4): ", half_cyl.get_face_count())

	var filleted: OcctBody = body.fillet_all_edges(0.1)
	print("fillet ok: ", filleted != null and not filleted.is_empty())
	print("fillet face count (expect 26): ", filleted.get_face_count())
	var fillet_edges := 0
	for e in filleted.get_edges():
		if (e as PackedVector3Array).size() > 0:
			fillet_edges += 1
	print("fillet visible edges (expect > 0, tangent edges kept): ", fillet_edges)

	var cutter: OcctBody = OcctBody.extrude_polygon(
		PackedVector2Array([Vector2(0.5, 0.25), Vector2(1.5, 0.25), Vector2(1.5, 0.75), Vector2(0.5, 0.75)]), 2.0)
	var cut: OcctBody = body.cut(cutter)
	print("boolean cut ok: ", cut != null and not cut.is_empty())
	print("cut face count (expect 10): ", cut.get_face_count())

	var mesh_data: Dictionary = filleted.triangulate(0.05)
	var verts: PackedVector3Array = mesh_data["vertices"]
	print("triangulation vertices: ", verts.size())

	var top := filleted.pick_face(Vector3(1.0, 5.0, 0.5), Vector3(0, -1, 0))
	print("pick_face from above: ", top, " transform: ", filleted.get_face_transform(top))

	var step_path := "user://test_body.step"
	print("step export ok: ", cut.export_step(ProjectSettings.globalize_path(step_path)))
	var imported: OcctBody = OcctBody.import_step(ProjectSettings.globalize_path(step_path))
	print("step import ok: ", imported != null and not imported.is_empty(), " faces: ", imported.get_face_count())

	quit()
